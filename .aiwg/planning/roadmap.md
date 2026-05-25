# Kintsugi USB — Roadmap

- **Owner**: Joseph Magly (roctinam)
- **Created**: 2026-05-23 (post-iteration-1 reconciliation) · **Updated**: 2026-05-24 (post build/imaging audit)
- **Anchors**: [ADR-005](../architecture/adr-005-toolkit-scope-and-user-driven-models.md) (user-driven models + toolkit surface), [ADR-006](../architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md) (wizard-first UX, signing deferred to v1.1), [ADR-007](../architecture/adr-007-build-tooling-live-build.md) (live-build is the builder)
- **Tracker**: https://git.integrolabs.net/roctinam/kintsugi-usb/issues
- **Sequencing note**: Work is expressed as scope and dependency order, not calendar dates (per `.claude/rules/no-time-estimates.md`). Items are grouped now / next / later.

---

## Status snapshot (2026-05-25)

**2026-05-25 — build pipeline validated end-to-end (through flash + on-drive integrity); agentic stack baked.** The ADR-008 remaster builder (`make-remaster-iso.sh`) is now proven: stock Xubuntu 24.04 → remaster (rescue tools + Kintsugi scripts + agentic CLIs) → bootable ISO (BIOS **and** UEFI El Torito) → `make-ventoy-image.sh` `.img` (Ventoy + 8 GiB persistence + KINTSUGI data partition + on-drive README) → flashed to the test USB (serial 05250930) at 64.9 MB/s with **bit-perfect on-drive ISO sha256** and correct `ventoy.json` persistence wiring. Pass-1 **booted on real hardware** (maintainer-confirmed). Pass-2 bakes the agentic stack: **5 AIWG-supported providers pre-installed in-chroot** — claude-code, codex, opencode, copilot, openclaw (npm globals on Node 22.22; verified ✓ at build time) — with auth left as a post-flash user step (ADR-006 §D5). **In progress:** the maintainer's pass-2 boot re-test (confirm the 5 CLIs launch + persistence survives reboot) — the remaining hardware half of #37. Deferred by design: `hermes` (per-user curl\|bash Python install, heavy — first-boot opt-in candidate) and the GUI IDEs (cursor/windsurf/warp/factory — desktop apps, out of scope for a CLI rescue drive). `aider` is a non-AIWG bonus (pipx; fixed for the next build).

