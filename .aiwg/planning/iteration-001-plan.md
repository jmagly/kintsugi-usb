# Iteration 1 Plan — Kintsugi USB v1.0 Wizard-First Release

**Iteration**: 001 (revised post-ADR-006)
**Start date**: TBD (after maintainer review of SDLC artifacts)
**Owner**: Joseph Magly (roctinam)
**Anchor decision**: [ADR-006](../architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md) — Wizard-first UX, user-driven agentic frameworks, VS Code/Copilot base, NFS publish target, signing deferred
**Extends**: [ADR-005](../architecture/adr-005-toolkit-scope-and-user-driven-models.md) — still authoritative for models and dual-runtime posture
**License**: MIT (ADR-001 RESOLVED per ADR-006 §D6; `LICENSE` committed)

## Iteration Goal

Ship **v1.0** as a **wizard-first build toolkit**: a forker clones this repo on an Ubuntu 24.04 host, runs `./scripts/kintsugi-build`, answers a short series of TUI prompts, and ends up with a personalised flashable `.img.zst` plus a sha256 checksum. The wizard orchestrates every downstream script (ISO build, model pull, agentic-framework install, master prep, image creation) and persists the answer-set as a replayable profile. The **self-build-from-fresh-clone** experience is the primary product for v1.0; the distributed signed image recedes.

**Acceptance gate**: a user on a clean Ubuntu 24.04 host runs `./scripts/kintsugi-build` from a fresh `git clone`, accepts defaults, and obtains (1) a flashable `kintsugi-*.img.zst` + `.sha256`, (2) a `kintsugi-build-profile.yaml` replayable via `--from-profile`, and (3) a `usb-test-harness.sh` PASS on a fleet host after flashing.

Iteration 1 retires R-01 (MIT), eases R-05 (wizard-driven imaging works end-to-end), reframes R-04 (field update = `git pull` + `kintsugi-models pull` + `kintsugi-frameworks install`), and introduces R-19 (VS Code telemetry) and R-20 (Copilot subscription dependency). Signing (minisign keypair, `verify-release.sh`, per-OS signed-verification one-liners) is **explicitly deferred** to iteration-2; v1.0 relies on sha256 plus NFS access control for integrity.

## Scope — Story Clusters

Stories are grouped by theme; Cluster 5 (Build Wizard) is the **central deliverable** that integrates every other cluster. All P0 stories are in scope; selected P1s ride along.

---

### Cluster 1 — License + Repo Hygiene (ADR-001 RESOLVED)

LICENSE is no longer a decision — it is MIT and committed. This cluster covers the remaining hygiene artifacts and the reduced-scope SECURITY.md.

#### US-010 — LICENSE file (DONE)
**Priority**: P0 | **Size**: XS | **ADR**: ADR-001 (ACCEPTED), ADR-006 §D6
**Status**: **DONE** — `LICENSE` (MIT + Third-Party Components appendix) committed at repo root.
**Acceptance**: File present; README references MIT SPDX id; no further work.
**Dependencies**: None.

#### US-010b — THIRD-PARTY-LICENSES.md (bundled binaries only)
**Priority**: P0 | **Size**: S | **ADR**: ADR-006 §D6, ADR-005 §D5
**Acceptance**: `manifest/THIRD-PARTY-LICENSES.md` enumerates components actually bundled in the base ISO: Ventoy (GPLv3), `llama.cpp` (MIT), Ollama (Apache-2.0), VS Code (Microsoft Software License Terms), GitHub Copilot extension (Microsoft), `gh` CLI (MIT), any rescue ISOs selected by default. Each entry: upstream URL, pinned version, SPDX id, redistribution note. Explicit exclusion clause: "model weights are user-pulled and not redistributed"; "agentic-framework installers are user-selected and not redistributed".
**Dependencies**: Bundled-binary inventory from Cluster 4 (`build-custom-iso.sh` adaptation).

#### US-SEC-001 — SECURITY.md (reduced scope)
**Priority**: P0 | **Size**: S | **ADR**: ADR-006 §D5
**Acceptance**: `SECURITY.md` documents the v1.0 integrity story: sha256-only verification for maintainer-published images on the warehouse NFS; tamper-reporting channel (email + Gitea issue label); explicit **"signing lands in v1.1"** carry-forward commitment citing ADR-006. Trust boundary language: maintainer attests to committed scripts/docs/manifests via git; does not attest to user-pulled model weights or agentic-framework binaries.
**Dependencies**: None.

---

### Cluster 2 — Ported Script Adaptation

Ported sysops scripts are largely intact. The notable expansion is Copilot/IDE infrastructure in the live-build chroot-hook step (see ADR-007 — the builder is live-build, not Cubic).

