# Kintsugi USB — Toolkit Guide (External Builders)

**Status**: v1.0 (iteration-1 deliverable — closes Gitea [#17](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/17) and [#24](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/24)).
**Audience**: Builders cloning this repo as an SDK to roll their own Kintsugi-like rescue USB.
**Authoritative references**: [ADR-005](../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md) · [ADR-006](../.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md) · [SECURITY.md](../SECURITY.md)

This document walks you from `git clone` to a flashed, self-signed Kintsugi USB that you personally tested and can hand to someone else.

---

## 1. Who this guide is for

Kintsugi USB is two products sharing one repo (ADR-005 §D1):

1. A **distributed tested image** — the maintainer's personally-tested signed image, for flash-and-go recipients.
2. A **toolkit** — scripts, manifests, and docs the maintainer publishes so you can build your own image, with your own choices, signed with your own key.

This guide is about path (2). ADR-005 §D1 and ADR-006 §D1 define the external-builder persona — the home-lab operator, the IT consultant outfitting clients, the family tech helper making recovery drives for relatives, the shop-floor sysadmin assembling a rescue kit for their fleet. If any of those sound like you, keep reading.

You are **not** required to ship what the maintainer ships. You pick your own rescue ISOs, your own local AI runtimes, your own agentic frameworks, your own models, your own branding. You also take on the responsibility that comes with that — the maintainer's signature does not cover your derivative image.

---

## 2. Prerequisites

### Hardware

| Resource | Minimum | Recommended |
|---|---|---|
| Build host OS | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS (fresh install or dedicated VM) |
| Free disk | 100 GB | 200 GB (keeps multiple builds + ISO caches) |
| RAM | 8 GB | 16 GB+ |
| Target USB | 64 GB USB 3.x | 128 GB USB 3.2 (faster persistence) |

Use a **dedicated VM or clean host** for release builds. The sanitization step (§7) scans for and refuses to image a build root containing API keys, SSH private keys, or other secrets that would leak from your daily-driver machine.

### Software

Install build dependencies:

```bash
sudo apt-get update
sudo apt-get install -y whiptail squashfs-tools xorriso zstd git curl ca-certificates
```

Plus the ADR-008 remaster toolchain: `livefs-edit` and a Ventoy release (`Ventoy2Disk.sh`) — see `../docs/build-guide.md` and [ADR-008](../.aiwg/architecture/adr-008-build-tooling-remaster-stock-iso.md). `live-build` is **no longer used**; the build remasters the stock Ubuntu ISO instead.

Install the `mikefarah/yq` YAML processor (the wizard uses it to read/write profiles and manifests):

```bash
sudo wget -O /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
yq --version   # confirm it prints "mikefarah"
```

Ubuntu's `yq` apt package is a different tool (Python-based) and will not work. The wizard aborts if it does not find `mikefarah/yq`.

---

## 3. Clone and orient

```bash
git clone https://git.integrolabs.net/roctinam/kintsugi-usb.git
cd kintsugi-usb
```

Top-level layout:

| Path | Role |
|---|---|
| `README.md` | Public overview and tagline |
| `LICENSE` | MIT (per ADR-006 §D6) |
| `SECURITY.md` | Trust boundary and disclosure process |
| `docs/` | Build guides, this file, sanitization checklist, flash guide |
| `scripts/` | `kintsugi-build` wizard + `usb-toolkit/` subdirectory with build/image/test/CLI tools |
| `manifest/` | `models-recommended.yaml`, `agentic-frameworks-recommended.yaml`, `THIRD-PARTY-LICENSES.md` |
| `.aiwg/` | SDLC artifacts — ADRs, requirements, risks, planning, tests |

The two places you will spend the most time as a builder:

- `scripts/kintsugi-build` — the interactive wizard that orchestrates a full build.
- `manifest/` — the two YAML files that declare which models and agentic frameworks you pick from.

---

## 4. Choose your models

Model **weights** are never shipped in the distributed base image (ADR-005 §D3). The maintainer publishes a tested list; you choose which of those you want, or you add your own.

### 4.1 The recommended manifest

`manifest/models-recommended.yaml` ships three tested entries:

| Slug | Runtime | Source | Size | Purpose |
|---|---|---|---|---|
| `qwen3.5:4b` | Ollama | Ollama registry | ~2.5 GB | General reasoning (<16 GB RAM hosts) |
| `qwen3.5:9b` | Ollama | Ollama registry | ~5.5 GB | General reasoning (≥16 GB RAM hosts) |
| `Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf` | llama.cpp | HuggingFace | ~4.7 GB | Code generation via direct GGUF |

Schema highlights: `slug`, `runtime` (`ollama` | `llama-cpp`), `source` (`ollama` | `huggingface` | `url`), `quant`, `sha256`, `purpose`, `status` (`recommended` | `evaluating` | `deprecated`). Full schema reference is at the bottom of the file.

Inspect it:

```bash
yq eval '.recommended[] | {"slug": .slug, "runtime": .runtime, "status": .status}' \
  manifest/models-recommended.yaml
```

### 4.2 Diverging from the recommended list

You have two options:

1. **Edit in place** — copy `models-recommended.yaml` to `models-chosen.yaml` and edit locally. This is appropriate if you are a one-off builder and want to keep your divergence in your own git fork.
2. **Add entries at runtime** — use the `kintsugi-models add` CLI (see §13), which writes to a user manifest instead of touching the committed file.

User-supplied entries shadow recommendations on slug collision, at both build-time and boot-time.

### 4.3 Trust boundary for models — R-17 mitigation (closes Gitea #24)

This is the most important section of this guide for supply-chain safety. Read it before pulling anything.

**The maintainer's trust boundary is precise**: the maintainer's signature (when it lands in v1.1) covers `manifest/models-recommended.yaml` **as committed** in a tagged release. It does not cover model weights, and it does not cover any slug you add that is outside this file.

> "The maintainer's signature covers `models-recommended.yaml` as committed; any slug you add or pull that is outside this file is your trust anchor, not the maintainer's."

This matters because Ollama registry pulls and HuggingFace downloads can, in principle, be tampered with or compromised upstream. R-17 in the risk register ([`.aiwg/risks/risk-list.md`](../.aiwg/risks/risk-list.md)) tracks this class of threat: a user pulling a malicious slug that appears legitimate but contains a poisoned quantization or a model trained to exfiltrate secrets.

The `kintsugi-models` CLI implements **two** R-17 mitigations today — the `--yes` gate (Mitigation 2) and `verify` (Mitigation 4). Two more — an interactive pull acknowledgment and the `--only-recommended` lockdown — are **planned, not yet implemented**; they are described below as the intended design so builders know the roadmap.

#### Mitigation 1: Source URL + digest printed before download

Every `kintsugi-models pull <slug>` prints the resolved source URL and (where available) the digest **before** the download starts, so you can eyeball what's about to be fetched:

```text
$ kintsugi-models pull qwen3.5:4b
Resolving slug: qwen3.5:4b
  Runtime:  ollama
  Source:   ollama registry
  URL:      registry.ollama.ai/library/qwen3.5:4b
  Digest:   sha256:ab34...ef90 (from Ollama manifest)
  Size:     ~2.5 GB download, ~3.0 GB resident
```

For HuggingFace-sourced entries, the URL is `huggingface.co/<hf_repo>/resolve/main/<hf_file>` and the sha256 from the manifest is printed; if the manifest's sha256 field is `null` (not yet populated), the CLI warns loudly. *(Planned: an interactive `Continue? [y/N]` acknowledgment before recommended-slug pulls — today, recommended slugs download immediately; only non-recommended slugs are gated, see Mitigation 2.)*

#### Mitigation 2: Non-recommended slugs require `--yes`

If the slug is **not** present in `manifest/models-recommended.yaml` with `status: recommended`, the CLI refuses to proceed without an explicit `--yes` flag:

```bash
kintsugi-models pull some-random-model:latest
# ERROR: 'some-random-model:latest' is not in the recommended list.
# To pull anyway (you are the trust anchor):
#   kintsugi-models pull some-random-model:latest --yes
```

This is the speed bump. You can always override, but the CLI will not silently fetch content the maintainer never tested.

#### Mitigation 3 (planned): `--only-recommended` lockdown flag

> **Not yet implemented.** `kintsugi-models` has no `--only-recommended` flag or `KINTSUGI_ONLY_RECOMMENDED` config today. The intended design: for a non-technical recipient, setting `--only-recommended` (via `KINTSUGI_ONLY_RECOMMENDED=1` in `/etc/kintsugi/kintsugi.conf`) would make `kintsugi-models pull` hard-refuse any non-recommended slug regardless of `--yes` — a friction point against casual social-engineering. Until it lands, Mitigation 2's `--yes` gate is the speed bump.

#### Mitigation 4: `kintsugi-models verify`

Every pulled model has its on-disk bytes hashed. `kintsugi-models verify` walks the user's installed set, recomputes sha256, and compares against:

- The manifest's `sha256` field (for HuggingFace and URL sources).
- The Ollama digest (via `ollama show --modelfile` for Ollama sources).

Mismatches produce a non-zero exit and a loud warning — this is how you detect post-install tampering (disk corruption, ransomware, manual replacement).

#### When to diverge anyway

You may absolutely want to pull a model the maintainer has not blessed. Common legitimate cases: a newer Qwen release, a domain-specific fine-tune, a smaller model for embedded use. That is fine — that is the whole point of the toolkit being a toolkit. Just understand that **you are the trust anchor for that choice**, you should be looking at the source's own provenance (vendor signature, repository reputation, upstream community review), and you should not represent a USB containing that model as "the maintainer's signed image."

---

## 5. Choose your agentic frameworks

Agentic framework binaries follow the same user-driven pattern as models (ADR-006 §D2). The toolkit does **not** redistribute Claude Code, Codex CLI, Cursor, Windsurf, Warp, or any other agentic CLI/IDE. Instead, `manifest/agentic-frameworks-recommended.yaml` declares install recipes, and `kintsugi-frameworks install <name>` runs those recipes at build time.

### 5.1 v1.0 ship set

Three frameworks ship as the tested set in v1.0 (ADR-006 Open Question #4):

| Name | Vendor | License | Install method | Auth model |
|---|---|---|---|---|
| `aider` | Paul Gauthier / community | Apache-2.0 | pipx | BYO API key (local or cloud) |
| `claude-code` | Anthropic | proprietary (EULA) | curl-bash | Subscription sign-in |
| `codex-cli` | OpenAI | proprietary (EULA) | npm | EULA + API key |

A further set (Cursor, Windsurf, Warp, OpenCode, Factory, Continue.dev) is declared in the manifest with `status: evaluating` and `v1.0_ship_decision: false` — these are not in the wizard menu yet but the install recipes are sketched so you can copy them into a user manifest and try them at your own risk.

### 5.2 Auth and EULAs are always post-flash

This is non-negotiable. The toolkit installs framework **binaries only**. It does not bake:

- API keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.)
- OAuth tokens (`gh auth`, Cursor, Factory accounts)
- EULA acceptance
- Subscription sign-ins

Any of those on a shipped image would leak credentials to every recipient. The user authenticates **after** booting the flashed USB on their target hardware. The sanitization checklist (§7) enforces this with a secret scan.

### 5.3 Adding a framework to your build

The wizard (§6) bakes the agentic CLI set with a **single yes/no** (`--with-agentic`): claude-code, codex, opencode, copilot, openclaw, omnius, and aider. There is no per-framework checkbox — selection of *additional* frameworks happens post-flash at runtime:

```bash
# On the flashed USB, post-first-boot:
kintsugi-frameworks list
kintsugi-frameworks install aider
kintsugi-frameworks install continue-dev   # evaluating-tier; uses user manifest
```

See §12 for how to author your own entry.

---

## 6. Run the wizard

With prerequisites installed and your model/framework choices in mind:

```bash
./scripts/kintsugi-build
```

That is the whole happy path. The wizard (`scripts/kintsugi-build`, ADR-006 §D1 / ADR-008 build) orchestrates the full pipeline — remaster → Ventoy assembly → package — with no manual steps. Walk-through of the prompts (full per-screen detail in [`wizard-guide.md`](wizard-guide.md) §3):

1. **Build name** — default `kintsugi-v2026.5.0-YYYYMMDD`. Output dir + artifact filename stem.
2. **Base ISO** — path to the stock Ubuntu/Xubuntu 24.04 live ISO to remaster (the new ADR-008 input; auto-detected from `~/kintsugi-builds/_base/`).
3. **Offline AI (Ollama)** (yes/no, default yes) — pre-installs Ollama + mikefarah `yq`, wired to a persistence-backed model store. Adds ~2.5 GB. No model weights are baked (ADR-005).
4. **Agentic CLIs** (yes/no, default yes) — bakes claude-code, codex, opencode, copilot, openclaw, omnius, and aider, offline-available. Auth is post-flash. (VS Code/IDE is deferred — [#43](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/43).)
5. **Persistence size** — Ventoy persistence in GiB (default 32; holds `/data`, incl. the Ollama model store).
6. **Recommended model hint** (yes/no) — does not bundle models (ADR-005); writes a post-flash `kintsugi-models pull` / `ollama pull` suggestion to the profile.
7. **Signing** (yes/no, default no) — v1.0 ships sha256 only (ADR-006 §D5); minisign arrives in v1.1.
8. **Confirm** — summary of all choices + the exact 3-stage pipeline. Approve to start.

Build output lands at `~/kintsugi-builds/<build_name>/`:

| File | Purpose |
|---|---|
| `build-profile.yaml` | The choices you made — resumable and replayable |
| `build.log` | Full pipeline output |
| `<build_name>.iso` | Remastered Kintsugi live ISO |
| `<build_name>-ventoy.img` | Assembled Ventoy disk image (bootloader + persistence) |
| `<build_name>.img.zst` + `.sha256` | Distributable compressed image — **flash this** |

### 6.1 Replay modes

The wizard always writes a profile early, so you can replay a build:

```bash
# Interactive confirmation before build (useful for iteration)
./scripts/kintsugi-build --from-profile ~/kintsugi-builds/my-build/build-profile.yaml

# Fully unattended, CI-friendly (no prompts at all)
./scripts/kintsugi-build --non-interactive ~/kintsugi-builds/my-build/build-profile.yaml

# Show the plan and exit (no build)
./scripts/kintsugi-build --dry-run --from-profile ~/kintsugi-builds/my-build/build-profile.yaml
```

If a build crashes mid-way, rerun from the profile — the profile is schema-versioned (`schema_version: 2`); `read_profile()` hard-fails on a mismatch, so re-create profiles with the matching wizard version (v1 profiles from the live-build era are not compatible).

---

## 7. Assemble, sanitize, image, and publish your build

A live ISO from step 6 is buildable and bootable, but it is not yet a **distributable Ventoy image**. The remaining steps turn it into one: assemble the Ventoy `.img`, sanitize, package, and publish.

### 7.0 Assemble the Ventoy image

`scripts/usb-toolkit/make-ventoy-image.sh` builds the flashable Ventoy `.img`: the Ventoy bootloader (UEFI + legacy), a **32 GiB persistence** `.dat` bound to the Kintsugi ISO, and your rescue ISOs + the Kintsugi ISO copied into the boot menu.

```bash
sudo scripts/usb-toolkit/make-ventoy-image.sh \
     --kintsugi-iso ~/kintsugi-builds/<build_name>/<build_name>.iso \
     [--rescue-iso <iso> …] [--persistence-size 32] \
     [--ollama-models <staged-ollama-store>]
# --ollama-models pre-loads a staged Ollama store (blobs/ + manifests/) into the
#   persistence at /data/ollama/models so the booted Ollama has the models offline.
# --dry-run validates inputs and prints the layout without touching disks.
```

> **Status:** This stage is now **auto-chained by `kintsugi-build`** ([#36](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/36) landed) — the wizard runs remaster → `make-ventoy-image.sh` → `create-image.sh` with no manual steps. Run `make-ventoy-image.sh` directly only for standalone/advanced use (e.g. adding rescue ISOs or pre-loading models via `--ollama-models`). `make-ventoy-image.sh` (#42) + 32 GiB persistence (#34) are committed; the boot/persistence round-trip is validated on hardware under [#37](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/37). For the fully manual Ventoy procedure this automates, see [`build-guide.md`](build-guide.md).

### 7.1 Sanitize

[`docs/sanitization-checklist.md`](sanitization-checklist.md) is the authoritative list of what must be scrubbed before imaging.

> **Scope (ADR-008):** the remaster pipeline builds from a clean stock ISO and accumulates no secrets by construction, so the wizard's auto-chain does **not** run a sanitize pass. `scripts/prep-master.sh` is for the **legacy/manual** path — a hand-mastered USB or a mounted master partition — not the remaster output. Run it only when sanitizing such a master:

```bash
sudo scripts/prep-master.sh <mounted-master-or-build-root>
```

It enforces (on the manual path): no API keys / SSH private keys / secret-bearing shell histories; clean shell/cache/log state; preserve the manifests; optional free-space zero-fill; and schema-validate the `kintsugi-models` / `kintsugi-frameworks` user manifests (those are `schema_version: 1`). If it reports warnings, investigate before imaging.

### 7.2 Image

```bash
# Source is the Ventoy .img assembled in §7.0 (create-image also accepts a raw .iso for a single-boot image).
scripts/create-image.sh dist/kintsugi-ventoy.img --name <build_name>
```

Produces `<build_name>.img.zst` + `<build_name>.img.zst.sha256`. The sha256 file is the only integrity artifact in v1.0 (signing deferred to v1.1, see §8).

### 7.3 Generate manifest

```bash
scripts/generate-manifest.sh ~/kintsugi-builds/<build_name>
```

Writes a release manifest capturing the profile, file list, sha256s, build environment, and the commit hash of your fork at build time.

### 7.4 Publish

`scripts/publish-release.sh` defaults to the maintainer's NFS warehouse path (`/mnt/warehouse/releases/kintsugi-usb/<version>/`), which you will not have. Override with either the `--publish-nfs` flag or the `KINTSUGI_PUBLISH_NFS` env var:

```bash
# Option A: flag
scripts/publish-release.sh --publish-nfs /path/to/your/mirror \
  ~/kintsugi-builds/<build_name>

# Option B: env var
KINTSUGI_PUBLISH_NFS=/path/to/your/mirror \
  scripts/publish-release.sh ~/kintsugi-builds/<build_name>
```

You are not restricted to NFS. Any writable path works — local disk, sshfs mount, S3 mount via `s3fs`. You can also skip this script entirely and scp the image + sha256 to wherever you like. See §9 for publishing to third-party channels.

---

## 8. Sign with your own key (NOT the maintainer's)

### 8.1 v1.0 — sha256 only

v1.0 ships sha256 checksums only (ADR-006 §D5, [SECURITY.md](../SECURITY.md)). Every `create-image.sh` run produces a `.sha256` file alongside the image. That is the only integrity artifact recipients verify against:

```bash
# Recipient command (Linux / macOS)
shasum -a 256 -c your-build.img.zst.sha256

# Recipient command (Windows PowerShell)
Get-FileHash your-build.img.zst -Algorithm SHA256
```

sha256 protects against **accidental corruption in transit**. It does not, on its own, defeat a targeted attacker who controls both the image and the checksum on the host serving them — that is the v1.1 minisign story.

### 8.2 v1.1 — minisign (when it lands)

Iteration-2 will reintroduce minisign (Ed25519 signatures). At that point, fork maintainers generate their own keypair:

```bash
# When v1.1 lands:
minisign -G -p ~/kintsugi-yourfork.pub -s ~/.minisign/yourfork.key
minisign -Sm your-build.img.zst -s ~/.minisign/yourfork.key
```

Commit `kintsugi-yourfork.pub` to your fork's repo (pin it in your README and SECURITY.md) so downstream users can `minisign -Vm your-build.img.zst -p kintsugi-yourfork.pub`.

**Critically**: do not use the upstream `kintsugi.pub` (when it exists) to sign your derivatives. That key belongs to the maintainer of this repo, and reusing it would falsely claim upstream provenance for your build.

### 8.3 For v1.0 right now

`sha256sum -c` is the only verification. That is fine — the v1.0 trust model explicitly accepts this (ADR-003 amended). Document the expectation clearly in your fork's README (§9).

---

## 9. Publish and distribute

You own your own release channel. Common choices:

- **Gitea release** on your own instance — attach a pointer file (not the multi-GB image) + sha256 + release notes.
- **GitHub release** — same pattern; keep the image on a separate host if it is over release-asset limits.
- **S3 / R2 / Backblaze B2** — public-read bucket, published URL, recipients `curl` directly.
- **NFS / SSH mount** — internal distribution to a fleet or family.
- **Plain HTTP** on a VPS — minimal, works fine with a reverse-proxy cache.

Update **your fork's** `README.md` with:

- The URL where recipients download your `.img.zst`.
- The URL (or text) of the matching `.sha256` file.
- A copy-paste one-liner for verification:
  ```bash
  curl -L -o kintsugi-yourfork.img.zst https://your.host/path/image
  curl -L -o kintsugi-yourfork.img.zst.sha256 https://your.host/path/image.sha256
  shasum -a 256 -c kintsugi-yourfork.img.zst.sha256
  ```
- A link to your fork's `SECURITY.md` describing your trust boundary (which you also need to edit — the upstream file describes the upstream maintainer's posture, not yours).

**Do NOT** claim the upstream maintainer's signature on your derivative image. Your README should say "built with the Kintsugi USB toolkit" and link to this repo, but the integrity story for your image is yours.

---

## 10. Trust boundaries summary

Quick reference. When in doubt, re-read [SECURITY.md](../SECURITY.md).

| Artifact | Upstream maintainer signs (v1.1+) | Upstream maintainer does not sign | Your fork signs (when you build) | User is trust anchor |
|---|---|---|---|---|
| Upstream base image (tagged release) | ✓ | | | |
| Upstream scripts + docs (tagged release) | ✓ | | | |
| `manifest/models-recommended.yaml` as committed | ✓ | | | |
| `manifest/agentic-frameworks-recommended.yaml` as committed | ✓ | | | |
| Model weights (Ollama / HF / URL pulled) | | ✓ | | ✓ |
| Agentic framework binaries (Aider, Claude Code, etc.) | | ✓ | | ✓ (via vendor) |
| User-added slug not in recommended manifest | | ✓ | | ✓ |
| Your fork's built image | | ✓ | ✓ | |
| Your fork's `manifest/*` edits | | ✓ | ✓ | |

---

## 11. Testing your build

Never announce a release you have not booted. `scripts/usb-toolkit/usb-test-harness.sh` is the 527-line automated validator ported from sysops.

### 11.1 Smoke test (fast)

Quick sanity check — boots, runtimes present, persistence mounted, manifests schema-valid:

```bash
sudo scripts/usb-toolkit/usb-test-harness.sh --smoke
```

Run this during build iteration. Typical runtime: a few minutes.

### 11.2 Full test (thorough)

All PASS/FAIL/SKIP/WARN checks — runtime startup, model discovery, network detection, SMART health, benchmark sanity, framework version queries:

```bash
sudo scripts/usb-toolkit/usb-test-harness.sh --full
```

Run this **on at least one fleet host** before you tag a release. Capture the JSON output (`/var/log/kintsugi/test-*/results.json`) as part of your release evidence.

Model-dependent tests report `WARN` until you pull at least one model via `kintsugi-models pull` — that is by design (the base image intentionally has no weights).

---

## 12. Adding a new agentic framework

If Aider + Claude Code + Codex CLI is not your set, author an entry. Schema (see `manifest/agentic-frameworks-recommended.yaml` for the full reference):

```yaml
- name: "my-framework"              # lowercase-hyphenated
  display_name: "My Framework"
  vendor: "Vendor Name"
  license: "Apache-2.0"             # SPDX or "proprietary" / "proprietary (EULA)"
  kind: "cli"                       # cli | ide | terminal | vscode-extension
  install_method: "curl-bash"       # pip | npm | curl-bash | apt-deb | flatpak | marketplace | manual
  install_recipe: |
    curl -fsSL https://example.com/install | bash
  auth_model: "byo-api-key"         # byo-api-key | subscription-signin | oauth-github | EULA+API-key | none
  runtime_dependency: "llama-server | ollama | cloud-api-anthropic"
  status: recommended               # recommended | evaluating | deprecated
  v1.0_ship_decision: true          # true = in wizard menu
  notes: "Anything else a user needs to know."
```

For your private use, add this to your local `manifest/agentic-frameworks-recommended.yaml` fork or to `/data/frameworks/user/frameworks.yaml` on the persistence overlay. For upstream contribution, see §15.

Install recipes run in the build chroot (for system-wide installs) or in the persistence overlay (for user-scoped). Keep them minimal, idempotent, and free of credentials.

---

## 13. Adding a new model slug

`kintsugi-models` CLI subcommands (ADR-005 §D3):

```bash
# Ollama source (auto-resolves from the Ollama registry)
kintsugi-models add newmodel:8b --runtime ollama --source ollama

# HuggingFace source (populate sha256 on first verify)
kintsugi-models add CoolCoder-13B-Q4.gguf \
  --runtime llama-cpp \
  --source huggingface \
  --hf-repo bartowski/CoolCoder-13B-GGUF \
  --hf-file CoolCoder-13B-Q4_K_M.gguf

# Arbitrary URL source (sha256 required)
kintsugi-models add custom-model \
  --runtime llama-cpp \
  --source url \
  --url https://your.host/model.gguf \
  --sha256 <hex>

# Pull it
kintsugi-models pull newmodel:8b

# Verify on-disk integrity later
kintsugi-models verify
```

### Build-time vs. post-flash pull behavior

- **Build-time** — on your build host, run with `--target <path>` pointing at the in-progress master's payload partition (`/mnt/master/payload/models/`). Models land in the base image; users get them pre-populated when they flash.
- **Post-flash** — on the booted USB, run without `--target`. Models land in `/data/models/user/` on the persistence overlay. Survives reboot; never touches the read-only squashfs.

User manifest entries (from `kintsugi-models add` at runtime) live at `/data/models/user/models.yaml` and shadow recommendations on slug collision.

---

## 14. Troubleshooting

### Wizard won't start — "mikefarah/yq required"

You have Ubuntu's Python-based `yq`, not mikefarah's Go binary. Re-install per §2.

### Wizard says "whiptail not installed"

It falls back to plain prompts, which work fine but are uglier. `sudo apt-get install -y whiptail` to fix.

### Remaster fails mid-build

Typical causes: network blip to an apt/npm mirror, full `/tmp`, an upstream installer that changed (e.g. an Ollama installer sha-pin mismatch), or a missing host tool (`livefs-edit`, `squashfs-tools`, `xorriso`, `zstd`). Read `~/kintsugi-builds/<build>/build.log`. In-chroot install detail for the agentic CLIs / AI stack is captured inside the image at `/etc/kintsugi/{agentic,ai-stack}-install.log` (extract with `unsquashfs` if a stage reported a failure). Fix, then rerun from the profile.

### sha256 mismatch on a pulled model

Re-pull. If it still mismatches, the source has changed (Ollama registry retag, HuggingFace file replacement) or there is network corruption. `kintsugi-models verify` will flag the mismatch; do not silently ignore it.

### Persistence overlay full

Ollama/model pulls can fill a 64 GB USB fast. `kintsugi-models` CLI soft-warns at 80% capacity and hard-refuses at 95% (R-18). Free space with `ollama rm <slug>` or `kintsugi-models remove <slug>`.

### Copilot extension installed but inert

Recipient has not signed in. `gh auth login` and then sign in to Copilot from the VS Code command palette. Copilot requires a paid GitHub subscription — the extension alone does not provide completions.

### Build works on your host, fails on a clean VM

You had a system tool installed that the build expected. Check `build.log` for the missing dependency and add it to your build-host prereq list.

---

## 15. Contributing back to upstream Kintsugi

Issues and PRs: https://git.integrolabs.net/roctinam/kintsugi-usb/issues

Upstream contribution rules (from [CLAUDE.md](../CLAUDE.md)):

- **Conventional commits** — `type(scope): subject`, imperative mood.
- **DCO sign-off** — sign commits you author; upstream accepts the Developer Certificate of Origin as the contribution license gate.
- **No AI attribution in commits** — the commit subject and body reflect the human author who reviewed and approved the change. Even if you used an agent to draft the change, you are the author.
- **Public-repo security** — never commit `.env`, API keys, SSH keys, fleet secrets, or `.img*` files. Upstream enforces this at review; flagging during PR is the norm.
- **Issue tracking is on Gitea** (`git.integrolabs.net`), not GitHub. Never open issues on the GitHub mirror.

Good first contributions:

- A new `status: evaluating` entry in `manifest/agentic-frameworks-recommended.yaml` with a tested install recipe.
- A new `status: evaluating` model entry in `manifest/models-recommended.yaml` with a populated `sha256` after first verify.
- A troubleshooting note you discovered that belongs in §14.
- A fleet-host test result from running `usb-test-harness.sh --full` on hardware the maintainer does not have.

---

## Appendix — related references

- [ADR-005 — toolkit scope + user-driven models](../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md)
- [ADR-006 — wizard-first UX + user-driven agentic frameworks](../.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md)
- [SECURITY.md](../SECURITY.md)
- [`manifest/models-recommended.yaml`](../manifest/models-recommended.yaml)
- [`manifest/agentic-frameworks-recommended.yaml`](../manifest/agentic-frameworks-recommended.yaml)
- [`docs/sanitization-checklist.md`](sanitization-checklist.md)
- [`scripts/README.md`](../scripts/README.md)
- Gitea [#17 — toolkit guide (this)](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/17)
- Gitea [#24 — R-17 documentation (closed by §4.3)](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/24)
