# Wizard Guide — `scripts/kintsugi-build`

Reference for the Kintsugi USB build wizard. This document assumes you have already run the wizard at least once; for the narrative introduction see [`README.md`](../README.md) and [ADR-006 §D1](../.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md). For the downstream toolkit (`kintsugi-models`, `kintsugi-frameworks`, `build-custom-iso.sh`) see [`docs/toolkit-guide.md`](toolkit-guide.md). For flashing and distributing the resulting ISO, see [`docs/update-strategy.md`](update-strategy.md) and the post-build tooling (`flash-image.sh`, `prep-master.sh`, `create-image.sh`, `publish-release.sh`).

---

## 1. Overview

`scripts/kintsugi-build` is the single-command entry point for producing a personalized Kintsugi rescue-USB master ISO. It is a Bash wizard (~455 lines) layered on top of `scripts/usb-toolkit/build-custom-iso.sh`. The wizard's job is to:

- Collect user choices through a whiptail TUI (with plain-prompt fallback).
- Persist those choices to a `build-profile.yaml` for reproducibility and replay.
- Export the correct `KINTSUGI_*` environment variables.
- Invoke `build-custom-iso.sh` under `sudo -E`, piping output to a build log.
- Report the resulting ISO, its size, and a sha256 digest at the end.

**What the wizard does not do**:

- It does **not** flash the ISO to a USB device. That is `scripts/flash-image.sh`'s job (direct `dd` path).
- It does **not** package the ISO for distribution. That pipeline is `prep-master.sh` → `create-image.sh` → `generate-manifest.sh` → `publish-release.sh` (see §9).
- It does **not** download models. Per ADR-005, model weights are never baked into the ISO. The wizard only records a post-flash pull hint for the user.
- It does **not** install agentic-framework binaries itself; `build-custom-iso.sh` runs the per-framework recipe from `manifest/agentic-frameworks-recommended.yaml` inside the chroot.

The wizard is the central iteration-1 deliverable per ADR-006 §D1: "a user with a fresh clone of this repo and a blank USB runs one command, gets guided through choices, and ends up with a personalized master USB ready to image."

---

## 2. Invocation modes

The wizard supports four modes: interactive (default), replay with confirm, replay without confirm, and dry run.

### 2.1 Interactive (default)

```bash
./scripts/kintsugi-build
```

Walks every prompt in §3 and, after showing the summary, asks "Proceed with the build above?" before invoking the builder.

### 2.2 Replay with confirm — `--from-profile <file>`

```bash
./scripts/kintsugi-build --from-profile ~/kintsugi-builds/kintsugi-v2026.5.0-20260420/build-profile.yaml
```

Loads an existing YAML profile, skips all prompts, shows the summary, and still asks for confirmation. Useful for "same build as last time" iteration without re-answering every question.

### 2.3 Replay without confirm — `--non-interactive <file>`

```bash
./scripts/kintsugi-build --non-interactive ./ci/fixtures/minimal-profile.yaml
```

Replay with **no** confirmation prompt. This is the CI / bats mode. The wizard still prints its summary to stdout, but proceeds to `run_build` immediately. Note that `sudo -E` will still prompt for a password unless you have cached credentials or an explicit sudoers rule.

### 2.4 Dry run — `--dry-run`

```bash
./scripts/kintsugi-build --dry-run
./scripts/kintsugi-build --dry-run --from-profile ./build-profile.yaml
```

Runs the wizard (either interactively or from profile), writes the profile YAML, prints the exact build command that would be run (including all env vars), and exits before calling `build-custom-iso.sh`. Combine with `--from-profile` for fully deterministic "show me what this profile does" output.

### 2.5 Help

```bash
./scripts/kintsugi-build --help
```

Prints invocation summary, flag list, version (wizard `0.1.0`, schema version `1`), and the `KINTSUGI_BUILDS_ROOT` env var default.

---

## 3. Every prompt explained

The six interactive prompts run in a fixed order. Each is rendered with whiptail when available; otherwise a plain-text `read` prompt. The table in each subsection notes the default and the downstream effect.

### 3.1 Build name

**Question**: *"Short name for this build (used in ISO filename + output dir)"*
**Default**: `kintsugi-v2026.5.0-$(date +%Y%m%d)` — e.g. `kintsugi-v2026.5.0-20260420`.
**Controls**: The output directory at `${KINTSUGI_BUILDS_ROOT}/${build_name}/`, the log path, the profile path, and the final ISO filename stem. Keep it shell-safe — no spaces.

