# Kintsugi USB — Update Strategy

**Audience**: you have already flashed a Kintsugi USB, booted it on a host, and connected to the internet. You want to bring the drive current without losing your work. This guide walks every refresh path end-to-end.

**Supersedes**: the `scripts/update-payload.sh` rsync mechanism from early drafts (retired under ADR-005; single-artifact imaging per the 2026-04-21 amendment to ADR-002).

---

## 1. The refresh model at a glance

A running Kintsugi USB has four independent content layers, each with its own refresh path. Touch only the layer that actually changed — in most cases that is `git pull`, full stop.

| Category | What's in it | Lives on | Refresh path | Requires reflash? |
|----------|--------------|----------|--------------|-------------------|
| **1. Docs & scripts** | `docs/`, `scripts/`, `manifest/*.yaml`, runbooks, recovery packs, ADRs | Persistence overlay (`/data/repo/kintsugi-usb/`) + binaries copied to `/usr/local/bin/` at ISO build time | `git pull` in the clone; re-copy scripts if you want the new versions to run | No |
| **2. Models** | GGUF weights (llama.cpp) and Ollama blobs | `/data/models/user/` and `/data/ollama/` in persistence | `kintsugi-models pull <slug>` / `--all` | No |
| **3. Agentic frameworks** | Aider, Claude Code, Codex CLI, Continue.dev, etc. | System paths (pipx, npm global, apt) or `~/.local/` in persistence | `kintsugi-frameworks install <name>` | No |
| **4. Base image** | Ubuntu squashfs, kernel, Ollama binary, llama.cpp binary, Ventoy, rescue ISO menu, VS Code + Copilot extension | Read-only ISO layer baked into `kintsugi-v2026.5.0.img.zst` | Download new `.img.zst`, verify, reflash | **Yes** (destroys persistence unless backed up) |

Rule of thumb:

- Ran `git pull`? You're done in 30 seconds.
- Want a new model? 5 minutes and a few GB.
- Want a new agentic CLI? 2 minutes.
- Need a reflash? Back up `/data/` first. Budget serious time.

---

## 2. Category 1 — Docs and scripts refresh via `git pull`

The maintainer's signed ISO ships with `/data/repo/kintsugi-usb/` already cloned during first-boot setup. That clone is the authoritative copy of the repo on your persistence overlay. `git pull` is the whole refresh mechanism for every text-file artifact in the toolkit.

### Step 1 — Confirm the clone is where it should be

```bash
# Expected default location (baked by first-boot-setup.sh)
ls -la /data/repo/kintsugi-usb/.git

# If it's there, check its remote and branch
cd /data/repo/kintsugi-usb
git remote -v
git status
```

If the directory is missing (you built from the toolkit yourself and skipped the clone step, or a file-system event wiped it), clone it now:

```bash
sudo mkdir -p /data/repo
sudo chown "$USER":"$USER" /data/repo
cd /data/repo
git clone https://git.integrolabs.net/roctinam/kintsugi-usb.git
cd kintsugi-usb
```

### Step 2 — Pull the latest

```bash
cd /data/repo/kintsugi-usb
git fetch --tags
git pull --ff-only
```

`--ff-only` refuses to create a merge commit — if you get a non-fast-forward error it means someone (you, earlier) committed locally. Either `git stash` your changes first, or `git log --oneline origin/main..HEAD` to see what you've added before deciding.

This single command now carries:

- Updated `docs/` (including this file)
- Updated `scripts/usb-toolkit/` (kintsugi-models, kintsugi-frameworks, etc.)
- Updated `manifest/models-recommended.yaml` — the maintainer's tested model list
- Updated `manifest/agentic-frameworks-recommended.yaml`
- New or revised recovery packs under `docs/`
- ADRs and architecture updates

### Step 3 — Propagate updated scripts into `/usr/local/bin/` (important)

This is the step most people miss. At ISO build time, scripts are **copied** from the repo into `/usr/local/bin/` inside the squashfs. A `git pull` updates the clone under `/data/repo/` but does **not** update the binaries that live in the read-only ISO layer. If you want the latest `kintsugi-models` to actually run when you type it, you must re-copy or symlink it:

```bash
# Re-copy approach (simple; wins on PATH because /usr/local/bin is writable via overlay)
sudo install -m 0755 /data/repo/kintsugi-usb/scripts/usb-toolkit/kintsugi-models    /usr/local/bin/kintsugi-models
sudo install -m 0755 /data/repo/kintsugi-usb/scripts/usb-toolkit/kintsugi-frameworks /usr/local/bin/kintsugi-frameworks

# Or symlink approach (easier to maintain; one git pull auto-updates)
sudo ln -sf /data/repo/kintsugi-usb/scripts/usb-toolkit/kintsugi-models    /usr/local/bin/kintsugi-models
sudo ln -sf /data/repo/kintsugi-usb/scripts/usb-toolkit/kintsugi-frameworks /usr/local/bin/kintsugi-frameworks
```