Agent role: **Systems engineer**.

#### US-PORT-001 — Adapt build-custom-iso.sh (VS Code + Copilot + gh)
**Priority**: P0 | **Size**: M | **ADR**: ADR-006 §D3, ADR-005 §D2
**Acceptance**: Adapt paths, version strings, branding. In the live-build chroot hook (`config/hooks/normal/`), add: Microsoft apt repo signing-key + source; `code` package install; `gh` CLI install; GitHub Copilot extension preinstalled via `code --install-extension github.copilot`; optional VS Code telemetry-disable default (wizard-driven; sets `telemetry.telemetryLevel: off`); Ollama install per US-MODEL-003. Shellcheck clean; SPDX header; invokable non-interactively so the wizard can drive it with answer vars.
**Dependencies**: LICENSE (DONE); US-MODEL-003 decision.

#### US-PORT-002 — Adapt first-boot-setup.sh
**Priority**: P0 | **Size**: S | **ADR**: ADR-005 §D3 boot-time path
**Acceptance**: Review `first-boot-setup.sh` (287 lines); create `/data/models/user/` persistence dir + Ollama symlink `/data/ollama/ -> ~/.ollama/models/`; create `/data/frameworks/user/` for post-flash agentic installs; ensure `kintsugi-models` and `kintsugi-frameworks` on PATH; surface first-boot hint text directing user to `kintsugi-models pull` and `gh auth login` (for Copilot).
**Dependencies**: US-MODEL-002 (kintsugi-models CLI), US-FW-002 (kintsugi-frameworks CLI).

#### US-PORT-003 — Refactor start-ai.sh: manifest-driven + Ollama status
**Priority**: P0 | **Size**: M | **ADR**: ADR-005 §D2, §D3
**Acceptance**: Reads `manifest/models-recommended.yaml` + `/data/models/user/models.yaml` with user-shadowing; reports health of both `llama-server` (:8080) and `ollama serve` (:11434); scans `/payload/models/` then `/data/models/user/` for GGUFs; Ollama discovery via `ollama list`; graceful empty-state with `kintsugi-models pull` hint; shellcheck clean.
**Dependencies**: US-MODEL-001 schema, US-MODEL-002 CLI.

#### US-PORT-004 — Adapt usb-test-harness.sh as v1.0 acceptance tool
**Priority**: P0 | **Size**: M | **ADR**: ADR-005 Consequences, ADR-006 acceptance gate
**Acceptance**: Review `usb-test-harness.sh` (527 lines); add tests for Ollama health, `kintsugi-models list`, `kintsugi-frameworks list`, manifest parse, dual-runtime status, VS Code + Copilot extension presence. Adopted as **v1.0 iteration-acceptance gate tool**. Invocation documented in `docs/toolkit-guide.md` and called by wizard at end-of-build for smoke validation (optional flag).
**Dependencies**: All Cluster 2 + 3 + 4 scripts present.

#### US-PORT-005 — Retain check-drive-health.sh + benchmark-inference.sh
**Priority**: P1 | **Size**: XS | **ADR**: ADR-005 Links
**Acceptance**: Confirm both run on flashed image; wire `benchmark-inference.sh` into NFR-1.3/1.4 verification evidence. No functional changes.
**Dependencies**: None.

---

### Cluster 3 — Model Toolkit (ADR-005 core deliverables; largely unchanged)

Agent role: **Build engineer + toolkit author**.

#### US-MODEL-001 — manifest/models-recommended.yaml (refinement)
**Priority**: P0 | **Size**: XS | **ADR**: ADR-005 §D4
**Status**: File committed; this story covers **refinement only** — pin sha256 values, confirm entries, add `purpose`/`tested_on` fields where missing. Starter entries: `qwen3.5:4b` (Ollama), `qwen3.5:9b` (Ollama), `Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf` (HF/llama-cpp).
**Dependencies**: None.

#### US-MODEL-002 — kintsugi-models CLI (Bash MVP)
**Priority**: P0 | **Size**: L | **ADR**: ADR-005 §D3, §D4
**Acceptance**: Subcommands `list`, `add <slug>`, `pull <slug>`, `remove <slug>`, `verify`. Source dispatch: `ollama` → `ollama pull`; `huggingface` → `curl` + `sha256sum` against manifest. Build-vs-boot path auto-detect with `--target` override; defaults to `/payload/models/` on a mounted build-root else `/data/models/user/`. Persistence guard: warn at 80%, refuse at 95% (R-18). `verify` walks slugs, checks sha256, reports license. Shellcheck clean; harness integration test. Callable non-interactively from the wizard.
**Dependencies**: US-MODEL-001.