### 3.2 AI runtimes (checklist)

**Question**: *"Which local AI runtimes to include? (both recommended)"*
**Options**:

| Tag | Description | Default |
|-----|-------------|---------|
| `llama_cpp` | llama.cpp — direct GGUF execution | ON |
| `ollama` | Ollama — model-management CLI + OpenAI-compat API | ON |

**Controls**: Only the `ollama` selection flows through to `PROFILE_INCLUDE_OLLAMA` (→ `KINTSUGI_SKIP_OLLAMA=0|1`). The `llama_cpp` tag is **informational only** in v1.0 — `llama-server` is always installed so the ISO always has an offline-capable runtime. Deselecting `llama_cpp` is a no-op today; the option exists so the prompt communicates the composition honestly.

### 3.3 VS Code + Copilot + `gh`

**Question**: *"Include VS Code + GitHub Copilot extension + gh CLI? Note: Copilot requires a paid GitHub subscription, signed in post-flash. Telemetry is disabled by default."*
**Default**: Yes.
**Controls**: `PROFILE_INCLUDE_VSCODE` → `KINTSUGI_SKIP_IDE=0|1`. When enabled, `build-custom-iso.sh` installs VS Code from Microsoft's apt repo inside the chroot, preinstalls the Copilot extension globally, installs `gh`, and drops a telemetry-disabled `/etc/skel/.config/Code/User/settings.json`. See ADR-006 §D3.

### 3.4 Agentic frameworks (checklist)

**Question**: *"Which agentic frameworks to install at build time? Recommended (v1.0-tested): aider (open), claude-code (EULA), codex-cli (EULA). None = user installs post-flash via: `kintsugi-frameworks install <name>`"*

| Tag | Description | Default |
|-----|-------------|---------|
| `aider` | Aider — Apache-2.0, BYO-API-key | **ON** |
| `claude-code` | Claude Code CLI — Anthropic EULA | OFF |
| `codex-cli` | OpenAI Codex CLI — OpenAI EULA | OFF |

**Why Aider is default ON and the other two are default OFF**: Aider is Apache-2.0 and has no EULA click-through at install time; it is safe to bake into a shareable ISO. Claude Code and Codex CLI both ship under vendor EULAs that the *user* accepts. We don't pre-accept EULAs on the user's behalf, per the ADR-006 §D2 "user-driven frameworks" principle. The wizard still offers them because installing them at build time is faster than post-flash, but the default is to let the user opt in consciously.

**Controls**: `PROFILE_FRAMEWORKS` → `KINTSUGI_FRAMEWORKS` (space-separated list). `build-custom-iso.sh` looks each tag up in `manifest/agentic-frameworks-recommended.yaml` and runs the recipe in the chroot. An empty list means "install nothing; user runs `kintsugi-frameworks install <name>` post-flash."

### 3.5 Post-flash model hint

**Question**: *"Model weights are NEVER baked into the ISO (per ADR-005 user-driven-loading). The wizard can print a post-flash pull suggestion. Suggest pulling recommended starter models (qwen3.5:4b, qwen3.5:9b) after first boot?"*
**Default**: Yes.
**Controls**: `PROFILE_MODELS_POST_FLASH` — purely informational. Written to the profile YAML and printed at the end of a successful build as `kintsugi-models pull <slug>` suggestions. Does not affect the ISO contents.

### 3.6 Signing

**Question**: *"Full minisign signing is deferred to v1.1 per ADR-006 §D5. sha256 checksums are always produced alongside the ISO. Enable minisign anyway? (requires minisign installed + your keypair configured)"*
**Default**: No (for v1.0).
**Controls**: `PROFILE_SIGN_RELEASE` — today this is recorded in the profile but not consumed by `build-custom-iso.sh`. When the v1.1 signing flow lands, `publish-release.sh` will honor this flag. For v1.0, rely on the sha256 printed at the end of the build and captured in `*.iso.sha256` by `create-image.sh` downstream. See [`SECURITY.md`](../SECURITY.md) for the sha256-only trust model.

### 3.7 Final confirmation

After all prompts, `show_summary` prints the build plan (build name, output dir, all selections, and the full build command + env vars). In interactive and `--from-profile` modes, a final yes/no "Proceed with the build above?" (default yes) gates the invocation. `--non-interactive` and `--dry-run` skip this gate.

---

## 4. Profile YAML schema reference

Profiles are written by `write_profile()` and read by `read_profile()`. Both use mikefarah/yq. The current schema is **v1**.

### 4.1 Minimal profile

