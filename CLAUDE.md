# CLAUDE.md

@AIWG.md

This file provides guidance to Claude Code when working with this codebase.

## Repository Purpose

**Kintsugi USB** — build, distribution, and recovery tooling for an AI-assisted rescue boot USB.

The drive is a Ventoy-based multi-boot USB built on top of Ubuntu 24.04 Desktop (with persistence) that ships with:

- Rescue ISOs (SystemRescue, Clonezilla, GParted Live, Memtest86+)
- Offline LLM stack (Ollama + `llama.cpp`); model weights are user-loaded into persistence (`/data/ollama/models`), never baked into the read-only image (ADR-005)
- Pre-installed agentic CLIs (claude-code, codex, opencode, copilot, openclaw, omnius, aider); auth is a post-flash user step (ADR-006 §D5). Hermes installs on demand via `kintsugi-install-hermes`.
- Host-specific recovery packs the drive *carries* (operator-provided from the fleet repos — authored in sysops/itops, not in this public repo)
- Fleet inventory and diagnostic scripts

See [README.md](README.md) for user-facing overview and [docs/about-the-name.md](docs/about-the-name.md) for the naming rationale.

This repo is the public distribution point. The drive carries a snapshot of this repo's `docs/` and `scripts/` at imaging time; recipients update in the field via `git pull` + `ollama pull` (see [docs/update-strategy.md](docs/update-strategy.md)) — a reflash is only needed for base-image changes.

## Tech Stack

- **Boot**: Ventoy multi-boot (UEFI + BIOS); inner ISO is GRUB+isolinux (preserved from the stock Ubuntu image)
- **Base OS**: Ubuntu 24.04 LTS (Xubuntu minimal, persistent via Ventoy)
- **Build**: remaster the stock Ubuntu 24.04 ISO via `livefs-edit` (squashfs repacked with xz) — [ADR-008](.aiwg/architecture/adr-008-build-tooling-remaster-stock-iso.md), supersedes the ADR-007 live-build approach
- **AI**: Ollama + `llama.cpp` (offline runtime); agentic CLIs (claude-code/codex/opencode/copilot/openclaw/omnius/aider)
- **Imaging**: Ventoy installer, `dd`, `zstd`, `sha256sum`
- **Scripting**: Bash · **Docs**: Markdown

## Directory Layout

```
README.md                       # Public overview + tagline
CLAUDE.md                       # This file (Claude Code context)
AIWG.md                         # AIWG framework context (auto-generated)
docs/                           # Authoritative build/use docs
├── about-the-name.md           # Etymology + philosophy
├── requirements.md             # Project requirements
├── architecture.md             # Design: Ventoy + persistence + AI layer
├── build-guide.md              # Manual/reference build (Ventoy mechanics)
├── toolkit-guide.md            # External-builder walkthrough
├── wizard-guide.md             # kintsugi-build reference (prompts, schema, flags)
├── update-strategy.md          # Post-flash refresh model
├── sanitization-checklist.md   # Pre-imaging secret-scan + hygiene rules
├── legacy-device-unlock.md     # Unlock legacy IronKey/Imation encrypted USBs (offline, 32-bit runtime)
├── physical-test-guide.md      # Physical hardware test procedure
└── test-strategy.md            # Test strategy
scripts/                        # Build wizard + imaging pipeline
├── kintsugi-build              # ⭐ single-command build wizard (remaster → ventoy → package)
├── create-image.sh             # package a built image → <name>.img.zst + .sha256
├── flash-image.sh / verify-image.sh / prep-master.sh / publish-release.sh
└── usb-toolkit/                # remaster + on-USB tooling
    ├── make-remaster-iso.sh    # ADR-008 builder (remaster stock ISO)
    ├── agentic-provision.sh    # in-chroot: the 6 agentic CLIs (+aider)
    ├── ai-stack-provision.sh   # in-chroot: Ollama + mikefarah yq
    ├── make-ventoy-image.sh    # assemble Ventoy .img (+ persistence, + --ollama-models)
    ├── kintsugi-models / kintsugi-frameworks / kintsugi-install-hermes
    ├── first-boot-setup.sh / start-ai.sh / usb-test-harness.sh
    └── build-custom-iso.sh     # superseded live-build builder (ADR-007→008; provenance)
manifest/                       # models-recommended.yaml, agentic-frameworks-recommended.yaml, THIRD-PARTY-LICENSES.md
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
- Sanitize any mastered-USB/persistence content before packaging (`scripts/prep-master.sh` — for the manual/master path; the remaster build is clean by construction)
- Host-specific recovery packs may reference internal hostnames but must not contain credentials

### Distribution Workflow

The `kintsugi-build` wizard auto-chains steps 1–3 (ADR-008 remaster pipeline); the rest are per-build operations:

1. **Build** the custom ISO — `scripts/usb-toolkit/make-remaster-iso.sh` remasters the stock Ubuntu 24.04 ISO (rescue tools + agentic CLIs + offline AI stack).
2. **Assemble** the Ventoy `.img` — `scripts/usb-toolkit/make-ventoy-image.sh` (bootloader + persistence; optional pre-loaded models via `--ollama-models`).
3. **Package** into a distributable archive — `scripts/create-image.sh` → `<name>.img.zst` + `.sha256`.
4. **Publish** as a Gitea release — `scripts/publish-release.sh` (sha256-verified; minisign signing arrives in v1.1, #19).
5. **Flash** recipients' USBs — `scripts/flash-image.sh` (+ `verify-image.sh` post-flash check).
6. **Update** deployed USBs in the field — `git pull` + `ollama pull` per [docs/update-strategy.md](docs/update-strategy.md); reflash only for base-image changes.

A fresh clone runs the whole thing with `./scripts/kintsugi-build`. Per-step work is tracked as issues in this repo.

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

@AIWG.md

<!--
  This block is managed by `aiwg regenerate` and `aiwg use`.
  Operator content above and below this block is preserved on regenerate.
  To change AIWG.md content, edit .aiwg/AIWG.md (the normalized source)
  then run `aiwg regenerate`.
-->

<!-- AIWG:claude-md-hook:end -->