Verify:

```bash
which kintsugi-models
kintsugi-models version
```

The symlink approach is recommended — you get "auto-updated at next `git pull`" behaviour for free.

---

## 3. Category 2 — Models

Model weights are never bundled by the maintainer (ADR-005). Every pull is a user-initiated action against the user's network and the user's storage budget.

### See what's installed

```bash
kintsugi-models list            # union of maintainer-recommended + user manifest
kintsugi-models list --sizes    # also inventories on-disk GGUF files and Ollama blobs
```

The `FROM` column tells you whether a slug is `recommended` (from `manifest/models-recommended.yaml`), `shadowed` (both manifests — user wins), or `user-only`.

### Add a new recommended model

When a `git pull` brings in a new entry in `manifest/models-recommended.yaml`, `kintsugi-models list` will show it. To actually fetch the weights:

```bash
kintsugi-models pull qwen3.5:4b
```

For Ollama slugs (`name:tag`) this runs `ollama pull` and stores the blob under `/data/ollama/`. For HuggingFace-sourced entries (`*.gguf`) it streams the file to `/data/models/user/` and verifies sha256 when the manifest provides one.

### Bulk-refresh against the updated manifest

There's no `--all` flag yet in the v0.1 CLI (tracked in the CLI's open work); the idiom is:

```bash
# Pull every recommended slug you don't already have
for slug in $(kintsugi-models list | awk 'NR>2 && $4=="recommended" {print $1}'); do
    kintsugi-models pull "$slug"
done
```

### Storage guards

`kintsugi-models` enforces two thresholds before every pull (ADR-005 §D3 / NFR-11.3):

- **Soft-warn at 80%** of the filesystem containing the target directory — you get a `WARN:` line but the pull proceeds.
- **Hard-refuse at 95%** — the pull aborts with `Storage at NN% of /data — refusing pull`.

Override via env vars (`KINTSUGI_STORAGE_WARN_PCT`, `KINTSUGI_STORAGE_REFUSE_PCT`) if you know what you're doing. If you hit the 95% wall, free space first:

```bash
kintsugi-models remove <large-slug> --delete-weights
ollama list                         # inventory Ollama blobs
ollama rm <slug>                    # manual removal
df -h /data                         # confirm recovered space
```

---

## 4. Category 3 — Agentic frameworks

Agentic frameworks (Claude Code, Codex CLI, Aider, Cursor, Continue.dev, ...) are **not baked into the base image** for recipients of the default wizard build (ADR-006 §D2). The image ships the installer CLI and the manifest; you opt in post-boot.

### See the catalog

```bash
kintsugi-frameworks list              # full catalog
kintsugi-frameworks list --installed  # only the ones already on PATH
```

### Install one

```bash
# Maintainer-recommended (status: recommended)
sudo kintsugi-frameworks install aider

# Vendor CLI with its own auth flow
sudo kintsugi-frameworks install claude-code
sudo kintsugi-frameworks install codex-cli

# User-added or 'evaluating' status frameworks require explicit opt-in
kintsugi-frameworks install some-evaluating-fw --yes
```

`sudo` is needed when the install recipe uses `apt-get`, `dpkg`, or writes to system paths. `pip`/`npm` recipes that target `~/.local` or user scope do not require root.

### Authentication is always the user's job

**This CLI never stores API keys, OAuth tokens, or EULA acceptance.** Regardless of which framework you install, activation is a post-install step:

- **Claude Code** — `claude` CLI; sign in via browser OAuth on first invocation
- **Codex CLI** — OpenAI API key via `export OPENAI_API_KEY=...` (add to `~/.bashrc` in persistence to survive reboots)
- **Aider** — BYO API key for whichever model provider; works out of the box against your local `ollama serve` or `llama-server` with no key
- **Cursor / Windsurf / Warp** — install the `.deb` yourself, sign in on first launch
- **GitHub Copilot** (already in the base image) — `gh auth login` then enable in VS Code

Credentials live in persistence (`/data/` via home-directory overlay) so they survive reboots. They do **not** live in the ISO — that's the whole point of user-driven loading.

### Verify installation

```bash
kintsugi-frameworks verify --all
```