```yaml
schema_version: 1
build_name: "kintsugi-minimal"
include_vscode: false
include_ollama: false
frameworks: []
models_post_flash: []
signing:
  enabled: false
```

This produces a bare ISO: llama-server only, no VS Code, no frameworks, no post-flash hints.

### 4.2 Full profile (every field)

```yaml
# Kintsugi USB build profile — schema v1
schema_version: 1
generated_by: "kintsugi-build 0.1.0"
generated_at: "2026-04-20T14:30:00-04:00"

build_name: "kintsugi-v2026.5.0-20260420"
include_vscode: true
include_ollama: true
ollama_version: "latest"
yq_version: "v4.44.3"
frameworks: ["aider", "claude-code"]
models_post_flash: ["qwen3.5:4b", "qwen3.5:9b"]
signing:
  enabled: false
  # v1.0 ships sha256-only (ADR-003 amended, ADR-006 §D5).
  # Set enabled: true once v1.1 minisign flow lands.
```

### 4.3 Field reference

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `schema_version` | int | `1` | Rejected if it doesn't match the wizard's built-in `SCHEMA_VERSION`. Bump when the schema changes. |
| `generated_by` | string | auto | `kintsugi-build <version>` — informational. |
| `generated_at` | ISO-8601 string | auto | Timestamp of profile write. |
| `build_name` | string | `kintsugi-v2026.5.0-YYYYMMDD` | Build directory + ISO filename stem. |
| `include_vscode` | bool | `true` | Maps to `KINTSUGI_SKIP_IDE` (inverted). |
| `include_ollama` | bool | `true` | Maps to `KINTSUGI_SKIP_OLLAMA` (inverted). |
| `ollama_version` | string | `"latest"` | Pinned to `KINTSUGI_OLLAMA_VERSION`. |
| `yq_version` | string | `"v4.44.3"` | Pinned to `KINTSUGI_YQ_VERSION`. |
| `frameworks[]` | string list | `["aider"]` | Joined with spaces into `KINTSUGI_FRAMEWORKS`. |
| `models_post_flash[]` | string list | `["qwen3.5:4b", "qwen3.5:9b"]` | Printed post-build as `kintsugi-models pull` hints. Not consumed by the builder. |
| `signing.enabled` | bool | `false` | Reserved for v1.1 minisign flow. Recorded but not acted on in v1.0. |

When editing a profile by hand, ensure the list syntax uses double-quoted strings inside square brackets (the wizard emits this shape; yq accepts block lists too, but the round-trip safest form is inline).

---

## 5. Environment variables

### 5.1 Respected (input) — from user environment

| Var | Default | Effect |
|-----|---------|--------|
| `KINTSUGI_BUILDS_ROOT` | `$HOME/kintsugi-builds` | Parent directory where each build's subdirectory lives. Set this to e.g. `/mnt/scratch/kintsugi-builds` if `$HOME` is tight on space. |
| `KINTSUGI_OLLAMA_VERSION` | `latest` | Pinned Ollama version; overrideable in profile. |
| `KINTSUGI_YQ_VERSION` | `v4.44.3` | Pinned mikefarah/yq version used inside the chroot. |

Example:

```bash
KINTSUGI_BUILDS_ROOT=/mnt/nvme1/kintsugi-builds ./scripts/kintsugi-build
```

### 5.2 Exported (output) — passed to `build-custom-iso.sh`

The wizard always exports these before `sudo -E "$BUILD_SCRIPT" "$build_dir"`:

| Var | Derived from | Notes |
|-----|--------------|-------|
| `KINTSUGI_FRAMEWORKS` | `PROFILE_FRAMEWORKS` | Space-separated list, e.g. `"aider claude-code"`. Empty string is valid. |
| `KINTSUGI_SKIP_IDE` | `PROFILE_INCLUDE_VSCODE` | `0` = install VS Code + Copilot + `gh`; `1` = skip. |
| `KINTSUGI_SKIP_OLLAMA` | `PROFILE_INCLUDE_OLLAMA` | `0` = install Ollama; `1` = skip (llama-server is always installed). |
| `KINTSUGI_OLLAMA_VERSION` | `PROFILE_OLLAMA_VERSION` | String, `latest` or `vX.Y.Z`. |
| `KINTSUGI_YQ_VERSION` | `PROFILE_YQ_VERSION` | yq version for in-chroot manifest parsing. |

The dry-run output prints the complete exported command, so you can copy-paste it to run manually with added flags or under a wrapper (e.g. `time`).

---

## 6. Output layout

