# ADR-004: AI Model Selection and Update Boundary

**Status**: **SUPERSEDED by ADR-005** (2026-04-20, same day). Retained for history.
**Date**: 2026-04-20
**Deciders**: Joseph Magly
**Supersession note**: Within hours of this ADR's acceptance, maintainer direction clarified that **models are loaded by end-users, not bundled by the maintainer**. The premise of this ADR — that the maintainer ships a curated dual-model loadout (Qwen2.5-Coder 7B + Phi-4-mini) with quarterly refresh — is therefore obsolete. See `adr-005-toolkit-scope-and-user-driven-models.md` for the replacement decision (user-driven model loading via `kintsugi-models` CLI + `manifest/models-recommended.yaml`; Ollama coexistence with llama.cpp; corrected tested-model inventory Qwen3.5 4B/9B). The original content below is preserved unchanged for audit trail — **do not act on it**.
**Consulted**: SAD §4.2 (AI stack), SAD §4.3 (payload), SAD §10 (ADR summaries), ADR-001 (license), ADR-002 (imaging / payload tarball), ADR-003 (verification rigor), R-09 (models go stale), R-04 (no field update)

---

## 1. Context

Kintsugi USB bundles an offline LLM inference stack (`llama.cpp` + GGUF model weights) so that UC-003 (AI-assisted script generation, offline) works on a host with no network — typically the worst-case rescue scenario. UC-002 (AI-assisted log analysis, online) prefers cloud CLIs when a network exists, but the local stack is the resilient fallback and the primary path for air-gapped work.

Today's master USB ships two model files (docs/architecture.md §4, layout in §2):

| Model | Size | Role |
|---|---|---|
| `qwen2.5-coder-7b-instruct-q4_k_m.gguf` | ~5.0 GB | Code-instruct model for script generation |
| `phi-4-mini-instruct-q4_k_m.gguf` | ~2.8 GB | General reasoning, fits 8 GB hosts |

`start-ai.sh` auto-selects at boot: Qwen on hosts with ≥16 GB RAM, Phi on hosts with <16 GB (FR-4.7). Performance targets per NFR-1.3/1.4 are Phi > 15 tok/s and Qwen > 8 tok/s on the i7-12700H reference host.

Four forces shape this ADR:

1. **Storage budget (NFR-2.1)**. Total USB utilization must stay under 95 % of 59 GB. ~8 GB of models is comfortable; adding a third 9 B-class model (~6 GB) stays under budget but erodes headroom for ISOs and persistence.
2. **License compatibility (ADR-001)**. Qwen 2.5-Coder is permissive for non-commercial redistribution but has commercial-use thresholds; Phi-4 ships under the MIT-style Microsoft Research license. Both are redistributable for the personal/family/small-fleet audience (§1 of the SAD).
3. **Model freshness (R-09)**. Open-weight LLMs in the 3 B–9 B size class publish meaningfully better checkpoints roughly every 2–4 months. Yearly refresh ships stale weights; monthly refresh is busywork.
4. **Update boundary (R-04, ADR-002)**. Models sit on the exFAT partition and are file-copyable. They must be updatable in the field via the payload tarball without reflashing the whole image.

The update-boundary requirement is load-bearing: a rescue USB whose models decay over 18 months without a path to refresh them becomes progressively less useful at the exact work it was built for.

---

## 2. Decision Drivers

- **Storage budget** (NFR-2.1): keep total model footprint ≤ 10 GB to leave headroom for ISOs, tools, and persistence.
- **License compatibility** per ADR-001; avoid bundled weights that require click-through acceptance or prohibit redistribution.
- **Model freshness** vs shipping cadence — the project ships quarterly, not monthly.
- **Coverage breadth**: UC-003 needs code-instruct behavior for script generation; UC-002 needs general reasoning for log analysis. A single model that does both acceptably is rare at this size class.
- **Field-updatability** (R-04, NFR-6.2): all model choices must remain swappable via `update-payload.sh` without reflash.
- **No runtime auto-download**: the rescue use case assumes network may be absent. Models must be on the drive at flash time.

