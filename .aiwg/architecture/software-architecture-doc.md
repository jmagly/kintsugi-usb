# Software Architecture Document (SAD) — Kintsugi USB

**Status**: BASELINED v1.0 (amended 2026-04-20 per ADR-005 — see §0 Amendment below)
**Date**: 2026-04-20
**Author**: Architecture Designer (SDLC Elaboration Wave 2)
**Synthesizer**: Documentation Synthesizer (Elaboration Wave 2)
**Reviewers**:
- Security Architect — CONDITIONAL (v0.1) → resolved in v1.0
- Test Architect — APPROVED with suggestions (v0.1) → addressed in v1.0
- Requirements Analyst — APPROVED with suggestions (v0.1) → addressed in v1.0

## 0. Amendment 2026-04-20 (per ADR-005 and ADR-006 — two same-day amendments)

Two successive amendments on 2026-04-20 materially reshape the architecture. Read this section before trusting any subsequent content in this document.

### 0.1 ADR-005 amendments (first pass)

ADR-005 (user-driven model loading + toolkit product surface + Ollama coexistence + model-inventory correction):

- **§1.2 Scope**: explicit dual product surface (maintainer image + external-builder toolkit).
- **§4.2 AI Stack**: Ollama coexists with llama.cpp as a second local runtime. Model weights are user-loaded, not bundled. `start-ai.sh` refactor target documented in ADR-005 §D3–D4.
- **§4.3 Tier B pipeline**: `kintsugi-models` CLI added; payload tarball amended (may collapse, pending iteration-1 spike per ADR-002 amendment).
- **§9.5 Licensing**: model-weight redistribution drops out of scope.
- **§10 ADR summaries**: ADR-004 marked SUPERSEDED; ADR-005 summary added; ADR-001/002 marked MATERIALLY AMENDED.
- **§11**: R-09 reframed; R-17 and R-18 added.

### 0.2 ADR-006 amendments (second pass)

ADR-006 (wizard-first UX + user-driven agentic frameworks + VS Code/Copilot base + NFS publish target + signing deferred):

- **§1.2 Scope**: primary UX is `scripts/kintsugi-build` wizard; distributed signed images recede in priority, the wizard-driven self-build is the primary product.
- **§4.2 AI Stack**: unchanged from §0.1 amendment; extended conceptually — user also picks agentic frameworks (Aider, Claude Code, Codex CLI, etc.) at build time.
- **§4.3 Tier B pipeline**: adds (a) `kintsugi-build` wizard as the orchestrator, (b) `kintsugi-frameworks` CLI + `manifest/agentic-frameworks-recommended.yaml` paralleling the model toolkit, (c) VS Code + GitHub Copilot + `gh` CLI installed in the Cubic chroot step of `build-custom-iso.sh` as default base IDE infrastructure.
- **§4.3 publish target**: changed from Gitea releases to **warehouse NFS mount** for v1.0 (`scripts/publish-release.sh` targets NFS).
- **§9.1 Security cross-cutting — signing commitment ROLLED BACK**: v1.0 ships sha256-only verification. Full signing flow (minisign keypair, `verify-release.sh`, per-OS one-liners) moves to v1.1. Trade-off documented in ADR-006 §D5.
- **§9.5 Licensing**: **RESOLVED → MIT** (ADR-001 accepted). LICENSE file committed.
- **§10 ADR summaries**: ADR-006 summary added; ADR-001 marked ACCEPTED (MIT); ADR-003 marked v1.0-deferred.
- **§11**: R-19 (VS Code telemetry default) and R-20 (Copilot subscription dependency) added; R-02 severity temporarily bumped for v1.0 sha256-only period.

### 0.3 Reading order

