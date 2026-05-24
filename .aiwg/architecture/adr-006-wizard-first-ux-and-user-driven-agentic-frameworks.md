# ADR-006: Wizard-First UX, User-Driven Agentic Frameworks, VS Code/Copilot Base, NFS Publish Target, Signing Deferred

**Status**: ACCEPTED (2026-04-20 — second amendment of Elaboration baseline; extends ADR-005)
**Date**: 2026-04-20
**Deciders**: Joseph Magly (maintainer)
**Amends**: ADR-001 (LICENSE resolved to MIT), ADR-002 (publish target → NFS for v1.0), ADR-003 (v1.0 signing commitment deferred to v1.1; sha256-only for v1.0)
**Extends**: ADR-005 (user-driven-loading pattern now also applies to agentic frameworks)
**Drives amendments to**: SAD §0, §1.2, §4.2, §4.3, §9.1 (signing), §9.5 (license resolved); iteration-1 plan (wizard becomes central deliverable); risk register (new risks); NFR register (new wizard UX category); user stories
**Build-tool note (2026-05-24)**: the Cubic references in this ADR (§D3, decision Q2, wizard prereq/IDE steps) are superseded by ADR-007 — the implemented builder is live-build, not Cubic. The other decisions in this ADR are unaffected.

## Context

Within hours of ADR-005 acceptance, maintainer clarified five additional design decisions that together pivot the product orientation:

1. **Wizard-first UX**: The primary entry point is a single-command interactive wizard (`scripts/kintsugi-build`). A user with a fresh clone of this repo and a blank USB runs one command, gets guided through choices (rescue ISOs, Ollama+llama.cpp setup, model selection, agentic-framework selection, IDE selection), and ends up with a personalized master USB ready to image. The distributed signed image recedes; the wizard-driven self-build is the primary product.

2. **Agentic frameworks user-driven** (mirrors ADR-005 model pattern): The toolkit does NOT bundle Claude Code, Codex CLI, Aider, Cursor, Windsurf, Warp, Factory, OpenCode, or any other agentic CLI. Instead, the wizard presents a list of AIWG-supported frameworks, the user picks one or more, and the toolkit fetches + installs them into the in-progress master at build time. The user owns licensing and auth for whatever they pick.

3. **VS Code + GitHub Copilot base**: VS Code is installed by default in the custom Ubuntu ISO during the Cubic build step; the GitHub Copilot extension is preinstalled. The user still signs in to GitHub post-flash to activate Copilot. This is treated as "IDE infrastructure" distinct from the agentic-framework toolkit because the user-base it serves (developers wanting a familiar editor + Copilot inline) is broad enough to justify default inclusion.

4. **Publish to NFS (not Gitea releases) for v1.0**: Maintainer's signed images (when they exist) go to an internal warehouse NFS mount for now. A later pipeline will move published images elsewhere. Gitea releases remain the canonical home for git tags, source archives, and possibly small artifacts (`kintsugi.pub`, `manifest/models-recommended.yaml`, changelog), but not for the multi-GB image files.

5. **Signing deferred**: Iteration-1 focus is on the build toolkit, not distribution infrastructure. Minisign keypair generation, `verify-release.sh`, full signing flow — all demoted from P0 (iteration-1) to P2 (iteration-2). For v1.0, recipients of any maintainer-published images rely on **sha256 verification only** (posted alongside the artifact on the NFS mount). The SAD §9.1 "v1.0 minisign signing commitment" (from the earlier Security review CONDITIONAL resolution) is **rolled back** to v1.1. Trade-off: weaker supply-chain story for any v1.0 maintainer-published images; justified because (a) the primary product is the toolkit for user-self-build, not the distributed image; (b) NFS-local distribution has a more-trusted delivery channel than public download; (c) iteration-2 will land the full signing flow before any public Gitea release.

Additionally, the user selected **MIT** for the repository license (resolves ADR-001).

## Decision Drivers

- **"Easy to fork, easy to run" is the product promise.** Anything that raises forker friction (complex signing, corporate-hostile license, heavyweight release pipeline) should be deferred or avoided.
- **User agency over frameworks + models**: treating agentic CLIs like models (user picks, toolkit fetches) maintains consistency with ADR-005 and avoids the EULA / redistribution minefield for proprietary CLIs.
- **VS Code + Copilot are commodity dev-environment infrastructure**: most recipients will want them; bundling them by default saves a post-flash install step; neither has a redistribution problem (VS Code bundled via Microsoft repo install; Copilot extension via VS Code marketplace; user auths post-flash).
- **Internal NFS → external pipeline later**: ship now to the infrastructure that exists; don't block iteration-1 on building a public release pipeline.
- **Signing-later is fine for a toolkit-first product**: the integrity story that matters to forkers is "I can read the scripts; I can see what they do" (git is the verification). The minisign story matters for the distributed-image audience, which is secondary in this amendment.

