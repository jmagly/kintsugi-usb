# ADR-005: Toolkit Product Surface, Ollama Coexistence, and User-Driven Model Loading

**Status**: ACCEPTED (2026-04-20 — amends/supersedes earlier ADRs where noted)
**Date**: 2026-04-20
**Deciders**: Joseph Magly (maintainer)
**Supersedes**: none directly, but MATERIALLY AMENDS ADR-001, ADR-002, and **SUPERSEDES ADR-004**
**Drives amendments to**: SAD §1.2, §4.2, §4.3, §9.5; risk-list (R-01, R-09 eased; R-17, R-18 new); nfr-register (storage, new toolkit-UX category); iteration-001-plan; user-stories; test-strategy
**Consulted**: maintainer direction 2026-04-20; ported sysops/usb-toolkit scripts (`start-ai.sh`, `usb-test-harness.sh`, `build-custom-iso.sh`, `first-boot-setup.sh`, plus `benchmark-inference.sh`, `check-drive-health.sh`)

## Context

Three scope clarifications from the maintainer late in Elaboration materially change the product definition that the baselined SAD and ADR-001..004 assumed:

1. **Dual product surface**: Kintsugi USB is both (a) a **toolkit** — an SDK of scripts and docs that others can use to roll their own Kintsugi-like USB, and (b) a **distributed tested image** — maintainer-signed releases that non-technical recipients can flash directly. The earlier SDLC baseline framed this as (b) only, with (a) implicit.
2. **Ollama coexistence**: Ollama sits alongside llama.cpp as a second local model runtime on the booted USB. Both are available; they serve different UX needs (llama.cpp for direct GGUF execution and embedded/scripted use; Ollama for model-management convenience and registry pulls).
3. **User-driven model loading**: Model weights are **loaded by end-users**, not bundled by the maintainer. Users populate their image in two ways:
   - **Build-time** — on the host that is imaging/setting up the USB, using toolkit scripts to download model weights into the in-progress master before imaging.
   - **Boot-time** — on the running USB when connected to the internet via the host's hardware, pulling models into the persistence overlay.

Additionally, inspection of the ported `start-ai.sh` from sysops shows the actual tested models are **Qwen3.5 4B and Qwen3.5 9B**, not the Qwen2.5-Coder 7B + Phi-4-mini combination that docs/requirements.md, docs/architecture.md, and ADR-004 describe. Those docs are stale relative to the code.

This ADR consolidates the four resulting decisions into a single coherent amendment.

## Decision Drivers

- **Clarity of maintainer obligation**: maintainer ships code, docs, signatures, and infrastructure — not model weights — so the licensing, supply-chain, and storage-budget stories are all simpler and cleaner.
- **Reuse of existing work**: four substantial scripts already exist in sysops (`build-custom-iso.sh`, `first-boot-setup.sh`, `start-ai.sh`, `usb-test-harness.sh`, totalling ~1,400 lines); port-and-adapt is the right posture, not rewrite.
- **Extensibility for builders**: a toolkit that others can use means the model set, not just the runtime, must be easy to configure from the outside.
- **Simplicity of signed release**: removing model weights from the distributed image removes the largest and most license-encumbered bundled content, shrinking the base image dramatically and simplifying ADR-001.
- **Separation of trust boundaries**: maintainer's signature attests to code/docs/toolkit; user-pulled models carry their source's own integrity story.

## Decision

### D1. Dual Product Surface (toolkit + distributed image)

Kintsugi USB is explicitly two products in one repo:

- **Toolkit** (`scripts/`, `docs/`, `manifest/`, `.aiwg/`) — documented, reusable. External builders clone the repo and use it as an SDK to produce their own master USBs. This is a first-class audience.
- **Distributed image** (Gitea releases) — the maintainer's personally-tested signed image for flash-and-go recipients.

Both audiences are addressed in README.md, SAD §1.2, and iteration-001-plan.

### D2. Ollama Coexistence

The booted USB provides **both** local model runtimes:

| Runtime | Role | Invocation |
|---------|------|-----------|
| `llama.cpp` (llama-server, llama-cli) | Direct GGUF execution, OpenAI-compat HTTP API, scripted use, embedded in `aider` flow | `start-ai.sh` starts llama-server on :8080; `llama-cli` for interactive |
| `ollama` | User-friendly model management, registry pulls, auto-quantization UX, OpenAI-compat HTTP API | `ollama serve` on :11434 (default); `ollama run <slug>` interactive |

Both are enabled; `start-ai.sh` reports status for both. Users pick either endpoint via env vars (`OPENAI_API_BASE=http://localhost:8080/v1` or `:11434/v1`).

Ollama's model store lives at `/data/ollama/` in the persistence overlay so pulls survive reboots.

### D3. User-Driven Model Loading

**No model weights ship in the distributed base image.** The maintainer publishes a *recommended-list document* (`manifest/models-recommended.yaml`) describing tested slugs and quantizations but does not bundle the files. Users populate their images themselves, via one of two paths.

#### Build-time path (on a host preparing the USB)

