# Option Matrix (Project Context & Intent)

**Purpose**: Capture what this project IS — its nature, audience, constraints, and intent — to determine appropriate SDLC framework application (templates, commands, agents, rigor levels).

**Generated**: 2026-04-20 (from codebase analysis; no `--interactive` flag, no `--guidance` provided)

## Step 1: Project Reality

### What IS This Project?

**Project Description**:

> Kintsugi USB is a build/distribution/recovery-tooling repository for an AI-assisted rescue boot USB. The drive itself (a Ventoy multi-boot Ubuntu 24.04 persistent live USB with bundled offline LLM stack and host-specific runbooks) already works on a small personal fleet (4 hosts: ref-host-1, ref-host-2, ref-host-3, ref-host-4). This repo is newly established as the **public home** for the drive's build docs, imaging pipeline, and field-update tooling — migrating content from `roctinam/sysops`. Solo maintainer (30+ yr systems-engineering background). Pre-release; scripts and imaging pipeline not yet written; license not yet chosen. Intended recipients are the maintainer himself, a small fleet of operators, and potentially non-technical family members — plus whoever discovers the public repo.

### Audience & Scale

**Who uses this?** (amended 2026-04-20 per ADR-005)
- [x] Just me (personal project) — solo git contributor; fleet is the maintainer's own
- [x] Small team (2–10 people, known individuals) — occasional fleet users, family recipients
- [ ] Department
- [ ] External customers
- [ ] Large scale
- [x] **External builders (NEW per ADR-005)** — home-lab operators who clone this repo as a **toolkit/SDK** to roll their own Kintsugi-like USB with their own model selections, runbooks, and possibly their own signing key. Dual product surface: maintainer ships (a) a tested signed image for flash-and-go recipients, and (b) a reusable toolkit for builders.

**Audience Characteristics**:
- Technical sophistication: **Mixed** — maintainer is expert; recipients explicitly include "non-technical" family members (per CLAUDE.md directive "End-user first")
- User risk tolerance: **Expects stability** for the already-working USB; **experimental OK** for the imaging/update tooling being built
- Support expectations: **Self-service** (README + docs); no SLA, no on-call