## Decision

### D1. Wizard-first UX (`scripts/kintsugi-build`)

A single-command interactive wizard becomes the primary user-facing entry point of this repo. Implementation posture:

- **Language**: Bash. Optional `gum` (Charm.sh) or `whiptail` / `dialog` as the TUI widget library; graceful fallback to plain prompts when the widget tool is not installed.
- **Invocation**: `./scripts/kintsugi-build` from a fresh clone. No arguments needed for the happy path; `--non-interactive` for scripted/CI use with answers supplied via a YAML profile.
- **Flow** (representative):
  1. Detect prerequisites (Ubuntu 24.04, Cubic, ≥100 GB disk, USB target). Offer to install missing tools via apt.
  2. Ask: name your build (default: `kintsugi-v2026.5.0-$(date +%Y%m%d)`).
  3. Ask: which rescue ISOs to include (SystemRescue, Clonezilla, GParted Live, Memtest86+, Hiren's PE — checkbox list with sensible defaults).
  4. Ask: which **AI runtimes** to include (llama.cpp: yes/no; Ollama: yes/no; default both).
  5. Ask: which **models** to pre-bundle (none; recommended list from `manifest/models-recommended.yaml`; custom slugs). Invokes `kintsugi-models add/pull --target <master>` per choice. None is a valid answer — user can pull at first boot.
  6. Ask: which **agentic frameworks** to include (none; from `manifest/agentic-frameworks-recommended.yaml`; custom). Default: none (user adds post-flash) — but offers quick defaults.
  7. Ask: IDE setup (VS Code + Copilot: yes/no; default yes). Install via Microsoft's apt repo during Cubic chroot.
  8. Ask: signed release? (default: no, for v1.0). If yes, sha256 only unless minisign is available on the build host.
  9. Confirm choices; write a `kintsugi-build-profile.yaml` capturing the answers for reproducibility.
  10. Run the build: `build-custom-iso.sh` → populate `/payload/` from choices → `prep-master.sh` → `create-base-image.sh`.
  11. Report: path to final `.img.zst`, sha256, and suggested flash command.
- **Resumability**: Wizard writes a profile file early. A rerun with `--from-profile <file>` replays choices. A crash mid-build surfaces a clear recovery hint (usually: rerun from profile).
- **Testability**: Wizard's non-interactive mode is covered by bats tests with fixture profiles.

### D2. Agentic-framework toolkit (user-driven, mirrors model pattern)

- **Manifest**: `manifest/agentic-frameworks-recommended.yaml` (new; schema similar to `models-recommended.yaml`). Lists AIWG-supported + other popular frameworks with install recipe, license, auth model, and post-flash activation notes.
- **CLI**: `scripts/usb-toolkit/kintsugi-frameworks` (parallel to `kintsugi-models`). Subcommands: `list`, `add`, `install`, `remove`, `verify`.
- **Recommended starter list** (draft — to be refined when authoring the manifest):
  - **Claude Code** — Anthropic EULA; user auths post-flash; highly capable agentic CLI
  - **Codex CLI** — Anthropic EULA; user auths post-flash
  - **Aider** — Apache-2.0; BYO API key (OpenAI/Anthropic/local llama-server/Ollama)
  - **Cursor** — proprietary IDE; user installs the .deb; post-flash sign-in
  - **Windsurf** — proprietary IDE; user installs the .deb
  - **Warp** — proprietary terminal; user installs
  - **OpenCode** — open source CLI
  - **Factory** — proprietary; user opts in
  - **Continue.dev** — Apache-2.0 VS Code extension
- **Scope**: toolkit fetches installer, runs it in the appropriate build context (chroot for system-wide installs into the custom ISO; or persistence overlay for user-scoped installs); the maintainer's signature (when signing resumes) attests to `agentic-frameworks-recommended.yaml` as committed, NOT to the installers or EULAs.
- **User-supplied entries** land in `/data/frameworks/user/frameworks.yaml` at build-time or post-flash.

### D3. VS Code + GitHub Copilot as default in base ISO

- VS Code installed via Microsoft's apt repository in the Cubic chroot step of `build-custom-iso.sh`.
- GitHub Copilot extension preinstalled to VS Code's global extensions directory.
- GitHub CLI (`gh`) added; user authenticates post-flash to activate Copilot (`gh auth login` + Copilot sign-in in VS Code).
- Wizard offers opt-out for users who prefer a minimal base.
- Licensing: VS Code is under the "Microsoft Software License Terms — Visual Studio Code" (permissive for personal and commercial use but proprietary telemetry by default). Copilot is a paid subscription gated by GitHub sign-in; preinstalled extension is free to install, but functionality requires user's GitHub + Copilot subscription.
- **Telemetry**: Wizard asks at IDE setup step whether to disable VS Code telemetry by default (recommended: yes; configurable per user).

### D4. Publish target: NFS warehouse (v1.0) → pipeline-elsewhere (v1.1+)

- For v1.0, any maintainer-produced images publish to a designated NFS mount on the warehouse server. Path pattern: `/mnt/warehouse/releases/kintsugi-usb/<version>/`.
- `scripts/publish-release.sh` mounts the NFS target (assumes NFS mount is already configured at known path), copies `.img.zst` + `.sha256`, updates a local `releases.json` index, optionally tags the git commit.
- No Gitea release attachment for images in v1.0 (Gitea release page carries source tarball + changelog + `kintsugi.pub` when signing lands, but NOT the multi-GB images).
- Recipient instructions (for those with warehouse access): mount the NFS, copy the image + sha256, verify, flash.
- Future pipeline (v1.1+): maintainer-configured post-publish step pushes from NFS to whatever external delivery endpoint is chosen later.

### D5. Signing deferred to iteration-2 (amends ADR-003)

- Iteration-1 ships **sha256 only** for any maintainer-published image. No minisign keypair; no `verify-release.sh`.
- Tamper-reporting channel (SECURITY.md) still authored in iteration-1, but with reduced scope: documents the sha256 expectation and the "iteration-2 will add signatures" commitment. Trust boundary language remains.
- Iteration-2 re-introduces minisign (keypair generation, committed `kintsugi.pub`, `verify-release.sh`, recipient per-OS one-liners). This is explicit carry-forward; it is not forgotten.
- `docs/flash-image.md` for v1.0 documents sha256 verification with per-OS one-liners. When signing lands in v1.1, the doc gets a minisign section added.

### D6. License: MIT (resolves ADR-001)

- `LICENSE` committed at repo root with MIT text (copyright 2026 Joseph Magly) and a "Third-Party Components" appendix pointing to `manifest/THIRD-PARTY-LICENSES.md`.
- ADR-001 status moves from PROPOSED to ACCEPTED with MIT selected.
- `manifest/THIRD-PARTY-LICENSES.md` authored in iteration-1, but with narrower scope (bundled binaries only: Ventoy GPLv3, llama.cpp MIT, Ollama Apache-2.0, VS Code MSFT license, GitHub Copilot extension MSFT license, any rescue ISOs shipped). No model weights. No agentic-framework binaries (user chooses).
- SPDX identifiers (`SPDX-License-Identifier: MIT`) added to script headers as scripts are authored.

## Consequences

### Positive

- **Single-command onboarding** — the key UX promise. Forker runs `./scripts/kintsugi-build` and gets a guided flow.
- **License choice is maximally fork-friendly** — MIT removes the adoption barrier.
- **Proprietary-CLI license risk evaporated** — we don't redistribute Claude Code, Cursor, Windsurf, etc. Users bring their own.
- **VS Code + Copilot is a real value-add** — most recipients want it; bundling saves a step.
- **NFS publish is pragmatic** — ships what exists without waiting to build a public release pipeline.
- **Iteration-1 scope becomes more achievable** — signing (significant net-new work) moves out; the wizard (the real value) moves in.
- **Consistent "user-driven" pattern** across models + agentic frameworks — fewer exceptions for the user to track.

### Negative

- **v1.0 maintainer-published images carry weaker supply-chain guarantees** (sha256-only). Any v1.0 image on NFS could be substituted before the user verifies. Mitigation: NFS access is internal-only; no broad public distribution in v1.0; `docs/flash-image.md` documents that signed releases arrive in v1.1.
- **Wizard is new code** — not ported from sysops. Biggest unknown in iteration-1 schedule. Partial mitigation: keep Bash-simple; defer polish (progress bars, animation) to iteration-2.
- **VS Code telemetry default** — Microsoft. Wizard should prompt. Risk register tracks (new R-19).
- **Agentic-framework install complexity** — each framework has its own install recipe, auth model, and quirks. Wizard's "agentic framework" step will be the most complex UI. Might need to ship v1.0 with only 2–3 supported frameworks and expand over iterations.
- **Copilot requires GitHub sign-in + subscription** — recipients without these get an installed-but-inert extension. Wizard documents this clearly.

### Neutral

- Start-ai.sh refactor (from ADR-005) unchanged in scope; wizard drives its configuration but the script itself doesn't need to know about the wizard.
- The existing usb-test-harness.sh (ported from sysops) becomes even more important — it validates that a wizard-produced image actually works.
- Iteration-1 plan's Cluster 5 (Verification + User-Facing Docs) reshuffles: signing out, wizard-guide in.

## Supersession / Amendment Map

| Prior artifact | Status after this ADR | Notes |
|----------------|-----------------------|-------|
| ADR-001 (LICENSE) | **RESOLVED** → MIT accepted | ADR-001 status updates from PROPOSED to ACCEPTED. Apache-2.0 alternative documented for posterity. |
| ADR-002 (imaging) | **FURTHER AMENDED** (after ADR-005's amendment): publish target is NFS, not Gitea releases, for v1.0 | Gitea release page still carries source tag, `kintsugi.pub` (when signing lands), `changelog.md`. |
| ADR-003 (verification rigor) | **DEFERRED** to v1.1; v1.0 is sha256-only | Recipient verification UX per-OS commands remain relevant; minisign column is removed from v1.0 release artifact list. |
| ADR-004 (model selection) | SUPERSEDED by ADR-005 (unchanged) | |
| ADR-005 (toolkit + models + Ollama) | Extended (user-driven pattern also applies to agentic frameworks) | |

## Resolved (2026-04-20, interactive Q&A)

1. **Wizard widget library** — **Whiptail** (universal on Ubuntu, zero-install). Plain-prompt fallback when whiptail absent. Hybrid "prefer gum when installed" was considered and rejected as unnecessary code paths for v1.0. Gum may return as an opt-in in iteration-2.
2. **VS Code install source** — **Microsoft apt repo**. MS apt key signed inside the Cubic chroot. VS Code pinned to a specific version at build time; `apt-mark hold code` to prevent auto-update post-boot (we manage version cadence). Telemetry disabled by default via `/etc/skel/.config/Code/User/settings.json` (R-19 mitigation).
3. **Warehouse NFS path** — default `/mnt/warehouse/releases/kintsugi-usb/`. Overridable via `KINTSUGI_PUBLISH_NFS` env var. `scripts/publish-release.sh` refuses to publish if the path is unmounted or unwritable.
4. **v1.0 agentic-framework count** — **three**: Aider (pipx, Apache-2.0, BYO-API-key), Claude Code (curl-bash, Anthropic EULA, post-flash auth), Codex CLI (npm, OpenAI EULA, post-flash auth). Cursor, Windsurf, Warp, OpenCode, Factory, Continue.dev remain `status: evaluating` in `manifest/agentic-frameworks-recommended.yaml`; move to iteration-2.
5. **Wizard profile format** — **YAML**, matching `models-recommended.yaml` and `agentic-frameworks-recommended.yaml`. Comments supported (wizard annotates user choices inline). Schema validated by the wizard; `yq` is the tooling dependency and is installable via apt.
6. **Smoke-test model bundled?** (open question carried from ADR-005) — **No**. Consistent with the user-driven-loading pattern. `usb-test-harness.sh` reports WARN on skipped model-dependent tests until the user pulls a model via `kintsugi-models pull`. Keeps base image lean; zero license complications.

## Previously open, now resolved

All six open questions from the 2026-04-20 drafting session are resolved above. Any new open questions will be appended here with the date of their capture.

## Implementation Plan (iteration-1 revisions)

See `.aiwg/planning/iteration-001-plan.md` (revised post-ADR-006). Net changes:

- **NEW central deliverable**: `scripts/kintsugi-build` wizard.
- **NEW**: `scripts/usb-toolkit/kintsugi-frameworks` CLI + `manifest/agentic-frameworks-recommended.yaml`.
- **NEW**: VS Code + Copilot + `gh` CLI installation in `build-custom-iso.sh` Cubic chroot step.
- **NEW**: `scripts/publish-release.sh` targeting NFS.
- **LICENSE**: committed (MIT); ADR-001 moves to ACCEPTED.
- **DEMOTED (→ iteration-2)**: minisign keypair (#19), `verify-release.sh` (#6 reframed), per-OS signed-verification one-liners in flash-image.md.
- **REDUCED**: SECURITY.md (#20) scope — document sha256 expectation + v1.1 signing commitment.
- **docs/flash-image.md** v1.0 version: sha256 verification only.
- **Risk register**: R-02 (supply-chain) severity adjusted (higher for sha256-only v1.0, downgraded again in v1.1); R-19 (VS Code telemetry) and R-20 (Copilot subscription dependency) new.

## Links

- SAD (to be amended with §0 addition): `.aiwg/architecture/software-architecture-doc.md`
- ADR-001 (now ACCEPTED / MIT): `.aiwg/architecture/adr-001-license-selection.md`
- ADR-003 (v1.0 signing deferred): `.aiwg/architecture/adr-003-verification-rigor.md`
- ADR-005 (models + toolkit surface): `.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md`
- `LICENSE` (MIT, committed alongside this ADR)
- `manifest/models-recommended.yaml` (existing)
- `manifest/agentic-frameworks-recommended.yaml` (iteration-1 deliverable)
- `scripts/kintsugi-build` (iteration-1 central deliverable)
- `scripts/usb-toolkit/kintsugi-frameworks` (iteration-1 deliverable)
