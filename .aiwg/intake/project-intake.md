# Project Intake Form (Existing System)

**Document Type**: Brownfield System Documentation
**Generated**: 2026-04-20
**Source**: Codebase analysis of `/home/roctinam/dev/kintsugi-usb`

## Metadata

- Project name: **Kintsugi USB**
- Repository: https://git.integrolabs.net/roctinam/kintsugi-usb.git (public)
- Current Version: pre-1.0 (scaffold phase; 2 commits on `main`)
- Last Updated: 2026-04-20
- Maintainer: Joseph Magly (`roctinam`) — solo
- Stakeholders: Maintainer (builder/operator), fleet users (recipients of flashed USBs), future public recipients

## System Overview

**Purpose**: Build, distribute, and maintain an AI-assisted rescue boot USB ("Kintsugi USB") — a Ventoy multi-boot drive pairing Ubuntu 24.04 with offline/online LLM tooling. The drive *carries* host-specific recovery packs as operator payload, but this repo does not author or own them — those live in the fleet repos (sysops/itops).

**Current Status**: Physical master USB exists and boots (per `README.md`); this repo is newly established as the public distribution point. Content is mid-migration from sibling `roctinam/sysops` repo. **No imaging, distribution, or update scripts exist yet** — `scripts/` and `manifest/` directories are empty.

**Users** (amended 2026-04-20 per ADR-005 — dual product surface):
- **Primary (maintainer)**: Home-lab operator rescuing fleet hosts `ref-host-1`, `ref-host-2`, `ref-host-3`, `ref-host-4` — builds and uses the USB.
- **Secondary (recipients)**: Family members or small-fleet operators receiving a maintainer-flashed copy — explicitly "non-technical recipient" per CLAUDE.md directives.
- **Tertiary (external builders — NEW persona per ADR-005)**: Other home-lab operators or enthusiasts who clone this repo as a **toolkit/SDK** and build their own Kintsugi-like USB with their chosen model set, possibly their own minisign key, their own fleet runbooks. The maintainer's defaults are a starting point, not a requirement.
- **Quaternary (future)**: Broader public via Gitea releases (flash-and-go distribution).

**Tech Stack**:
- **Boot**: Ventoy v1.1.10 (GPT, UEFI + Legacy BIOS, Secure Boot via MOK)
- **Base OS**: Ubuntu 24.04 LTS (Server base + xfce4) with persistence (ext4 `.dat` overlay)
- **AI (offline)**: `llama.cpp` + GGUF models (Qwen2.5-Coder 7B, Phi-4-mini)
- **AI (online)**: `claude` CLI, Codex CLI, Aider
- **Imaging** (planned, not yet built): `dd`, `zstd`, `sha256sum`
- **Repo content**: Markdown documentation + (future) Bash scripts
- **SDLC framework**: AIWG sdlc-complete (installed; intake now in progress)

## Problem and Outcomes

**Problem Statement**: A broken fleet host — or a broken family member's computer — needs recovery. The operator may not have internet, may not be the person who built the fleet, and may need AI assistance to diagnose an unfamiliar failure. Existing rescue USBs (SystemRescue, Clonezilla) solve fragments of this; none combine a persistent desktop OS, offline LLM, host-specific runbooks, and a distributable imaging pipeline.

**Target Personas**:
1. **The builder-operator** (Joseph): needs one USB that works on every fleet host with every rescue tool and both AI modes.
2. **The handoff recipient**: non-technical person receiving a flashed USB; must be able to boot it and either follow a runbook or hand control to an AI agent.
3. **The field updater**: deployed-USB holder who needs to refresh docs/scripts without reflashing.

**Success Metrics** (inferred; not yet formally tracked):
- USB boots on 100% of fleet x86_64 hosts (NFR-3.1)
- Time from power-on to shell: < 60s (NFR-1.1)
- Offline inference usable: Phi-4-mini > 15 tok/s, Qwen 7B > 8 tok/s on target hardware (NFR-1.3, NFR-1.4)
- Distribution artifact produced with verifiable SHA-256 checksum (implicit from CLAUDE.md "Verification always")