**Usage Scale**:
- Active users: low single-digit to low-dozens of flashed USBs (no telemetry — unknown, estimated)
- Request volume: N/A (not a service)
- Data volume: ~55 GB per flashed USB (ISOs + models + tools)
- Geographic distribution: Single location (maintainer's fleet + local circle)

### Deployment & Infrastructure

**Expected Deployment Model**:
- [ ] Client-only app
- [ ] Static site
- [ ] Client-server
- [ ] Full-stack application
- [ ] Multi-system
- [ ] Distributed application
- [ ] Embedded/IoT
- [ ] Hybrid
- [x] **Other — Bootable appliance / distributable disk image.** The "deployment" is flashing a USB; there is no running service. Repo ships docs + (future) scripts; the artifact is a `.img.zst` Gitea release.

**Where does this run?**
- [x] Local only (each USB runs on whatever host it's booted into)
- [ ] Personal / cloud / on-premise / edge / mobile / desktop / browser
- Repo itself: Gitea self-hosted (`git.integrolabs.net`)

**Infrastructure Complexity**:
- Deployment type: **Physical USB mass production** (one master → N flashed copies); no servers, no containers, no orchestration
- Data persistence: Per-USB `.dat` overlay (ext4), user-scoped; no centralized state
- External dependencies (at drive runtime, optional): Anthropic API, OpenAI API
- Network topology: Standalone (drive works fully offline; online AI is an upgrade, not a requirement)

### Technical Complexity

**Codebase Characteristics**:
- Size: **<1k lines** (10 markdown docs; no scripts yet)
- Languages: Markdown (docs), Bash (planned for scripts)
- Architecture: **Single-artifact appliance** documented in Markdown; companion (unwritten) Bash pipeline
- Team familiarity: **Brownfield from the maintainer's POV** — the USB itself is mature; this repo is a fresh public-facing wrapper

**Technical Risk Factors**:
- [ ] Performance-sensitive — target perf is already met on reference hardware
- [x] **Security-sensitive (supply chain)** — recipients trust a binary image they can't easily verify today
- [ ] Data integrity-critical
- [ ] High concurrency
- [ ] Complex business logic
- [x] **Integration-heavy on the drive** — Ventoy + squashfs + overlayfs + llama.cpp + cloud CLIs + rescue ISOs
- [ ] None

---

## Step 2: Constraints & Context

### Resources

**Team**:
- Size: 1 developer (solo)
- Experience: Senior (per CLAUDE.md stated background)
- Availability: Part-time (personal/hobby project adjacent to home-lab operations)

**Budget**:
- Development: Zero (volunteer/personal)
- Infrastructure: Free tier — self-hosted Gitea already exists; USB hardware per-recipient is a fixed cost ($10–$25 per 64 GB USB 3.x)
- Timeline: **No hard deadline**; the drive already works, so there is no urgency to publish

### Regulatory & Compliance

**Data Sensitivity**:
- [x] Public data only — the repo and shipped image contain no PII/PHI/payment data
- Note: Recipient-supplied API keys go into the per-USB persistence overlay, not the distributed image

**Regulatory Requirements**:
- [x] None

**Contractual Obligations**:
- [x] None

**Licensing** (not regulatory, but critical):
- **LICENSE is TBD** — must be resolved before public distribution, especially given bundled third-party artifacts with differing licenses (Ventoy GPLv3, Ubuntu, llama.cpp MIT, Qwen/Phi model licenses, Claude Code EULA). **Flagged as a Phase-1 blocker.**

### Technical Context

**Current State**:
- Current stage: **Prototype validated, pre-MVP distribution**
- Test coverage: Manual physical-hardware test procedure only
- Documentation: **Comprehensive** for a 2-commit repo — 7 docs plus extensive CLAUDE.md team directives
- Deployment automation: **None yet** (core gap this intake should help address)

**Technical Debt**:
- Severity: **Minor** (repo is days old; debt is "not yet written" rather than "written wrong")
- Type: Missing scripts, missing license, missing checksum/signing pipeline
- Priority: **Should address** before first public release

---

## Step 3: Priorities & Trade-offs

### What Matters Most?

**Priority ranking** (inferred from README, CLAUDE.md, project shape — mark for interactive confirmation):

- `2` Speed to delivery — no external deadline, but maintainer wants to stop hand-building each USB
- `3` Cost efficiency — solo/volunteer; every hour counts, but not desperate
- `1` Quality & security — CLAUDE.md directives emphasize reproducibility, verification, no secrets in repo; recipients include non-technical family
- `4` Reliability & scale — scale is tiny; reliability of the already-working drive is a given

**Priority Weights** (inferred; confirm on review):

| Criterion | Weight | Rationale |
|-----------|--------|-----------|
| **Delivery speed** | 0.25 | Maintainer benefit: automate the manual imaging step |
| **Cost efficiency** | 0.15 | Solo project; time is the scarce resource |
| **Quality/security** | 0.45 | Shipping binary images to non-technical recipients; supply-chain trust is the core risk |
| **Reliability/scale** | 0.15 | Drive already meets its reliability targets; scale is intentionally small |
| **TOTAL** | **1.00** | |

### Trade-off Context

**What are you optimizing for?**

> Automate the "master-USB → distributable image → flashed copy → in-field update" pipeline without over-engineering it for an audience that will never exceed a few dozen recipients.

**What are you willing to sacrifice?**

> - No CI/CD initially; manual physical test remains the release gate
> - No reproducible-build guarantee for the custom Ubuntu ISO (Cubic is interactive; documenting the gap is acceptable)
> - No SBOM / no telemetry / no user metrics
> - Runbooks and release notes can be terse; the drive is its own documentation

**What is non-negotiable?**

> - **No secrets in repo or shipped image** (CLAUDE.md explicit directive)
> - **Verification step at the end of every procedure** (CLAUDE.md explicit directive — every doc must end with a checksum, boot test, or smoke test)
> - **End-user-first README and flashing docs** — must be readable by non-technical family member
> - **Reproducible imaging** — scripts must be idempotent so any flashed USB matches the published checksum
> - **No AI attribution in commits** (CLAUDE.md directive)
> - **Gitea-only issue tracking**, never GitHub

---

## Step 4: Intent & Decision Context

### Why This Intake Now?

- [ ] Starting new project
- [x] **Documenting existing project** (the physical drive predates this repo)
- [x] **Preparing for scale/growth** (public repo, imaging pipeline, field-update story)
- [ ] Compliance
- [ ] Team expansion
- [ ] Technical pivot
- [x] **Handoff/transition** — recipients are a form of handoff (they don't build the USB; they consume it)
- [ ] Funding

**What decisions need making?**

> 1. **License** — what LICENSE to apply, compatible with bundled third-party artifacts
> 2. **Audience scope** — is this strictly family + personal fleet, or a genuine public release with broader expectations?
> 3. **Verification rigor** — checksums only, or signed releases (cosign/minisign)?
> 4. **Imaging approach** — `dd | zstd` full-partition image, or a leaner "rehydrate Ventoy + rsync payload" model?
> 5. **Field-update contract** — what exactly is updatable in place (docs? scripts? binaries? models?) and what requires reflashing?

**What's uncertain or controversial?**

> - Whether to invest in reproducible-ISO tooling now or accept Cubic's non-reproducibility and document it
> - Whether to expect non-technical recipients at all, or scope docs only to capable operators

**Success criteria for this intake process**:

> A clear, right-sized SDLC plan for publishing the first distributable image: what docs/scripts must exist, what the release gate looks like, and what's explicitly deferred.

---

## Step 5: Framework Application

### Relevant SDLC Components

**Templates**:
- [x] Intake — **always include** (this doc)
- [ ] Requirements — existing `docs/requirements.md` is already sufficient; **skip the formal templates**
- [x] Architecture (lightweight) — existing `docs/architecture.md` covers most needs; may add one or two ADRs (license choice, imaging strategy)
- [x] Test (lightweight) — `docs/test-strategy.md` + `docs/physical-test-guide.md` already exist; no template doc needed
- [x] Security (single threat-model page for supply chain) — **narrow scope**
- [x] Deployment (flash-image.md, update-payload.md runbooks) — **user-facing, must be non-technical-friendly**
- [ ] Governance — **skip** (solo project)

**Commands**:
- [x] Intake commands — already in use
- [x] Flow commands (gate-check, concept-to-inception) — use sparingly to mark release milestones
- [ ] Quality gates — **skip heavy versions**; physical test guide is the gate
- [x] Specialized — `pr-review` N/A (solo); potentially `troubleshooting-guide` for recipients

**Agents**:
- [x] Core SDLC agents as needed (architecture-designer for ADRs, technical-writer for recipient-facing docs)
- [ ] Security specialists — **light use** for supply-chain threat model only
- [ ] Operations specialists — **skip** (no running service)
- [ ] Enterprise specialists — **skip**

**Process Rigor Level** (updated per user guidance 2026-04-20 — full doc set):
- [ ] Minimal
- [ ] Moderate
- [x] **Full** — complete SDLC artifact set: formal use cases, user stories, NFR register, multi-agent-reviewed SAD, 3–5 ADRs, formal test strategy, supply-chain threat model, iteration-1 plan, team profile, CI/CD scaffold. Existing `docs/*.md` content becomes source material for the formal artifacts.
- [ ] Enterprise (skipped — no regulatory driver)

### Rationale for Framework Choices

> Kintsugi USB is a solo, non-commercial, distributable-appliance project with a well-documented mature core and an unbuilt imaging/update pipeline. It warrants **Moderate rigor** focused on: (1) licensing and supply-chain integrity, (2) user-facing flash/update docs for non-technical recipients, (3) a small risk register tracking distribution concerns, and (4) one or two ADRs for the decisions called out in Step 4. Everything else — formal use-case elaboration, governance, compliance templates, enterprise orchestration — is overkill and should be skipped.

**What we're skipping and why**:

> - Use-case / user-story templates — existing `docs/requirements.md` already has 5 use cases and a traceability matrix
> - Governance / change-control — solo project, no stakeholders to coordinate
> - Compliance templates — no regulatory scope
> - Performance engineering templates — NFRs in `docs/requirements.md` are sufficient; no optimization work planned
> - Production operations templates (ORR, hypercare, incident response) — not a running service
>
> Revisit if: the project attracts multiple maintainers, gains a commercial dimension, or starts carrying user data.

---

## Step 6: Evolution & Adaptation

### Expected Changes

- [ ] No planned changes
- [ ] User base growth (plausible if public release lands, but not expected to exceed "small")
- [x] **Feature expansion** — imaging pipeline, field-update mechanism, possibly additional host runbooks
- [ ] Team expansion
- [ ] Commercial / monetization
- [ ] Compliance
- [x] **Technical pivot** — potential migration to a reproducible-build toolchain if public recipients demand it

**Adaptation Triggers**:

> - If a second maintainer joins → add a lightweight contributor guide, PR review requirement
> - If recipients start reporting tampering concerns or the image is hosted on third-party mirrors → invest in signed releases
> - If a non-personal-fleet user files a substantial issue → escalate user-facing docs priority
> - If bundled binaries get flagged by any recipient's endpoint protection → need a provenance / SBOM story

**Planned Framework Evolution**:

- Current: intake + lightweight architecture + user-facing deployment runbooks
- 3 months: add a supply-chain threat model page + 1–2 ADRs (license, imaging strategy) + the actual scripts
- 6 months: add a minimal CI (QEMU boot smoke test) if scripts have stabilized
- 12 months: revisit only if audience, team, or risk posture changes materially

---

## Summary for the Maintainer

**Bottom line**: This is a solo, pre-MVP distribution project with a mature core artifact and an unbuilt pipeline. Keep SDLC rigor **Moderate and narrowly focused** on three concerns: **license**, **supply-chain integrity**, and **non-technical-friendly flash/update docs**. Everything else is available but not warranted. The natural next step after reviewing this intake is `/flow-concept-to-inception` with guidance pointing at those three concerns.
