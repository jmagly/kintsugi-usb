# ADR-002: Imaging Strategy for Distributable Artifacts

**Status**: PROPOSED — **MATERIALLY AMENDED by ADR-005 (2026-04-20)**
**Date**: 2026-04-20
**Deciders**: Joseph Magly
**Consulted**: SAD §4.3 (Tier B pipeline), SAD §5.2 (build-time process), SAD §5.3 (update-time process), R-04 (no field-update), R-05 (imaging NYE), R-08 (USB hardware variance), US-001..US-005, US-008..US-009

## Amendment 2026-04-20 (per ADR-005)

ADR-005 moves model loading to end-users, removing ~8 GB of model weights from the bundled image. The "Hybrid" scheme below (base image + separate payload tarball) was motivated in part by the size of bundled models. With weights gone:

- **Base image** (ISO + Ventoy + tools + llama.cpp + Ollama + manifest + scripts) is dramatically smaller — estimated single-digit GB compressed.
- The **separate payload tarball** may no longer be necessary. Iteration-1 includes a measurement spike (see `iteration-001-plan.md` Cluster 4, US-IMG-SPIKE) to decide whether to keep the hybrid structure or collapse to a single signed base image.
- If the spike shows a lean base image is viable, the recommended structure simplifies to: `kintsugi-vX.Y.Z.img.zst` + `.sha256` + `.minisig` + `kintsugi.pub` + `manifest.json`.
- **Field update** (R-04) stops relying on a payload-tarball rsync; the new path is `git pull` for docs/scripts on the persistence overlay + `kintsugi-models pull` for user-refreshed models. See `docs/update-strategy.md` (iteration-1 deliverable).

Signed-release verification (ADR-003, sha256 + minisign) is unchanged in either structure. Manifest hash-chain still applies.

## Amendment 2026-04-21 (per spike #21 — collapse to single artifact)

### Spike findings (estimate-based; wet-run measurement deferred to first v1.0 release build)

No wet build was available at spike time (live-build runs ≈20 min as root and this repo has no CI host yet). Using a component-wise size estimate against the resolved v1.0 contents:

| Component | Uncompressed | Source |
|-----------|--------------|--------|
| Ubuntu 24.04 Server base + live-build boot layer | 900–1100 MB | apt package-list `kernel.list` + base live-boot tooling |
| Xfce4 desktop + NetworkManager | 250–350 MB | `desktop.list` from `build-custom-iso.sh` |
| Rescue tool suite (fsck family, gparted, smartctl, testdisk, grub tools, nmap, tcpdump, htop, etc.) | 500–800 MB | `rescue.list` from `build-custom-iso.sh` |
| Python 3 + pip + build-essential + cmake | 400–500 MB | `rescue.list` |
| VS Code + gh CLI (ADR-006 §D3) | 350–450 MB | Microsoft + GitHub apt repos |
| GitHub Copilot extension VSIX (cached) | 30–50 MB | marketplace fetch |
| Ollama binary + pinned model-runtime (no weights) | 150–250 MB | `ollama.com/install.sh` |
| mikefarah yq | 10 MB | GitHub release |
| llama.cpp binaries (bundled per `build-custom-iso.sh` copy) | 50–100 MB | existing |
| kintsugi scripts + manifests | <5 MB | this repo |
| Agentic framework installers (Aider pipx + Claude Code + Codex npm per default wizard flow) | 400–600 MB | `kintsugi-frameworks install` in 07-hook |
| Squashfs overhead + isohybrid structures + kernel/initrd | 100–150 MB | live-build |
| **Total uncompressed** | **3.1 – 4.4 GB** | |
| **Compressed with `zstd -19`** (55–65% ratio on mixed binaries+text) | **1.7 – 2.6 GB** | |

### Decision: **collapse the payload tarball**

Ship a single signed artifact per release: `kintsugi-vX.Y.Z.img.zst` (plus `.sha256` and `manifest.json`; `.minisig` + `kintsugi.pub` arrive in v1.1 per ADR-006 §D5).

Rationale:
1. **Estimated compressed size (1.7–2.6 GB) comfortably fits any reasonable release host**, including Gitea attachments, NFS, S3-compatible mirrors. The original Hybrid concern (images too large for Gitea release attachments) is no longer load-bearing.
2. **Simpler mental model for recipients**: one file to download + verify + flash, not two files that must both be present.
3. **Field-update story was already simplified** by ADR-006 §D5: `git pull` for docs/scripts, `kintsugi-models pull` for models, `kintsugi-frameworks install` for new frameworks. No payload-rsync flow needed.
4. **Re-expanding to Hybrid if the estimate proves wrong is cheap**: we keep `scripts/create-base-image.sh` generic; a future `scripts/create-payload-tarball.sh` can join it if a real build exceeds the single-artifact threshold.