---

## 3. Considered Options

### Option 1 — Status quo: Qwen2.5-Coder 7B + Phi-4-mini (dual-model split)

- **Pros**: covers both code (UC-003) and general reasoning (UC-002-offline fallback); RAM-based auto-select already works; ~7.8 GB total is comfortable; both already vetted on fleet hosts.
- **Cons**: two models means two sets of licenses to track and two refresh decisions per cycle.

### Option 2 — Single model (Phi-4-mini only, or Qwen-Coder 7B only)

- **Pros**: simpler payload, smaller footprint (~2.8 GB or ~5 GB), single license to reason about.
- **Cons**: Phi-alone leaves 16 GB+ hosts underutilized and under-performs Qwen on code tasks; Qwen-alone strands 8 GB hosts (Qwen 7B Q4 barely fits and thrashes). Loses the graceful-degradation property of RAM-based selection.

### Option 3 — Upgrade to a 9 B-class companion (e.g., Qwen3 9B alongside current pair)

- **Pros**: better quality on hosts with ≥24 GB RAM; keeps the 7 B and 3.8 B as fallback.
- **Cons**: adds ~6 GB to the image, pushing model footprint toward 14 GB and eroding storage headroom; three-way RAM-based routing adds complexity; no fleet host today has ≥24 GB as the dominant profile.

### Option 4 — Multiple models, user-selectable at runtime via `start-ai.sh` prompt

- **Pros**: operator can force a specific model for a specific task.
- **Cons**: rescue-context UX friction; operators want the tool to work, not to answer questions. Auto-select with an override flag (Option 1 refinement) captures the benefit without the friction.

### Option 5 — No bundled models, download on first boot

- **Pros**: smallest image; always freshest weights.
- **Cons**: **directly defeats the offline/air-gapped rescue use case** (UC-003). Unacceptable.

---

## 4. Decision

**Maintain the status quo dual-model loadout for v1.0** — Qwen2.5-Coder 7B Q4_K_M + Phi-4-mini Q4_K_M — with the following formalizations:

1. **RAM-based auto-select remains the default**, with a new `--model phi|qwen` override flag added to `start-ai.sh` for operators who want to force a specific model regardless of host RAM.
2. **Model files live at `/models/`** on the exFAT VENTOY partition (per docs/architecture.md §2) and are shipped as part of the payload tarball produced by ADR-002's imaging pipeline.
3. **Model updates are a payload-tarball operation, not a reflash**. `scripts/update-payload.sh` (NYE, SAD §4.3) is the single supported path for refreshing weights in the field. Models must never be baked into the squashfs.
4. **Refresh cadence is QUARTERLY**. The maintainer reviews open-weight model releases in the 3 B–7 B size class at the start of each quarter; when a superior checkpoint exists in the same size class under a compatible license, it ships in that quarter's payload release. Monthly churn is explicitly rejected.
5. **License compliance posture**: a bundled model must permit free non-commercial redistribution. Models with commercial-use thresholds (Qwen's current posture) ship under the same assumption as today — a non-commercial recipient audience — and the threshold is documented in `manifest/THIRD-PARTY-LICENSES.md` (SAD §8.2, NFR-10.2). Models requiring per-user license acceptance (click-through EULA) are disqualified from bundling and must instead be offered as a recipient-fetched companion.

---

## 5. Update Boundary (Normative)

This ADR fixes the update-boundary contract first sketched in SAD §4.3:

| Component | Update mechanism | Frequency |
|---|---|---|
| GGUF model files (`/models/*.gguf`) | payload tarball via `update-payload.sh` | Quarterly |
| `llama.cpp` binaries (`llama-server`, `llama-cli`) on exFAT | payload tarball via `update-payload.sh` | When upstream ships meaningful perf or stability improvements |
| `start-ai.sh` and payload scripts | payload tarball via `update-payload.sh` | As needed |
| `docs/`, `scripts/`, `data/recovery/` | payload tarball via `update-payload.sh` | As needed |
| Custom Ubuntu ML-Support squashfs ISO | base image — **REQUIRES REFLASH** | Annually, or on critical security update |
| Ventoy + bootloader + MOK chain | base image — **REQUIRES REFLASH** | When Ventoy upstream ships a critical fix |
| Persistence overlay | recipient-owned; updater never touches | Per recipient |

This boundary directly mitigates R-04 (field update) and R-09 (models go stale). It also preserves the supply-chain-integrity story from ADR-003: each quarterly payload tarball is its own signed release with its own manifest and SHA, so model updates are as verifiable as the original image.

---

## 6. Future Considerations (out of scope for v1.0)

- **Adaptive quantization per host** (Q4_K_M / Q5_K_M / Q8_0 selection based on RAM headroom and disk read throughput).
- **Warm-load from tmpfs** to shorten `llama-server` startup time on hosts with ample RAM (NFR-1.2).
- **Vision-capable models** (e.g., for screenshot-based diagnosis) — gated by the multi-modal ecosystem maturing at the 4 B–7 B size class.
- **Per-host model preference file** in persistence overlay so a repeatedly-used host boots directly into its preferred model.
- **Telemetry on model selection** — explicitly deferred per SAD §9.2; a solo, non-commercial project with a few dozen recipients has no justification for a telemetry pipeline.

---

## 7. Consequences

**Positive**:

- Zero net change to what the v1.0 release physically ships — derisks the LAM gate.
- Model refresh becomes a routine quarterly task with a single documented script (`update-payload.sh`), not a reflash campaign.
- The update-boundary table gives recipients a clear mental model of what they get automatically (quarterly payload) vs what requires them to reflash (rare, announced).
- Keeps RAM-based auto-select — the single most operator-friendly behavior in the AI stack — while adding the `--model` override escape hatch for power users.

**Negative**:

- Quarterly refresh still ships weights that are up to 90 days behind the frontier at any given moment; recipients who track HN release notes will occasionally know about a better model before the project ships it. Accepted; the refresh cadence is a deliberate cost/value tradeoff.
- Two bundled models means two license-review lines in `manifest/THIRD-PARTY-LICENSES.md` per release.
- If Qwen's commercial threshold ever changes to a click-through EULA, the project must drop it from the default bundle (fall back to a single-model loadout or find a replacement). Documented risk, handled by the license-compliance posture in §4.5.

---

## 8. Open Questions

1. **Qwen redistribution in a publicly-downloadable image**. Is Qwen2.5-Coder's current license compatible with hosting a signed `.img.zst` on a public Gitea release page, or must the recipient fetch the weights themselves on first run? Touches ADR-001's open question on cloud-CLI redistribution and must be resolved jointly. Owner: project lead (jointly with ADR-001).
2. **Models-only payload variant**. Should `update-payload.sh` support a `--models-only` flag so recipients on bandwidth-constrained links can refresh weights without re-downloading docs and scripts? Lightweight addition; defer to Construction.
3. **Benchmark-on-first-boot**. Should `start-ai.sh` capture a `llama-cli --benchmark` run on first boot per host and archive it under `/var/log/kintsugi/` so NFR-1.3/1.4 are field-measurable? SAD §9.2 already specifies this; confirming here that the benchmark output is the canonical signal for whether a new model passes its NFR target on a given host.

---

## 9. Links

- SAD §4.2 (AI stack), §4.3 (payload components), §8.2 (manifest schema), §9.2 (observability)
- ADR-001 (License Selection and Bundled-Artifact Compatibility)
- ADR-002 (Imaging Strategy / payload tarball)
- ADR-003 (Verification Rigor / signed releases)
- R-04 (No field-update mechanism), R-09 (GGUF models outdate), R-10 (cloud CLI auth flow changes)
- FR-4.1..4.7 in `docs/requirements.md`
- NFR-1.3, NFR-1.4 (inference speed targets); NFR-2.1 (storage budget); NFR-6.2 (model update path); NFR-10.2, NFR-10.5 (license manifest + runtime surfacing)

---

*End of ADR-004.*