## Current Scope and Features

**Implemented on the physical master USB** (per `docs/architecture.md` and `docs/requirements.md`):
- Ventoy multi-boot with custom Ubuntu ML-Support ISO + SystemRescue + Clonezilla + GParted Live + Ubuntu installer + Hiren's BootCD + Memtest86+
- Ventoy persistence (`.dat` file, ~12 GB ext4)
- Offline AI stack: `llama-server`, `llama-cli`, two GGUF models
- Online AI stack: `claude`, `codex`, `aider` binaries
- `start-ai.sh` entrypoint that auto-selects model by RAM and online/offline state
- SSH keychain + fleet `/etc/hosts` entries (10.0.0.x)
- Rescue tool suite (fsck family, gparted, smartctl, testdisk, ddrescue, nmap, grub repair tools, etc.)
- Mechanism to carry operator-provided host recovery packs (the packs themselves — e.g. the N5 Pro SOP — live in sysops, not in this repo)

**Documented but not yet in this repo** (migration in progress):
- Build script for master USB from scratch (`docs/build-guide.md` is narrative; no executable form)
- Imaging script (master → distributable `.img.zst`)
- Flashing script (user-facing)
- Field payload update script (rsync to Ventoy partition)

**Explicitly planned (coming)**:
- `docs/create-image.md`
- `docs/flash-image.md`
- `docs/update-payload.md`

## Architecture (Current State)

**Architecture Style**: Single-artifact bootable appliance + supporting documentation/tooling repository. Not a running service.

**Physical layout** (from `docs/architecture.md` §2):
- GPT USB with: BIOS boot slot, exFAT VENTOY partition (~37 GB, holds ISOs + tools + models + data), EFI system partition, reserved expansion
- Persistence overlay is a `.dat` file inside the VENTOY partition

**Logical components**:
- **Boot layer**: Ventoy bootloader → ISO menu → (selected ISO, optionally with persistence)
- **Base runtime**: squashfs (read-only) + overlayfs (persistence `.dat`, read-write)
- **AI runtime**: `start-ai.sh` orchestrates `llama-server` (OpenAI-compatible API on :8080) + optional cloud CLIs gated by network detection
- **Data plane**: `/data/` on exFAT (scripts, SSH material, docs, recovery packs) — cross-platform readable

**Integration Points**:
- Anthropic API (for `claude`)
- OpenAI API (for `codex`, optionally `aider`)
- Local `llama-server` HTTP API (fallback when offline)
- Fleet SSH (10.0.0.x network)

## Scale and Performance

**Scale**: Single-digit to low-dozens of distributed USBs across a personal fleet and immediate circle. **Not a service** — no concurrency model, no uptime SLO. "Scale" means "number of physical USBs in the field."

**Performance targets** (from NFRs):
- Boot to shell < 60s
- `llama-server` ready < 90s from script start
- Inference throughput depends on target host RAM; model auto-selection handles 8 GB vs 16 GB+

**Bottlenecks / open questions**:
- No imaging pipeline exists yet — current "distribution" is manual Ventoy rebuild per USB
- No field-update mechanism yet — deployed USBs' docs/scripts go stale
- No automated boot test on the fleet (`docs/physical-test-guide.md` is a manual procedure)

## Security and Compliance

**Security Posture**: Baseline, intentionally scoped.

**Controls present** (from `docs/architecture.md` §5):
- Secrets (API keys, SSH private keys) live **only in the persistence overlay** (ext4 with UNIX perms, mode 600); **never in squashfs, never in exFAT data partition**
- API keys sourced at runtime via environment from `~/.config/ai-keys.env` (600)
- Optional LUKS encryption of persistence overlay (stretch goal)
- Repo-level: `.gitignore` in place; CLAUDE.md enforces "no tokens, no `.env`, no `*.img` in repo"

**Data classification**: The repo and distributed image contain **no PII, no customer data, no secrets**. Persistence-layer secrets are user-supplied after flashing and never shipped.