#### US-MODEL-003 — Ollama inclusion decision
**Priority**: P0 | **Size**: S | **ADR**: ADR-005 §D2
**Acceptance**: Decide and record: bundle Ollama binary vs. apt-install in `build-custom-iso.sh`. Chosen path implemented; `ollama.service` starts cleanly on flashed image.
**Dependencies**: US-PORT-001.

#### US-MODEL-004 — HuggingFace pull recipe + verification docs
**Priority**: P0 | **Size**: S | **ADR**: ADR-005 Open Q4
**Acceptance**: `docs/toolkit-guide.md` documents HF URL resolution, sha256 pinning workflow, gated-repo `HF_TOKEN` env var, troubleshooting (401, rate-limit, resume).
**Dependencies**: US-MODEL-002.

#### US-MODEL-005 — Smoke-test model decision
**Priority**: P1 | **Size**: S | **ADR**: ADR-005 Open Q1
**Acceptance**: Decide: bundle ~50 MB TinyLlama GGUF for offline `llama-server` smoke-test, or skip with harness-test adjustments. If bundled, add to THIRD-PARTY-LICENSES + harness step. If skipped, harness documents internet precondition.
**Dependencies**: US-PORT-004.

---

### Cluster 4 — Agentic-Framework Toolkit (NEW per ADR-006 §D2)

Mirrors the model-toolkit pattern. v1.0 ships three frameworks in the recommended list; the rest are documented as "iteration-2 expansion". Agent role: **Toolkit author**.

#### US-FW-001 — manifest/agentic-frameworks-recommended.yaml
**Priority**: P0 | **Size**: S | **ADR**: ADR-006 §D2
**Acceptance**: New manifest file parallel to `models-recommended.yaml`. Schema fields per entry: `slug`, `name`, `license`, `source` (apt | pip | npm | deb | script), `install_recipe` (command or script path), `auth_model` (e.g. `post-flash-login`, `api-key`), `post_flash_notes`, `tested_on`. **v1.0 entries scoped to three frameworks**:

- `aider` — Apache-2.0, pip install, BYO API key (OpenAI/Anthropic/local llama-server/Ollama)
- `claude-code` — Anthropic EULA, npm install, post-flash `claude login`
- `codex-cli` — Anthropic-compatible EULA, npm install, post-flash auth

Each entry includes a comment block flagging license + auth obligations the user inherits. The manifest is signed-with-repo (git commit attestation); no installer binaries committed.
**Dependencies**: None; independent of model toolkit.

#### US-FW-002 — kintsugi-frameworks CLI (Bash MVP)
**Priority**: P0 | **Size**: M | **ADR**: ADR-006 §D2
**Acceptance**: Parallel to `kintsugi-models`. Subcommands: `list`, `add <slug>`, `install <slug>`, `remove <slug>`, `verify`. Source dispatch per `source` field — `apt` → `apt-get install`; `pip` → `pipx install`; `npm` → `npm install -g`; `deb` → `curl + dpkg -i`; `script` → run the linked install recipe. Build-vs-boot path auto-detect: inside chroot (`--target <chroot>` override) installs system-wide for ISO bake; on booted USB installs to persistence overlay (`/data/frameworks/user/`) with PATH shim. `verify` checks install recipes are syntactically sound + source URLs resolve (no binary verification — per-framework by design). Shellcheck clean; callable non-interactively.
**Dependencies**: US-FW-001.

#### US-FW-003 — Install-recipe implementations (Aider, Claude Code, Codex CLI)
**Priority**: P0 | **Size**: M | **ADR**: ADR-006 §D2
**Acceptance**: Three concrete install recipes implemented and tested:

- Aider: `pipx install aider-chat`; post-install smoke: `aider --version`
- Claude Code: `npm install -g @anthropic-ai/claude-code`; post-install smoke: `claude --version`
- Codex CLI: `npm install -g @openai/codex` (or current package); post-install smoke: `codex --version`

Each recipe works in both build-time (chroot) and boot-time (persistence overlay) contexts. Post-flash auth instructions documented in `docs/toolkit-guide.md`.
**Dependencies**: US-FW-002.

---

### Cluster 5 — Build Wizard (NEW central deliverable per ADR-006 §D1)

The wizard is the integrating surface. Every other cluster's deliverable is invokable non-interactively so that the wizard can drive it. Agent role: **TUI developer + systems integrator**.

