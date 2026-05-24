# CLAUDE.md
<!-- aiwg-managed -->
<!-- AIWG.md is the CLAUDE.md companion for non-Claude providers; same content. -->


This file provides guidance to Claude Code when working with this codebase.

## Repository Purpose

**Kintsugi USB** — build, distribution, and recovery tooling for an AI-assisted rescue boot USB.

The drive is a Ventoy-based multi-boot USB built on top of Ubuntu 24.04 Desktop (with persistence) that ships with:

- Rescue ISOs (SystemRescue, Clonezilla, GParted Live, Memtest86+)
- Offline LLM inference stack (`llama.cpp` + Qwen GGUF models)
- Online LLM stack (`claude` CLI)
- Host-specific recovery runbooks and AGENT-CONTEXT packs
- Fleet inventory and diagnostic scripts

See [README.md](README.md) for user-facing overview and [docs/about-the-name.md](docs/about-the-name.md) for the naming rationale.

This repo is the public distribution point. The drive itself carries a snapshot of this repo's `docs/` and `scripts/` at imaging time; recipients can update in the field via `scripts/update-payload.sh` once it exists.

## Tech Stack

- **Boot**: Ventoy multi-boot, GRUB (UEFI + legacy)
- **Base OS**: Ubuntu 24.04 LTS Desktop (persistent)
- **AI**: `llama.cpp`, GGUF models (Qwen 3.5 4B/9B), `claude` CLI
- **Imaging**: `dd`, `zstd`, `sha256sum`, Ventoy installer
- **Scripting**: Bash
- **Docs**: Markdown

## Directory Layout

```
README.md                       # Public overview + tagline
CLAUDE.md                       # This file (Claude Code context)
AIWG.md                         # AIWG framework context (auto-generated)
docs/                           # Authoritative build/use docs
├── about-the-name.md           # Etymology + philosophy
├── requirements.md             # Project requirements
├── architecture.md             # Design: Ventoy + persistence + AI layer
├── build-guide.md              # Master USB build from scratch
├── physical-test-guide.md      # Physical hardware test procedure
└── test-strategy.md            # Test strategy
scripts/                        # Image pipeline + payload update tools (TBD)
manifest/                       # ISO/tool/model manifests + checksums (TBD)
.aiwg/                          # SDLC artifacts (intake, requirements, architecture, …)
```

## Related Repos

| Repo | Relation |
|------|----------|
| `roctinam/sysops` | Source of migrated docs; cross-references fleet hosts |
| `roctinam/itops` | CMDB and fleet operational inventory |
| `roctinam/aiwg` | SDLC framework powering `.aiwg/` and `.claude/` tooling |

## Team Directives & Standards

### Documentation Principles

1. **End-user first.** The README and flashing docs must be readable by a non-technical recipient (e.g., a family member, a fleet user who did not build the drive).
2. **Reproducible imaging.** Every step from master USB → distributable image → flashed copy must be scripted and idempotent.
3. **Anti-patterns explicit.** Say what NOT to do (wrong `dd` target, unsigned downloads, tokens in persistence).
4. **Verification always.** Every procedure ends with a verification step (checksum, boot test, or smoke test).

### Issue Tracking (Gitea)

Issues for this repo are tracked at https://git.integrolabs.net/roctinam/kintsugi-usb/issues

Gitea is the origin for all issue tracking across this org. Never create issues on GitHub.

**API Tokens** (same pattern as sysops):

| Token | File | Purpose |
|-------|------|---------|
| **roctibot-token** | `~/.config/gitea/roctibot-token` | Default for all operations |
| **admin-token** | `~/.config/gitea/admin-token` | Repo creation, admin only |

```bash
# Standard API access
TOKEN=$(cat ~/.config/gitea/roctibot-token)
curl -s -H "Authorization: token $TOKEN" \
  "https://git.integrolabs.net/api/v1/repos/roctinam/kintsugi-usb/issues?state=all"
```

**Conventions:**
- Labels for phase (`phase: imaging`, `phase: distribution`, `phase: payload`) and priority (`priority: high`)
- Close issues when resolved; Gitea preserves history

### Git Commit Conventions

- Conventional commits: `type(scope): subject`
- **No AI attribution** — commits reflect the human author who reviewed and approved changes
- Imperative mood in subject