Tool: `scripts/kintsugi-models` CLI (Bash or Python; MVP Bash).

```
kintsugi-models list                     # show configured slugs (default + user)
kintsugi-models add <slug> [--quant Q4_K_M]   # add to user manifest
kintsugi-models pull <slug>              # download now (build-time: writes to in-progress master)
kintsugi-models remove <slug>            # remove from user manifest + optionally delete weights
kintsugi-models verify                   # sha256 + license check for each bundled slug
```

At build-time, `pull` writes to `/mnt/usb/payload/models/` on the in-progress master (or the configured build root). After imaging, those files are present on the flashed USB — so the builder ships their chosen models with their image.

#### Boot-time path (on the flashed USB with internet)

Same CLI works on the running USB. `pull` writes to `/data/models/user/` in the persistence overlay (not to squashfs or to the payload partition, both of which are read-only at runtime).

#### Runtime model discovery

`start-ai.sh` (after refactor) scans `/payload/models/` then `/data/models/user/`. Entries with matching slug names prefer the user-copy (shadowing). Ollama's own `~/.ollama/models/` store (symlinked into `/data/ollama/`) is independent and discoverable via `ollama list`.

### D4. Model Manifest Schema

File: `manifest/models-recommended.yaml` (in-repo; tracked; signed as part of release). Schema:

```yaml
schema_version: 1
description: "Maintainer-tested model slugs. Users may freely edit or replace."
signed_release: true   # maintainer's signature attests to THIS file; NOT to the weights

recommended:
  - slug: qwen3.5:4b
    runtime: ollama     # or: llama-cpp
    source: ollama      # or: huggingface | url
    quant: Q4_K_M
    sha256: null        # Ollama manages its own digest; populate when source is hf/url
    purpose: "General reasoning, log analysis. Default for hosts with <16 GB RAM."
    tested_on: [ref-host-1, ref-host-2]
    notes: ""

  - slug: qwen3.5:9b
    runtime: ollama
    source: ollama
    quant: Q4_K_M
    purpose: "General reasoning + light code. Default for hosts with ≥16 GB RAM."
    tested_on: [ref-host-1, ref-host-2]

  - slug: Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf
    runtime: llama-cpp
    source: huggingface
    hf_repo: bartowski/Qwen2.5-Coder-7B-Instruct-GGUF
    hf_file: Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf
    sha256: <fill-on-first-add>
    purpose: "Code generation (direct GGUF, llama.cpp-compatible, scriptable)."
```

User manifest (`/data/models/user/models.yaml` in persistence) follows the same schema. Runtime unions both; user entries shadow on slug conflict.

### D5. Supersession and Amendment of Prior ADRs

