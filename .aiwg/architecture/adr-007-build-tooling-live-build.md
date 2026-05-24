# ADR-007: Build Tooling — live-build (supersedes the Cubic references in ADR-003/ADR-006)

**Status**: ACCEPTED (2026-05-24)
**Date**: 2026-05-24
**Deciders**: Joseph Magly (maintainer)
**Supersedes**: the Cubic build-tool assumption in ADR-006 (§D3 VS Code chroot, decision Q2, wizard prereq step) and ADR-003 (reproducibility paragraph)
**Amends**: R-03 (risk register)
**Driven by**: [#39](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/39) (2026-05-24 build/imaging audit)

## Context

ADR-006 and the earlier Elaboration artifacts describe building the custom Ubuntu ISO with **Cubic** — an interactive, GUI-driven chroot customization tool. The implemented toolchain does not use Cubic. `scripts/usb-toolkit/build-custom-iso.sh` builds the ISO with Debian/Ubuntu **`live-build`** (`lb config` + package lists + `config/hooks/normal/*.hook.chroot` + `lb build`).

This change was made in code during iteration-1 but never recorded as a decision. As of the 2026-05-24 audit, ~18 artifacts still reference Cubic, and **R-03** mis-describes the build as "interactive Cubic (chroot + GUI)". The architectural record contradicts the shipped code: a reader following the ADRs would look for a Cubic project that does not exist.

## Decision

**`live-build` is the permanent build tool for the custom Kintsugi ISO. Cubic is not used.**

## Rationale

`live-build` is the better fit for this product, and specifically for the wizard-first orientation of ADR-006:

- **Non-interactive** — the `kintsugi-build` wizard can drive it end-to-end; a GUI Cubic workflow cannot be scripted.
- **Declarative** — the entire build recipe (package lists, chroot hooks, bootloader config) lives in version control and is auditable. This is itself a provenance improvement: a recipient can read `build-custom-iso.sh` to see exactly what goes into the image.
- **CI-able** — supports the deferred Gitea Actions automated-build goal without a display server.

## Consequences

- **Positive**: scriptable/CI-able builds; the build recipe is git-tracked and reviewable; stronger "read the script" provenance story.
- **R-03 re-assessed**: the risk is no longer "interactive Cubic GUI". `live-build` is declarative, but the ISO is still **not bit-for-bit reproducible by default** (build timestamps, apt cache state, package-install order). Unlike Cubic, bit-for-bit reproducibility is now *achievable* with `live-build` reproducibility options (`SOURCE_DATE_EPOCH`, pinned apt snapshots) if pursued. R-03 stays **MED / ACCEPTED-with-documentation**; only its cause and mitigation text change. Pursuing reproducible-build flags remains deferred (backlog).
- **Documentation debt**: live, present-tense Cubic references are corrected under #39; historical point-in-time records (`.aiwg/reports/`, `.aiwg/intake/`, `.aiwg/working/`) are left as-is — they accurately record what was believed at the time. The accepted-ADR bodies of ADR-003 and ADR-006 are not rewritten; each carries a pointer to this ADR.
- **No other ADR-006 decision changes** — wizard-first UX, user-driven frameworks, VS Code/Copilot base, NFS publish, and signing-deferral are all unaffected.

## References

- `scripts/usb-toolkit/build-custom-iso.sh` — the live-build implementation (`lb config` / `lb build`)
- [ADR-003](adr-003-verification-rigor.md), [ADR-006](adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md) — superseded re: build tool only
- `.aiwg/risks/risk-list.md` — R-03 (re-assessed)
- [#39](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/39) — audit finding