Reports `OK` or `NOT INSTALLED` per entry based on whether the expected binary is on `$PATH` (or the expected VS Code extension is registered).

---

## 5. Category 4 — Base image (reflash required)

Everything above is zero-reflash. The following changes *do* require a reflash because they live inside the read-only squashfs or the boot layer:

- **Ubuntu security patches** that need a rebuilt squashfs (kernel, systemd, OpenSSL, glibc)
- **Ollama version bump** — bundled as a binary in the ISO
- **llama.cpp version bump** — same
- **Ventoy version bump** — affects the boot layer, not the filesystem
- **New default-bundled feature** — e.g. a different IDE, a new rescue ISO added to the boot menu
- **Root filesystem layout changes** — e.g. a new default user, a changed `/data/` schema

### Back up persistence first (non-negotiable if you want to keep work)

Reflashing overwrites the drive. Anything under `/data/` is lost unless you copy it off first.

```bash
# Mount an external drive at /mnt/backup first, then:
sudo rsync -aHAX --info=progress2 /data/ /mnt/backup/kintsugi-data-$(date +%F)/
```

What's in `/data/` worth saving:

- `/data/repo/kintsugi-usb/` — your clone, possibly with local branches
- `/data/models/user/` — HuggingFace GGUFs you downloaded
- `/data/ollama/` — all pulled Ollama models
- `/data/frameworks/user/` — custom framework manifest entries
- Home directory overlays if persistence is configured with `persistence-home.conf` — API keys, shell history, VS Code settings, Claude Code sign-in, etc.

### Fetch, verify, flash

```bash
# 1. Download the new image + its sha256
# NFS mount (maintainer's internal distribution, v1.0 — ADR-006 §D4):
sudo mount -t nfs warehouse.integrolabs.net:/exports/releases /mnt/warehouse
cp /mnt/warehouse/kintsugi-usb/v0.2.0/kintsugi-v0.2.0.img.zst ./
cp /mnt/warehouse/kintsugi-usb/v0.2.0/kintsugi-v0.2.0.img.zst.sha256 ./

# 2. Verify
/data/repo/kintsugi-usb/scripts/verify-image.sh kintsugi-v0.2.0.img.zst

# 3. Flash (confirm target device; this IS destructive)
sudo /data/repo/kintsugi-usb/scripts/flash-image.sh kintsugi-v0.2.0.img.zst /dev/sdX
```

(v1.1 will add minisign signature verification; v1.0 is sha256-only per ADR-006 §D5.)

### Restore your persistence

After first-boot of the reflashed drive:

```bash
sudo rsync -aHAX /mnt/backup/kintsugi-data-YYYY-MM-DD/ /data/
```

Expect a few things to need re-linking:

- Re-run the symlinks from §2 Step 3 (the new ISO shipped a newer script version in `/usr/local/bin/`; re-create the symlinks to prefer your clone, or accept the fresh version).
- Re-verify models: `kintsugi-models verify --all`.

---

## 6. Rollback and version pinning

### Docs and scripts — pin to a tag

```bash
cd /data/repo/kintsugi-usb
git fetch --tags
git tag -l 'v*'                 # list release tags
git checkout v2026.5.0          # pin to a specific tag
# (detached HEAD is fine here — you're consuming, not committing)

# To go back to rolling updates
git checkout main
git pull --ff-only
```

### Models — pin Ollama versions

```bash
ollama pull qwen3.5:4b-q4_0          # specific quantization
ollama pull qwen3.5:4b@sha256:abc…   # pin by digest
```

HuggingFace GGUFs pinned in `manifest/models-recommended.yaml` by `sha256` in the entry — the maintainer bumps this when upstream changes. Your local weight file doesn't change until you re-pull.

### Frameworks — per vendor

Each vendor has its own pinning story:

- `pipx install "aider-chat==0.70.0"` for Aider
- `npm install -g @anthropic-ai/claude-code@0.2.42` for Claude Code
- `npm install -g @openai/codex-cli@X.Y.Z` for Codex CLI

Consult the manifest's `install_recipe` for each framework and adapt.

### Base image — keep old `.img.zst` around

Nothing stops you from keeping the previous release's image file on a backup drive. To roll back, repeat §5 with the older file. The maintainer does not formally support rollback beyond "re-flash an older release" — schema drift in persistence across versions is documented in release notes when it occurs.

---

## 7. Network-constrained recipient flow

On limited bandwidth (hotspot, slow DSL, field deployment), minimize what you pull:

- **Always prefer `git pull`**. Repo is small (<20 MB typical); docs and scripts are the highest-leverage refresh.
- **Defer model pulls**. A model weight is typically 2–20 GB. On a constrained link, don't pull unless you actively need that model.
- **Sync the manifest without pulling weights**: the `manifest/models-recommended.yaml` file arrives via `git pull`. You can inspect what's available (`kintsugi-models list`) without spending any bandwidth on weights. (A `kintsugi-models pull --only-update-manifest` convenience flag is on the roadmap; today the pattern is "git pull, then inspect, then selectively pull specific slugs".)
- **Avoid reflashing** unless there's a security fix you specifically need. A 1.7–2.6 GB image download is hours on constrained links.
- **Use local AI, not cloud CLIs**. Running Aider against `http://localhost:11434/v1` (Ollama) or `http://localhost:8080/v1` (llama-server) costs zero bandwidth per interaction. Claude Code and Codex CLI talk to the cloud and will dominate your usage.

---

## 8. Rollback procedure for a bad `git pull`

`git pull --ff-only` brought in something that broke your scripts. Recover:

```bash
cd /data/repo/kintsugi-usb

# Find the last-known-good commit
git reflog                         # shows HEAD history
git log --oneline -20              # visible history

# Reset (destructive — loses uncommitted local changes)
git reset --hard <good-commit-sha>

# If you were running scripts via direct copy (not symlinks),
# re-copy the old versions back:
sudo install -m 0755 scripts/usb-toolkit/kintsugi-models    /usr/local/bin/kintsugi-models
sudo install -m 0755 scripts/usb-toolkit/kintsugi-frameworks /usr/local/bin/kintsugi-frameworks

# Confirm
kintsugi-models version
```

File an issue describing the breakage at https://git.integrolabs.net/roctinam/kintsugi-usb/issues so the next release can fix it.

---

## 9. Automating the refresh

Optional cron entries for a drive that lives online most of the time. Put these in `/etc/cron.d/kintsugi-refresh` (survives reboot via persistence) or a user crontab.

```cron
# Weekly: pull latest docs/scripts on Sunday at 03:00
0 3 * * 0 root cd /data/repo/kintsugi-usb && git pull --ff-only >> /var/log/kintsugi-gitpull.log 2>&1

# Monthly: verify existing model integrity on the 1st at 04:00
0 4 1 * * root kintsugi-models verify --all >> /var/log/kintsugi-verify.log 2>&1
```

**Deliberately absent**: auto-pull of models. Two reasons:

1. **Bandwidth unpredictability** — a new recommended slug might be 20 GB. An overnight auto-pull on a metered connection would be hostile.
2. **Weight-size unpredictability** — quantization changes at upstream can silently grow a model by gigabytes. User consent per pull is the safer default.

Leave model pulls and framework installs interactive.

---

## 10. Reference table

| Category | Command(s) | Recommended frequency | Needs internet? | Needs reflash? | Data loss? |
|----------|------------|------------------------|-----------------|----------------|------------|
| Docs & scripts | `cd /data/repo/kintsugi-usb && git pull --ff-only` | Weekly or ad hoc | Yes | No | No |
| Scripts → `/usr/local/bin/` | `sudo ln -sf …/scripts/usb-toolkit/* /usr/local/bin/` | Once after first pull (symlinks) | No | No | No |
| Models — maintainer list | `kintsugi-models pull <slug>` | On demand, after a recommended-list change | Yes | No | No |
| Models — integrity | `kintsugi-models verify --all` | Monthly | No | No | No |
| Agentic frameworks | `sudo kintsugi-frameworks install <name>` | On demand | Yes | No | No |
| Base image | `verify-image.sh` + `flash-image.sh` | Rare (security, major feature) | Yes | **Yes** | **Yes** — back up `/data/` first |
| Persistence backup | `rsync -aHAX /data/ /mnt/backup/` | Before every reflash; quarterly otherwise | No | No | No (creates backup) |
| Version pinning (docs) | `git checkout v0.X.Y` | As needed | No | No | No |

---

## Related documents

- [ADR-002 — Imaging Strategy](../.aiwg/architecture/adr-002-imaging-strategy.md) — why reflash is rare
- [ADR-005 — Toolkit Scope & User-Driven Models](../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md)
- [ADR-006 — Wizard-First UX & User-Driven Agentic Frameworks](../.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md)
- `scripts/usb-toolkit/kintsugi-models` — source of truth for model CLI behaviour
- `scripts/usb-toolkit/kintsugi-frameworks` — source of truth for framework CLI behaviour
- `manifest/models-recommended.yaml` — the maintainer's tested model set
- `manifest/agentic-frameworks-recommended.yaml` — the maintainer's tested framework set
