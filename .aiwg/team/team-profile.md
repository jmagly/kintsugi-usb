# Team Profile — Kintsugi USB

**Document status**: BASELINED v1.0
**Last updated**: 2026-04-20

## Team Composition

### Current (size 1)

| Role | Person | Responsibility |
|------|--------|----------------|
| Maintainer / Architect / Release Manager | **Joseph Magly** (`roctinam`) | All roles: vision, design, implementation, release, support |

### Contributor Policy (if the team grows)

This is currently a solo project. If a second contributor joins:
- New contributor adds themselves to this table via PR
- A contributor guide (`CONTRIBUTING.md`) will be authored at that point
- PR review becomes REQUIRED for merges to `main` once there are 2+ contributors

## Communication

- **Issues**: Gitea only — https://git.integrolabs.net/roctinam/kintsugi-usb/issues (per CLAUDE.md "Never create issues on GitHub")
- **Decisions**: captured in ADRs under `.aiwg/architecture/adr-*.md`
- **Design discussion**: SDLC artifacts under `.aiwg/` + inline doc comments
- **Security concerns**: `SECURITY.md` (to be authored per sad-review-security.md required change)

## Decision-Making Authority

| Decision type | Authority |
|---------------|-----------|
| Architectural (ADR-level) | Maintainer + published ADR |
| Release approval | Maintainer |
| License / legal | Maintainer, consulting published guidance |
| Security-impacting change | Maintainer; escalation path: the change is paused until the ADR or risk-list update is drafted |
| Documentation / doc-only fix | Maintainer or any future contributor |

Since it's a solo project today, "maintainer" and "team" are synonymous. This document exists to prevent ambiguity if that changes.

## Tools and Platforms

### Source Control
- Gitea (self-hosted at `git.integrolabs.net`) — canonical home
- GitHub is explicitly NOT used (per CLAUDE.md directive)

### Issue Tracking
- Gitea labels: `phase: imaging`, `phase: distribution`, `phase: payload`, `priority: high`, `priority: low`
- Iteration labels: `iteration-1`, etc.

### API Access
- `roctibot-token` at `~/.config/gitea/roctibot-token` — standard operations
- `admin-token` at `~/.config/gitea/admin-token` — repo creation only

### CI/CD
- Currently NONE
- Target: Gitea Actions once `scripts/` has shellcheckable content (see test-strategy.md §5)

### Development Environment
- Primary workstation: the maintainer's Linux dev box (where this repo lives)
- Hardware test pool: fleet hosts ref-host-1, ref-host-2, ref-host-3, ref-host-4
- Recipient simulation: any non-fleet machine + a spare 64 GB USB 3.x

## Workflow Conventions (from CLAUDE.md)

### Commits
- Conventional commits: `type(scope): subject`
- **No AI attribution** (per CLAUDE.md; commits reflect the human author who reviewed and approved)
- Imperative mood

### Branching
- Trunk-based: `main` branch
- Short-lived topic branches for larger work; merge via PR when contributor count grows
- No persistent `develop` or `release` branches planned

### Documentation principles (from CLAUDE.md §"Documentation Principles")
1. End-user first (README + flash docs readable by non-technical recipient)
2. Reproducible imaging (all build steps scripted + idempotent)
3. Anti-patterns explicit (say what NOT to do — wrong `dd` target, unsigned downloads, tokens in persistence)
4. Verification always (every doc ends with checksum/boot test/smoke test)

### Public-repo security rules (from CLAUDE.md §"Public Repo Security")
- NEVER commit `.env`, tokens, SSH keys, API keys, fleet secrets
- NEVER commit `*.img`, `*.img.zst` (published via Gitea releases, not git)
- Sanitize persistence-file content before packaging (prep-master.sh)
- Host-specific recovery packs may reference internal hostnames but MUST NOT contain credentials

## Agent / AI Collaboration Policy

- AIWG SDLC framework installed; agents orchestrate artifact generation under `.aiwg/`
- AI-generated content is reviewed by the maintainer before commit
- No unreviewed AI output ships in runbooks or user-facing docs (mitigates R-15)
- AI commits follow the "No AI attribution" rule (maintainer reviews and signs off)

## Onboarding a New Contributor (future)

If someone joins:
1. They read `README.md`, `CLAUDE.md`, `AIWG.md`, and `.aiwg/intake/*` to understand scope and conventions
2. They review SAD + ADRs
3. They submit a first PR adding themselves to the team table in this doc
4. A `CONTRIBUTING.md` is drafted collaboratively at that point
5. PR review becomes required for merges to `main`

## References

- `.aiwg/intake/project-intake.md`
- `CLAUDE.md`
- `AIWG.md`
- `.aiwg/reports/abm-gate-report.md`