#### US-WIZ-001 — scripts/kintsugi-build (interactive TUI wizard)
**Priority**: P0 | **Size**: L | **ADR**: ADR-006 §D1
**Acceptance**: Single Bash script invocable as `./scripts/kintsugi-build` from a fresh clone. Default widget library `whiptail` (Ubuntu main); prefers `gum` when present; falls back to plain `read` prompts otherwise. Flow per ADR-006 §D1: prerequisite detection → build name → rescue ISO selection → AI runtime selection → model pre-bundle → agentic-framework selection (quick-pick for Aider/Claude Code/Codex) → IDE setup (VS Code + Copilot default yes; telemetry prompt) → signed-release prompt (default no for v1.0) → confirm → build → final report (path to `.img.zst`, sha256, flash command). Writes `kintsugi-build-profile.yaml` **before** starting the build so crashes surface a resume hint. Shellcheck clean; SPDX header; handles Ctrl-C cleanly.
**Dependencies**: US-PORT-001, US-MODEL-002, US-FW-002, US-IMG-001, US-IMG-002.

#### US-WIZ-002 — kintsugi-build-profile.yaml schema + replay
**Priority**: P0 | **Size**: S | **ADR**: ADR-006 §D1, Open Q5
**Acceptance**: YAML schema (matches models-recommended.yaml convention) capturing every wizard answer. Top-level keys: `schema_version`, `build_name`, `rescue_isos`, `runtimes`, `models`, `frameworks`, `ide`, `telemetry`, `signing`. `scripts/kintsugi-build --from-profile <file>` replays the build non-interactively. Schema documented in `docs/wizard-guide.md`.
**Dependencies**: US-WIZ-001.

#### US-WIZ-003 — Non-interactive mode + bats test coverage
**Priority**: P0 | **Size**: M | **ADR**: ADR-006 §D1 Testability
**Acceptance**: `--non-interactive` flag with profile-file required. Bats test suite in `tests/wizard/` covers: minimal profile (no models, no frameworks), happy-path profile (defaults + Aider), full profile (all three frameworks + both runtimes + multiple models). Tests mock external commands (`apt`, `pipx`, `npm`, `ollama`, `curl`) so they run offline in CI. Harness documented in `docs/wizard-guide.md`.
**Dependencies**: US-WIZ-001, US-WIZ-002.

#### US-WIZ-004 — Wizard-to-pipeline integration smoke-test
**Priority**: P0 | **Size**: S | **ADR**: ADR-006 Consequences
**Acceptance**: End-to-end test on a real Ubuntu 24.04 host: wizard drives `build-custom-iso.sh` → `kintsugi-models pull` → `kintsugi-frameworks install` → `prep-master.sh` → `create-base-image.sh` producing a flashable `.img.zst`. Documented as the iteration-acceptance procedure in `docs/toolkit-guide.md`. Captures typical timing and disk-use figures (for `docs/wizard-guide.md` expectations section — not estimates, just measured figures).
**Dependencies**: All Cluster 5 + predecessor clusters complete.

---

### Cluster 6 — Imaging Pipeline + NFS Publish (ADR-002 further amended)

Agent role: **Build engineer + release manager**.

#### US-IMG-SPIKE — Measure base-image size without model weights
**Priority**: P0 | **Size**: S | **ADR**: ADR-002 (amended)
**Acceptance**: Build master per adapted `build-custom-iso.sh` with no model weights but with VS Code + Copilot + gh bundled; measure post-zstd size; decide whether the separate payload-tarball concept still pays for itself or collapses into base image. Record in ADR-002 amendment.
**Dependencies**: Cluster 2 ports complete.

#### US-IMG-001 — prep-master.sh
**Priority**: P0 | **Size**: M | **ADR**: ADR-002 step 1; ADR-005 step 7
**Acceptance**: Sanitizes secrets (`ai-keys.env`, shell history, SSH known_hosts, `*.env`); zero-fills free space; flushes caches; idempotent. Preserves `/payload/models/`, `/data/models/user/`, `/data/frameworks/user/` but warns on secret-pattern hits inside them. Secret-pattern grep (`BEGIN OPENSSH PRIVATE KEY`, `sk-ant-`, `sk-`, `ghp_`, `AKIA`, internal hostnames) aborts on hit. Callable non-interactively from wizard.
**Dependencies**: LICENSE (DONE).

#### US-IMG-002 — create-base-image.sh
**Priority**: P0 | **Size**: M | **ADR**: ADR-002 step 2
**Acceptance**: `dd` → `zstd -T0 -19` → `kintsugi-<name>-vX.Y.Z.img.zst` + `.sha256`. No `.minisig` for v1.0 (deferred). Refuses wrong target with anti-pattern banner. Idempotent. Callable non-interactively from wizard.
**Dependencies**: prep-master.sh clean.

