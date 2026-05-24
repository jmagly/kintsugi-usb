# Pre-Imaging Sanitization Checklist

**Status**: v1.0 (iteration-1 deliverable, Gitea issue #8).
**Authority**: CLAUDE.md `Public Repo Security` + `Distribution Workflow` directives; R-06 (secret leak to squashfs/exFAT); R-07 (API keys in repo); `sad-review-security.md` required change.
**Consumed by**: `scripts/prep-master.sh` (automates every item that can be automated).

## Why this exists

Images shipped to recipients are read-only in practice — by the time someone flashes and boots the USB, any secret on the image is essentially public. The maintainer's image goes to NFS first (trusted channel for v1.0), but iteration-2 signing + broader distribution demand that v1.0 images also be clean. This checklist is the definitive list of what must be removed / verified before `create-image.sh` runs.

## Rule 1: API keys and auth tokens

**MUST NOT be in the image**:
- Anthropic `claude` auth (`~/.claude/`, `~/.config/anthropic/`)
- OpenAI `codex` auth (`~/.config/openai/`, `~/.config/codex/`)
- GitHub Copilot / `gh` auth (`~/.config/gh/`, `~/.local/share/gh/`)
- AWS credentials (`~/.aws/credentials`, `~/.aws/config`)
- Generic `.env` files anywhere
- `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or similar env exports in any shell rc

**Verification method**: `scripts/prep-master.sh` scans for these paths inside the build-root chroot and refuses to proceed if any are non-empty. Pattern file at `scripts/secret-patterns.txt`.

## Rule 2: SSH private keys and fleet credentials

**MUST NOT be in the image**:
- Any `id_ed25519`, `id_rsa`, `id_ecdsa`, or derivative private-key file under `~/.ssh/`
- Fleet-host SSH host keys
- Kerberos tickets (`/tmp/krb5cc_*`)
- GPG secret keys (`~/.gnupg/private-keys-v1.d/`)

**MAY be in the image** — but only via operator-provided, git-ignored local config, never committed to this public repo:
- **Public** `authorized_keys` lists — operator-provided, scoped to internal network ranges
- `/etc/hosts` fleet entries — operator-provided via `config/includes.chroot/etc/kintsugi/fleet-hosts` (git-ignored; see `config/fleet-hosts.example`). The public toolkit bakes in **no** fleet topology.
- SSH client configs (`/etc/ssh/ssh_config.d/kintsugi.conf`) that reference public keys

**Verification method**: prep-master scans for private-key magic strings (`-----BEGIN OPENSSH PRIVATE KEY-----`, `-----BEGIN RSA PRIVATE KEY-----`, etc.) across the build root.

## Rule 3: Shell history, command caches

Nothing sensitive should live in shell history on a shipped image. Wipe:

- `~/.bash_history`, `~/.zsh_history`, `~/.python_history`, `~/.node_repl_history`, `~/.mysql_history`, `~/.psql_history`
- `~/.lesshst`, `~/.viminfo`
- `/root/.bash_history` etc. for the root user
- `~/.cache/` directories for any auth-bearing tool (selectively — see Rule 7 for what to keep)

## Rule 4: Persistence overlay content (live-build)

`build-custom-iso.sh` does not create a persistence overlay; Ventoy does when a user plugs in the USB. But any on-master persistence scratch must be wiped:

- `/var/lib/kintsugi/persistence-test-*`
- `/data/` (if populated at build time by accident)
- `/home/live/.local/share/` (live-build user's XDG data)

## Rule 5: Installer caches

- `/var/cache/apt/archives/*.deb` → `apt-get clean` inside chroot (already in `build-custom-iso.sh`'s end-of-chroot script; verified by prep-master)
- `/var/lib/apt/lists/*` → optional (saves ~300 MB but recipients may want offline apt capability; default: KEEP)
- `/root/.cache/pip/*` → wipe
- `/tmp/*`, `/var/tmp/*` → wipe

## Rule 6: Logs with potentially sensitive content

- `/var/log/auth.log*`, `/var/log/syslog*`, `/var/log/messages*`, `/var/log/journal/*`
- `/root/.xsession-errors`
- `/home/live/.xsession-errors`
- `/var/log/kintsugi/start-ai.log` (may contain model-selection output with filenames)
- `/var/log/kintsugi/test-*/` (test harness results from build-time runs)

## Rule 7: What prep-master MUST preserve

Not everything is a secret. Explicit keep-list:

- **`manifest/models-recommended.yaml`** at `/opt/kintsugi-usb/manifest/` — maintainer-signed starter list
- **`manifest/agentic-frameworks-recommended.yaml`** at same path
- **`/etc/kintsugi/build-info.conf`** — metadata the test harness reads
- **`/etc/kintsugi/ollama-first-boot.conf`** — first-boot setup marker
- **Framework install artifacts** (baked in via 07-hook): `/usr/bin/aider`, `/usr/local/bin/claude`, etc.
- **Fleet `/etc/hosts` entries** (public-only)

## Rule 8: Verify zero-fill / free-space zero (optional)

Zero-filling free space compresses better and prevents accidental data exposure from deleted files:

```
dd if=/dev/zero of=/build-root/ZEROFILL bs=1M status=progress 2>/dev/null
rm /build-root/ZEROFILL
sync
```

`prep-master.sh --zero-free-space` runs this. Default: ON for release builds; OFF for quick-iteration builds (env `KINTSUGI_SKIP_ZEROFILL=1`).

## Rule 9: Sanity-check manifest presence

Before calling the build done:

- Run `yq eval '.schema_version' manifest/models-recommended.yaml` — must equal `1`
- Run `yq eval '.schema_version' manifest/agentic-frameworks-recommended.yaml` — must equal `1`
- Run `ls /etc/kintsugi/build-info.conf` — must exist
- Run `test -x /usr/local/bin/start-ai.sh /usr/local/bin/kintsugi-models /usr/local/bin/kintsugi-frameworks` — all must be executable

## Rule 10: Hash the result

After all sanitization: compute `sha256` of the final `.iso` or `.img` (done by `create-image.sh`, not by prep-master).

## Pattern file for prep-master

`scripts/secret-patterns.txt` (text file, one regex per line, searched recursively with grep):

```
-----BEGIN OPENSSH PRIVATE KEY-----
-----BEGIN RSA PRIVATE KEY-----
-----BEGIN DSA PRIVATE KEY-----
-----BEGIN EC PRIVATE KEY-----
-----BEGIN PGP PRIVATE KEY BLOCK-----
^ANTHROPIC_API_KEY=
^OPENAI_API_KEY=
^AWS_SECRET_ACCESS_KEY=
^AWS_SESSION_TOKEN=
^GH_TOKEN=
^GITEA_TOKEN=
xoxb-[0-9]{10,}
sk-[a-zA-Z0-9]{20,}
```

## Operator responsibilities beyond this checklist

- Do NOT run a build on a host where you have personal API keys set in `~/.config/ai-keys.env` and then image it. Use a clean VM or set `unset ANTHROPIC_API_KEY OPENAI_API_KEY` before invoking `kintsugi-build`.
- Review the `prep-master.sh` scan report before authorizing `create-image.sh` to run. Any warnings should be investigated.
- For **distributed images** (not just local testing): build on a dedicated VM with no personal credentials.

## References

- `scripts/prep-master.sh` — automated enforcement
- `scripts/secret-patterns.txt` — regex source for the scanner
- ADR-005 §D2 (secret-boundary design)
- R-06, R-07 in `.aiwg/risks/risk-list.md`
- CLAUDE.md "Public Repo Security" section
- `sad-review-security.md` required change that drove prep-master.sh scope