### Verification gate

The first actual v1.0.x build (Gitea #7) measures the real compressed size and writes it to `manifest.json` at release time (`create-image.sh` computes this automatically). If the real number materially exceeds the estimate (say, >6 GB compressed), we revisit this decision. Until then: single-artifact shipping is authoritative.

### Open to revisit in v1.1+

- Incremental / differential base-image updates (zsync-style) — makes sense only once the base image stabilizes version-to-version. Not v1.0.
- Multi-arch (per NFR-8/SAD §12) — a per-arch image would use the same single-artifact structure, not a hybrid.

---

## Context

Kintsugi USB is a Ventoy-based multi-boot rescue drive layered on a custom Ubuntu 24.04 ML-Support squashfs, with a bundled offline LLM stack (llama.cpp + GGUF models) and cloud CLIs (`claude`, `codex`). The master USB is mature; the **repository-side build/distribution pipeline does not yet exist** (R-05). Distribution today means a hand-rebuilt Ventoy USB per recipient — slow, error-prone, and unverifiable against any published checksum.

This ADR chooses how the master USB is packaged into the artifact recipients actually download and flash. The decision shapes every downstream pipeline script (`prep-master.sh`, `create-image.sh`, `flash-image.sh`, `update-payload.sh`), the Gitea release layout, the recipient flash UX, and the field-update story (R-04). It is the single highest-leverage architectural choice in Tier B and must be made before Construction work on those scripts can begin coherently.

"Distribution" here means: a non-technical recipient (family member, fleet user, ops peer) downloads one or more artifacts from a Gitea release, verifies a SHA-256 (and optionally a minisign signature), and flashes a 64 GB USB stick — with a reasonable probability of success on their first try. Once flashed, that drive must also be updatable in the field without a second reflash for at least the `docs/`, `scripts/`, and model-weight layers (R-04, US-008, US-009).

---

## Decision Drivers

- **Recipient simplicity** — a non-technical user must be able to flash without understanding Ventoy, partition tables, or exFAT layouts (NFR-5.4, NFR-8.2, NFR-9.2).
- **Download size vs. release-host limits** — Gitea release storage at integrolabs.net has practical ceilings; recipient bandwidth and patience are also bounded. A ~55 GB download is untenable.
- **Reproducibility** — recipients should get bit-identical critical layers, or at minimum an artifact set that is content-addressed and hash-verifiable end to end (NFR-2.1, §9.1 secrets-only-in-persistence invariant).
- **Natural field-update path** — R-04 requires in-place updates to `docs/`, `scripts/`, models, and cloud CLI binaries without reflash. The imaging strategy should make this easy, not fight against it.
- **Verification UX** — one-line, platform-native SHA commands plus optional minisign verification, with the expected hash displayed side-by-side (SAD §4.3 recipient verification UX).
- **Supply-chain provenance (R-02)** — every bundled ISO, binary, and model must be traceable to an upstream SHA and license; the packaging format must not obscure this.

---

## Considered Options

### Option 1: Full-partition `dd | zstd`

Image the entire 64 GB VENTOY partition (or whole device), compress with `zstd -T0 -19`, ship a single `kintsugi-vX.Y.Z.img.zst` of ~25–30 GB. Recipient runs `zstdcat kintsugi-vX.Y.Z.img.zst | dd of=/dev/sdX` or uses balenaEtcher's native `.zst` support.

- **Pros**: simplest recipient experience (one file, one flash); maximum reproducibility (bit-identical USBs by construction); single SHA + signature covers everything; aligns closely with SAD §5.2's current sketch; the verification story is trivially one-line.
- **Cons**: 25–30 GB is at or beyond plausible Gitea release size limits; every payload refresh (new docs, new model, new CLI) forces recipients to redownload tens of GB and reflash — a direct violation of R-04's intent; wastes bandwidth because ~95% of content is unchanged across minor releases.

### Option 2: Ventoy-rehydrate + payload rsync

Recipient runs the Ventoy installer themselves against a blank USB, then downloads a payload tarball (ISOs + tools + models + docs, ~15 GB compressed) and rsyncs it onto the formatted VENTOY exFAT partition.

- **Pros**: smallest download; no image-compression step in the build pipeline; payload tarball is naturally content-addressed by component.
- **Cons**: forces non-technical recipients to run the Ventoy installer — a two-step manual process that breaks NFR-5.4 and NFR-8.2; expands the recipient trust surface (Ventoy upstream now a direct dependency for each recipient); gives up bit-identical reproducibility of the boot sector and partition table; divergence across recipients becomes likely (Ventoy version skew, partition-table quirks on cheap sticks — R-08 worsens).

### Option 3: Hybrid — minimal base image + payload tarball

Ship two artifacts: (a) `kintsugi-base-vX.Y.Z.img.zst` (~5 GB: Ventoy + custom Ubuntu ML-Support ISO + persistence skeleton + minimal `/data` scaffold), and (b) `kintsugi-payload-vX.Y.Z.tar.zst` (~15–20 GB: rescue ISOs, GGUF models, `/tools/bin/` binaries, full `docs/` and `scripts/` snapshot). Recipient flashes the base image once (simple, Etcher-compatible), then either pulls the payload onto the mounted VENTOY partition via a helper script or the maintainer publishes a pre-populated full-image variant for users who prefer one-step flashing.

- **Pros**: recipient flash UX stays one-step for the base; payload is separable, so field updates (R-04) are literally "fetch new payload tarball, run `update-payload.sh`" — no new code path needed; base image is small enough for any release host; payload tarball can be hosted on alternative storage (Backblaze B2, Gitea LFS, releases attached to separate tags) if it exceeds release-attachment limits; reproducibility is preserved for the base (the only layer recipients all share) while payload contents are content-addressed via per-component manifest hashes.
- **Cons**: two artifacts means two SHA verifications — verification UX and release docs must handle the compound case cleanly; more build-pipeline tooling (two create-* scripts instead of one); the first-time-flash flow is "flash base, then apply payload," which is more steps than Option 1 if the recipient wants a fully-loaded drive immediately (mitigated by optionally publishing a convenience full-image alongside the split artifacts for non-technical recipients who want one-shot).

---

## Decision

**Option 3 (Hybrid)** is adopted.

Each release produces:

1. `kintsugi-base-vX.Y.Z.img.zst` — the flashable base (Ventoy + custom Ubuntu ML-Support ISO + persistence skeleton + empty `/data` + `/tools` + `/models` scaffolding). Full-partition `dd | zstd` capture of a minimal master. ~5 GB compressed.
2. `kintsugi-payload-vX.Y.Z.tar.zst` — tar archive of the `/ISO/rescue`, `/tools`, `/models`, `/data/docs`, `/data/scripts`, `/data/recovery` trees. ~15–20 GB compressed.
3. `manifest/vX.Y.Z.json` — per-artifact SHA-256s, upstream source URLs and SHAs for every bundled component, and redistribution license per component (R-02).
4. `kintsugi-base-vX.Y.Z.img.zst.minisig` and `kintsugi-payload-vX.Y.Z.tar.zst.minisig` — detached minisign signatures; manifest hash-chained into both signatures per SAD §9.1.

**Rationale**:

- The base image is the only layer that must be bit-identical across all recipients (boot sector, partition table, Ventoy, squashfs). Keeping it small makes it flashable by any recipient and fits any reasonable Gitea release limit.
- The payload is exactly what `update-payload.sh` already needs to apply per SAD §4.3's update-boundary table — so field update is a natural consequence of the distribution format rather than an afterthought requiring separate tooling. R-04 is retired by construction.
- Splitting the artifacts decouples release cadence: a docs/scripts refresh ships as a new payload tarball without rebuilding the base image. This reduces recipient bandwidth cost on minor releases from ~30 GB to ~15 GB (or much less, if we later adopt per-component payload sub-tarballs — see Open Questions).
- Reproducibility is preserved where it matters (base) and content-addressed where it's flexible (payload). The manifest is the trust anchor; minisign binds it to a maintainer identity.

---

## Consequences

**Positive**:
- R-04 (no field-update) is architecturally retired: update-payload.sh applies the payload tarball against a flashed USB's VENTOY partition with no reflash required.
- R-05 (imaging NYE) decomposes into four well-scoped scripts instead of one monolithic imaging tool.
- Base image size comfortably fits any reasonable release attachment limit, avoiding dependency on external storage for the primary artifact.
- Minor-version releases (docs/script refreshes, model swaps) are cheap for both maintainer and recipients.
- Verification UX remains a platform-native one-liner per artifact; the manifest ties them together.

**Negative / tradeoffs**:
- Two-artifact distribution requires clearer recipient docs than a single-file flash. `docs/flash-image.md` must cover flash-then-populate explicitly, including the case where a recipient flashes base but defers payload.
- Two create-* scripts (`create-base-image.sh`, `create-payload-tarball.sh`) plus `publish-release.sh` — more pipeline surface area than Option 1's single imager.
- A recipient who flashes only the base and never applies a payload has a bootable but mostly-empty drive. Mitigation: boot-time banner displays `PAYLOAD-VERSION` (NFR-6.6); if absent, `start-ai.sh` prints a clear "run update-payload.sh to populate this drive" notice.

**Field update is naturally supported**: the same `update-payload.sh` used for minor refreshes is also the first-time populate path. No separate code path.

---

## Implementation Plan

1. `scripts/prep-master.sh` — sanitize secrets (CLI auth-state paths per SAD §4.3), zero free space on the base partition slice, flush caches, unmount cleanly. Idempotent.
2. `scripts/create-base-image.sh` — `dd` the minimal base slice of the master USB → `zstd -T0 -19` → `sha256sum` → `minisign -S` → produce `kintsugi-base-vX.Y.Z.img.zst` + `.sha256` + `.minisig`.
3. `scripts/create-payload-tarball.sh` — `tar` the payload tree (excluding ISOs already in base, excluding persistence) → `zstd -T0 -19` → `sha256sum` → `minisign -S` → produce `kintsugi-payload-vX.Y.Z.tar.zst` + `.sha256` + `.minisig`.
4. `scripts/publish-release.sh` — Gitea API client (via `mcp__git-gitea__create_release` or `curl`) that attaches both artifacts, both signatures, both SHAs, the manifest, and the signing key to a tagged release.
5. `docs/flash-image.md` — non-technical recipient procedure covering Etcher (primary) and `dd`/Rufus (alternates) for the base, followed by payload application. Includes per-OS verification one-liners with side-by-side expected SHAs.
6. `scripts/flash-base.sh` — operator helper that verifies SHA + signature, prompts for target device with `lsblk` confirmation, `zstdcat | dd`, verifies flashed device, reports success.
7. `scripts/update-payload.sh` — applies a payload tarball onto a mounted VENTOY partition. Idempotent. Supports `--dry-run`. Used for both first-time populate and field update.

---

## Verification

Each release artifact gets a SHA-256 and a minisign detached signature. The manifest is hash-chained into both signatures so a tampered manifest cannot misrepresent bundled components (SAD §9.1). Release-blocker rule (SAD §5.2) applies: no version ships without a full round-trip — master → base image → flash to spare USB → apply payload → boot — plus a QEMU UEFI smoke test of the flashed base.

---

## Open Questions

- **Gitea release attachment size limits at integrolabs.net** — confirm with admin (Joseph). If the ~15–20 GB payload exceeds the attachment ceiling, fall back to hosting the payload tarball on Backblaze B2 or equivalent, keeping the base image on the Gitea release. Manifest remains the trust anchor either way.
- **Differential payload updates** — should the payload be one tarball or several content-addressed sub-tarballs (`payload-iso-vX.tar.zst`, `payload-models-vX.tar.zst`, `payload-docs-vX.tar.zst`) so a docs-only refresh is a ~10 MB download instead of 15 GB? Deferred; revisit after first full release ships and cadence is observed.
- **Convenience full-image variant** — should `publish-release.sh` optionally also produce a pre-populated full `.img.zst` (base + payload already applied) for recipients who prefer a single-file flash? Cheap to generate as a byproduct of the round-trip verification flash; defer pending recipient feedback.

---

## Links

- SAD §4.3 (Tier B components), §5.2 (build-time process), §5.3 (update-time process), §9.1 (secrets invariant and manifest hash-chain)
- `docs/architecture.md` §2 (USB physical layout)
- US-001..US-005 (imaging pipeline), US-008..US-009 (field update and update boundary)
- R-02 (supply-chain provenance), R-04 (no field-update), R-05 (imaging NYE), R-08 (USB hardware variance)
- ADR-001 (License Choice) — a prerequisite for publishing any artifact