#### US-IMG-003 — publish-release.sh (NFS target)
**Priority**: P0 | **Size**: M | **ADR**: ADR-006 §D4
**Acceptance**: Copies `.img.zst` + `.sha256` + `manifest.json` + `models-recommended.yaml` + `agentic-frameworks-recommended.yaml` to `/mnt/warehouse/releases/kintsugi-usb/<version>/`. NFS mount path configurable via `KINTSUGI_NFS_ROOT` env var (default `/mnt/warehouse/releases/kintsugi-usb`). Updates local `releases.json` index at the target root. Refuses overwrite unless `--force`. Optionally tags the git commit with `vX.Y.Z`. No Gitea release artifact attachment for images in v1.0 (Gitea gets source tarball + changelog + manifests only, via normal `gh release create` or Gitea UI flow). Shellcheck clean.
**Dependencies**: create-base-image.sh; tag + CHANGELOG.

#### US-IMG-004 — manifest.json per release
**Priority**: P0 | **Size**: S | **ADR**: ADR-002, ADR-005 §D5, ADR-006 §D6
**Acceptance**: `manifest/vX.Y.Z.json` lists every bundled ISO/binary with name, version, upstream URL, upstream sha256, SPDX license. Excludes model weights + agentic-framework binaries (user-provided). Unsigned for v1.0 (iteration-2 adds minisign).
**Dependencies**: Bundled-binary inventory from Cluster 1 + Cluster 2.

---

### Cluster 7 — User-Facing Docs (signing content removed)

Agent role: **Docs engineer**.

#### US-DOCS-001 — docs/toolkit-guide.md (EXPAND from stub)
**Priority**: P0 | **Size**: M | **ADR**: ADR-005 §D1, ADR-006 §D1
**Acceptance**: Full external-builder walkthrough. Covers: cloning the repo; running `./scripts/kintsugi-build`; wizard screens (described textually with sample prompts and expected answers); editing manifests (models, frameworks) before build; non-interactive mode via profile; running `build-custom-iso.sh` / `prep-master.sh` / `create-base-image.sh` directly for advanced use; `kintsugi-models` and `kintsugi-frameworks` CLI reference; `usb-test-harness.sh` invocation.
**Dependencies**: All Clusters 2/3/4/5/6 scripts stable.

#### US-DOCS-002 — docs/update-strategy.md (EXPAND from stub)
**Priority**: P0 | **Size**: S | **ADR**: ADR-005 step 8, ADR-006 §D4
**Acceptance**: Field-update flow documented: (a) `git pull` in `/data/scripts/` for toolkit/doc updates; (b) `kintsugi-models pull` for model refresh; (c) `kintsugi-frameworks install` for new/updated agentic frameworks; (d) full reflash only for base-image security updates (NFS mount → flash). Explicitly retires the payload-tarball-per-model-refresh model.
**Dependencies**: None.

#### US-DOCS-003 — docs/flash-image.md (sha256-only verification for v1.0)
**Priority**: P0 | **Size**: M | **ADR**: ADR-006 §D5
**Acceptance**: Non-technical friendly; covers Etcher (primary), `dd` (Linux/macOS fallback), Rufus (Windows fallback); anti-pattern callouts before every destructive command; **sha256 verification one-liners for Linux / macOS / Windows PowerShell** (minisign commands deferred to v1.1; placeholder note at bottom: "Signature verification arrives in v1.1. See ADR-006 §D5 for the rationale and iteration-2 plan."); includes post-flash steps: `kintsugi-models pull`, `kintsugi-frameworks install`, `gh auth login` (for Copilot); boot-test verification.
**Dependencies**: create-base-image.sh output format finalised.

#### US-DOCS-004 — docs/wizard-guide.md (NEW — dedicated wizard UX reference)
**Priority**: P0 | **Size**: M | **ADR**: ADR-006 §D1
**Acceptance**: Dedicated reference for `scripts/kintsugi-build`. Covers: prerequisites, invocation, every wizard screen (with text of prompt + valid answers + defaults), profile-file schema, `--from-profile` replay, `--non-interactive` mode, troubleshooting (crashed mid-build recovery, widget-library fallback behaviour), measured reference figures from US-WIZ-004 for disk-use and external-download expectations.
**Dependencies**: US-WIZ-001, US-WIZ-002, US-WIZ-003, US-WIZ-004.

#### US-DOCS-005 — Tag / CHANGELOG / version
**Priority**: P1 | **Size**: S | **ADR**: ADR-002
**Acceptance**: `docs/release-procedure.md` documents `vMAJOR.MINOR.PATCH` scheme, git tag (unsigned for v1.0), CHANGELOG entry, NFS publish step.
**Dependencies**: publish-release.sh.

---

### Cluster 8 — Documentation Correction (small; blocks release)

#### US-CORR-001 — docs/requirements.md FR-4 correction
**Priority**: P0 | **Size**: S | **ADR**: ADR-005 step 4, ADR-006 §D2/§D3
**Acceptance**: FR-4.x reflects Ollama coexistence, user-driven model loading, user-driven agentic frameworks, VS Code + Copilot default inclusion, and corrected model inventory (Qwen3.5 4B/9B + Qwen2.5-Coder 7B as recommended, not bundled).

