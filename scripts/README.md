# Kintsugi USB — Scripts

**Status**: Initial port from `roctinam/sysops` (commit snapshot 2026-04-20) + iteration-1 deliverables per ADR-005 pending.

This directory is the **toolkit half** of Kintsugi USB. Paired with `../docs/`, `../manifest/`, and the signed base image, it's what external builders use to roll their own Kintsugi-like USB. See `../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md` for the product-surface decision.

## Layout

```
scripts/
├── README.md                    # this file
├── check-drive-health.sh        # ported from sysops — SMART / NVMe / disk-level health
├── benchmark-inference.sh       # ported from sysops — NFR-1.3/1.4 measurement (llama.cpp + Ollama tok/s)
└── usb-toolkit/
    ├── build-custom-iso.sh      # ported — Cubic-driven custom Ubuntu ISO build
    ├── first-boot-setup.sh      # ported — on-USB first-boot config (paths, services, perms)
    ├── start-ai.sh              # ported — AI stack launcher (needs refactor per ADR-005 §D3)
    └── usb-test-harness.sh      # ported — 527-line automated test harness (PASS/FAIL/SKIP/WARN + JSON)
```

> **Note:** the layout above and the status/net-new tables below predate the shipped
> iteration-1 scripts and are stale — the imaging pipeline (`prep-master.sh`,
> `create-image.sh`, `flash-image.sh`, `verify-image.sh`, `publish-release.sh`),
> the `kintsugi-build` wizard, and the `kintsugi-models` / `kintsugi-frameworks`
> CLIs all exist now. A dedicated docs pass will refresh this file.

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

## Provenance

All six scripts were copied from `git.integrolabs.net/roctinam/sysops` on 2026-04-20:

| Script | Sysops path |
|--------|-------------|
| `usb-toolkit/build-custom-iso.sh` | `scripts/usb-toolkit/build-custom-iso.sh` |
| `usb-toolkit/first-boot-setup.sh` | `scripts/usb-toolkit/first-boot-setup.sh` |
| `usb-toolkit/start-ai.sh` | `scripts/usb-toolkit/start-ai.sh` |
| `usb-toolkit/usb-test-harness.sh` | `scripts/usb-toolkit/usb-test-harness.sh` |
| `check-drive-health.sh` | `scripts/check-drive-health.sh` |
| `benchmark-inference.sh` | `scripts/benchmark-inference.sh` |

The sysops `docs/projects/usb-toolkit/README.md` is now a stub that redirects back here. The content migration is authoritative in this direction: **scripts and docs are maintained here; sysops points to us.**

## Status per script

| Script | State | Iteration-1 action |
|--------|-------|---------------------|
| `usb-toolkit/build-custom-iso.sh` | Ported as-is | Review + light adapt (paths, version strings); no refactor |
| `usb-toolkit/first-boot-setup.sh` | Ported as-is | Adapt to reference `/data/models/user/` per ADR-005 |
| `usb-toolkit/start-ai.sh` | Ported as-is | **Refactor**: add Ollama status reporting + manifest-driven model discovery per ADR-005 §D3 |
| `usb-toolkit/usb-test-harness.sh` | Ported as-is | Review + adopt as v1.0 acceptance tool; extend with kintsugi-models tests |
| `check-drive-health.sh` | Ported as-is | Retain; may invoke from usb-test-harness |
| `benchmark-inference.sh` | Ported as-is | Retain; wire into NFR-1.3/1.4 verification |

## Iteration-1 net-new scripts (per `.aiwg/planning/iteration-001-plan.md`)

These do **not** exist yet. They are the iteration-1 deliverables layered on top of the ports.

| Planned script | Purpose | Driver |
|----------------|---------|--------|
| `usb-toolkit/kintsugi-models` | Model-management CLI (list/add/pull/remove/verify) | ADR-005 §D3 |
| `prep-master.sh` | Sanitize secrets, zero free space, flush caches on master USB | sad-review-security.md |
| `create-image.sh` | `dd | zstd | sha256` of base/Ventoy image (minisign deferred to v1.1, #19) | ADR-002 (amended) |
| `create-payload-tarball.sh` | Payload tarball (only if spike decides it's still needed) | ADR-002 (amended), conditional |
| `verify-release.sh` | Recipient-side wrapper for sha256 + minisign verification | ADR-003 |
| `publish-release.sh` | Gitea API upload of release artifacts | ADR-002 |

## Usage — external builders

If you are cloning this repo to build your own Kintsugi-like USB, see `../docs/toolkit-guide.md` (iteration-1 deliverable) for the end-to-end walkthrough. Short version:

```bash
# 1. Choose your models
cp ../manifest/models-recommended.yaml ../manifest/models-chosen.yaml
# edit models-chosen.yaml to taste

# 2. Build a master USB (interactive Cubic step)
sudo ./usb-toolkit/build-custom-iso.sh

# 3. Populate models into your in-progress master
sudo ./usb-toolkit/kintsugi-models pull qwen3.5:4b --target /mnt/master/payload/models/
# (repeat for each slug you want bundled)

# 4. Finalize + image (iteration-1 deliverables)
sudo ./prep-master.sh /mnt/master
sudo ./create-base-image.sh /mnt/master kintsugi-mybuild-v0.1.0.img.zst
minisign -Sm kintsugi-mybuild-v0.1.0.img.zst   # with YOUR key; don't depend on the maintainer's

# 5. Validate
./usb-toolkit/usb-test-harness.sh --full
```

## Trust boundaries (per ADR-005 §D5)

- The maintainer's minisign signature (`../kintsugi.pub` when committed) attests to the **base image**, **scripts**, and **`manifest/models-recommended.yaml`** as committed in tagged releases.
- It does **not** attest to model weights. Weights are user-pulled and carry the source's (Ollama / HuggingFace / URL) own integrity story.
- External builders signing their own releases use their own minisign key; the maintainer's key is not part of downstream trust chains.

## Conventions

- Bash; POSIX-friendly where practical; `set -euo pipefail` required in new scripts.
- All scripts must pass `shellcheck` with zero error-level findings (per iteration-1 CI scaffold).
- User-facing scripts print a one-line summary of what they will do + require explicit confirmation for destructive operations (no silent `dd`, no silent partition writes).
- No AI attribution in commit messages (per `../CLAUDE.md`).
