# Kintsugi USB — Roadmap

- **Owner**: Joseph Magly (roctinam)
- **Created**: 2026-05-23 (from post-iteration-1 reconciliation)
- **Anchors**: [ADR-005](../architecture/adr-005-toolkit-scope-and-user-driven-models.md) (user-driven models + toolkit surface), [ADR-006](../architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md) (wizard-first UX, signing deferred to v1.1)
- **Tracker**: https://git.integrolabs.net/roctinam/kintsugi-usb/issues
- **Sequencing note**: This roadmap expresses work as scope and dependency order, not calendar dates. Items are grouped now / next / later.

---

## Status snapshot (2026-05-23)

Iteration-1 ("wizard-first build toolkit") is **feature-complete in code** but **not formally released**:

- **Shipped**: imaging pipeline (`prep-master`, `create-image`, `flash-image`, `verify-image`, `publish-release`), build wizard (`scripts/kintsugi-build`), `kintsugi-models` + `kintsugi-frameworks` CLIs, custom-ISO build with VS Code/Copilot/gh + Ollama, MIT LICENSE + THIRD-PARTY-LICENSES, SECURITY.md, user docs. 28 of 31 Gitea issues closed. `first_deploy` milestone recorded 2026-05-24.
- **Not done (release tail)**: no git tag, no `CHANGELOG.md`, no Gitea release (source tarball + manifests), README still reads "Status: Early" and references `v0.1.0`.
- **Open issues**: #10 (CMDB add, p1), #12 (physical labeling, p2/post-v1.0), #19 (minisign keypair, p2/v1.1), #32 (secret scanner, p1 — from reconciliation), #33 (runbook review gate, p2 — from reconciliation).
- **Risk posture**: 20 active (1 CRITICAL R-07, 4 HIGH, 11 MED, 4 LOW), 2 closed/retired. See `risks/risk-list.md` (reconciled same day).

**Version decision (resolved 2026-05-23)**: the project adopts **CalVer** (`YYYY.M.PATCH`, no leading zeros, per `.claude/rules/versioning.md`). First tagged release is **v2026.5.0**. This supersedes the earlier v0.1.0 / v1.0.0 semver framing in `README.md` and `docs/release-process.md`, which are updated to match in the Now lane.

---

## Now — v1.0 release finalization

The goal of this milestone is to turn the shipped code into a tagged, documented, reproducible release. No new features.

| # | Work | Drives | Tracking |
|---|------|--------|----------|
| 1 | **Version scheme = CalVer** (resolved 2026-05-23). First release **v2026.5.0** (`YYYY.M.PATCH`, no leading zeros). Update `docs/release-process.md` (currently semver `vX.Y.Z`) and README version strings to match. | release clarity | done (decision) |
| 2 | **Write `CHANGELOG.md`** — first entry covering the iteration-1 toolkit. | iteration DoD | new issue |
| 3 | **Refresh `README.md`** — drop "Status: Early"; reflect wizard-first toolkit, one-command `./scripts/kintsugi-build`, post-flash `kintsugi-models pull` / `kintsugi-frameworks install` / `gh auth login`, NFS publish note, sha256 verification + "signing arrives in v1.1" line. | iteration DoD | new issue |
| 4 | **Tag + Gitea release** — git tag, Gitea source tarball + CHANGELOG + manifests (no image artifact per ADR-006 §D4). | iteration DoD | follows #1–3 |
| 5 | **#10 — Add Kintsugi USB to CMDB** (OpsInventory.yaml). p1, itops. | asset tracking | #10 |
| 6 | **#32 — Pre-commit secret scanner** (gitleaks). p1. Closes the last unbuilt R-07 mitigation before more public commits. | R-07 (CRITICAL) | #32 |

**Exit criteria:** tag pushed; CHANGELOG + refreshed README committed; Gitea release published; #10 and #32 closed.

---

## Next — v1.1 signing & provenance

The provenance milestone deferred from v1.0 per ADR-006 §D5. Retires the residual on R-02.

| Work | Drives | Tracking |
|------|--------|----------|
| **#19 — Generate minisign keypair**, commit `kintsugi.pub`, publish on an independent channel. | R-02 | #19 |
| **`verify-release.sh`** with minisign verification. | R-02 | new (was deferred in iteration-1 OOS) |
| **Per-OS signed-verification one-liners** in `docs/flash-image.md` (replace the v1.1 placeholder). | R-02 | new |
| **Re-tag/release as signed v1.0.0** (if version recommendation above is adopted). | release | follows |

**Exit criteria:** every published image has a `.minisig`; verification documented per-OS; R-02 → MITIGATING/RETIRED.

---

## Later — hardening & expansion (backlog)

Risk- and quality-driven; none block a release.

| Work | Drives | Tracking |
|------|--------|----------|
| **#33 — Runbook human-review gate** + checklist; wire into `publish-release.sh`. | R-15 (HIGH) | #33 |
| **#12 — Physical labeling scheme** for distributed copies. | R-08/R-11 | #12 |
| **Agentic-framework catalog expansion** — add Cursor, Windsurf, Warp, OpenCode, Factory, Continue.dev beyond the v1.0 three (Aider, Claude Code, Codex). | product | new |
| **SBOM generation** (CycloneDX/SPDX) beyond the `manifest.json` SBOM-lite. | supply chain | new |
| **Gitea Actions CI** — automated build + the sanitize/secret scans as gates. | R-06/R-07 CI enforcement | new |
| **CI-enforced sanitize pass** — promote R-06 MITIGATING → MONITORING once `prep-master` secret scan runs in CI. | R-06 | depends on CI |
| **Hardware compatibility matrix** — collect field boot reports into `docs/compatibility.md`. | R-12 | new |
| **Multi-arch (arm64)** — explicitly out of scope today; revisit on demand. | reach | — |

---

## Risk-driven workstreams (cross-reference)

| Risk | Severity | Status | Roadmap home |
|------|----------|--------|--------------|
| R-07 secrets in public repo | CRITICAL | MITIGATING | Now (#32 scanner) |
| R-02 no image provenance | HIGH | OPEN | Next (v1.1 signing, #19) |
| R-15 AI runbook accuracy | HIGH | OPEN | Later (#33) |
| R-06 secrets in image | HIGH | MITIGATING | Later (CI enforcement) |
| R-17 malicious model slug | HIGH | MITIGATING | covered; monitor |
| R-04 field update | MED | OPEN (reframed) | optional `PAYLOAD-VERSION` marker, backlog |
| R-19 VS Code telemetry | MED | MONITORING | resolved; watch upstream |
| R-20 Copilot inert | MED | MITIGATING | doc-covered; monitor |
| R-21 framework install fail | MED | MITIGATING | covered; monitor |

---

## Open decisions

1. ~~**Version line**~~ — **RESOLVED 2026-05-23**: adopted **CalVer** (`YYYY.M.PATCH`); first release **v2026.5.0**. Signing lands in a later CalVer release, not gated to a 1.0 semver.
2. **Release channel**: confirm v1.0 stays NFS-internal (per ADR-006) until signing lands, or whether a sha256-only public Gitea release is acceptable interim.
3. **CI timing**: stand up Gitea Actions now (enables R-06/R-07 enforcement as gates) or defer until post-v1.1.

## References

- @.aiwg/planning/iteration-001-plan.md — iteration-1 scope and Definition of Done
- @.aiwg/risks/risk-list.md — reconciled risk register (2026-05-23)
- @.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md — wizard-first + signing-deferred decision
- @.aiwg/architecture/adr-003-verification-rigor.md — verification/signing standard
- @docs/release-process.md — release procedure