#### US-CORR-002 — SAD §10 supersession + amendment entries
**Priority**: P0 | **Size**: S | **ADR**: ADR-005 §D5, ADR-006 Supersession Map
**Acceptance**: SAD §10 contains:
- ADR-004 marked SUPERSEDED
- ADR-005 summary row (models/toolkit)
- ADR-006 summary row (wizard-first + frameworks + VS Code + NFS + signing deferred + MIT)
- ADR-001 status updated PROPOSED → ACCEPTED (MIT)
- ADR-002 amendment block (further amended; publish target now NFS for v1.0)
- ADR-003 amendment block (v1.0 signing deferred to v1.1)
- SAD §9.1 signing-commitment rollback noted
- SAD §9.5 license-resolved note

#### US-CORR-003 — ADR-004 supersession header (if not yet applied)
**Priority**: P0 | **Size**: XS | **ADR**: ADR-005 §D5
**Acceptance**: `adr-004-model-selection.md` carries `**Status**: SUPERSEDED by ADR-005` banner.

---

## Out of Scope for Iteration 1 (deferred to iteration-2 or later)

- **Minisign keypair generation** — deferred to iteration-2 (ADR-006 §D5).
- **`verify-release.sh` with minisign** — deferred. v1.0 ships a sha256-wrapper only if needed (covered by per-OS one-liners in `docs/flash-image.md`).
- **Per-OS minisign verification one-liners** in `docs/flash-image.md` — deferred; placeholder note pointing at v1.1 commitment.
- **Full agentic-framework catalog** — v1.0 ships three (Aider, Claude Code, Codex CLI); Cursor, Windsurf, Warp, OpenCode, Factory, Continue.dev, and anything else added in iteration-2+.
- **Reproducible-build flags** — live-build is the builder (ADR-007); opting into bit-for-bit reproducibility (`SOURCE_DATE_EPOCH` + pinned apt snapshots) is deferred per R-03.
- **LUKS persistence** (NFR-4.3 stretch) — out of scope.
- **SBOM generation** (CycloneDX/SPDX) — deferred; `manifest.json` serves as SBOM-lite for v1.0.
- **Multi-arch support** (arm64) — deferred.
- **Gitea release artifact attachment for images** — not used in v1.0 per ADR-006 §D4 (Gitea still holds source tarball + changelog + small manifests).
- **Gitea Actions CI** for automated build — deferred.
- **`update-payload.sh`** — reframed permanently as `git pull` + `kintsugi-models pull` + `kintsugi-frameworks install`; dedicated script not written.
- **`qemu-smoke.sh`** — `usb-test-harness.sh` covers the need.
- **Third-party pubkey mirror / cosign / sigstore** — post-signing-iteration.
- **`kintsugi-models` URL+sha256 source type** (beyond Ollama + HuggingFace) — iteration-2.
- **Public release pipeline** replacing NFS — iteration-2+ per ADR-006 §D4.

## Dependencies (cross-cluster)

The wizard (Cluster 5) is the integration surface. Every other cluster delivers a non-interactive, scriptable artifact that the wizard orchestrates.

1. **LICENSE (DONE)** unblocks all committed code (SPDX headers required on new Bash).
2. **`models-recommended.yaml` (US-MODEL-001)** blocks `kintsugi-models` CLI (US-MODEL-002) and `start-ai.sh` refactor (US-PORT-003).
3. **`agentic-frameworks-recommended.yaml` (US-FW-001)** blocks `kintsugi-frameworks` CLI (US-FW-002) and install-recipe implementations (US-FW-003).
4. **`kintsugi-models` CLI (US-MODEL-002) and `kintsugi-frameworks` CLI (US-FW-002)** block `first-boot-setup.sh` adaptation (US-PORT-002) and the wizard (US-WIZ-001).
5. **Adapted `build-custom-iso.sh` (US-PORT-001)** blocks the wizard's ISO-build step (US-WIZ-001) and the bundled-binary inventory for THIRD-PARTY-LICENSES (US-010b) and manifest.json (US-IMG-004).
6. **`prep-master.sh` + `create-base-image.sh` (US-IMG-001, US-IMG-002)** block wizard end-stage (US-WIZ-001) and publish (US-IMG-003).
7. **US-IMG-SPIKE** gates the final decision on whether any payload-tarball concept survives; most likely it collapses into the base image.
8. **All Cluster 2/3/4 scripts callable non-interactively** is a hard prerequisite for wizard integration (US-WIZ-001).
9. **Full wizard-to-pipeline smoke (US-WIZ-004)** is the iteration-acceptance gate.

