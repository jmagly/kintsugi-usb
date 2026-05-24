# Solution Profile

**Document Type**: Existing System Profile
**Generated**: 2026-04-20

## Current Profile

**Profile**: **Prototype → MVP (transitioning)**

**Selection Rationale**:
- The physical master USB **works** (Prototype validated) but the **repo-level distribution pipeline does not yet exist** (no imaging scripts, no manifest, no release automation)
- Audience is very small (solo operator + handful of fleet/family recipients)
- No compliance, no SLA, no customer data, no paying users
- Solo maintainer with strong systems-engineering background (Joseph Magly, per git)

**Not Production / Not Enterprise** because:
- No running service, no users-as-a-service, no uptime commitments
- No regulatory driver
- Team of one; process rigor should match

## Current State Characteristics

### Security
- **Posture**: Baseline (thoughtfully scoped; not comprehensive)
- **Controls Present**:
  - Clear secret boundary (persistence-only, not squashfs, not exFAT)
  - Env-var sourcing for API keys, mode-600 key files
  - Repo hygiene directives in CLAUDE.md (no tokens, no images in git)
- **Gaps**:
  - No release signing / checksums / SBOM for distributed images
  - No verification tooling recipients can run before flashing
  - LICENSE unresolved — legal gap before public release
- **Recommendation**: Add checksum + signature story before first public release; LUKS-on-persistence stays optional.

### Reliability
- **Current SLOs**: N/A — not a service.
- **Boot reliability target**: 100% on fleet x86_64 hosts (NFR-3.1); currently verified manually per `docs/physical-test-guide.md`.
- **Monitoring**: None applicable. The "reliability" signal is "it booted when I plugged it in."
- **Recommendation**: Keep a simple smoke-test checklist; consider a QEMU boot test in CI once scripts land.

### Testing & Quality
- **Test Coverage**: No automated tests. Manual physical-hardware test procedure is documented.
- **Quality Gates**: None in CI (no CI exists).
- **Recommendation**:
  - Short-term: keep manual physical-test-guide as the authoritative gate per release
  - Medium-term: add a QEMU UEFI boot smoke test to CI (Ventoy menu appears → selected ISO boots → shell reachable)
  - Low priority: script-level shellcheck/lint once `scripts/` has content

### Process Rigor
- **SDLC Adoption**: Just beginning (AIWG framework installed, this intake is first artifact)
- **Code Review**: Solo
- **Documentation**: **Strong for a solo project.** 7 well-structured docs, team directives in CLAUDE.md, architecture diagrams included.
- **Recommendation**: Lean into docs-first; skip heavyweight SDLC artifacts that don't fit a solo distribution project.

## Recommended Profile Adjustments

**Current Profile**: Prototype transitioning to MVP
**Recommended Profile**: **Production** — full SDLC doc set per user guidance (2026-04-20)

**Rationale (updated)**:
- Per user guidance, target a **complete documented SDLC artifact set** — not narrowly-scoped Moderate rigor
- Treat this as a publishable, auditable distribution project: reproducible build, signed releases, full traceability, formal test strategy, iteration planning, and CI/CD scaffolding
- Existing `docs/requirements.md`, `docs/architecture.md`, and `docs/test-strategy.md` become authoritative sources that the formal SDLC artifacts build on (not replace)

**Tailoring Notes**:
- **Include**: full use-case elaboration (UC-001..005), formal user stories, NFR register, SAD (multi-agent reviewed), 3–5 ADRs, formal test strategy, supply-chain threat model, iteration-1 plan, team profile, CI/CD scaffold
- **Elevate**: existing `docs/*.md` content feeds into baseline SAD and requirements — don't duplicate, reference
- **Flag for later**: compliance templates, enterprise governance (still out of scope — no regulatory driver)

## Improvement Roadmap

### Phase 1 — Immediate (before first public-ish release)
- Choose and add LICENSE (bundled-artifact compatibility matters: Ventoy GPL, Ubuntu, llama.cpp MIT, model licenses)
- Write `scripts/prep-master.sh` (zero free space, sanitize persistence, flush caches)
- Write `scripts/create-image.sh` (dd + zstd + sha256sum)
- Publish first image to Gitea release with checksum
- Produce `docs/flash-image.md` for non-technical recipients

### Phase 2 — Short-term
- `scripts/update-payload.sh` — rsync `docs/` and `scripts/` snapshots to a deployed USB's Ventoy partition
- QEMU UEFI smoke-test in CI (boots Ventoy menu, selects custom ISO, reaches shell)
- Manifest file with SHA-256s for every ISO, binary, and model shipped on the USB
- Threat-model write-up for the supply chain (one page, not a template dump)

### Phase 3 — Longer-term (only if audience grows)
- Signed releases (cosign / minisign)
- Reproducible-build story for the custom Ubuntu ISO (Cubic is interactive; reproducing bit-for-bit is hard — document the gap)
- Automated fleet-host boot test (PXE-style or via a test rig with IPMI)
- Consider an SBOM if recipients ever include third parties with policies about it