### Public Repo Security

This repo is **public**. Before committing:

- Never commit `.env`, tokens, SSH keys, API keys, or fleet secrets
- Never commit images (`*.img`, `*.img.zst`) — publish via Gitea releases
- Sanitize any persistence-file content before packaging (see `scripts/prep-master.sh` once written)
- Host-specific recovery packs may reference internal hostnames but must not contain credentials

### Distribution Workflow

1. **Build** a master USB using `docs/build-guide.md` (still sysops-era content; will be refined)
2. **Prep** the master for imaging — zero free space, flush caches, sanitize persistence (script TBD)
3. **Image** the master into a compressed distributable archive (script TBD)
4. **Publish** the image as a Gitea release with SHA-256 checksum
5. **Flash** recipients' USBs from the published image (script TBD)
6. **Update** deployed USBs' payloads in the field via rsync to Ventoy partition (script TBD)

Scripts and per-step docs are tracked as issues in this repo.

## AIWG Framework Integration

All AIWG framework context (agents, commands, orchestration patterns, phase workflows) is loaded via the `@AIWG.md` directive at the top of this file.

**Installation**: `/home/roctinam/dev/aiwg` (edge/dev channel, git `main`)

**Project artifacts**: `.aiwg/`

**Installed frameworks**: sdlc (see `aiwg list`)

**Maintenance**:
- Regenerate this file: `/aiwg-regenerate-claude`
- Regenerate AIWG.md: `aiwg hook-regenerate`
- Disable AIWG context: `aiwg hook-disable`
- Health check: `aiwg doctor`

<!-- AIWG:claude-md-hook:start -->

# AIWG


<!--
  This block is managed by `aiwg regenerate` and `aiwg use`.
  Operator content above and below this block is preserved on regenerate.
  To change AIWG.md content, edit .aiwg/AIWG.md (the normalized source)
  then run `aiwg regenerate`.
-->

<!-- AIWG:claude-md-hook:end -->

<!-- AIWG-PARALLELISM-CAP:START -->
## Parallelism Cap

This project caps parallel agent fan-out (#1359):

- **max_parallel_subagents**: 4 (provider default for claude)
- **max_parallel_ralph_loops**: 2 (provider default for claude)
- **max_parallel_mc_missions**: 4 (provider default for claude)

When spawning parallel subagents, take the MIN of: this cap, `AIWG_CONTEXT_WINDOW` budget, the RLM 7-agent hard cap (RLM dispatches only), and the natural task decomposition. Bump via `aiwg config set --project parallelism.max_parallel_subagents N`.

<!-- AIWG-PARALLELISM-CAP:END -->

<!-- aiwg-context-finalization:START -->
## Context Finalization

This section is synthesized after template emission from the current workspace state. Preserve operator-authored content outside AIWG-managed blocks; rerun `aiwg regenerate` to refresh this section after provider, framework, or MCP wiring changes.

### Workspace Snapshot

- Configured providers: claude
- Installed frameworks/addons: sdlc, all
- Recorded deployments: claude, codex
- Normalized project context: `.aiwg/AIWG.md`

### Discover-First Protocol

Before declining an AIWG request as out of scope or inventing a workflow from memory, run `aiwg discover "<the user need>"`. The CLI ranks AIWG capabilities across the installed corpus. Fetch the selected item with `aiwg show <type> <name>`. This prevents decline-without-search failures and hallucinated skill or agent names. Full rule: `agentic/code/addons/aiwg-utils/rules/skill-discovery.md`.

### Engagement Verification

When a user asks whether AIWG is active or engaged in this project, run or read `aiwg status --probe --json` and report the result plainly: engaged state, project root, deployed provider files, installed frameworks/addons, and the next action from the probe. Do not add AIWG attribution, signatures, generated-by text, or passive footers to user files, commits, PRs, comments, code headers, or docs.

### Source Model

- `.aiwg/AIWG.md` is the normalized project-local context entry point.
- Root `AIWG.md` is the generated cross-provider companion loaded through `AGENTS.md` and provider twins.
- `AGENTS.md`, `WARP.md`, `.hermes.md`, and `.github/copilot-instructions.md` are provider-facing bridges, not replacements for `.aiwg/AIWG.md`.
<!-- aiwg-context-finalization:END -->