## Agent Role Assignments

Per CLAUDE.md no-time-estimates, scope is expressed as **agent-clusters with serial (S) / parallel (P) relationships**, not weeks. Solo-maintainer = Joseph wearing each hat.

| Cluster | Role-hat | Serial/Parallel | Gate |
|---|---|---|---|
| A. License + docs correction (Clusters 1 + 8) | Maintainer-as-legal-editor | S — front-loaded; LICENSE DONE | LICENSE + amendments committed; SAD §10 current |
| B. Ported script adaptation (Cluster 2) | Systems engineer | P with C and D and F | shellcheck clean; VS Code + Copilot + gh land in chroot; boot-smoke on USB |
| C. Model toolkit (Cluster 3) | Toolkit author (models) | P with B and D; feeds B (PORT-002, PORT-003) | `kintsugi-models pull` round-trip on test host |
| D. Agentic-framework toolkit (Cluster 4) | Toolkit author (frameworks) | P with B and C; feeds B (PORT-002) | `kintsugi-frameworks install aider` succeeds end-to-end |
| E. Build wizard (Cluster 5) | TUI developer + systems integrator | S — **blocked on B, C, D complete**; is the central deliverable | Wizard runs non-interactively from profile; happy-path run produces flashable image |
| F. Imaging pipeline + NFS publish (Cluster 6) | Build engineer + release manager | P with B/C/D once spike complete; feeds E | First `.img.zst` + sha256 land on NFS |
| G. User-facing docs (Cluster 7) | Docs engineer | P with E/F once wizard stable | toolkit-guide, update-strategy, flash-image, wizard-guide drafted and reviewed |
| H. Release publication | Release manager | S — last, depends on A–G | v1.0.0 git tag + NFS publish + iteration-acceptance smoke passes |

Parallel clusters sync at the **iteration-acceptance gate** in H: a user runs `./scripts/kintsugi-build` from a fresh clone, takes defaults, obtains a flashable `.img.zst` + sha256, flashes, boots, and `usb-test-harness.sh` passes on a fleet host.

## Definition of Done

### Story-level DoD

A story is DONE when:

1. Code/docs committed via conventional-commits (no AI attribution).
2. `shellcheck` passes on any bash.
3. SPDX headers on Bash (`SPDX-License-Identifier: MIT`).
4. Acceptance criteria validated on real hardware where applicable.
5. Secret-pattern grep passes.
6. Linked Gitea issue closed with commit SHA.
7. Any cross-cluster interface (non-interactive flag, profile-file key, manifest schema field) documented in the consuming cluster's doc.

### Iteration-level DoD

Iteration 1 is DONE when:

- All P0 stories meet story-level DoD.
- `LICENSE` committed (DONE); MIT SPDX headers on every Bash file.
- `manifest/models-recommended.yaml` and `manifest/agentic-frameworks-recommended.yaml` committed and refined.
- `manifest/THIRD-PARTY-LICENSES.md` enumerates every bundled binary actually in the v1.0 base ISO.
- `SECURITY.md` committed with sha256 integrity story + v1.1 signing commitment.
- `scripts/kintsugi-build` runs end-to-end from a fresh clone on a clean Ubuntu 24.04 host.
- **Iteration-acceptance smoke (US-WIZ-004)**: a user runs `./scripts/kintsugi-build`, picks defaults, obtains `.img.zst` + `.sha256` + `kintsugi-build-profile.yaml`; `./scripts/kintsugi-build --from-profile <file>` reproduces the same artifact-set; flashing the image to a fleet USB and running `usb-test-harness.sh` on that USB returns PASS.
- `publish-release.sh` successfully copies the image set to the warehouse NFS mount; `releases.json` index updated.
- v1.0.0 git tag created; CHANGELOG entry committed.
- `README.md` updated with MIT badge, one-command wizard invocation, post-flash `kintsugi-models pull` / `kintsugi-frameworks install` / `gh auth login` hints, NFS publish note, and a sha256-verification paragraph (with "signing arrives in v1.1" line).
- Risks R-01 → RETIRED (MIT); R-05 → MITIGATED (imaging works); R-02 → PARTIAL (sha256 only; full mitigation lands in v1.1 with signing); R-04 → MITIGATING (git-pull-based update flow documented); R-17, R-18 → tracked with CLI guards; R-19, R-20 → documented with wizard-driven mitigations.

## Risks to Iteration 1

See `.aiwg/risks/risk-list.md` for full risk entries. Iteration-1 snapshot:

| Risk | Iteration-1 impact | Mitigation |
|------|--------------------|------------|
| R-01 LICENSE | **RETIRED** — MIT accepted | LICENSE committed (DONE); THIRD-PARTY-LICENSES narrow scope |
| R-02 supply-chain provenance | Signing deferred — **weaker for v1.0** | sha256 documented; NFS mount internal-only; SECURITY.md commits to v1.1 signing; `docs/flash-image.md` placeholder note |
| R-05 imaging pipeline | Primary deliverable; mitigated by wizard | US-WIZ-004 gates release on full wizard-to-image round-trip |
| R-06 accidental secrets | Iteration-1-critical | `prep-master.sh` secret-pattern grep + iteration-acceptance smoke surfaces leaks |
| R-08 flash hardware variance | Surfaces at iteration-acceptance smoke | Accept one-stick failure budget; document known-good sticks in `docs/flash-image.md` |
| R-11 non-technical flash UX | `flash-image.md` acceptance | Anti-pattern callouts, GUI-first, post-flash pull/install/login steps clearly explained |
| R-15 AI-generated runbook errors | Human-review gate on every destructive step | "Verification always" rule; wizard confirmation screens |
| R-17 malicious user-pulled slug (ADR-005) | User pulls compromised model | `kintsugi-models verify` enforces sha256 for HF; Ollama trust model documented in toolkit-guide |
| R-18 persistence fill from runaway pulls (ADR-005) | USB fills, system breaks | CLI soft-warn 80%, hard-refuse 95%; documented |
| **R-19 VS Code telemetry default (NEW, ADR-006 §D3)** | Microsoft telemetry enabled unless user opts out | Wizard asks at IDE step; default is "disable telemetry"; documented in toolkit-guide |
| **R-20 Copilot subscription dependency (NEW, ADR-006 §D3)** | Recipients without GitHub+Copilot get inert extension | Wizard and flash-image.md both document: post-flash `gh auth login`, Copilot sign-in, or opt-out at wizard step |
| R-09 model staleness | Reframed by ADR-005 as user concern | `docs/update-strategy.md` documents refresh mechanism |

R-19 and R-20 are filed as new entries in `.aiwg/risks/risk-list.md` separately from this plan.

## Tracking

Issues at `https://git.integrolabs.net/roctinam/kintsugi-usb/issues` — one per story (prefixes: US-010b, US-SEC-001, US-PORT-00x, US-MODEL-00x, US-FW-00x, US-WIZ-00x, US-IMG-00x, US-DOCS-00x, US-CORR-00x). Labels: `iteration-1`, `priority-p0`/`p1`, `phase: construction`, plus cluster label (`cluster-1` … `cluster-8`). Close on commit SHA reference. Mid/end-iteration status notes in `.aiwg/reports/`.

## References

- `.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md` — **anchor decision for this iteration**
- `.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md` — extended
- `.aiwg/architecture/adr-001-license-selection.md` (ACCEPTED / MIT), ADR-002 (further amended), ADR-003 (v1.0 signing deferred), ADR-004 (SUPERSEDED)
- `.aiwg/architecture/software-architecture-doc.md` §0, §1.2, §4.2, §4.3, §9.1, §9.5, §10 (amendments pending per US-CORR-002)
- `.aiwg/requirements/user-stories.md` — P0 story source (pending ADR-006 refresh)
- `.aiwg/risks/risk-list.md` — R-01 (retired), R-02 (partial), R-04, R-05, R-06, R-08, R-09, R-11, R-15, R-17, R-18, R-19 (new), R-20 (new)
- `.aiwg/reports/abm-gate-report.md`
- `docs/physical-test-guide.md`, `docs/toolkit-guide.md`, `docs/update-strategy.md`, `docs/flash-image.md`, `docs/wizard-guide.md` (NEW)
- `scripts/kintsugi-build` (NEW — central deliverable)
- `scripts/usb-toolkit/` — `build-custom-iso.sh`, `first-boot-setup.sh`, `start-ai.sh`, `usb-test-harness.sh`, `kintsugi-models`, `kintsugi-frameworks` (NEW)
- `scripts/prep-master.sh`, `scripts/create-base-image.sh`, `scripts/publish-release.sh` (all NEW/iteration-1)
- `scripts/check-drive-health.sh`, `scripts/benchmark-inference.sh`
- `manifest/models-recommended.yaml` (committed; refinement pending)
- `manifest/agentic-frameworks-recommended.yaml` (NEW — iteration-1 deliverable)
- `manifest/THIRD-PARTY-LICENSES.md` (NEW — bundled binaries only)
- `LICENSE` (MIT; DONE)
- `SECURITY.md` (NEW — reduced scope)
- `CLAUDE.md` §Distribution Workflow, §Public Repo Security, §Issue Tracking; `.claude/rules/RULES-INDEX.md` §no-time-estimates
