# Wizard Guide — `scripts/kintsugi-build`

Reference for the Kintsugi USB build wizard. For the narrative introduction see [`README.md`](../README.md) and [ADR-006 §D1](../.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md). The wizard drives the **ADR-008 remaster pipeline** ([ADR-008](../.aiwg/architecture/adr-008-build-tooling-remaster-stock-iso.md) superseded the original `live-build` approach). For the downstream toolkit (`kintsugi-models`, `kintsugi-frameworks`) see [`docs/toolkit-guide.md`](toolkit-guide.md); for flashing and distribution see [`docs/update-strategy.md`](update-strategy.md).

> **Build-tool note (2026-05-25):** This guide documents wizard **v0.2.0 / profile schema v2**, which drives `make-remaster-iso.sh` → `make-ventoy-image.sh` → `create-image.sh`. The earlier `live-build`-based wizard (v0.1.0 / schema v1, `build-custom-iso.sh`, `KINTSUGI_SKIP_*` env vars) is gone — see [ADR-008](../.aiwg/architecture/adr-008-build-tooling-remaster-stock-iso.md).

---

## 1. Overview

`scripts/kintsugi-build` is the single-command entry point for producing a personalized, **flashable** Kintsugi rescue USB. It is a Bash wizard layered on the remaster pipeline. The wizard:

- Collects choices through a whiptail TUI (plain-prompt fallback).
- Persists them to a `build-profile.yaml` for reproducibility and replay.
- **Auto-chains the full pipeline** with no manual steps:
  1. `make-remaster-iso.sh` — remaster a stock Ubuntu/Xubuntu 24.04 ISO (rescue tools + Kintsugi scripts, optionally the agentic CLIs and the offline AI stack).
  2. `make-ventoy-image.sh` — assemble a Ventoy `.img` (bootloader + persistence + the Kintsugi ISO).
  3. `create-image.sh` — compress to a distributable `.img.zst` + `.sha256`.
- Reports the final `.img.zst`, its size, and the flash command.

**What the wizard does not do**:

- It does **not** flash the image to a USB. Flashing is destructive and explicit — see §9.
- It does **not** download models. Per [ADR-005](../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md), model weights are never baked; the wizard only records a post-flash pull hint.
- It does **not** bundle rescue ISOs by default yet (Gitea #35). Add them with `make-ventoy-image.sh --rescue-iso/--rescue-dir`.
- It does **not** install a desktop IDE (VS Code/Copilot). That is a tracked, undecided scope item (Gitea #43); the baked agentic CLIs cover the coding-assistant need.

The wizard is the central iteration-1 deliverable per ADR-006 §D1: a fresh clone + one command → a personalized, flashable `.img.zst`.

---

## 2. Invocation modes

### 2.1 Interactive (default)

```bash
./scripts/kintsugi-build
```

Walks every prompt in §3, shows the summary, then asks "Proceed with the build above?" before running the pipeline.

### 2.2 Replay with confirm — `--from-profile <file>`

```bash
./scripts/kintsugi-build --from-profile ~/kintsugi-builds/<build_name>/build-profile.yaml
```

Loads a saved profile, skips prompts, shows the summary, still asks for confirmation.

### 2.3 Replay without confirm — `--non-interactive <file>`

```bash
./scripts/kintsugi-build --non-interactive ./tests/fixtures/minimal-profile.yaml
```

Replay with **no** confirmation (CI / bats mode). The pipeline's `sudo` stages still need cached credentials or a NOPASSWD sudoers rule.

### 2.4 Dry run — `--dry-run`

```bash
./scripts/kintsugi-build --dry-run
./scripts/kintsugi-build --dry-run --from-profile ./build-profile.yaml
```

Runs the wizard, writes the profile, prints the **exact three-stage pipeline** that would run, and exits before invoking it. The safest way to inspect what a profile does.

### 2.5 Help

```bash
./scripts/kintsugi-build --help
```

Prints the usage, flags, version (wizard `0.2.0`, schema `2`), and key env vars.

---

## 3. Every prompt explained

The interactive prompts run in a fixed order (whiptail, or plain `read` fallback).

### 3.1 Build name

**Question**: *"Short name for this build (used in filenames + output dir)"*
**Default**: `kintsugi-v2026.5.0-$(date +%Y%m%d)`.
**Controls**: the output dir `${KINTSUGI_BUILDS_ROOT}/${build_name}/`, the log/profile paths, and the ISO/`.img`/`.img.zst` filename stems. Keep it shell-safe (no spaces).

### 3.2 Base ISO

**Question**: *"Path to the stock Ubuntu/Xubuntu 24.04 live ISO to remaster"*
**Default**: the newest `*.iso` under `${KINTSUGI_BUILDS_ROOT}/_base/` (or `$KINTSUGI_BASE_ISO`).
**Controls**: `--base` for `make-remaster-iso.sh`. This is the **new ADR-008 input** — the bootable base whose boot structure (BIOS + UEFI) the remaster preserves. Download + verify it separately (see [`docs/build-guide.md`](build-guide.md)). Xubuntu-minimal is recommended (it provides the XFCE desktop + casper live session the remaster builds on).

### 3.3 Offline AI (Ollama)

**Question**: *"Pre-install the offline LLM runtime (Ollama + mikefarah yq)?"*
**Default**: Yes.
**Controls**: `--with-ai-stack`. Installs Ollama (the drive's headline offline-inference feature; ADR-005 §D2) and mikefarah `yq` (the runtime dependency of `kintsugi-models`/`kintsugi-frameworks`). Adds ~2.5 GB. Models are **never** baked — you pull them post-flash. The Ollama installer is sha256-pinned (supply-chain guard, #40).

### 3.4 Agentic CLIs

**Question**: *"Pre-install the AIWG-supported agentic coding CLIs?"*
**Default**: Yes.
**Controls**: `--with-agentic`. Bakes the five AIWG-supported CLI providers — **claude-code, codex, opencode, copilot, openclaw** (npm globals on Node 22) — plus **aider** (pipx). All offline-available after build; you sign in with your own credentials post-flash (no auth is ever baked — ADR-006 §D5). `hermes` is **not** baked (per-user `curl|bash` install); run `kintsugi-install-hermes` in the live session if you want it. The VS Code/IDE option is deferred (#43).

### 3.5 Persistence size

**Question**: *"Ventoy persistence size in GiB (holds /data across reboots; #34)"*
**Default**: `32`.
**Controls**: `--persistence-size` for `make-ventoy-image.sh`. The Ventoy persistence `.dat` bound to the Kintsugi ISO.

### 3.6 Post-flash model hint

**Question**: *"Suggest pulling starter models (qwen3.5:4b, qwen3.5:9b) after first boot?"*
**Default**: Yes.
**Controls**: `models_post_flash` — informational only. Printed post-build as `kintsugi-models pull <slug>` hints. Never affects image contents (ADR-005).

### 3.7 Signing

**Question**: *"Enable minisign? (deferred to v1.1; sha256 is always produced)"*
**Default**: No.
**Controls**: `signing.enabled` — recorded for the future v1.1 minisign flow; not consumed in v1.0. sha256 is always produced by `create-image.sh`. See [`SECURITY.md`](../SECURITY.md).

### 3.8 Final confirmation

`show_summary` prints the build plan + the full three-stage pipeline. Interactive and `--from-profile` modes gate on a final "Proceed?" (default yes); `--non-interactive` and `--dry-run` skip it.

---

## 4. Profile YAML schema reference (v2)

Profiles are written by `write_profile()` and read by `read_profile()` (mikefarah/yq). Current schema: **v2**.

### 4.1 Minimal profile

```yaml
schema_version: 2
build_name: "kintsugi-minimal"
base_iso: ""            # empty → auto-detect newest *.iso under _base/
include_agentic: false
include_ai_stack: false
persistence_gib: 32
models_post_flash: []
signing:
  enabled: false
```

This produces a bare rescue ISO: rescue tools + Kintsugi scripts only, no agentic CLIs, no Ollama.

### 4.2 Full profile (every field)

```yaml
# Kintsugi USB build profile — schema v2
schema_version: 2
generated_by: "kintsugi-build 0.2.0"
generated_at: "2026-05-25T14:30:00-04:00"

build_name: "kintsugi-v2026.5.0-20260525"
base_iso: "/home/you/kintsugi-builds/_base/xubuntu-24.04.4-minimal-amd64.iso"
include_agentic: true     # claude-code, codex, opencode, copilot, openclaw, aider
include_ai_stack: true    # Ollama + mikefarah yq
persistence_gib: 32
models_post_flash: ["qwen3.5:4b", "qwen3.5:9b"]
signing:
  enabled: false
  # v1.0 ships sha256-only (ADR-006 §D5). Set true once v1.1 minisign lands.
```

### 4.3 Field reference

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `schema_version` | int | `2` | Rejected if it doesn't match the wizard's `SCHEMA_VERSION`. |
| `generated_by` / `generated_at` | string | auto | Informational. |
| `build_name` | string | `kintsugi-v2026.5.0-YYYYMMDD` | Build dir + artifact filename stem. |
| `base_iso` | string | `""` (auto-detect) | Stock ISO to remaster (`--base`). Empty → newest `*.iso` under `_base/`. |
| `include_agentic` | bool | `true` | → `--with-agentic` (5 AIWG CLIs + aider). |
| `include_ai_stack` | bool | `true` | → `--with-ai-stack` (Ollama + yq). |
| `persistence_gib` | int | `32` | → `--persistence-size` (#34). |
| `models_post_flash[]` | string list | `["qwen3.5:4b","qwen3.5:9b"]` | Post-build `kintsugi-models pull` hints. Not baked. |
| `signing.enabled` | bool | `false` | Reserved for v1.1 minisign. |

---

## 5. Environment variables

All inputs — there are no `KINTSUGI_SKIP_*` exports anymore (those were live-build chroot-hook knobs; the remaster builder takes flags).

| Var | Default | Effect |
|-----|---------|--------|
| `KINTSUGI_BUILDS_ROOT` | `$HOME/kintsugi-builds` | Parent dir for build subdirectories. |
| `KINTSUGI_BASE_ISO` | newest `*.iso` under `_base/` | Stock base ISO to remaster. |
| `KINTSUGI_LIVEFS_EDIT` | `$BUILDS_ROOT/_tools/livefs-venv/bin/livefs-edit` | Path to the `livefs-edit` entry point (ADR-008). |
| `KINTSUGI_VENTOY_BIN` | first `Ventoy2Disk.sh` under `_ventoy/`, else PATH | Ventoy installer used by the assembly stage. |

```bash
KINTSUGI_BUILDS_ROOT=/mnt/nvme1/kintsugi-builds \
KINTSUGI_BASE_ISO=/isos/xubuntu-24.04.4-minimal-amd64.iso \
  ./scripts/kintsugi-build
```

---

## 6. Output layout

After a successful build:

```text
$KINTSUGI_BUILDS_ROOT/<build_name>/
├── build-profile.yaml          # Replay with --from-profile
├── build.log                   # Full pipeline output (tee'd)
├── <build_name>.iso            # Remastered Kintsugi live ISO (BIOS + UEFI bootable)
├── <build_name>-ventoy.img     # Assembled Ventoy disk image (bootloader + persistence)
├── <build_name>.img.zst        # Distributable compressed image  ← flash this
└── <build_name>.sha256         # Checksum of the .img.zst
```

The wizard prints the `.img.zst` path, size, and the flash command at the end.

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Missing prerequisites: livefs-edit (...)` | `livefs-edit` not installed/at the expected path | Install per [ADR-008](../.aiwg/architecture/adr-008-build-tooling-remaster-stock-iso.md), or set `KINTSUGI_LIVEFS_EDIT`. |
| `Missing prerequisites: Ventoy2Disk.sh` | Ventoy not found | Set `KINTSUGI_VENTOY_BIN` or place a Ventoy release under `$BUILDS_ROOT/_ventoy`. |
| `Missing prerequisites: squashfs-tools / xorriso / zstd` | Host toolchain incomplete | `sudo apt-get install -y squashfs-tools xorriso zstd`. |
| `mikefarah/yq required to parse profile` | Wrong yq (Ubuntu ships python-yq) | `sudo wget -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq`. Verify `yq --version` says "mikefarah". |
| `Only N GB free ... (recommended: 30+ GB)` | Disk space low | The 6 GB ISO + ~16 GB `.img` + `.img.zst` need headroom. Clear space or set `KINTSUGI_BUILDS_ROOT` to a larger filesystem. |
| Build halts at a sudo password prompt | Stages 1-2 use `sudo` | Cache credentials or configure NOPASSWD for the builder; or run `--dry-run` for tests that shouldn't build. |
| Ollama not installed (build log: `✗ Ollama install script failed`) | Network unavailable at build time, or upstream installer changed (sha mismatch) | Ollama is fetched on demand; ensure network. On a sha mismatch, review the new upstream installer and update the pin. Build continues without it (non-fatal). |
| `Build pipeline FAILED (exit N). See ...` | A stage failed | Full output is in `build.log`. Common: apt/npm network (rerun), or a remaster/livefs-edit error. |
| Profile replay fails with `schema_version=X (expected 2)` | Profile from a different wizard version | Re-create the profile with this wizard (schema v2). v1 profiles are not compatible. |

---

## 8. Example: non-interactive CI-style build

### 8.1 Fixture profile

```yaml
schema_version: 2
build_name: "kintsugi-ci-minimal"
base_iso: ""
include_agentic: false
include_ai_stack: false
persistence_gib: 8
models_post_flash: []
signing:
  enabled: false
```

### 8.2 Dry-run smoke test (no build, no sudo)

```bash
export KINTSUGI_BUILDS_ROOT="${CI_ARTIFACTS}/kintsugi-builds"
KINTSUGI_BASE_ISO=/isos/xubuntu-24.04.4-minimal-amd64.iso \
  ./scripts/kintsugi-build --dry-run --non-interactive ci/fixtures/kintsugi-ci-minimal.yaml
# Asserts: exit 0, prints the 3-stage pipeline, writes build-profile.yaml.
```

A full build additionally needs the remaster toolchain (`livefs-edit`, Ventoy, `squashfs-tools`, `xorriso`, `zstd`) and passwordless sudo for stages 1-2. The offline bats suite uses `--dry-run` to avoid both.

---

## 9. What comes after the wizard

The wizard hands off a finished `<build_name>.img.zst` + `.sha256` — no separate packaging step (it auto-chains `create-image.sh`).

### 9.1 Flash it (DESTRUCTIVE — verify the device by serial!)

```bash
zstd -dc ~/kintsugi-builds/<build_name>/<build_name>.img.zst \
  | sudo dd of=/dev/sdX bs=4M status=progress oflag=direct conv=fsync
```

Pick the correct `/dev/sdX` — confirm by serial (`lsblk -o NAME,SERIAL,TRAN,SIZE`) and that it is removable, never an internal disk. After flashing, verify the on-drive Kintsugi ISO sha256 against the source if in doubt.

### 9.2 Distribution

Publish the `.img.zst` + `.sha256` as a Gitea release (sha256-only trust model for v1.0; signed releases arrive with v1.1 minisign — #19). See [`docs/release-process.md`](release-process.md) and ADR-006 §D4.

---

## 10. Versioning notes

- **Wizard version**: `VERSION="0.2.0"` in `scripts/kintsugi-build` — tracks the wizard's own behavior. The ADR-008 rewire (live-build → remaster, new flag/option contract) is the `0.2.0` minor.
- **Profile schema**: `SCHEMA_VERSION=2`. `read_profile()` hard-fails on a mismatch. v1 profiles (live-build era) are **not** compatible — the option model changed (`include_vscode`/`include_ollama`/`frameworks` → `include_agentic`/`include_ai_stack`/`base_iso`).
- **Product version**: Kintsugi USB uses **CalVer** (`YYYY.M.PATCH`; first release v2026.5.0), independent of the wizard semver.
- **When you bump the schema**: update `SCHEMA_VERSION`, the `write_profile()` header, this guide, and provide a migrator or document the manual edits.

---

## Cross-references

- [ADR-008 — Remaster the stock Ubuntu ISO](../.aiwg/architecture/adr-008-build-tooling-remaster-stock-iso.md) — the build-tool the wizard now drives.
- [ADR-006 §D1 — Wizard-first UX](../.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md) — design rationale.
- [ADR-005 — User-driven model loading](../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md) — why model weights are never baked.
- [`docs/build-guide.md`](build-guide.md) — manual/reference build (base-ISO acquisition + verification).
- [`docs/toolkit-guide.md`](toolkit-guide.md) — `kintsugi-models`, `kintsugi-frameworks`, and the remaster/assembly scripts.
- [`SECURITY.md`](../SECURITY.md) — trust boundary and the sha256-only v1.0 model.
- Gitea **#43** (offline-AI/IDE scope) · **#36** (wizard rewire) · **#34** (persistence) · **#42** (Ventoy assembly) · **#35** (rescue catalog) · **#37** (hardware acceptance).