After a successful build:

```text
$KINTSUGI_BUILDS_ROOT/<build_name>/
├── build-profile.yaml      # The profile the wizard wrote (replay with --from-profile)
├── build.log               # Full stdout+stderr from build-custom-iso.sh (tee'd)
├── <build_name>.iso        # The Live ISO (or .hybrid.iso — live-build names vary)
└── ...live-build artifacts # cache/, chroot/, binary/ (can be cleaned post-build)
```

After a successful build, the wizard prints the ISO path, size, and sha256, plus a ready-to-run command to save the sha256 next to the ISO:

```bash
echo '<sha>  <basename>.iso' > <path>.iso.sha256
```

Later stages (distribution packaging) add:

```text
├── <build_name>.iso.sha256 # Saved checksum (by the user or by create-image.sh)
└── <build_name>.img.zst    # Compressed distributable image (create-image.sh)
```

Once [`create-image.sh`](../scripts/create-image.sh) and [`generate-manifest.sh`](../scripts/generate-manifest.sh) land, they write their artifacts into the same build directory. [`publish-release.sh`](../scripts/publish-release.sh) then pushes to the NFS warehouse per ADR-006 §D4.

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Missing prerequisites: live-build` | `lb` not in PATH | `sudo apt-get install -y live-build` |
| `whiptail not installed — falling back to plain prompts` | whiptail missing | Non-fatal; wizard continues with `read -rp`. Install with `sudo apt-get install -y whiptail` for the TUI experience. |
| `mikefarah/yq required to parse profile` | Wrong yq installed | Ubuntu's `apt install yq` ships the Python Go-yq alternative, not mikefarah's. Install the binary from GitHub: `sudo wget -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq`. Verify with `yq --version` — must say "mikefarah". |
| `Only N GB free at $BUILDS_ROOT (recommended: 20+ GB)` warning | Disk space under 20 GB | The wizard continues but live-build may fail mid-chroot. Clear space or set `KINTSUGI_BUILDS_ROOT` to a larger filesystem. |
| Build halts at sudo password prompt | Interactive `sudo -E` | The wizard uses `sudo -E` to preserve env vars. If running under `--non-interactive` from CI, configure NOPASSWD sudoers for the builder user or run the whole wizard under sudo. |
| `Build FAILED (exit N). See $log for details.` | live-build / chroot error | Full output is in `build.log`. Common causes: apt network failure (transient — rerun), Microsoft repo key install failure in chroot (retry or disable VS Code), broken agentic-framework install recipe (check the manifest entry). |
| ISO built but filename says `.hybrid.iso` instead of `.iso` | live-build output name variation | Non-fatal. The wizard's `find` picks up both. Rename if you prefer a consistent extension. |
| Profile replay fails with `schema_version=X (expected 1)` | Profile produced by a future wizard | Rebuild the profile with the matching wizard version, or update the wizard. See §10 on schema bumps. |

For failures inside the chroot (Cubic-like issues — packages failing to configure, dpkg errors), inspect `build.log` around the failing stage and cross-reference with `scripts/usb-toolkit/build-custom-iso.sh`'s step comments. See [`docs/toolkit-guide.md`](toolkit-guide.md) for per-step debugging.

---

## 8. Example: fully non-interactive CI-style build

This is the shape a bats test or CI job uses. A profile is committed as a fixture; the wizard is invoked with `--non-interactive`; the build runs end-to-end.

### 8.1 Fixture profile — `ci/fixtures/kintsugi-ci-minimal.yaml`

```yaml
schema_version: 1
build_name: "kintsugi-ci-$(BUILD_ID)"
include_vscode: false
include_ollama: false
ollama_version: "latest"
yq_version: "v4.44.3"
frameworks: []
models_post_flash: []
signing:
  enabled: false
```

### 8.2 CI driver script

```bash
#!/usr/bin/env bash
set -euo pipefail

export KINTSUGI_BUILDS_ROOT="${CI_ARTIFACTS}/kintsugi-builds"
mkdir -p "$KINTSUGI_BUILDS_ROOT"

# Substitute BUILD_ID into the fixture
BUILD_ID="${CI_PIPELINE_ID:-local}"
sed "s/\$(BUILD_ID)/${BUILD_ID}/" \
    ci/fixtures/kintsugi-ci-minimal.yaml \
    > "${KINTSUGI_BUILDS_ROOT}/profile.yaml"

# Run the wizard non-interactively
./scripts/kintsugi-build --non-interactive "${KINTSUGI_BUILDS_ROOT}/profile.yaml"

