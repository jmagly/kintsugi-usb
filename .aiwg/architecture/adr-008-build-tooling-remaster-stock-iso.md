# ADR-008: Build Tooling — remaster the stock Ubuntu ISO (supersedes ADR-007 live-build)

**Status**: ACCEPTED (2026-05-25)
**Date**: 2026-05-25
**Deciders**: Joseph Magly (maintainer)
**Supersedes**: [ADR-007](adr-007-build-tooling-live-build.md) — `live-build` as the build tool
**Amends**: R-03, R-05 (risk register); the iteration-1 imaging/US-PORT-001 stories
**Driven by**: [#37](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/37) (first real release build, 2026-05-24/25)

## Context

ADR-007 made `live-build` the permanent build tool, chosen over Cubic for being **non-interactive and scriptable** (so the `kintsugi-build` wizard can drive it). That decision was sound on the scriptability axis but was never validated by an actual end-to-end build.

The first real release build (the `v2026.5.0` profile, in service of the #37 hardware-acceptance gate) was attempted six times. After clearing environmental and config issues (a file-manager `proc` race, root-owned build dirs, a `grub-legacy` reference), it surfaced a structural blocker:

**The Ubuntu-shipped `live-build` (`3.0~a57-1ubuntu49.1`) cannot build a bootable Ubuntu 24.04 (noble) ISO.** It is the 3.0-alpha series (circa 2013) and hardcodes EOL package names throughout its bootloader/theme stages:

- `--bootloader grub` → `grub-legacy` — *no installation candidate in noble*.
- There is **no `grub-efi` binary stage** at all (valid `--bootloader` values are only `grub`/`syslinux`/`yaboot`), so `--bootloader grub-efi` silently produced a **non-bootable** ISO (`xorriso` confirmed no El Torito boot record; `genisoimage` was invoked with no boot options).
- `--bootloader syslinux` → `lb_binary_syslinux` tries to install `syslinux-themes-ubuntu-oneiric` + `gfxboot-theme-ubuntu` — **Ubuntu 11.10 (oneiric, 2011)** packages, long gone.

Each fix exposed the next hardcoded-EOL wall. Producing a bootable noble ISO this way would require editing `/usr/lib/live/build/*` system scripts to strip 2011-era references — a fragile, non-reproducible, host-modifying hack across the whole oneiric-era boot subsystem. Notably, **Ubuntu does not build its own ISOs with `live-build`** (it uses `livecd-rootfs`); the shipped `live-build` is effectively unmaintained for modern Ubuntu.

The chroot **content** build worked correctly throughout — all packages, VS Code/Copilot/`gh`, Ollama, and the agentic frameworks installed via `config/hooks/normal/*.hook.chroot`. Only `live-build`'s **boot/ISO packaging** is unusable.

## Decision

**Build the custom Kintsugi ISO by remastering the official, already-bootable Ubuntu 24.04 ISO — non-interactively and scriptably. `live-build` is dropped.**

The supported flow becomes: download + verify the stock Ubuntu 24.04 ISO → extract → `chroot` into its squashfs → install our tools/frameworks (reusing the existing chroot-hook logic) → repack the squashfs → rebuild the ISO **preserving the stock El Torito + EFI boot structure**.

The **non-interactive/scriptable requirement from ADR-007/ADR-006 is retained** — Cubic (interactive GUI) is still rejected. The change is the *source*: instead of assembling a bootable image from scratch with an EOL tool, we start from Ubuntu's known-good bootable image and inject content.

## Rationale

- **Already bootable, both modes** — the stock Ubuntu ISO is UEFI **and** BIOS bootable and noble-current. Remastering preserves that boot structure, so it **also resolves the native-UEFI gap** that `live-build` could not provide. (Ventoy provides the outer boot for the distributed drive, but a properly bootable inner ISO is still required for reliable chainloading in both modes.)
- **We only need to change content, not boot** — our value-add is the bundled tools/scripts in the squashfs, not the bootloader. Remastering scopes the build to exactly that.
- **Reuses existing logic** — the iteration-1 chroot hooks (Ollama, VS Code/Copilot/`gh`, framework installers, system/shell config) install into a chroot; the remaster also chroots, so that content logic carries over largely intact.
- **Maintained tooling** — purpose-built remaster tools (`livefs-editor`) and the well-trodden manual `unsquashfs`/`mksquashfs` + `xorriso` path are current and noble-aware, unlike the EOL `live-build`.
- **Provenance preserved** — the remaster recipe stays in version control and scriptable; the "read the build script" story from ADR-007 is retained.

## Tool selection (implementation detail)

Approach decision is remaster; the specific tool is an implementation choice to be finalized in the new builder:

- **Preferred**: [`livefs-editor`](https://github.com/mwhudson/livefs-editor) — purpose-built for editing Ubuntu live ISOs (add-packages / shell hooks / repack) and preserves boot/EFI automatically; non-interactive.
- **Fallback**: scripted `xorriso -osirrox` extract → `unsquashfs` → `chroot` install → `mksquashfs` → `xorriso` rebuild re-using the source ISO's El Torito + EFI catalog (`-boot_image any replay`). More code, no extra dependency.

Cubic is **not** used (interactive; violates the scriptability requirement carried over from ADR-007/ADR-006).

## Consequences

- **Positive**: bootable ISO (UEFI + BIOS, noble-current); the build is scoped to content injection; the chroot-content logic is reused; native-UEFI gap resolved; off an unmaintained tool.
- **New build entry point**: `scripts/usb-toolkit/build-custom-iso.sh` (live-build) is superseded by a remaster-based builder. The `grub-efi`/`syslinux`/`iso`/`isohybrid`/prereq fixes made to it during the investigation become moot for the live-build path but remain useful provenance of *why* the pivot happened; the script is replaced or rewritten around remastering.
- **New inputs**: the stock Ubuntu 24.04 ISO must be fetched + sha256-verified (a pinned URL + hash, mirroring the rescue-ISO catalog pattern in #35). This is a new manifest entry.
- **R-05 (imaging pipeline)** stays the live risk until the remaster builder produces a booting ISO validated under #37. **R-03 (reproducibility)**: remastering is inherently *less* bit-reproducible than a declarative build, but it was never reproducible in practice anyway; stays MED/ACCEPTED-with-documentation.
- **Wizard contract unchanged** — `kintsugi-build` still drives the build non-interactively and emits the same downstream artifacts; only the ISO-production step it calls changes.
- **THIRD-PARTY-LICENSES**: the base is now the redistributed stock Ubuntu ISO (already covered as "Ubuntu 24.04" in the manifest); note the remaster relationship.

## References

- [ADR-007](adr-007-build-tooling-live-build.md) — superseded (live-build)
- [ADR-006](adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md) — wizard-first/non-interactive requirement retained
- `scripts/usb-toolkit/build-custom-iso.sh` — the superseded live-build implementation (investigation provenance)
- [#37](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/37) — the build investigation that drove this decision
- `.aiwg/risks/risk-list.md` — R-03, R-05
