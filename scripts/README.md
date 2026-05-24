# Kintsugi USB — Scripts

**Status**: Iteration-1 toolkit shipped; scope amended 2026-05-24 for the Ventoy/persistence build (see `../.aiwg/planning/iteration-001-plan.md`). The first tagged release **v2026.5.0** is gated on the hardware acceptance round-trip ([#37](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/37)).

This directory is the **toolkit half** of Kintsugi USB. Paired with `../docs/`, `../manifest/`, and the (NFS-internal) image, it is what builders use to roll their own Kintsugi USB. The supported entry point is the build wizard **`kintsugi-build`**, which orchestrates every other script. See `../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md` (toolkit scope) and `../.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md` (wizard-first UX).

## Layout

```
scripts/
├── kintsugi-build              # ⭐ build wizard — single-command TUI; orchestrates the pipeline below
├── prep-master.sh              # pre-imaging sanitize (secrets, caches, zero free space)
├── create-image.sh             # package a built ISO/.img → distributable <name>.img.zst + .sha256
├── flash-image.sh              # recipient-facing flasher (verify + dd, anti-pattern guards)
├── verify-image.sh             # post-flash sha256 sanity check
├── generate-manifest.sh        # per-release manifest.json (bundled component SBOM-lite)
├── publish-release.sh          # copy the release set to the warehouse NFS target
├── check-drive-health.sh       # SMART / NVMe / disk-level health (ported from sysops)
├── benchmark-inference.sh      # NFR-1.3/1.4 tok/s measurement (llama.cpp + Ollama)
├── check-runbooks.sh           # runbook human-review gate (R-15)
├── install-hooks.sh            # set core.hooksPath = scripts/hooks
├── secret-patterns.txt         # shared secret-scan patterns (image-time + commit-time)
├── hooks/
│   └── pre-commit              # commit-time secret scan (R-07, #32)
└── usb-toolkit/
    ├── build-custom-iso.sh     # custom Ubuntu live ISO via live-build (ADR-007)
    ├── make-ventoy-image.sh    # assemble the Ventoy .img (bootloader + persistence + ISOs) (#42)
    ├── kintsugi-models         # user-driven model management CLI (ADR-005 §D3)
    ├── kintsugi-frameworks     # agentic-framework toolkit CLI (ADR-006 §D2)
    ├── first-boot-setup.sh     # on-USB first-boot config (paths, services, perms)
    ├── start-ai.sh             # AI stack launcher (manifest-driven; Ollama status)
    └── usb-test-harness.sh     # automated acceptance harness (PASS/FAIL/SKIP/WARN + JSON; TC-6 persistence)
```

`kintsugi-rescue` (rescue-ISO catalog CLI) + `manifest/rescue-isos-recommended.yaml` are in progress ([#35](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/35)).

## Usage — external builders

If you are cloning this repo to build your own Kintsugi USB, the supported path is the **wizard**. See `../docs/toolkit-guide.md` for the full walkthrough and `../docs/wizard-guide.md` for the per-screen reference.

```bash
# Supported path — the wizard orchestrates ISO build → Ventoy assembly → package
./scripts/kintsugi-build                      # interactive TUI (defaults give a working build)
./scripts/kintsugi-build --from-profile p.yaml  # replay a saved profile

# Output: a flashable Ventoy <build>.img.zst + .sha256 (32 GiB persistence by default).
# Models are user-driven: pulled post-flash with `kintsugi-models pull` (ADR-005),
# or optionally pre-bundled at build time via `kintsugi-models pull <slug> --target …/payload/models/`.
```

> **Build status (2026-05-24):** the wizard builds the custom live ISO today; the Ventoy `.img` assembly (`make-ventoy-image.sh`, #42) and 32 GiB persistence (#34) are committed, and wiring them into a single unattended wizard run is in progress ([#36](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/36)). Until that lands, run the assembly + package steps explicitly:

```bash
# Advanced / until #36 auto-chains the wizard:
sudo ./scripts/usb-toolkit/build-custom-iso.sh <build-dir>          # 1. custom live ISO (live-build)
sudo ./scripts/usb-toolkit/make-ventoy-image.sh \
     --kintsugi-iso <build-dir>/*.iso [--rescue-iso <iso> …]        # 2. assemble Ventoy .img + persistence
sudo ./scripts/prep-master.sh <build-dir>                           # 3. sanitize
./scripts/create-image.sh dist/kintsugi-ventoy.img                  # 4. package → .img.zst + .sha256
```

For the **fully manual** Ventoy assembly (install Ventoy by hand, lay out the data partition, create the persistence image) — the under-the-hood procedure that `make-ventoy-image.sh` automates — see `../docs/build-guide.md`.

Signing is **deferred to v1.1** ([#19](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/19)); v1.0 ships sha256-only integrity. Fork maintainers who want to sign their own images can do so with their own minisign key (see `../docs/toolkit-guide.md` §8).

## Git hooks — commit-time secret scan (R-07, #32)

`scripts/hooks/pre-commit` blocks commits that introduce a secret-pattern match,
reusing the same `scripts/secret-patterns.txt` as the image-time scan in
`prep-master.sh`. It inspects only the **added** lines of staged changes and reports
offending files by name (never the secret content, which would leak it to scrollback).

Activate once per clone:

```bash
scripts/install-hooks.sh      # sets core.hooksPath = scripts/hooks
```

A genuine false positive should be fixed by refining the pattern. Bypass
(`git commit --no-verify`) is a last resort and must be justified in the commit body.

## Trust boundaries (per ADR-005 §D5)

- The maintainer's minisign signature (`../kintsugi.pub` when committed in v1.1) attests to the **base image**, **scripts**, and **`manifest/models-recommended.yaml`** as committed in tagged releases.
- It does **not** attest to model weights. Weights are user-pulled and carry the source's (Ollama / HuggingFace / URL) own integrity story.
- External builders signing their own releases use their own minisign key; the maintainer's key is not part of downstream trust chains.

## Conventions

- Bash; POSIX-friendly where practical; `set -euo pipefail` required in new scripts.
- All scripts must pass `shellcheck` with zero error-level findings.
- User-facing scripts print a one-line summary of what they will do + require explicit confirmation for destructive operations (no silent `dd`, no silent partition writes).
- No AI attribution in commit messages (per `../CLAUDE.md`).

## Provenance

The original six scripts were copied from `git.integrolabs.net/roctinam/sysops` on 2026-04-20 and have since been adapted/extended:

| Script | Sysops origin |
|--------|---------------|
| `usb-toolkit/build-custom-iso.sh` | `scripts/usb-toolkit/build-custom-iso.sh` |
| `usb-toolkit/first-boot-setup.sh` | `scripts/usb-toolkit/first-boot-setup.sh` |
| `usb-toolkit/start-ai.sh` | `scripts/usb-toolkit/start-ai.sh` |
| `usb-toolkit/usb-test-harness.sh` | `scripts/usb-toolkit/usb-test-harness.sh` |
| `check-drive-health.sh` | `scripts/check-drive-health.sh` |
| `benchmark-inference.sh` | `scripts/benchmark-inference.sh` |

The sysops `docs/projects/usb-toolkit/README.md` is now a stub redirecting here: **scripts and docs are maintained here; sysops points to us.**