**Compliance requirements**: **None identified.**
- No GDPR scope (no user accounts, no data collection)
- No PCI-DSS (no payments)
- No HIPAA (no health data)
- No SOC2/ISO27001 (no service)

**Supply-chain considerations** (relevant given distribution model):
- Shipping ISOs, binaries (`llama.cpp`, `claude`, `codex`), and GGUF model weights → recipients trust the maintainer's build. No SBOM, signing, or verification pipeline yet. **Noted as a gap.**

## Team and Operations

**Team Size**: 1 (solo maintainer).
**Active Contributors** (git, last 90 days): 1 (Joseph Magly).
**Velocity**: 2 commits on `main` to date; repo is days old.

**Process Maturity**:
- Version Control: Git, Gitea-hosted (`git.integrolabs.net`), public
- Issue tracking: Gitea (https://git.integrolabs.net/roctinam/kintsugi-usb/issues) — **GitHub is explicitly not used**
- Code review: solo; no PR requirements
- Testing: manual physical-hardware procedure documented (`docs/physical-test-guide.md`); no automation
- CI/CD: **none** (no `.github/workflows/`, no Gitea actions yet)
- Documentation: Strong — 7 markdown files in `docs/`, comprehensive `README.md`, CLAUDE.md with explicit team directives
- SDLC adoption: AIWG framework just installed; this intake is the first artifact

**Operational Support**: N/A — this is a build/distribution project, not a running service. "Ops" means "reflash USBs when things drift."

## Dependencies and Infrastructure

**Third-Party Services** (runtime, on the USB):
- Anthropic API (optional, for `claude`)
- OpenAI API (optional, for `codex`/`aider`)

**Third-Party Artifacts** (bundled on USB):
- Ventoy (GPL v3)
- Ubuntu 24.04 LTS (base)
- `llama.cpp` (MIT)
- GGUF models: Qwen2.5-Coder 7B, Phi-4-mini (model licenses vary)
- Rescue ISOs: SystemRescue, Clonezilla, GParted Live, Hiren's BootCD PE
- Claude Code, Codex CLI, Aider

**Repo-level infrastructure**:
- Gitea (self-hosted, internal)
- No CI runners configured yet
- No release automation

## Known Issues and Technical Debt

**Gaps** (migration incomplete, scripts pending):
- `scripts/` empty → imaging, flashing, prep, field-update all manual
- `manifest/` empty → no checksums or reproducibility manifest for the current master
- `docs/build-guide.md` still sysops-era content per CLAUDE.md — needs refinement for public audience
- No automated smoke test for a freshly flashed USB
- No binary signing / supply-chain provenance for shipped image

**LICENSE**: Marked TBD in `README.md` — must resolve before public distribution, especially given bundled third-party artifacts.

## Why This Intake Now?

**Context**: The repo was just established (2 commits old) as a public distribution point. The AIWG SDLC framework was installed alongside the migration. Intake is the first step in bringing the brownfield "USB that already works" under a documented lifecycle suitable for:
- Publishing a reproducible image recipients can flash themselves
- Resolving licensing before public release
- Adding a field-update path so deployed USBs don't decay
- Formalizing the supply-chain story (what's inside, how to verify it)

**Goals**:
- Establish a documented baseline for the existing master USB
- Plan the imaging → distribution → update pipeline as tracked work
- Decide rigor level proportional to a solo, small-audience, non-commercial project

## Attachments

- Solution profile: `solution-profile.md`
- Option matrix: `option-matrix.md`
- Codebase location: `/home/roctinam/dev/kintsugi-usb`
- Repository: https://git.integrolabs.net/roctinam/kintsugi-usb

## Next Steps

1. **Review** this intake and the two companion files for accuracy. Key unknowns flagged below.
2. **Unknowns to clarify**:
   - Distribution audience size (just fleet + family, or broader public release?)
   - License choice (MIT? GPL? Private-only?)
   - Whether compliance-style supply-chain rigor (SBOM, signed releases) is in scope
3. **Start Inception** when ready: `/flow-concept-to-inception`
