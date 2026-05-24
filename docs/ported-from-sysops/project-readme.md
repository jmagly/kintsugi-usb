# USB Toolkit — moved

The USB Toolkit project has been renamed **Kintsugi USB** and relocated to its own public repository.

## New home

- **Repo**: https://git.integrolabs.net/roctinam/kintsugi-usb
- **Issues**: https://git.integrolabs.net/roctinam/kintsugi-usb/issues

## What moved

All prior contents of `docs/projects/usb-toolkit/` in this repo (`architecture.md`, `build-guide.md`, `requirements.md`, `test-strategy.md`, `physical-test-guide.md`, `n5pro-recovery-sop.md`) were migrated to `docs/` in the new repo as of commit `54f1e15` (this repo) / `f535034` (new repo).

**Correction (2026-05-24)**: `n5pro-recovery-sop.md` was subsequently moved **back to sysops** (`docs/runbooks/`) — a host-specific recovery SOP is fleet-operational content, out of scope for the public Kintsugi USB toolkit. Kintsugi USB *carries* such packs as operator payload but does not author them.

## Why

The drive is being prepared for public distribution (multiple end users, imaging pipeline, Gitea-published releases). Keeping a distributable, user-facing project inside the private fleet-ops repo did not scale. See [docs/about-the-name.md](https://git.integrolabs.net/roctinam/kintsugi-usb/src/branch/main/docs/about-the-name.md) in the new repo for the rename rationale.

## What remains here

This stub only. Update any internal links to point at the new repo.