# Verify ISO exists and compute sha256 for the pipeline
ISO=$(find "${KINTSUGI_BUILDS_ROOT}/kintsugi-ci-${BUILD_ID}" -maxdepth 1 -name '*.iso' | head -1)
[ -f "$ISO" ] || { echo "No ISO produced"; exit 1; }
sha256sum "$ISO" > "${ISO}.sha256"
```

### 8.3 Bats-style test sketch

```bash
@test "wizard produces an ISO from a minimal profile" {
    export KINTSUGI_BUILDS_ROOT="${BATS_TEST_TMPDIR}/builds"
    run ./scripts/kintsugi-build --dry-run \
        --non-interactive tests/fixtures/minimal-profile.yaml
    [ "$status" -eq 0 ]
    [ -f "${KINTSUGI_BUILDS_ROOT}/kintsugi-test/build-profile.yaml" ]
}
```

Note that `--non-interactive` still invokes `sudo -E`; CI runners need passwordless sudo for the `lb` toolchain. Use `--dry-run` for tests that shouldn't actually build.

---

## 9. What comes after the wizard

The wizard hands off at a single `.iso` file in the build directory. Two downstream paths exist:

### 9.1 Direct flash (fastest for personal use)

```bash
sudo ./scripts/flash-image.sh \
    ~/kintsugi-builds/kintsugi-v2026.5.0-20260420/kintsugi-v2026.5.0-20260420.iso \
    /dev/sdX
```

This is destructive — the target USB is overwritten. `flash-image.sh` does device sanity checks, size checks, and a post-flash sha256 verification. See its `--help`.

### 9.2 Distribution pipeline (for sharing a signed / hash-verified image)

```bash
./scripts/prep-master.sh      <build-dir>   # Sanitize the build for redistribution
./scripts/create-image.sh     <build-dir>   # Compress to .img.zst + sha256
./scripts/generate-manifest.sh <build-dir>  # Write a release manifest JSON
./scripts/publish-release.sh  <build-dir>   # Push to NFS warehouse (ADR-006 §D4)
```

See [`docs/update-strategy.md`](update-strategy.md) for the update cadence and [ADR-006 §D4](../.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md) for the NFS publish target.

---

## 10. Versioning notes

- **Wizard version**: `VERSION="0.1.0"` in `scripts/kintsugi-build`. This tracks the wizard's own behavior, not the Kintsugi USB product version.
- **Product version**: Kintsugi USB uses **CalVer** (`YYYY.M.PATCH`; first release v2026.5.0) — independent of the wizard's own semver. A wizard bugfix is a `0.1.x` patch; a new prompt or changed env-var contract is a `0.2.0` minor; a breaking profile-schema change is a `1.0.0` major. The default build name tracks the product (release) version, e.g. `kintsugi-v2026.5.0-YYYYMMDD`.
- **Profile schema version**: `SCHEMA_VERSION=1`. `read_profile()` hard-fails when the profile's `schema_version` doesn't match. Bump this field when:
  - A new required field is added.
  - An existing field's meaning changes (e.g. `include_vscode` becomes a checklist).
  - A field is removed or renamed.
- **Optional-field additions** don't require a schema bump — `read_profile()` uses `yq eval '.field // "default"'` for backward-compatible defaults (`ollama_version`, `yq_version` already work this way).
- **When you bump the schema**: update `SCHEMA_VERSION`, update the emitted header in `write_profile()`, add a migration note to this guide, and provide a one-shot migrator (or document the manual edits) for existing profiles.

---

## Cross-references

- [ADR-006 §D1 — Wizard-first UX](../.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md) — the design rationale for this script.
- [ADR-005 — User-driven loading pattern for models](../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md) — why model weights are never baked in.
- [ADR-003 — Verification rigor](../.aiwg/architecture/adr-003-verification-rigor.md) — sha256 trust model for v1.0.
- [`docs/toolkit-guide.md`](toolkit-guide.md) — `kintsugi-models`, `kintsugi-frameworks`, `build-custom-iso.sh` internals.
- [`docs/update-strategy.md`](update-strategy.md) — distribution cadence and release pipeline.
- [`SECURITY.md`](../SECURITY.md) — trust boundary and tamper-reporting.
- [`manifest/agentic-frameworks-recommended.yaml`](../manifest/agentic-frameworks-recommended.yaml) — framework install recipes.
- [`manifest/models-recommended.yaml`](../manifest/models-recommended.yaml) — starter model list referenced by the post-flash hint.