| Prior ADR | Status after this ADR | Notes |
|-----------|-----------------------|-------|
| ADR-001 License | **MATERIALLY AMENDED** | Model-weight redistribution concerns removed (we no longer redistribute weights). Apache-2.0 + THIRD-PARTY-LICENSES still applies for bundled binaries (llama.cpp, Ollama, Ventoy, `claude`/`codex` CLIs, rescue ISOs). The Qwen commercial threshold and Anthropic model EULAs drop out of scope. |
| ADR-002 Imaging | **MATERIALLY AMENDED** | Base image drops from ~5 GB (with models) to significantly smaller (no weights; just OS + tools + llama.cpp + ollama + rescue ISO menu). The separate "payload tarball" shrinks to docs + scripts only, or may collapse entirely — revisited during Iteration 1 once sizes are measured. Signed-release model (sha256 + minisign per ADR-003) unchanged. |
| ADR-003 Verification | **unchanged** | sha256 + minisign remains the v1.0 integrity story. Applies to the base image, scripts, and the recommended-models manifest file itself (not to user-pulled weights — those are the user's integrity concern). |
| ADR-004 Model selection | **SUPERSEDED** | Model selection is a user-driven configuration, not a maintainer-curated bundle. The recommended-list approach (D4 above) replaces the "maintainer ships X by default" model. Prior ADR-004 file is retained for history with a supersession notice. |

## Considered Alternatives

**A. Maintainer bundles curated models + user can override** (the earlier ADR-004 posture).
- Pros: zero-network first-boot UX; signed weight chain.
- Cons: license redistribution exposure; bloated image; maintainer has to track model refreshes; user slug overrides fight with bundled defaults.

**B. Toolkit-only, no distributed image.**
- Pros: simplest maintainer story; no release artifacts beyond tagged git.
- Cons: abandons the non-technical recipient audience; loses the "I tested this" value proposition.

**C. User-driven + no runtime model management** (users hand-copy GGUFs).
- Pros: simplest code.
- Cons: terrible UX; Ollama's convenience value is thrown away; "pull on boot" flow never works.

**Chosen: D (user-driven + kintsugi-models CLI + dual runtime + dual product surface)**, described above — combines the audience reach of a distributed image, the flexibility of user-driven models, and the reuse of ported scripts.

## Consequences

### Positive

- License risk (R-01) significantly reduced — no model-weight redistribution.
- Base image is small (GB, not tens of GB); faster downloads, simpler Gitea release hosting, fewer size-limit worries.
- External builders get a real toolkit they can extend (manifest schema + CLI + docs).
- Users stay current: model refresh is a `kintsugi-models pull <slug>` away, not a maintainer reflash.
- Supply-chain story is cleaner: maintainer's signature covers what maintainer actually authored (scripts, docs, manifest, ISO), not weights the maintainer didn't make.

### Negative

- Non-technical recipients need internet at some point to populate their USB with models — loses the "fully offline from minute zero" pitch. Mitigation: `docs/flash-image.md` recommends the initial `kintsugi-models pull` as a step immediately after first boot on a trusted network.
- Users can pull malicious or compromised slugs from Ollama registry or HuggingFace. Risk R-17 (new) tracks this.
- Users can fill persistence with runaway model pulls. Risk R-18 (new) tracks this; `kintsugi-models` CLI enforces a soft-warn at 80% and hard-refuse at 95%.
- The `kintsugi-models` CLI is new code to write and test — iteration-1 scope expansion.

### Neutral

- `start-ai.sh` needs a refactor to manifest-driven discovery + Ollama status reporting. The ported script is a solid base; not a rewrite.
- `build-custom-iso.sh` and `first-boot-setup.sh` are compatible as-is (they don't touch model weights — they build the OS layer).
- `usb-test-harness.sh` becomes more important in this architecture — it's how we validate a user-populated USB boots and runs end-to-end.

## Implementation Plan (iteration-1 scope)

See `.aiwg/planning/iteration-001-plan.md` for the authoritative iteration plan. Summary of the net-new or revised iteration-1 deliverables driven by this ADR:

1. **Port-and-adapt** `scripts/usb-toolkit/start-ai.sh` — refactor to read `manifest/models-recommended.yaml` + `/data/models/user/models.yaml`; add Ollama status reporting.
2. **New** `scripts/usb-toolkit/kintsugi-models` CLI — Bash MVP; subcommands `list`, `add`, `pull`, `remove`, `verify`; supports Ollama and HuggingFace sources for v1.0, URL + sha256 deferred.
3. **New** `manifest/models-recommended.yaml` — starter schema with Qwen3.5 4B/9B entries (Ollama-source) plus Qwen2.5-Coder 7B (HuggingFace/llama-cpp-source) as recommended coder.
4. **Update** `docs/requirements.md` — FR-4.x corrected to reflect Ollama coexistence + user-driven loading + corrected model inventory.
5. **Update** `docs/architecture.md` or new supplement — document the manifest schema + CLI commands for external builders (a main toolkit-documentation commitment).
6. **Retain** `build-custom-iso.sh`, `first-boot-setup.sh`, `usb-test-harness.sh`, `check-drive-health.sh`, `benchmark-inference.sh` as ported; apply light adaptations (paths, version strings) only as needed.
7. **Revise** `scripts/prep-master.sh` (iteration-1 deliverable) to work against a build-root that may have user-pulled models already in `/payload/models/`.
8. **Defer** the `scripts/update-payload.sh` design in light of (a) smaller payload — field update may now be just `git pull` in `/data/scripts/` + `kintsugi-models pull` for any new recommended slugs.

## Open Questions

1. **Bundle a tiny smoke-test model?** — e.g., a 50 MB TinyLlama GGUF shipped in the base image, used by `usb-test-harness.sh` to validate that llama-server can load *something* without internet. Probably yes; license check required. Tracked as iteration-1 decision.
2. **Ollama registry availability risk** — what if `registry.ollama.ai` is down during a user pull? Document as a known limitation; `--source huggingface` alternative remains.
3. **Build-time path rooting** — should `kintsugi-models` detect a running Ventoy master mount vs. a local build root? Probably yes, with `--target <path>` override. Deferred to CLI design phase.
4. **HuggingFace auth for gated repos** — some GGUFs require a HF token. `kintsugi-models add --hf-token env:HF_TOKEN`? Probably; document but do not hard-require.

## Links

- SAD §1.2 (scope), §4.2 (AI stack), §4.3 (toolkit pipeline), §9.5 (licensing) — being amended to match
- ADR-001 (material amendment pending), ADR-002 (material amendment pending), ADR-003 (unchanged), ADR-004 (superseded)
- `scripts/usb-toolkit/start-ai.sh` (ported from sysops, 235 lines, refactor target)
- `scripts/usb-toolkit/usb-test-harness.sh` (ported from sysops, 527 lines, retained)
- `scripts/benchmark-inference.sh` (ported from sysops, 450 lines, retained — powers NFR-1.3/1.4 measurement)
- R-01 (license — eased), R-09 (model staleness — reframed as user concern), R-17 (malicious user-pulled slug — NEW), R-18 (persistence fill — NEW)
- `docs/requirements.md` FR-4.x (to be corrected)
- `manifest/models-recommended.yaml` (to be authored)
- user-stories.md (new cluster: "Toolkit for External Builders" + "User-Driven Model Loading")