For any detail: ADR-006 supersedes ADR-005 supersedes the section content below where they conflict. Inline amendment notes are marked in affected sections; the formal SAD §10 erratum pass (Gitea issue #23) is an iteration-1 deliverable that will reconcile this document's body with these amendments.

---

**Project**: Kintsugi USB — AI-assisted rescue boot media
**Repository**: https://git.integrolabs.net/roctinam/kintsugi-usb

---

## 1. Introduction

### 1.1 Purpose

This Software Architecture Document (SAD) describes the architecture of Kintsugi USB: a distributable Ventoy multi-boot rescue USB with a bundled offline/online AI assistance stack, and the build/distribution/update pipeline that produces and maintains it. It is the authoritative architecture reference for the Elaboration baseline and the target against which Construction work (scripts, runbooks, release automation) will be validated.

The SAD deliberately covers **two distinct architectural surfaces**:

- **Tier A — the Runtime Artifact**: the flashed USB as it exists in the hands of an operator. This tier is mature; a working master USB already exists.
- **Tier B — the Build & Distribution Pipeline**: the repository-side tooling that produces, publishes, flashes, and updates copies of the drive. This tier is the new architectural surface area for v1.0 and is **not yet implemented**.

Tier A is summarized here by reference to the existing [docs/architecture.md](../../docs/architecture.md); this SAD does not duplicate its ASCII diagrams. Tier B is given its first formal architectural treatment in this document.

### 1.2 Scope

**In scope (v1.0)**:

- The USB physical layout, boot flow, AI runtime, data plane, and security boundaries
- The build pipeline from master USB to distributable `.img.zst`
- The publication workflow (Gitea releases, checksums, **detached signatures — see §9.1 signing commitment**)
- The end-user flash workflow and its recipient-facing documentation (including the **recipient verification UX** contract)
- The in-field payload update workflow for deployed USBs
- A `SECURITY.md` and tamper-reporting / coordinated-disclosure channel
- Non-functional qualities captured in [`.aiwg/requirements/nfr-register.md`](../requirements/nfr-register.md)

**Out of scope (v1.0, deferred to later releases)**:

- LUKS-encrypted persistence (stretch goal; see NFR-4.3). Even deferred, LUKS passphrase rotation is the recipient's responsibility.
- Reproducible builds for the custom Ubuntu ISO (Cubic is non-reproducible by design; accepted with documentation — see R-03)
- SBOM generation (the third-party license manifest substitutes for v1.0)
- ARM64 and non-x86_64 architectures
- Automated CI (Gitea Actions). Pre-publish scanning runs locally via the build host until Gitea Actions is adopted post-v1.0.
- Any running service, telemetry, or multi-user concurrency model

### 1.3 Definitions and Acronyms

| Term | Meaning |
|------|---------|
| **Ventoy** | Multi-boot USB bootloader (GPL v3) that boots ISOs directly without extraction |
| **GGUF** | GPT-Generated Unified Format; binary container for quantized LLM weights |
| **llama.cpp** | C++ inference engine for GGUF models; ships `llama-server` (HTTP API) and `llama-cli` |
| **MOK** | Machine Owner Key; used to enroll third-party boot components under UEFI Secure Boot |
| **Persistence overlay** | Ventoy-managed `.dat` file (ext4) layered via overlayfs on top of the read-only squashfs |
| **exFAT** | Cross-platform filesystem used for the VENTOY partition; no UNIX permissions |
| **squashfs** | Compressed, read-only filesystem containing the base OS image |
| **Cubic** | GUI chroot-based Ubuntu ISO customization tool used to build the custom ML-Support ISO |
| **AIWG** | AI Writing Guide; the SDLC framework under which this SAD is produced |
| **minisign** | Small signing tool (Ed25519) considered for detached release signatures |

### 1.4 References

- [docs/architecture.md](../../docs/architecture.md) — runtime artifact architecture (PRIMARY source for Tier A)
- [docs/requirements.md](../../docs/requirements.md) — original FR/NFR list
- [docs/build-guide.md](../../docs/build-guide.md) — master USB build procedure (Cubic walkthrough)
- [docs/physical-test-guide.md](../../docs/physical-test-guide.md) — manual boot test procedure (authoritative for TC-3 rescue-tool list and per-host compatibility matrix, referenced by NFR-3.1 / NFR-8.1)
- [docs/test-strategy.md](../../docs/test-strategy.md) — test strategy
- Host-specific recovery SOPs (e.g. N5 Pro) are out of repo scope — they live in the fleet repos (sysops); the USB carries them as operator payload
- [.aiwg/requirements/use-cases.md](../requirements/use-cases.md) — formal UC-001..005 + UC-006/007 placeholders
- [.aiwg/requirements/nfr-register.md](../requirements/nfr-register.md) — formal NFR register (NFR-1..NFR-10)
- [.aiwg/intake/project-intake.md](../intake/project-intake.md) — brownfield system intake
- [.aiwg/intake/option-matrix.md](../intake/option-matrix.md) — non-negotiables and framework decisions
- [.aiwg/risks/risk-list.md](../risks/risk-list.md) — 16-risk register (R-01..R-16)
- [CLAUDE.md](../../CLAUDE.md) — team directives (secrets hygiene, conventional commits, Gitea-only)
- `SECURITY.md` (NYE; see §9.1) — tamper-reporting and coordinated-disclosure policy

### 1.5 Document Conventions

- Requirements are referenced by ID: `FR-*`, `NFR-*`, `UC-*`, `R-*`, `ADR-*`.
- Tier A = the USB artifact; Tier B = the build/distribution pipeline.
- Components marked **(NYE)** — "not yet existing" — are architecturally specified here but unimplemented as of 2026-04-20.

---

## 2. Architectural Goals and Constraints

The architecture is shaped by three forces: non-negotiables from the intake, measurable NFR targets, and the risks the architecture must actively mitigate.

**Non-negotiables** (from [option-matrix.md Step 3](../intake/option-matrix.md) and CLAUDE.md):

1. **No secrets in the repo or the shipped image.** Secrets exist only in per-USB persistence overlays, populated by recipients after flashing.
2. **Verification always.** Every procedure — build, publish, flash, update — ends with a verifiable step (checksum, signature verification, boot test, or smoke test).
3. **End-user-first recipient docs.** Flash documentation must be readable by a non-technical family member and must include platform-native verification commands.
4. **Reproducible imaging.** Scripts must be idempotent so any flashed USB matches the published checksum.
5. **Gitea-only issue tracking** (`git.integrolabs.net`); GitHub is not used.
6. **No AI attribution in commits.** Human author is the accountable reviewer.
7. **Public tamper-reporting channel.** A `SECURITY.md` file establishes a coordinated-disclosure address so recipients and third parties can report suspected tampered images, leaked secrets, or vulnerabilities in bundled components.

**NFR-driven constraints** (from [nfr-register.md](../requirements/nfr-register.md)):

- Boot < 60s to shell (NFR-1.1); llama-server ready < 90s (NFR-1.2)
- Offline inference throughput: Phi-4-mini > 15 tok/s, Qwen 7B > 8 tok/s on reference hardware (NFR-1.3/1.4)
- Published image size ≤ 30 GB compressed (NFR-1.6); USB utilization < 95% of 59 GB (NFR-2.1)
- 100% boot success on the four fleet hosts (NFR-3.1); ≥ 95% first-try flash success with documented tools (NFR-3.4)
- Supply-chain integrity: SHA-256 + detached signature on every release (NFR-4.4); zero secrets in repo or image (NFR-4.1, NFR-4.5, NFR-4.7)
- Flash docs pass a non-technical-reader review (NFR-5.4)
- Field-update script is idempotent and a no-op on a second run (NFR-6.5)
- Licensing reconciled before first public release (NFR-10.1..10.5)

**Risk-driven architecture decisions** (from [risk-list.md](../risks/risk-list.md)):

- R-01 (license TBD) and R-02 (no provenance) force a published-manifest + checksum + signature architecture and drive ADR-001 and ADR-003.
- R-04 (no field-update) and R-05 (imaging is manual) define the entire Tier B scope.
- R-06 and R-07 (accidental secrets in image or repo) shape `prep-master.sh` (NYE) as a sanitize-and-fail-closed tool — including enumeration of CLI auth-state paths (§4.3) — and the `.gitignore` posture.
- R-03 (Cubic non-reproducibility) is ACCEPTED with documentation; reproducibility is not a v1.0 goal.
- R-15 (AI-drafted runbooks) requires human-reviewed sign-off on every shipped runbook and a "verification always" tail on every procedure.

---

## 3. Use Case View

Kintsugi USB's architecture is driven by five current use cases and two future ones (formalized in [use-cases.md](../requirements/use-cases.md)). Each UC exerts specific architectural pressure:

- **UC-001 (Boot Fleet Host for Rescue)** — Drives the multi-boot + persistence architecture (Ventoy, GRUB, MOK, overlayfs). Primary force behind Tier A boot layer and the rescue-ISO bundle.
- **UC-002 (AI-Assisted Log Analysis, Online)** — Drives the network-aware `start-ai.sh` orchestrator, the persistence-only secret architecture (API keys never in squashfs), and the online CLI inclusion decision.
- **UC-003 (AI-Assisted Script Generation, Offline)** — Drives bundling `llama.cpp` + GGUF models directly on the USB, RAM-based model auto-selection, and the OpenAI-compatible local API that lets Aider run against `localhost:8080` without code changes.
- **UC-004 (Disk Imaging Before Major Change)** — Drives inclusion of Clonezilla and `ddrescue`-grade tooling in the custom ISO; shapes the data-partition expectation that recipients can store image artifacts. Alternate flow 2a's `dd | zstd | sha256sum` manual recipe depends on those binaries being on PATH in the custom ISO.
- **UC-005 (Fresh OS Installation)** — Drives inclusion of the Ubuntu 24.04 Desktop installer ISO and the `/data/scripts/` fleet-tooling layout (including FR-7.3 `/etc/hosts` fleet entries).
- **UC-006 (future — Distribute a Flashed USB to a Non-Technical Recipient)** — Motivates the entire Tier B pipeline: `create-image.sh`, Gitea releases, non-technical flash docs (with verification UX), licensing reconciliation, tamper-reporting channel.
- **UC-007 (future — In-Field Payload Update Without Reflashing)** — Motivates the update-boundary decision (what is mutable in place vs what requires reflash) and `update-payload.sh`.

Full scenarios, alternate flows, and NFR linkages are in [use-cases.md](../requirements/use-cases.md).

---

## 4. Logical View

### 4.1 Two-Tier Architecture

```
                         ┌──────────────────────────────────┐
                         │   Tier B: Build & Distribution   │
                         │   (this repo — mostly NYE)       │
                         │                                  │
                         │   docs/ + scripts/ + manifest/   │
                         │              │                   │
                         │   prep ──► image ──► publish     │
                         │                                  │
                         └─────────────┬────────────────────┘
                                       │ produces (.img.zst + .sha256 + .sig)
                                       ▼
                         ┌──────────────────────────────────┐
                         │   Tier A: Runtime Artifact       │
                         │   (the flashed USB)              │
                         │                                  │
                         │   Ventoy + ISOs + squashfs +     │
                         │   persistence + AI stack + data  │
                         │                                  │
                         └──────────────────────────────────┘
                                       ▲ updated in field
                                       │ (payload only)
                         ┌─────────────┴────────────────────┐
                         │   update-payload.sh (NYE)        │
                         └──────────────────────────────────┘
```

The deployed artifact and the repository that produces it are one system viewed through two lenses. The boundary between them is the `.img.zst` release asset plus its detached signature (§9.1).

### 4.2 Tier A — Runtime Artifact

Tier A is fully described in [docs/architecture.md](../../docs/architecture.md) §§1–7. This SAD summarizes the architecturally significant elements:

**Boot layer** (docs/architecture.md §3). Ventoy v1.1.10 on a GPT USB handles both UEFI and legacy BIOS (FR-1.1). Secure Boot traverses the Ventoy shim + MOK enrollment path (FR-1.5, NFR-7.4). The Ventoy menu is the single user-facing entry point to every bundled ISO (FR-1.3, NFR-5.1).

**Base runtime** (FR-2.1). The custom Ubuntu ML-Support ISO boots as a standard live session: `squashfs` read-only base + overlayfs on top of a `ubuntu-ml-persist.dat` ext4 file (~12 GB) held in the VENTOY exFAT partition. All user state (installed packages, shell history, configs, API keys) lives in the overlay (FR-5.1..FR-5.4, NFR-3.5). All FR-6 rescue tooling — including FR-6.9 chroot via bind-mounts — ships inside the squashfs and is on PATH in the live session.

**AI stack** (docs/architecture.md §4). A systemd/rc.local hook runs `start-ai.sh`, which:

1. Detects available RAM and selects a GGUF model (Qwen2.5-Coder 7B for ≥16 GB hosts, Phi-4-mini for 8 GB hosts — FR-4.7).
2. Starts `llama-server` on `localhost:8080` exposing the OpenAI-compatible API. **Exit contract**: non-zero RC if `llama-server` fails to bind, so the boot smoke test can catch it.
3. Tests network reachability to `api.anthropic.com`.
4. If online: sources API keys from `~/.config/ai-keys.env` (mode 600) **in the persistence overlay**. FR-3.1 (`claude` in PATH), `codex`, and `aider` are then reported as available. Note: the `claude` and `codex` CLIs may also write auth state to `~/.claude/`, `~/.config/anthropic/`, and `~/.config/openai/` on first login; these paths also live in the persistence overlay (not in squashfs) and are enumerated in `prep-master.sh`'s scan set (§4.3) so that a master USB that was ever logged into is rejected by imaging.
5. If offline: points Aider at the local server and reports the offline toolset.
6. Emits a structured status banner and writes `/var/log/kintsugi/boot-timing.log` capturing RAM detection, model load start/end timestamps, and `llama-server` ready timestamp so NFR-1.1/1.2 are measurable by a test harness rather than a stopwatch. `llama-cli --benchmark` output is captured to the same log directory for NFR-1.3/1.4.

The local `llama-server` API is the **architectural seam** that lets Aider and other OpenAI-compatible clients work identically online and offline. This seam is load-bearing for UC-003 and is contract-testable via `curl /v1/chat/completions` independently of model choice.

**Data plane** (FR-9.1). The VENTOY exFAT partition carries ISOs, tools, models, and `/data/` (scripts, SSH **public** authorized_keys, fleet docs, per-host recovery packs). exFAT is chosen for cross-platform readability (NFR-7.1) and has no UNIX permissions — therefore **no secrets, no private keys, and no CLI auth tokens live on exFAT** (NFR-4.7). The ext4 persistence overlay is the only location where mode-600 files are meaningful and is where FR-7.1 private SSH keys live.

**Security boundaries** (docs/architecture.md §5). Three concentric zones:

- squashfs (read-only, world-readable) — ships OS + tools + AI binaries, zero secrets (NFR-4.1).
- persistence overlay (ext4, UNIX perms) — the only place secrets live (NFR-4.2, NFR-4.6). Live-session user model: the live session runs as the default Ubuntu live user; files under `~/.config/` and `~/.ssh/` are owner-only (mode 600) with that user as owner. Where NFR-4.2 names `root`, it refers to the effective privilege available via `sudo` in the live session, not a separate root-owned store.
- exFAT data partition (no perms, cross-platform) — public artifacts only: ISOs, tool binaries, GGUF models, markdown docs, scripts, `authorized_keys`. **NEVER** secrets, private keys, or auth tokens (NFR-4.7).

This layering is the single most important Tier A invariant. Every Tier B pipeline step must preserve it.

### 4.3 Tier B — Build & Distribution Pipeline

Tier B is the repository side of the system. It is largely **not yet existing (NYE)**; this SAD provides its first-pass architecture.

**Components**:

| Component | Status | Responsibility |
|-----------|--------|----------------|
| `docs/build-guide.md` | Exists (sysops-era, needs refinement per R-14) | Human-followed procedure to produce a master USB using Cubic + Ventoy installer |
| `scripts/prep-master.sh` | **NYE** | Sanitize a master USB before imaging. Steps: (1) wipe shell history; (2) confirm persistence overlay carries no secrets; (3) zero free space on VENTOY partition (for better zstd ratio); (4) flush filesystem caches; (5) **enumerate and scan all known CLI auth-state paths** — `~/.config/ai-keys.env`, `~/.claude/`, `~/.config/anthropic/`, `~/.config/openai/`, `~/.config/codex/`, `~/.aws/credentials`, `~/.ssh/id_*` — and abort on any non-empty find; (6) grep for known secret patterns (`sk-ant-`, `sk-`, `BEGIN OPENSSH PRIVATE KEY`, `AKIA[0-9A-Z]{16}`, `ghp_[A-Za-z0-9]{36}`, internal hostname ranges — authoritative list pinned in `scripts/secret-patterns.txt` and cross-referenced from R-06) and abort on any hit. Idempotency: the script is pure-sanitize; a second run on an already-sanitized master is a no-op. (Mitigates R-06.) |
| `scripts/create-image.sh` | **NYE** | Read the prepped master USB via `dd` → pipe through `zstd` → compute `sha256sum` → produce detached signature; emit `kintsugi-<version>.img.zst` + `kintsugi-<version>.img.zst.sha256` + `kintsugi-<version>.img.zst.sig` + a `manifest/<version>.json` listing every bundled ISO/binary/model with its upstream checksum. The manifest is itself hash-chained into the signed release artifact so a tampered manifest cannot lie about bundled components. |
| Publish workflow | **NYE** (manual today; will use `mcp__git-gitea__create_release`) | Attach `.img.zst`, `.sha256`, `.sig`, manifest, and the public signing key to a Gitea release. The signing key fingerprint is also pinned in `SECURITY.md`. |
| `docs/flash-image.md` | **NYE** | Non-technical recipient flash procedure covering: (1) **recipient verification UX** — one-line platform-native verification commands per OS: `shasum -a 256 <file>` (macOS/Linux), `certutil -hashfile <file> SHA256` (Windows cmd), `Get-FileHash <file>` (PowerShell), each with the expected SHA-256 side-by-side for visual comparison; (2) optional but recommended signature verification using minisign with the published public key; (3) balenaEtcher as primary flash path, `dd` / Rufus as alternates; (4) post-flash boot smoke test; (5) top-5 common-error remediation table (NFR-5.4, NFR-8.2, NFR-9.2). A one-line copy-pasteable helper script is shipped alongside the release for recipients who prefer automation over manual comparison. |
| `scripts/flash-image.sh` | **NYE** | Technical-operator helper: prompt for target device with `lsblk`-style confirmation, verify source SHA, verify source signature, `zstdcat \| dd`, verify flashed device, report success. |
| `scripts/update-payload.sh` | **NYE** | In-field update: `rsync` current `docs/`, `scripts/`, `data/recovery/` (and optionally swap `.gguf` models and cloud CLI binaries) onto a mounted VENTOY partition without touching ISOs or the persistence overlay. Must be idempotent (NFR-6.5) and safe against a mounted live session. Supports `--dry-run` flag emitting a planned-delta report so CI-style tests can assert "second run is a no-op" without manual file-tree diffs. |
| `docs/update-payload.md` | **NYE** | Instructions for running `update-payload.sh` on any Linux host against a plugged-in deployed USB |
| `manifest/` | **NYE** | Per-release JSON listing every bundled artifact, upstream source URL, upstream SHA-256, and redistribution license |
| `SECURITY.md` | **NYE** | Tamper-reporting address (security@integrolabs.net or Gitea private-issue policy), coordinated-disclosure expectations, published signing-key fingerprint, and vulnerability-report SLA for bundled components |

**Update boundary**. The Tier B architecture commits to a clear contract about what is mutable in place and what requires reflash:

| Kind of content | Mutable via `update-payload.sh` | Requires reflash |
|-----------------|---------------------------------|------------------|
| `docs/`, `scripts/`, `data/recovery/` runbooks | YES | — |
| Cloud CLI binaries (`claude`, `codex`) on exFAT `/tools/bin/` | YES (pending license resolution — R-01, R-10) | — |
| GGUF model files on exFAT `/models/` | YES (NFR-6.2) | — |
| Bundled rescue ISOs | YES (file-copy per NFR-6.1), but large | — |
| Custom Ubuntu ML-Support squashfs ISO | NO | YES |
| `llama.cpp` binary (baked into squashfs) | NO | YES |
| Persistence overlay content | Operator's responsibility, never touched by updater | — |

This boundary is what makes field updates tractable: all frequently-changing content sits on exFAT and is file-copyable; only the structural base (the squashfs) requires a full reflash.

---

## 5. Process View

### 5.1 Boot-time Process (Tier A)

1. Firmware hands off to Ventoy (UEFI via shim+MOK, or legacy via MBR stage).
2. User selects "Ubuntu ML-Support 24.04" from the Ventoy menu.
3. Ventoy mounts the custom ISO's squashfs and overlays the persistence `.dat` via overlayfs.
4. Ubuntu userspace reaches multi-user target; a systemd unit (or `/etc/rc.local`) invokes `start-ai.sh`.
5. `start-ai.sh` performs RAM detection, starts `llama-server`, tests reachability, sources persistence secrets if online, prints status (NFR-9.1), and writes `/var/log/kintsugi/boot-timing.log`.
6. Operator obtains a shell with all tools on PATH; recovery work begins.

NFR-1.1 (<60s to shell) and NFR-1.2 (<90s to llama-server ready) constrain this flow and are independently verifiable from the boot-timing log.

### 5.2 Build-time Process (Tier B)

```
  master USB (Cubic-built, hand-curated)
        │
        ├─► [prep-master.sh]
        │      ├── sanitize persistence overlay (NYE)
        │      ├── enumerate & clear CLI auth-state paths
        │      ├── zero free space on VENTOY partition
        │      ├── grep secret patterns; ABORT on hit (R-06)
        │      └── flush caches, unmount cleanly
        │
        ├─► [create-image.sh]
        │      ├── dd if=/dev/sdX | zstd -T0 -19 > kintsugi-v1.0.img.zst
        │      ├── sha256sum kintsugi-v1.0.img.zst > .sha256
        │      ├── minisign -S kintsugi-v1.0.img.zst > .sig
        │      └── produce manifest/v1.0.json (hash-chained into .sig)
        │
        ├─► [QEMU smoke test]
        │      └── zstdcat | qemu-system-x86_64 -bios OVMF → boot-to-menu in ~30s
        │
        └─► [publish]
               ├── gitea create_release v1.0
               └── attach .img.zst, .sha256, .sig, manifest, public key
```

The pipeline is linear and idempotent once the master exists. Each step's verification is its own exit condition (non-zero RC aborts the chain). **Release-blocker rule**: no version ships without a full round-trip (master → image → flash-to-spare-USB → boot) plus a QEMU UEFI smoke test.

### 5.3 Update-time Process (Tier B, field)

```
  maintainer publishes payload update (docs/ + scripts/ tagged snapshot)
        │
        ▼
  recipient plugs deployed USB into any Linux host
        │
        ├─► mount VENTOY exFAT partition
        ├─► [update-payload.sh]   (optionally --dry-run first)
        │      ├── rsync repo docs/ → /data/docs/
        │      ├── rsync repo scripts/ → /data/scripts/
        │      ├── optional: swap /models/*.gguf or /tools/bin/* binaries
        │      ├── write PAYLOAD-VERSION with git SHA + timestamp (NFR-6.6)
        │      └── idempotent: second run is a no-op
        └─► unmount; USB ready for next boot
```

### 5.4 Verification Hooks

Each pipeline step emits a machine-readable pass/fail probe so test authoring does not have to guess the success contract:

| Step | Successful output contract | Failure indicator |
|------|----------------------------|-------------------|
| `prep-master.sh` | RC=0; stdout ends with `PREP OK <master-id> <timestamp>`; no matches printed from secret-scan phase | RC=1; stderr names the matched pattern and file (abort-fail-closed) |
| `create-image.sh` | RC=0; produces `.img.zst`, `.sha256`, `.sig`, manifest; stdout prints image SHA and signature fingerprint | RC=1; partial artifacts moved to `work/failed/` |
| QEMU smoke | RC=0; Ventoy menu visible within 30s (asserted via screenshot or serial-console grep) | RC=1; serial console captured for diagnosis |
| `update-payload.sh` | RC=0; `--dry-run` prints planned deltas; a follow-up real run matches; a third run is empty | RC=1; dirty-state detected |
| Boot smoke (post-flash) | `usb-test-harness.sh --full` passes; `/var/log/kintsugi/boot-timing.log` exists and parses | harness non-zero RC with test-case-level detail |

---

## 6. Deployment View

**Physical artifact**: a single 64 GB USB 3.x stick. Partition layout is specified in docs/architecture.md §2: a 1 MB BIOS-boot slot, a ~37 GB exFAT VENTOY partition (carrying ISOs, tools, models, data, and the persistence `.dat`), a 32 MB EFI system partition, and ~22 GB of reserved/unallocated expansion room.

**Distribution channel**: https://git.integrolabs.net/roctinam/kintsugi-usb/releases. Each release is a Gitea release asset comprising `kintsugi-<version>.img.zst`, its `.sha256`, its detached `.sig` (minisign), and `manifest/<version>.json`. The release page hosts the public signing key and links to `SECURITY.md` for tamper-reporting. (See §9.1 for the signing commitment and §1.2 scope.)

**Recipient environments**: x86_64 UEFI or legacy-BIOS PCs. Verified on the fleet (`ref-host-1`, `ref-host-2`, `ref-host-3`, `ref-host-4` — NFR-3.1, NFR-8.1; authoritative per-host expected-result matrix in [docs/physical-test-guide.md](../../docs/physical-test-guide.md)). Unverified on broader hardware; R-12 tracks the compatibility uncertainty; `docs/compatibility.md` (living document fed by field reports) is the only v1.0 mitigation.

**Flash hosts**: any Windows/macOS/Linux machine with balenaEtcher, `dd`, or Rufus (NFR-8.2). Documentation assumes a non-technical recipient by default and an `lsblk`-capable operator as the secondary audience. Every recipient is routed through the **platform-native verification command** in `docs/flash-image.md` before flashing.

**Tamper-reporting channel**: `SECURITY.md` at the repo root establishes a coordinated-disclosure address and the published signing-key fingerprint. Recipients and third parties report suspected tampered images, leaked secrets, or vulnerabilities in bundled components through this channel.

---

## 7. Implementation View

**Repository structure**:

```
kintsugi-usb/
├── README.md                    # Public overview + tagline
├── CLAUDE.md                    # Team directives for Claude Code agents
├── AIWG.md                      # AIWG framework context
├── SECURITY.md                  # Tamper-reporting & disclosure (NYE)
├── LICENSE                      # TBD — blocked on ADR-001 (R-01)
├── docs/                        # Authoritative build/use docs (exists)
├── scripts/                     # Pipeline scripts (empty; NYE)
│   └── secret-patterns.txt      # Authoritative scan patterns (NYE)
├── manifest/                    # Per-release artifact manifests (empty; NYE)
└── .aiwg/                       # SDLC artifacts (intake, requirements, architecture, risks)
```

**Languages**:

- Markdown — all documentation (authoritative source for both repo and USB `/data/docs/`).
- Bash — all pipeline scripts (when written). Constraint: POSIX-ish, run-anywhere-Linux, no exotic dependencies.
- JSON — `ventoy.json` (exists on the master), per-release `manifest/<version>.json` (NYE).

**Tooling**:

- Cubic — interactive Ubuntu ISO customizer for the master (R-03 accepted).
- Ventoy installer — writes Ventoy to a USB.
- `dd`, `zstd`, `sha256sum`, `rsync` — pipeline primitives.
- `minisign` — detached release signatures (v1.0 commitment, see §9.1).
- `gitleaks` or `detect-secrets` — pre-commit and pre-publish secret scanner (run locally pending CI adoption per R-07).
- `qemu-system-x86_64` + OVMF — build-host smoke test harness.
- Gitea MCP tools (`create_release`, `get_latest_release`) — release automation when adopted.

---

## 8. Data View

### 8.1 Persistence Overlay Schema

The ext4 `ubuntu-ml-persist.dat` is the single writable store for per-USB state. Owner of user-home files is the live-session Ubuntu user (see §4.2 live-session user model note). Its logical schema:

| Path | Purpose | Permissions | Lifecycle |
|------|---------|-------------|-----------|
| `~/.config/ai-keys.env` | API keys (ANTHROPIC_API_KEY, OPENAI_API_KEY) | 600 owner-only | Recipient populates post-flash |
| `~/.claude/` | `claude` CLI auth/session state | 700 dir | Recipient populates via `claude login` post-flash; scanned by prep-master |
| `~/.config/anthropic/`, `~/.config/openai/`, `~/.config/codex/` | Cloud CLI auth directories | 700 dir | Same as above |
| `~/.ssh/` | Operator **private** SSH keys and known_hosts | 700 dir, 600 keys | Recipient populates post-flash |
| `~/.bash_history` | Shell history | default | Accumulates per session |
| `/var/lib/apt/` | Installed packages from `apt install` | default | Persists across reboots (FR-5.4) |
| `/etc/` customizations | Hostname, network overrides | default | Persists |

**Invariants**:

- Nothing pre-populated by the maintainer lives in the overlay. The overlay starts empty on a freshly-flashed USB. This is why the master-USB prep step must wipe any overlay content (R-06).
- **Private** SSH keys live only in this overlay (FR-7.1). **Public** authorized_keys are the only SSH material permitted on the exFAT `/data/` partition (NFR-4.7).

### 8.2 Manifest Schema (NYE)

Each published release carries `manifest/<version>.json`, which is hash-chained into the release's detached signature (§4.3) so a tampered manifest cannot lie about bundled components:

```
{
  "version": "v1.0.0",
  "git_sha": "<repo SHA at build time>",
  "image": {"name": "kintsugi-v1.0.img.zst", "sha256": "..."},
  "signing_key_fingerprint": "RWQ...",
  "flash_benchmark_minutes": 25,
  "artifacts": [
    {"type": "iso",    "name": "systemrescue-11.03-amd64.iso",
     "upstream_url": "...", "upstream_sha256": "...", "license": "GPL-3.0"},
    {"type": "binary", "name": "llama-server",
     "upstream_url": "...", "upstream_sha256": "...", "license": "MIT"},
    {"type": "model",  "name": "qwen2.5-coder-7b-instruct-q4_k_m.gguf",
     "upstream_url": "...", "upstream_sha256": "...", "license": "..."}
    /* ... every bundled third-party component ... */
  ]
}
```

The manifest is the programmatic counterpart to `manifest/third-party-licenses.md` (NFR-10.2). The `flash_benchmark_minutes` row lets recipients compare local flash time to the published reference (NFR-1.5).

### 8.3 /data Partition Organization

On the VENTOY exFAT partition:

```
/data/
├── docs/          # Synced from repo docs/ (updatable in field)
├── scripts/       # Synced from repo scripts/ (updatable in field)
├── recovery/      # Host-specific recovery runbooks (updatable in field)
└── PAYLOAD-VERSION  # git SHA + last-update timestamp (NFR-6.6)
```

Models at `/models/` and tool binaries at `/tools/bin/` sit alongside `/data/` on the same partition (layout per docs/architecture.md §2). SSH `authorized_keys` (public only) may live under `/data/ssh/authorized_keys`.

---

## 9. Cross-Cutting Concerns

### 9.1 Security Architecture

Fully specified in docs/architecture.md §5. Restated here as invariants the architecture must preserve:

- **Zero secrets in the shipped squashfs** (NFR-4.1). Enforced by `prep-master.sh` grep-and-abort (NYE) and manual review checklists in docs/build-guide.md.
- **Zero secrets, zero private keys, zero CLI auth tokens on exFAT `/data/`** (NFR-4.7). Enforced by the same scanner and by CLAUDE.md-mandated build hygiene. Public `authorized_keys` are permitted.
- **Zero secrets in the public repo** (NFR-4.5, R-07). Enforced by `.gitignore` + `gitleaks` pre-commit hook (run locally pending CI).
- **Persistence is the only secret store**; recipient-populated after flashing.
- **Supply-chain integrity via checksums AND signatures** (NFR-4.4). Every published v1.0 release carries a `SHA-256` file **and** a minisign (or cosign) detached signature over both the image and the manifest. The public signing key is published on the release page and pinned in `SECURITY.md`. This is the v1.0 **commitment** — not a deferral. Rationale: the audience-scope question (Open Question 1) remains OPEN; since a public-repo Gitea release implies at least the *possibility* of a non-fleet recipient, we cannot safely ship v1.0 on checksums-only (R-02). Signing infrastructure is modest for a solo maintainer (minisign is a single binary plus a single keypair stored offline) and is the smallest additional control that closes the R-02 substitution threat.
- **Signing-key rotation and recovery posture**: the signing key is stored offline on the maintainer's air-gapped medium; key compromise triggers an immediate revocation notice in `SECURITY.md` and a re-signed release.
- **LUKS passphrase rotation** (deferred stretch NFR-4.3): if LUKS persistence is later adopted, passphrase rotation is the recipient's responsibility, not the maintainer's. This is stated now so the expectation ships with the architecture.

**Security contact and disclosure** (new):

A `SECURITY.md` artifact at the repo root (NYE; see §4.3) establishes:

1. A tamper-reporting address (email or Gitea private-issue policy) for recipients, third parties, or downstream integrators.
2. The coordinated-disclosure expectation (triage acknowledgment within one week; fix-or-statement within a reasonable window for a solo maintainer).
3. The published signing-key fingerprint (mirroring the release-page copy).
4. A vulnerability-report SLA for bundled components (Ventoy, llama.cpp, Qwen/Phi, cloud CLIs).

Without this channel, the "verification always" non-negotiable would have no escalation path for the case where verification *fails*.

### 9.2 Observability

- `start-ai.sh` prints a structured status banner on every boot (NFR-9.1): detected RAM, selected model, online/offline, per-tool OK/FAIL, `llama-server` URL, and structured timing written to `/var/log/kintsugi/boot-timing.log` for test-harness consumption.
- Boot banner also displays the `PAYLOAD-VERSION` git SHA and last-update timestamp so operators see at a glance whether their runbooks are stale (mitigates R-15).
- `llama-cli --benchmark` output is captured on first run and archived to `/var/log/kintsugi/benchmark-<date>.log` so NFR-1.3/1.4 are measurable without ad-hoc timing.
- Flash-tool errors are surfaced with a top-5 common-error remediation table in `docs/flash-image.md` (NFR-9.2) (NYE).
- Persistence load failures are visible on first boot with a prominent banner rather than a silent fallback (NFR-9.3).
- `usb-test-harness.sh --full` (per `physical-test-guide.md`) is architecturally promoted to a first-class runtime component: it is the canonical implementation of TC-3/TC-6/TC-11 and the post-flash boot smoke test.
- **Release telemetry / usage metrics are explicitly deferred.** A solo, non-commercial project with a few dozen recipients has no justification for a telemetry pipeline; revisit only if audience expands.

### 9.3 Internationalization

Out of scope. English-only documentation and tool surfaces.

### 9.4 Accessibility

Out of scope for v1.0. The primary user surface is a terminal and a documentation tree; no GUI is in the critical path. Future consideration only if a broader public recipient base materializes.

### 9.5 Licensing

**Unresolved as of 2026-04-20.** Tracked as R-01 (CRITICAL) and NFR-10.1..10.5. The first public release is blocked until:

1. A top-level `LICENSE` compatible with all bundled artifacts is chosen (likely GPL-3.0 to align with Ventoy's copyleft — see ADR-001).
2. `manifest/third-party-licenses.md` enumerates every bundled component with its upstream license.
3. The Claude Code and Codex CLI redistribution terms are reviewed; if redistribution is disallowed, those binaries ship as a post-flash installer rather than baked into the image. This review also covers whether the cloud CLIs phone home with telemetry from a rescue-boot context (a privacy concern distinct from redistribution).
4. GGUF model weights' licenses are surfaced to the user at runtime (NFR-10.5).

---

## 10. Architectural Decisions Summary

Amended 2026-04-21 (#23) to reflect the final state after the two same-day ADR amendments (ADR-005, ADR-006) and the 2026-04-21 ADR-002 spike (#21):

- **ADR-001 — License Selection**. **ACCEPTED 2026-04-20: MIT.** Originally scoped to cover bundled-artifact license compatibility (Qwen/Phi/Claude EULA redistribution). After ADR-005 + ADR-006 moved model weights and agentic-framework binaries to user-driven loading, ADR-001's scope reduced significantly — MIT repo-license plus `manifest/THIRD-PARTY-LICENSES.md` enumerating bundled **binaries only** (Ventoy GPLv3, llama.cpp MIT, Ollama MIT, VS Code MSFT license, Copilot extension MSFT license, gh MIT, rescue ISOs). Model-weight + framework-binary license concerns are out of scope. R-01 CLOSED.

- **ADR-002 — Imaging Strategy**. **Amended twice**: first by ADR-005 (payload tarball may collapse since weights are gone); second by the 2026-04-21 spike (#21) which resolved to **collapse**. v1.0 ships a single signed artifact `kintsugi-vX.Y.Z.img.zst` + `.sha256` + `manifest.json`. Estimated compressed size 1.7–2.6 GB. First real build measures and records in `manifest.json`; >6 GB revisits the decision.

- **ADR-003 — Verification Rigor**. **Amended by ADR-006 §D5: v1.0 signing DEFERRED to v1.1.** Iteration-1 ships sha256-only verification (`scripts/verify-image.sh` handles this); minisign keypair + `kintsugi.pub` + `verify-release.sh` + per-OS signed-verification one-liners all move to iteration-2 (Gitea #19). Trade-off: weaker supply-chain posture on v1.0 maintainer-produced images; mitigated by NFS-internal-only distribution in v1.0 (ADR-006 §D4) and by the toolkit-first product orientation (most users build their own).

- **ADR-004 — AI Model Selection and Update Boundary. SUPERSEDED by ADR-005** (2026-04-20, hours after original acceptance). The "maintainer ships curated Qwen2.5-Coder 7B + Phi-4-mini" premise is obsolete — models are now user-driven via `kintsugi-models` CLI + `manifest/models-recommended.yaml`. The superseded ADR file is retained for history with a supersession banner.

- **ADR-005 — Toolkit Scope + Ollama + User-Driven Models**. **ACCEPTED 2026-04-20.** Establishes the dual product surface (toolkit SDK + distributed image), Ollama coexistence with llama.cpp, user-driven model loading (no bundled weights), and the model-inventory correction (Qwen3.5 4B/9B are the tested defaults, not 2.5-Coder). Drives §0, §1.2, §4.2, §4.3, §9.5, §11 amendments throughout this SAD.

- **ADR-006 — Wizard-First UX + User-Driven Agentic Frameworks + NFS Publish + Signing Deferred**. **ACCEPTED 2026-04-20.** Introduces `scripts/kintsugi-build` as the single-command entry point; extends the user-driven-loading pattern from models to agentic frameworks via `kintsugi-frameworks` CLI + `manifest/agentic-frameworks-recommended.yaml`; adds VS Code + GitHub Copilot + gh CLI as default base IDE infrastructure (with telemetry off); changes v1.0 publish target to warehouse NFS; defers minisign signing to v1.1.

---

## 11. Architecturally Significant Risks

The architecture actively mitigates the following risks (numbered per [risk-list.md](../risks/risk-list.md)):

- **R-01 LICENSE TBD** — Mitigated by ADR-001 and NFR-10.1..10.5; first public release is gated on resolution.
- **R-02 No supply-chain provenance** — Mitigated by NFR-4.4 (SHA-256 **+ minisign signature**) on every v1.0 release, the manifest schema (§8.2) hash-chained into the signature, a recipient verification UX in `docs/flash-image.md`, and a tamper-reporting channel via `SECURITY.md`.
- **R-04 No field-update mechanism** — Architecturally addressed by `update-payload.sh` (NYE) and the §4.3 update-boundary contract.
- **R-05 Imaging pipeline NYE** — Architecturally addressed by the Tier B component decomposition (§4.3); concrete implementation is Construction-phase work.
- **R-06 Accidental secrets in squashfs or exFAT** — Mitigated by `prep-master.sh`'s scan-and-abort pattern (with explicit CLI-auth-state path enumeration, §4.3), the §9.1 secrets-only-in-persistence invariant, and `scripts/secret-patterns.txt` as the single source of truth for scan patterns.
- **R-07 Secrets in public repo** — Mitigated by `.gitignore`, CLAUDE.md directives, and a `gitleaks` pre-commit hook (run locally; CI adoption deferred).
- **R-08 Flash failure on recipient hardware** — Partially mitigated by the documented USB compatibility table (NFR-8.3) and the post-flash smoke-test requirement.
- **R-11 Non-technical recipient flashing struggle** — Mitigated by the Etcher-primary, `dd`-secondary recipient doc architecture, the platform-native verification UX (§4.3), and a copy-pasteable helper script (NFR-5.4, NFR-9.2).
- **R-15 AI-generated runbooks shipping bad guidance** — Mitigated by the "verification always" tail on every procedure, a human-review sign-off gate before any runbook ships, and the boot-banner PAYLOAD-VERSION/timestamp display (§9.2).

Risks **ACCEPTED** at the architectural level:

- **R-03 Cubic non-reproducibility** — Documented as a known limitation; migration path to a declarative builder (live-build, mkosi) is deferred until audience growth or external demand justifies it.
- **R-13 Persistence corruption on unclean shutdown** — ext4 journaling provides structural protection; secrets are treated as reconstructable rather than irreplaceable.
- **R-16 Bus factor of 1** — Accepted for a personal/small-fleet project; docs-as-product partially mitigates.

Risks **MONITORING** (no architectural action unless triggered):

- **R-09 GGUF models outdate** — Handled by the 6-month refresh cadence; no auto-update mechanism.
- **R-10 `claude`/`codex` CLI auth flow changes** — Handled via `update-payload.sh` in-field binary swap; the llama.cpp offline path is the resilient fallback. CLI auth-state paths are enumerated in `prep-master.sh` (§4.3) so changes in upstream auth-storage conventions are caught at build time.
- **R-12 Non-fleet hardware boot variance** — Handled by a `docs/compatibility.md` living document fed by field reports.
- **R-14 Sysops-era doc drift** — Handled by the per-doc migration checklist; LAM gate prerequisite.

---

## 12. Open Questions

Questions remaining open at v1.0 baseline of this SAD:

1. **Audience scope** (**STILL OPEN**). Is v1.0 strictly personal fleet + family, or a genuine public release with broader expectations? The answer tightens or relaxes several v1.0 controls: the plain-language depth of `docs/flash-image.md` (NFR-5.4), the formality of the `SECURITY.md` disclosure SLA, and whether signing-key ceremony needs witnesses. **The v1.0 signing commitment in §9.1 resolves the most consequential branch of this question defensively** — we ship signed regardless of where on the audience spectrum v1.0 lands. Remaining effect of this question is on documentation register and disclosure-process formality, not on cryptographic posture. Owner: project lead.

2. **Reproducible-build investment** (RESOLVED for v1.0, open for v1.x). Is a migration from Cubic to a declarative builder (live-build, mkosi, debos) in scope for this lifecycle, or do we ship R-03 accepted and document the gap? Default for v1.0: accept. Revisit in v1.x if external reproducibility demand materializes.

3. **Cloud CLI redistribution mode** (owned by ADR-001). Do `claude` and `codex` ship baked into the image (subject to EULA review) or as a post-flash installer invoked on first online boot? Owned by ADR-001 and NFR-10.4. This question also covers the cloud-CLI telemetry review (§9.5 item 3).

4. **CI adoption timing**. Gitea Actions is deferred for v1.0; pre-publish scanning runs locally. When does CI become a v1.x blocker? Default: when a second maintainer joins or when the release cadence exceeds one per quarter.

5. **SECURITY.md authorship split**. Should `SECURITY.md` content be co-authored with the risk-register owner, or owned purely by the architecture track? Default: architecture drafts, risk-register owner reviews.

---

## 13. Use Case → Component Coverage Matrix

| Use Case | Tier A Components | Tier B Components | Primary NFRs |
|----------|-------------------|-------------------|--------------|
| **UC-001** Boot for Rescue | Ventoy + GRUB + MOK; squashfs + overlayfs; rescue-tool suite in custom ISO; rescue ISOs (SystemRescue, Clonezilla, GParted); FR-6.9 chroot via bind-mounts | `docs/physical-test-guide.md`; compatibility table | NFR-1.1, NFR-3.1, NFR-7.4, NFR-8.1 |
| **UC-002** AI Log Analysis (Online) | `start-ai.sh`; persistence `~/.config/ai-keys.env` and `~/.claude/` etc.; `claude`/`codex`/`aider` binaries; network-detect logic | Cloud-CLI redistribution resolution (ADR-001); `update-payload.sh` binary-swap path | NFR-4.2, NFR-4.6, NFR-5.2, NFR-10.4 |
| **UC-003** AI Script Gen (Offline) | `llama.cpp` (server + cli) in squashfs; GGUF models on exFAT; OpenAI-compat API seam at `localhost:8080`; RAM-based model selection | `update-payload.sh` model-swap; ADR-004 model selection | NFR-1.2, NFR-1.3, NFR-1.4, NFR-6.2 |
| **UC-004** Disk Imaging | Clonezilla ISO; custom Ubuntu ISO with `dd`/`ddrescue`/`zstd` on PATH (supports alt-flow 2a manual recipe); data partition as local scratch | — | NFR-2.1, NFR-3.3 |
| **UC-005** Fresh OS Install | Ubuntu 24.04 Desktop ISO; `/data/scripts/` fleet tooling; `/etc/hosts` fleet entries (FR-7.3); SSH authorized_keys (public only) on exFAT | `update-payload.sh` script refresh | NFR-7.1, NFR-7.4 |
| **UC-006** (future) Distribute to Non-Technical Recipient | `.img.zst` as the atomic deliverable | `prep-master.sh`, `create-image.sh`, publish workflow, `docs/flash-image.md` (with verification UX), `scripts/flash-image.sh`, manifest, `SECURITY.md`, ADR-001, ADR-003 | NFR-1.6, NFR-3.4, NFR-4.4, NFR-5.4, NFR-8.2, NFR-9.2 |
| **UC-007** (future) In-Field Payload Update | `/data/` layout; `PAYLOAD-VERSION` marker; boot-banner version display | `scripts/update-payload.sh`, `docs/update-payload.md`, update-boundary contract (§4.3), `--dry-run` flag | NFR-6.1, NFR-6.2, NFR-6.5, NFR-6.6 |

### 13.1 FR Coverage Index

| FR group | SAD section(s) | Notes |
|---|---|---|
| FR-1.x (boot) | §4.2 Boot layer; §5.1; NFR-7.2/7.4 | UEFI, legacy, Ventoy menu, MOK enrollment |
| FR-2.x (custom ISO) | §4.2 Base runtime | squashfs + overlayfs + PATH for rescue tools |
| FR-3.x (cloud AI) | §4.2 AI stack step 4; §8.1 auth-state rows; §13 UC-002 | Redistribution in ADR-001 |
| FR-4.x (local AI) | §4.2 AI stack; §13 UC-003; ADR-004 | llama.cpp + GGUF models; RAM-based selection |
| FR-5.x (persistence) | §4.2 Base runtime; §8.1 schema | overlay is sole writable store |
| FR-6.x (rescue tools) | §4.2 Base runtime (incl. FR-6.9 chroot); §9.2 | TC-3 tool list authoritative in `physical-test-guide.md` |
| FR-7.x (fleet tooling) | §4.2 Data plane; §8.1 SSH row; §8.3; §13 UC-005 | Public keys on exFAT, private in overlay |
| FR-8.x (model/tooling installers) | §4.3 `update-payload.sh`; §8.3 /tools | — |
| FR-9.x (cross-platform data) | §4.2 Data plane; NFR-7.1 | exFAT choice rationale |

---

## 14. Glossary

- **ADR** — Architecture Decision Record; a short document capturing a single architectural decision and its rationale.
- **Cubic** — Custom Ubuntu ISO Creator; a GUI chroot-based tool for customizing Ubuntu ISOs.
- **exFAT** — Extensible File Allocation Table; a cross-platform filesystem with no UNIX permission model.
- **GGUF** — A binary container format for quantized LLM weights used by llama.cpp.
- **llama.cpp** — An MIT-licensed C++ inference engine for GGUF models. Ships `llama-server` (HTTP API) and `llama-cli`.
- **minisign** — Ed25519 signing tool; selected in ADR-003 as the v1.0 detached-signature mechanism.
- **MOK** — Machine Owner Key; the UEFI Secure Boot enrollment mechanism used by Ventoy's shim.
- **NYE** — Not Yet Existing. Components marked NYE are architecturally specified in this SAD but unimplemented as of 2026-04-20.
- **overlayfs** — A Linux union filesystem that layers a read-write overlay on top of a read-only lower layer.
- **persistence overlay** — The ext4 `.dat` file managed by Ventoy that holds per-USB writable state.
- **squashfs** — A compressed, read-only filesystem used as the base layer of the custom Ubuntu live image.
- **Tier A / Tier B** — This SAD's shorthand for the runtime USB artifact (A) and the repository-side build/distribution pipeline (B).
- **Ventoy** — A GPL v3 multi-boot USB bootloader that boots ISO files directly without extraction.

---

## Change Log

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| v0.1 | 2026-04-20 | Architecture Designer | Initial draft for parallel review |
| **v1.0 (BASELINED)** | 2026-04-20 | Documentation Synthesizer | Merged Security (CONDITIONAL → resolved), Testability (APPROVED w/ suggestions), Traceability (APPROVED w/ suggestions) reviews |

**v0.1 → v1.0 notable changes**:

- §1.2, §9.1, §10 (ADR-003): **committed to minisign detached signatures for v1.0** (was deferred). Resolves Security required-change 1.
- §4.3 (`docs/flash-image.md` row), §6, §9.1: added **recipient verification UX** specification with platform-native commands per OS and a helper script. Resolves Security required-change 2.
- §2 non-negotiable 7, §4.3, §6, §9.1, §11 R-02, §12 Q5: added **`SECURITY.md` / tamper-reporting channel**. Resolves Security required-change 3.
- §4.2 AI stack step 4, §4.3 `prep-master.sh` row, §8.1, §11 R-06/R-10: **enumerated CLI auth-state paths** (`~/.claude/`, `~/.config/anthropic/`, `~/.config/openai/`, `~/.config/codex/`, `~/.aws/credentials`, `~/.ssh/id_*`) in prep-master's scan set. Resolves Security required-change 4.
- §5.4 (new): added **Verification Hooks** subsection with per-step pass/fail contracts (Testability R-1).
- §4.2 step 6, §9.2: added `/var/log/kintsugi/boot-timing.log` and `llama-cli --benchmark` capture for observable NFR-1.1..1.4 (Testability R-2).
- §4.3 `prep-master.sh` row, §7: named `scripts/secret-patterns.txt` as the authoritative pattern set (Testability R-3, Security suggested-change 1).
- §4.3 `update-payload.sh` row, §5.4: added `--dry-run` flag for idempotency testing (Testability R-4).
- §1.2, §5.2, §7: added QEMU UEFI smoke test and Gitea Actions deferral statement (Testability S-1, S-2).
- §9.2: elevated `usb-test-harness.sh --full` to first-class runtime component; added PAYLOAD-VERSION boot banner (Testability S-3; Security suggested-change 2).
- §8.2: added `flash_benchmark_minutes` and `signing_key_fingerprint` rows (Testability S-4; Security suggested-change 4 via hash-chained signature over manifest).
- §4.2, §8.1, §11: clarified private-key vs public-key placement; added FR-6.9 chroot note; clarified live-session user model reconciling NFR-4.2 root ownership with §8.1 owner-only (Traceability required-changes 1, 2, 3).
- §13.1 (new): added **FR coverage index** appendix (Traceability suggested-change 1).
- §13: added **Primary NFRs** column to the UC matrix (Traceability suggested-change 2).
- §1.2 LUKS / §9.1: added LUKS passphrase-rotation responsibility note (Security suggested-change 3).
- §12: consolidated open questions; Open Question 1 (audience scope) explicitly noted as **STILL OPEN**; signing-timeline question CLOSED (committed for v1.0); added CI-adoption-timing and SECURITY.md-authorship questions.

**Review items deferred to v1.x** (not blocking for baseline):

- Gitea Actions CI adoption (deferred per §1.2 scope).
- Reproducible-build migration (R-03 accepted).
- LUKS-encrypted persistence (stretch NFR-4.3).

---

*End of SAD v1.0 BASELINED.*