The 2026-05-24 build/imaging audit (`audit-2026-05-24`, Gitea #34–#42) is the defining event of the prior snapshot. It found that the shipped toolkit, while feature-rich, **could not satisfy its own iteration-1 acceptance gate**: the build produced a single `live-build` ISO with no Ventoy assembly and no persistence, and the wizard stopped at an `.iso` rather than the `.img.zst` the gate requires. Triage resolved every finding (decisions recorded on each issue); `iteration-001-plan.md` was amended in place to match. (The `live-build` tool itself was subsequently found unbuildable on noble → ADR-008 remaster pivot, below.)

- **Shipped (iteration-1 code)**: build wizard (`scripts/kintsugi-build`), imaging pipeline (`prep-master`, `create-image`, `flash-image`, `verify-image`, `publish-release`), `kintsugi-models` + `kintsugi-frameworks` CLIs, custom live-build ISO (VS Code/Copilot/gh + Ollama), MIT LICENSE + THIRD-PARTY-LICENSES, SECURITY.md, CHANGELOG.md, user docs.
- **Landed since (audit response, `main` @ `1cb5af0`)**: `make-ventoy-image.sh` (Ventoy assembler, #42 — offline-verified), persistence provisioning code (#34), wizard end-stage wiring + stale-comment removal (#36), and the residual Cubic→live-build doc corrections (#39 completeness).
- **Not done (the real release blockers)**: rescue catalog (#35), wizard unattended auto-chain (#36), the hardware acceptance round-trip (#37), and the tag/release (#41). The build does **not** yet pass its DoD.
- **Open issues (9)**: #34, #35, #36 (wizard rewire — code landed 2026-05-25; remaining: IDE option + #37 run), #37, #42 (Ventoy build), #43 (offline-AI core **landed**; IDE decision + casper-safe config remain), #44 (**new** — reconcile remaining docs to ADR-008/rewired wizard), #41 (release, gated), #19 (v1.1 signing). Everything else (#1–#33, #38, #39, #40) is closed.
- **Risk posture**: R-05 (imaging pipeline) is the live risk — the audit showed it is not yet retired; it retires when #37 passes. R-07 (secrets) MITIGATING (scanner #32 landed). See `risks/risk-list.md`.

**Resolved decisions (2026-05-24):**
- **Version scheme = CalVer** (`YYYY.M.PATCH`, no leading zeros). First tagged release **v2026.5.0**. `docs/release-process.md` and `README.md` already reflect this.
- **First-release scope**: v2026.5.0 **includes the full Ventoy multi-boot build** (do not re-scope to single ISO, #35) and **stays gated on the #37 hardware round-trip** (#41). The tag marks a build that passes its acceptance gate — not before.
- **Persistence**: Ventoy persistence plugin, **32 GiB default** (#34). LUKS-encrypted `/data` remains the NFR-4.3 stretch goal, out of scope.

---

## Now — make v2026.5.0 pass its acceptance gate

The release is blocked behind the Ventoy build. This lane closes that gap. Most of it is code (no maintainer hardware); the exceptions are called out.

> **Build-tool pivot — [ADR-008](../architecture/adr-008-build-tooling-remaster-stock-iso.md) (2026-05-25).** The first real build proved the Ubuntu-shipped `live-build` (3.0~a57) cannot build a bootable noble ISO (hardcoded 2011-era EOL boot/theme packages; no working EFI stage). The custom-ISO builder is being rebuilt to **remaster the stock, already-bootable Ubuntu 24.04 ISO** (non-interactive; reuses the chroot-hook content logic; also resolves native UEFI). Supersedes ADR-007. The Ventoy assembly (#42), persistence (#34), and wizard wiring (#36) are unaffected — only the ISO-production step changes.

| # | Work | Issue | State |
|---|------|-------|-------|
| 1 | **Ventoy `.img` assembler** — bootloader + persistence + rescue/Kintsugi ISOs into the layout. | #42 | **code landed** (`--dry-run`/validation offline-verified); hardware build → #37 |
| 2 | **Persistence provisioning** — 32 GiB `.dat`, plugin binding, `/data` on the overlay. | #34 | **code landed**; mount/boot validation → #37 |
| 3 | **Rescue catalog** — `kintsugi-rescue` CLI + `manifest/rescue-isos-recommended.yaml` + wizard rescue-selection step + doc updates. Needs **network** to fetch+hash real ISOs; carries the forensics-distro survey. | #35 | remaining |
| 4 | **Remaster content parity** — port the offline-AI stack (Ollama, llama.cpp/llama-server), mikefarah `yq`, and (decision) VS Code/Copilot/gh into `make-remaster-iso.sh`. The ADR-008 pivot ported rescue tools + scripts + agentic CLIs but **not** the drive's headline offline-LLM feature. Code-only (mirrors `agentic-provision.sh` chroot-exec); blocks the wizard's runtime/IDE options. | #43 | **new (2026-05-25)** — discovered during pass-2/3 build |
| 5 | **Wizard unattended auto-chain + ADR-008 rewire** — repoint `kintsugi-build` off the dead live-build builder onto `make-remaster-iso.sh --base … --with-agentic --with-ai-stack → make-ventoy-image.sh → create-image.sh`; swap prereqs; reconcile the option model to remaster flags. | #36 | **code landed (2026-05-25, `4c1371f`)** — schema-v2 rewrite, auto-chains end-to-end, `--dry-run` verified. Remaining: IDE option (gated on #43) + the end-to-end *run* (#37). |

**Exit criteria:** a fresh clone → `./scripts/kintsugi-build` (defaults) produces a Ventoy `.img.zst` + `.sha256` + profile, with rescue ISOs in the menu and persistence wired — i.e. the artifact #37 will flash.

---

## Next — acceptance gate + release

| Work | Issue | Notes |
|------|-------|-------|
| **Hardware acceptance round-trip** — fresh clone → wizard → `.img.zst` → flash a real USB → boot a test host → `usb-test-harness.sh` PASS incl. **TC-6 persistence** → `--from-profile` reproduces → capture measured timing/disk figures → backfill `docs/wizard-guide.md` → record in `.aiwg/reports/`. | #37 | **Requires hardware.** *Progress (2026-05-25):* build→assemble→flash→on-drive-integrity all PASS; **pass-1 booted on hardware (confirmed)**; pass-2 (agentic stack baked) flashed → maintainer re-testing CLI launch + TC-6 persistence. Remaining: capture timings, `--from-profile` reproduce, backfill docs, `.aiwg/reports/` record. Still the release linchpin. |
| **Tag + Gitea release** — tag `v2026.5.0`; publish source tarball + CHANGELOG + manifests (no image artifact, ADR-006 §D4); refresh this roadmap's snapshot. Mechanical via `release-profiles/v2026.5.0.yaml` + `flow-release`. | #41 | Gated on #37 passing. |

**Exit criteria:** `v2026.5.0` tag pushed; Gitea source release published; R-05 → RETIRED.

---

## Later — v1.1 signing & backlog

None of these block v2026.5.0.

| Work | Drives | Tracking |
|------|--------|----------|
| **Minisign signing** — generate keypair, commit `kintsugi.pub` on an independent channel, `verify-release.sh`, per-OS signed-verification one-liners, re-tag/release signed. | R-02 | #19 (v1.1) |
| ~~**Doc-reconciliation pass**~~ — **DONE 2026-05-24** (`9874b23`): `scripts/README.md` rewritten to the wizard+Ventoy flow; `toolkit-guide.md` §7.0 Ventoy assembly added; `build-guide.md` positioned as the manual reference; stale `create-base-image`/Cubic/`vX.Y.Z`/`do-not-exist-yet` cruft removed across docs. | doc accuracy | done |
| **Agentic-framework catalog expansion** — Cursor, Windsurf, Warp, OpenCode, Factory, Continue.dev beyond the v1.0 three. | product | new |
| **Gitea Actions CI** — automated build + sanitize/secret scans as gates. | R-06/R-07 | new |
| **SBOM generation** (CycloneDX/SPDX) beyond `manifest.json`. | supply chain | new |
| **Hardware compatibility matrix** — field boot reports → `docs/compatibility.md`. | R-12 | new |
| **Multi-arch (arm64)** — out of scope today; revisit on demand. | reach | — |

---

## Open decisions

1. ~~**Version line**~~ — RESOLVED 2026-05-23: CalVer, first release v2026.5.0.
2. ~~**Release channel**~~ — RESOLVED 2026-05-24 (#41): NFS-internal, **sha256-only source release** sanctioned; no public image until signing (#19).
3. ~~**First-release scope**~~ — RESOLVED 2026-05-24: v2026.5.0 = full Ventoy build, gated on #37.
4. **Forensics-distro catalog (#35)**: which recovery/forensics ISOs join the default four — pending a survey that must clear **redistribution licensing** (CAINE/Tsurugi/Kali/Parrot have varied terms). Decide when fetching+pinning the bundle.
5. **CI timing**: stand up Gitea Actions now (enables R-06/R-07 gate enforcement) or defer until post-v2026.5.0.

## References

- @.aiwg/planning/iteration-001-plan.md — iteration-1 scope + DoD (amended 2026-05-24)
- @.aiwg/risks/risk-list.md — reconciled risk register
- @.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md — wizard-first + signing-deferred
- @.aiwg/architecture/adr-007-build-tooling-live-build.md — live-build is the builder
- @docs/release-process.md — release procedure (CalVer)
