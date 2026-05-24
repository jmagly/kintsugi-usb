# Kintsugi USB — Risk Register

- **Project**: Kintsugi USB
- **Owner**: Joseph Magly (roctinam)
- **Last updated**: 2026-05-24 (sysops-drift reconciliation; see top amendment)
- **Phase**: Construction → Transition (iteration-1 delivered; `first_deploy` milestone recorded 2026-05-24)

## 2026-05-24 Sysops-drift reconciliation (R-14)

Scope-correction pass: host-specific / fleet-operational content that drifted in during the sysops migration was removed from this public toolkit repo.

- **N5 Pro SOP migrated to sysops** (`~/sysops/docs/runbooks/`); `docs/n5pro-recovery-sop.md` removed here. Repo scope reframed (intake, CLAUDE.md, SAD, README): the USB *carries* host recovery packs as operator payload but does not author them.
- **Fleet topology externalized**: hardcoded `10.0.0.x` fleet hosts removed from the public build scripts → operator-provided git-ignored optional config (`config/fleet-hosts.example`). The sanitization-checklist "fleet /etc/hosts MAY be baked in" blessing was retracted.
- **Private hostnames genericized** (ref-host-1/ref-host-2/… → ref-host-N) across test-strategy, physical-test-guide, requirements.
- **R-14 (doc drift)** — advanced from MITIGATING; major sysops-era content reconciled. Remaining: per-doc migration status tracking.
- **R-15 (runbook accuracy)** — the #33 gate infra remains but is now **dormant** (no runbook-tagged docs here once the N5 SOP left). Runbook-review discipline for host SOPs now belongs in the fleet repo (sysops) where they are authored. #33 closed on the kintsugi side.
- Stale `docs/n5pro-recovery-sop.md` references in the R-13/R-14 mitigation bodies below now point at sysops; retained as historical context.

## 2026-05-23 Reconciliation (post-iteration-1 shipping)

Iteration-1 shipped (28 of 31 Gitea issues closed; imaging pipeline, build wizard, and `kintsugi-models` / `kintsugi-frameworks` CLIs all landed). This pass reconciles the register against delivered code, verified against the working tree:

- **R-05 (imaging scripts don't exist)** — **RETIRED**. `scripts/{prep-master,create-image,flash-image,verify-image,publish-release}.sh` all exist and were exercised end-to-end (Gitea #2/#3/#4/#6/#29 closed; commit `b3031e5`). No longer a risk.
- **R-04 (no field update)** — mitigation reframed, **downgraded HIGH → MED**. `update-payload.sh` was superseded (Gitea #5); the supported model is now `git pull` on persistence + `kintsugi-models pull` (ADR-005). Residual is user-education only; `docs/update-strategy.md` shipped (#18).
- **R-17 (malicious model slug)** — **OPEN → MITIGATING**. Trust-model doc shipped (#24); `kintsugi-models verify` (sha256) + `--only-recommended` lockdown landed (#15). Residual is inherent registry risk.
- **R-19 (VS Code telemetry)** — **MITIGATING → MONITORING (effectively resolved)**. `scripts/usb-toolkit/build-custom-iso.sh` writes `telemetry.telemetryLevel: "off"` as the skel default and `usb-test-harness.sh` asserts it. Watch only for upstream VS Code default changes. (Correction: the writer is `build-custom-iso.sh`, not `first-boot-setup.sh` as the R-19 body originally stated.)
- **R-21 (framework install failures)** — **OPEN → MITIGATING**. `kintsugi-frameworks` CLI shipped (#27) with per-framework transactional installs and a resumable wizard profile (#26).
- **R-06 (secrets in squashfs/exFAT)** — unchanged MITIGATING; `scripts/prep-master.sh` + `scripts/secret-patterns.txt` sanitize pass shipped. Promotion to MONITORING gated on CI enforcement.
- **R-07 (secrets in public repo)** — unchanged CRITICAL/MITIGATING. The Phase-2 pre-commit secret scanner (`gitleaks`/`detect-secrets`) is **still not implemented** — now tracked as **Gitea #32**.
- **R-15 (AI runbook accuracy)** — unchanged HIGH/OPEN. `docs/n5pro-recovery-sop.md` exists but no human-review-before-ship gate is enforced — now tracked as **Gitea #33**.

Summary and Top 5 below are updated to reflect these changes.

## 2026-04-20 Amendment #2 (per ADR-006)

Second amendment on 2026-04-20, extending the user-driven-loading pattern and pivoting to wizard-first UX:

- **R-01 (license)** — **CLOSED 2026-04-20**. LICENSE (MIT) and `manifest/THIRD-PARTY-LICENSES.md` both committed. ADR-001 ACCEPTED.
- **R-02 (supply-chain provenance)** — severity **temporarily bumped** for v1.0. ADR-006 defers signing to v1.1; v1.0 maintainer-produced images ship sha256-only. Mitigation: NFS-internal distribution in v1.0 (limited exposure). When signing lands in v1.1, severity returns to its ADR-003 posture.
- **R-19 (NEW)** — VS Code ships with telemetry enabled by default. Wizard must prompt.
- **R-20 (NEW)** — GitHub Copilot extension is preinstalled but inert without GitHub sign-in + Copilot subscription. Recipients without either get an installed-but-useless extension; document clearly.
- **R-07 (secrets)** — unchanged; sha256 is still verifiable integrity for NFS-delivered images.
- New CLI risks (R-21 framework install failures, R-22 Copilot extension version drift) added; see bottom.

## 2026-04-20 Amendment (per ADR-005)

ADR-005 (user-driven model loading + toolkit product surface + Ollama coexistence) changes the risk landscape:
- **R-01 (license)** — downgraded **CRITICAL → HIGH**. Model-weight redistribution removed from scope (Qwen commercial threshold and Claude EULA no longer apply to our release). Repo-level Apache-2.0 + THIRD-PARTY-LICENSES for bundled binaries remains the plan.
- **R-04 (no field update)** — severity unchanged, but mitigation simplified: the new update model is `git pull` on persistence + `kintsugi-models pull`. Update-payload.sh deferred/collapsed.
- **R-09 (models go stale)** — REFRAMED. No longer a maintainer responsibility (no bundled weights). User-owned; `kintsugi-models` CLI provides the refresh path. Severity adjusted LOW → LOW (same), status → ACCEPTED-for-maintainer / documented-for-user.
- **R-17 (NEW)** — user pulls malicious or compromised model slug from Ollama registry / HuggingFace. HIGH.
- **R-18 (NEW)** — user fills persistence overlay with runaway model pulls. MED.
- Risk Summary and Top 5 updated below.
- **Scoring**: Likelihood (L/M/H), Impact (L/M/H), Severity (Likelihood × Impact → LOW / MED / HIGH / CRITICAL)
- **Status values**: OPEN / MITIGATING / MONITORING / RETIRED / ACCEPTED

### Severity Matrix

| Likelihood ↓ / Impact → | L | M | H |
|---|---|---|---|
| **H** | MED | HIGH | CRITICAL |
| **M** | LOW | MED | HIGH |
| **L** | LOW | LOW | MED |

---

## Risk Summary (reconciled 2026-05-23)

- **2 CLOSED/RETIRED**: R-01 (LICENSE → MIT + THIRD-PARTY-LICENSES.md, 2026-04-20), R-05 (imaging pipeline shipped, 2026-05-23)
- **1 CRITICAL**: R-07 (secrets in public repo — MITIGATING; pre-commit scanner pending, Gitea #32)
- **4 HIGH**: R-02 (signing → v1.1), R-06 (secret bake — MITIGATING), R-15 (AI runbook accuracy — OPEN, #33), R-17 (model slug — MITIGATING)
- **11 MED**: R-03, R-04, R-08, R-10, R-11, R-12, R-14, R-18, R-19, R-20, R-21
- **4 LOW**: R-09, R-13, R-16, R-22

**Total**: 22 tracked (20 active + 2 closed/retired). Severities are grouped by impact level; current status per risk is in the body and the 2026-05-23 amendment above.

### Top 5 Risks to Watch (reconciled 2026-05-23)

1. **R-07 — Accidental secrets in public repo** (CRITICAL, MITIGATING) — Phase-2 pre-commit secret scanner (`gitleaks`) still unbuilt; tracked as Gitea #32.
2. **R-15 — AI-generated runbook ships inaccurate guidance** (HIGH, OPEN) — no human-review-before-ship gate yet; tracked as Gitea #33.
3. **R-02 — No supply-chain provenance for distributed image** (HIGH, OPEN) — minisign keypair deferred to v1.1 (Gitea #19, post-v1.0); v1.0 ships sha256-only over NFS.
4. **R-06 — Accidental secrets in squashfs / exFAT** (HIGH, MITIGATING) — `prep-master.sh` + `secret-patterns.txt` sanitize pass shipped; promote on CI enforcement.
5. **R-17 — Malicious / compromised model slug** (HIGH, MITIGATING) — `kintsugi-models verify` + `--only-recommended` shipped; residual is inherent registry risk.

---

## Risks

### R-01: LICENSE TBD — bundled-artifact license incompatibility
**Category**: Legal
**Description**: `README.md` marks LICENSE as TBD. The distributed USB bundles artifacts with heterogeneous licenses.
**Likelihood**: H
**Impact**: H
**Severity**: HIGH (downgraded from CRITICAL per ADR-005 — model-weight redistribution removed from scope)
**Status**: **CLOSED 2026-04-20** — MIT LICENSE committed (ADR-001 ACCEPTED per ADR-006 §D6); `manifest/THIRD-PARTY-LICENSES.md` committed enumerating bundled binaries only (no model weights, no agentic-framework binaries per ADR-005/006). Retained here for audit trail.
**Mitigation (resolved)**: ADR-005 removed model-weight redistribution from scope; ADR-006 extended the same pattern to agentic-framework binaries. MIT selected for repo-level license (lowest forker friction for the wizard-first toolkit product). Bundled binaries (Ventoy GPLv3, llama.cpp MIT, Ollama MIT, VS Code MSFT license, Copilot extension MSFT license, gh MIT, rescue ISOs) enumerated in `manifest/THIRD-PARTY-LICENSES.md`. No closed-source CLI EULA conflicts remain — Claude Code / Codex / Cursor etc. are user-fetched at build time via `kintsugi-frameworks`, not redistributed.
**Owner**: Joseph
**Closed by**: Gitea issue #1 (closed 2026-04-20), #30 (THIRD-PARTY-LICENSES.md, closed 2026-04-20).

---

### R-02: No supply-chain provenance for distributed image
**Category**: Supply-chain / Security
**Description**: Recipients of a published `.img.zst` have no cryptographic way to verify the image came from the maintainer and has not been tampered with in transit or on a mirror. A SHA-256 checksum alone, if hosted on the same server as the image, defends against accidental corruption but not against malicious substitution.
**Likelihood**: M
**Impact**: H
**Severity**: HIGH
**Status**: OPEN
**Mitigation strategy**: Phase 1: publish SHA-256 on Gitea release page (covers accidental corruption). Phase 2: detached minisign or cosign signature; publish public key in `README.md` and an independent channel (pinned in maintainer's profile, optionally in sysops repo). Document verification procedure in `docs/flash-image.md`. Maintain a manifest file listing every ISO / binary / model shipped with its upstream-sourced checksum. Link to ADR-002 (Verification Strategy).
**Owner**: Joseph
**Trigger / review date**: Review before Phase-2 release; re-evaluate if image appears on a third-party mirror.

---

### R-03: Cubic-built custom Ubuntu ISO is not bit-for-bit reproducible
**Category**: Technical
**Description**: The custom `ubuntu-24.04-ml-support.iso` is built interactively via Cubic (chroot + GUI). Package install order, timestamps, and apt cache state make the resulting ISO not reproducible byte-for-byte. A recipient cannot rebuild and compare; they must trust the maintainer's artifact plus a signature (see R-02).
**Likelihood**: H
**Impact**: L
**Severity**: MED
**Status**: ACCEPTED (with documentation)
**Mitigation strategy**: Document the non-reproducibility gap explicitly in `docs/build-guide.md` and in ADR-002. Mitigate transitively via strong signing and a per-release manifest of installed package versions (`apt list --installed`) captured from inside the Cubic chroot. Revisit only if audience grows materially or if a recipient's policy demands reproducible builds — migration path would be `live-build` or `mkosi` replacing Cubic.
**Owner**: Joseph
**Trigger / review date**: Revisit if audience expands beyond fleet + family, or on any third-party reproducibility complaint.

---

### R-04: No field-update mechanism — deployed USBs go stale
**Category**: Operational / Distribution
**Description**: Once a recipient flashes a USB, there is no supported path to pull fresh `docs/`, `scripts/`, runbooks, or updated model weights without reflashing the entire image (~55 GB). Stale docs on a rescue USB are worse than none — they can point at decommissioned hosts, wrong IPs, or removed tools.
**Likelihood**: H
**Impact**: L
**Severity**: MED (downgraded from HIGH 2026-05-23 per ADR-005 reframe)
**Status**: OPEN (mitigation reframed)
**Mitigation strategy**: `update-payload.sh` was **superseded** (Gitea #5). The supported field-update model per ADR-005 is `git pull` on the persistence overlay + `kintsugi-models pull` for weights — no full reflash. `kintsugi-models` CLI shipped (#15) and `docs/update-strategy.md` documents the flow (#18). Residual risk is purely user-education; a boot-visible `PAYLOAD-VERSION` / last-updated marker remains a nice-to-have.
**Owner**: Joseph
**Trigger / review date**: Review when the first recipient USB is in the field > 90 days.

---

### R-05: Imaging scripts don't exist — distribution is manual
**Category**: Operational / Distribution
**Description**: `scripts/` and `manifest/` directories are empty. Producing a distributable copy today means a hand-run Ventoy build per USB — slow, error-prone, and divergent across copies. Without a scripted pipeline, every shipped drive is a snowflake that cannot be audited against a published checksum.
**Likelihood**: H
**Impact**: M
**Severity**: HIGH
**Status**: **RETIRED 2026-05-23** — all scripts exist under `scripts/` and were exercised end-to-end (Gitea #2/#3/#4/#6/#29 closed; commit `b3031e5`). Retained for audit trail.
**Mitigation strategy (delivered)**: `scripts/prep-master.sh` (zero free space, flush caches, sanitize persistence), `scripts/create-image.sh` (dd | zstd | sha256sum), `scripts/flash-image.sh` (target-device safety prompts), `scripts/verify-image.sh` (post-flash check), `scripts/publish-release.sh` (NFS target). LAM milestone cleared.
**Owner**: Joseph
**Trigger / review date**: LAM gate.

---

### R-06: Accidental secrets in squashfs or exFAT data partition
**Category**: Security
**Description**: The security architecture requires secrets (API keys, SSH private keys) to live only in the ext4 persistence overlay. A mistake during master-USB prep — forgetting to remove `~/.ssh/` from the chroot, leaving `ai-keys.env` in `/data/`, caching a token in a shell history file that gets squashfs-baked — would publish those secrets to every recipient. exFAT has no UNIX permissions and is cross-platform-readable; squashfs is world-readable by design.
**Likelihood**: M
**Impact**: H
**Severity**: HIGH
**Status**: MITIGATING
**Mitigation strategy**: `scripts/prep-master.sh` must run a sanitize pass that greps persistence and exFAT for known-sensitive patterns (`BEGIN OPENSSH PRIVATE KEY`, `sk-ant-`, `sk-`, `ghp_`, `AKIA`, `gitea_token`, hostnames in `10.0.0.*`) and aborts on any hit. Enforce in CI once CI exists. Reinforced by CLAUDE.md repo-hygiene rules and `.gitignore`. Document the sanitize checklist in `docs/build-guide.md`. Post-flash, require the recipient to populate `~/.config/ai-keys.env` themselves.
**Owner**: Joseph
**Trigger / review date**: Every master-USB prep run; any commit touching `scripts/prep-master.sh`.

---

### R-07: API keys or secrets committed to the public Gitea repo
**Category**: Security
**Description**: The repo is public. A single `git add .` that sweeps up a dotfile, a `.env`, or a fleet inventory snapshot with embedded credentials would leak those secrets publicly and irrevocably (git history is forever barring destructive force-push + rewrite + mirror purge).
**Likelihood**: L
**Impact**: H
**Severity**: CRITICAL (but well-mitigated)
**Status**: MITIGATING
**Mitigation strategy**: Multi-layer: (1) `.gitignore` already excludes `*.env`, `*.img`, `*.img.zst`, key patterns; (2) CLAUDE.md §"Public Repo Security" is the explicit team directive; (3) Conventional-commits discipline + no AI attribution encourages human review of every commit; (4) Add pre-commit hook using `gitleaks` or `detect-secrets` as a Phase-2 improvement; (5) On any leak: rotate immediately, force-push rewrite, notify Gitea admin to purge caches, treat all leaked credentials as compromised.
**Owner**: Joseph
**Trigger / review date**: Review quarterly; re-evaluate immediately on any accidental commit of sensitive file patterns.

---

### R-08: Flash failure on recipient hardware due to USB variance
**Category**: Technical / Distribution
**Description**: Recipient USB sticks vary in controller quality, write endurance, and reported block sizes. A `dd`-style flash may fail mid-write, produce corrupted geometry on quirky controllers, or succeed on write but fail to boot due to Ventoy's specific partition-table expectations.
**Likelihood**: M
**Impact**: M
**Severity**: MED
**Status**: OPEN
**Mitigation strategy**: Recommend specific known-good USB 3.x models in `docs/flash-image.md` (e.g., SanDisk Extreme, Samsung BAR Plus; 64 GB minimum). Post-flash `docs/flash-image.md` mandates a checksum verification of the flashed device (`sha256sum /dev/sdX` with size cap) and a boot smoke test before declaring success. Accept that some cheap USBs will fail; document the failure modes and the remediation (try a different stick).
**Owner**: Joseph
**Trigger / review date**: Review after first 3 recipient flashings in the field.

---

### R-09: Model staleness (reframed per ADR-005)
**Category**: Technical / UX
**Description**: Models evolve quickly. Users could end up running stale weights indefinitely. **Per ADR-005 (user-driven model loading), this is no longer a maintainer-distribution problem** — no weights are bundled. It becomes a user-education + toolkit-UX problem: users need to know they can and should refresh, and the tooling must make it trivial.
**Likelihood**: M
**Impact**: L
**Severity**: LOW
**Status**: ACCEPTED (for maintainer) / documented-for-user
**Mitigation strategy**: `kintsugi-models` CLI `list` command surfaces installed model versions. `manifest/models-recommended.yaml` is versioned in git — `git pull` + `kintsugi-models pull --all` is a one-command refresh. `docs/update-strategy.md` (iteration-1 deliverable) documents the refresh flow. No fixed cadence obligation on the maintainer beyond updating `models-recommended.yaml` when meaningfully better open-weight models appear.
**Owner**: Joseph (manifest updates); users own their own model refresh decisions.
**Trigger / review date**: Review `models-recommended.yaml` quarterly; update only when a clearly-better slug exists.

---

### R-10: Bundled `claude` CLI auth flow changes
**Category**: Technical / Distribution
**Description**: The `claude` CLI and Codex CLI are vendor-controlled binaries whose auth flows, binary format, and model-endpoint contracts can change unilaterally with upstream releases. A breaking change stranding recipients with an older CLI version is plausible.
**Likelihood**: M
**Impact**: M
**Severity**: MED
**Status**: MONITORING
**Mitigation strategy**: Keep the `claude` / Codex binaries on the exFAT partition so `scripts/update-payload.sh` can replace them in-field. Document "if `claude login` fails, update the payload" as a recipient troubleshooting step. Consider removing proprietary CLIs from the shipped image entirely (see R-01) — ship a post-flash installer instead, which sidesteps both licensing and stale-binary concerns. The `llama.cpp` offline path is a resilient fallback that works even if every cloud CLI is broken.
**Owner**: Joseph
**Trigger / review date**: On any Anthropic/OpenAI CLI major-version bump.

---

### R-11: Non-technical recipient struggles with flashing tool (Etcher / Rufus / `dd`)
**Category**: Documentation / UX
**Description**: CLAUDE.md explicitly scopes "non-technical recipient (e.g., a family member)" as a persona. Tools like Etcher are friendly; `dd` is unforgiving — a wrong target device overwrites the recipient's primary disk. Confusing instructions produce either frustrated non-completion or catastrophic data loss.
**Likelihood**: M
**Impact**: M
**Severity**: MED
**Status**: OPEN
**Mitigation strategy**: `docs/flash-image.md` (pending) must be recipient-first per CLAUDE.md directive, with Etcher (cross-platform, GUI, verify-on-write) as the primary recommended path. Include screenshots; include an explicit "DO NOT select your laptop's internal disk" warning with example output of `lsblk` / Disk Utility showing how to tell them apart. Provide `dd` / `rufus` as alternates for technical recipients. End with a mandatory post-flash verification (boot the USB and confirm Ventoy menu appears).
**Owner**: Joseph
**Trigger / review date**: Before first non-technical recipient handoff.

---

### R-12: Boot failure on a non-fleet host (compatibility unknown beyond 4 reference machines)
**Category**: Technical
**Description**: The drive is verified on 4 hosts (`ref-host-1`, `ref-host-2`, `ref-host-3`, `ref-host-4`). Recipients' machines span a wider universe — older UEFI firmwares, Secure Boot + MOK enrollment quirks, vendor-specific boot-menu idiosyncrasies, 32-bit EFI on certain Atom/Surface devices, and ARM laptops that cannot boot an x86_64 image at all.
**Likelihood**: M
**Impact**: M
**Severity**: MED
**Status**: OPEN
**Mitigation strategy**: Document in `README.md` the known-tested hardware matrix and explicit non-goals (ARM, 32-bit EFI, legacy BIOS-only on GPT). Publish a troubleshooting section covering MOK enrollment, Secure Boot toggle, and vendor boot-menu keys. Solicit boot reports from early recipients into a `docs/compatibility.md` living document. QEMU UEFI smoke test in CI (Phase-2) catches regressions but not vendor-firmware quirks.
**Owner**: Joseph
**Trigger / review date**: Review after first 5 field reports.

---

### R-13: Persistence overlay corruption on unclean shutdown
**Category**: Technical
**Description**: The `ubuntu-ml-persist.dat` overlay is ext4 with journaling. An unclean shutdown (pulling the USB, power loss) mid-write can still cause partial data loss or, worst case, overlay unmountability on next boot, stranding the user's saved keys and shell state.
**Likelihood**: L
**Impact**: L
**Severity**: LOW
**Status**: ACCEPTED
**Mitigation strategy**: ext4 journaling mitigates structural corruption in the common case. Document "always shut down cleanly before removing the USB" in the quickstart. Provide an `fsck.ext4` recovery procedure in `docs/n5pro-recovery-sop.md` or a sibling runbook. Accept that an overlay is recoverable or rebuildable; secrets should be reconstructable (rotate the API key; re-copy the SSH keypair) rather than treated as irreplaceable.
**Owner**: Joseph
**Trigger / review date**: Only on actual field report.

---

### R-14: Repo doc drift — sysops-era content confuses new readers
**Category**: Documentation
**Description**: CLAUDE.md notes `docs/build-guide.md` and other migrated files still carry sysops-era voice, references, and assumptions. A public reader — especially a potential contributor — encountering internal-only references (internal hostnames, private runbook links, team conventions) forms an inaccurate mental model and either abandons the project or files noise issues.
**Likelihood**: M
**Impact**: L
**Severity**: MED
**Status**: MITIGATING
**Mitigation strategy**: Track per-doc migration status in a checklist (Gitea issues or a `docs/MIGRATION.md`). Prioritize `README.md`, `docs/flash-image.md`, and `docs/build-guide.md` first — these are the recipient-facing surfaces. Keep the `docs/n5pro-recovery-sop.md` style (host-specific runbook) but scrub internal-only IP/hostname references. A lightweight "migration pass" review is a prerequisite for LAM gate.
**Owner**: Joseph
**Trigger / review date**: LAM gate; continuous.

---

### R-15: AI-generated runbooks ship inaccurate guidance; recipient acts on bad advice
**Category**: Documentation / Security
**Description**: This repo's docs, and the runbooks/recovery-packs shipped on the USB, may be drafted or revised with AI assistance. Inaccurate, confidently-wrong guidance in a rescue context can escalate a recoverable failure into data loss — e.g., a wrong `dd if=...` direction, a wrong partition target, a destructive `wipefs` recommendation applied to the wrong device.
**Likelihood**: M
**Impact**: H
**Severity**: HIGH
**Status**: OPEN
**Mitigation strategy**: Apply CLAUDE.md "Verification always" directive: every runbook must end with a verification step that catches wrong-device errors before they are destructive (e.g., confirm `lsblk` output matches expectation; dry-run `--dry-run` or `testdisk`-style read-first before write). For any command that writes to `/dev/sdX`, the runbook must require the operator to re-state the target device before proceeding. Human-reviewed sign-off on every runbook before it ships on the USB — no unreviewed AI drafts in the recovery path. Cross-reference ADR-003 (Runbook Quality Standard) once drafted.
**Owner**: Joseph
**Trigger / review date**: Before any runbook is added to a shipped release; continuous.

---

### R-16: Solo maintainer — bus factor of 1
**Category**: Operational
**Description**: Single maintainer, no co-owner, no documented succession path. If the maintainer becomes unavailable, deployed USBs in the field lose their update source, license questions cannot be resolved, and the repo stalls.
**Likelihood**: L
**Impact**: L
**Severity**: LOW
**Status**: ACCEPTED
**Mitigation strategy**: Accepted for a personal / small-fleet project. Mitigated indirectly by: (1) public Gitea repo so content is visible and forkable under whatever LICENSE is ultimately chosen (R-01); (2) docs are the product — a competent operator can rebuild the USB from `docs/build-guide.md` without the maintainer; (3) bundled artifacts are all independently obtainable upstream. Revisit only if a second maintainer is recruited or if fleet/family reliance on the USB grows meaningfully.
**Owner**: Joseph
**Trigger / review date**: Annual review, or on material audience growth.

---

## Review Cadence

- **Weekly** during Elaboration and Construction — re-score top-5 risks; update status.
- **At each gate** (LOM, LAM, IOC, PR) — full register walk; retire or escalate.
- **On any field incident** — reopen relevant risks, add new ones, capture lessons in the gate retro.

## Traceability

- **CLAUDE.md §Public Repo Security** → R-06, R-07
- **CLAUDE.md §Distribution Workflow** → R-04, R-05, R-08, R-11
- **docs/architecture.md §5 Security Architecture** → R-06, R-07, R-13
- **.aiwg/intake/project-intake.md §Known Issues** → R-01, R-02, R-03, R-04, R-05, R-14
- **.aiwg/intake/solution-profile.md Improvement Roadmap** → R-01, R-02, R-05
- **.aiwg/intake/option-matrix.md Step 4 decisions** → R-01, R-02, R-04

Pending ADRs referenced: ADR-001 (License Choice), ADR-002 (Verification / Signing Strategy), ADR-003 (Runbook Quality Standard).

---

## Risks Added 2026-04-20 per ADR-005

### R-17: User pulls malicious or compromised model slug
**Category**: Security / Supply-chain (user-side)
**Description**: With user-driven model loading (ADR-005), users can `kintsugi-models pull` arbitrary slugs from the Ollama registry or HuggingFace. A malicious slug (typosquat, compromised upload, backdoored fine-tune) could ship weights designed to generate subtly wrong recovery guidance or exfiltrate data if wired into an agent loop. The maintainer's signature covers `models-recommended.yaml` but NOT the weights themselves.
**Likelihood**: L–M (Ollama and HuggingFace moderate their registries, but typosquats do occur)
**Impact**: H (bad advice in a rescue context can cause data loss)
**Severity**: HIGH
**Status**: MITIGATING (updated 2026-05-23 — trust-model doc #24 + `kintsugi-models verify` / `--only-recommended` #15 shipped; residual is inherent Ollama/HF registry risk)
**Mitigation strategy**: (1) `kintsugi-models pull` prints the source URL and, where available, the source-advertised digest before download; requires `--yes` for non-recommended slugs. (2) `kintsugi-models verify <slug>` re-checks sha256 against the manifest entry. (3) Document the trust boundary explicitly in `docs/toolkit-guide.md` — maintainer vouches for `models-recommended.yaml` entries only; anything else is user-owned. (4) Mitigate further via an `--only-recommended` lockdown flag for non-technical recipients.
**Owner**: Joseph (tooling design) + user (runtime judgment)
**Trigger / review date**: Revisit if a malicious slug incident is reported in the Ollama/HF ecosystems.

---

### R-18: User fills persistence overlay with runaway model pulls
**Category**: Operational / UX
**Description**: Users can unintentionally fill the persistence overlay by pulling many or very large models, causing USB writes to fail and potentially corrupting the overlay on unclean shutdown.
**Likelihood**: M
**Impact**: M
**Severity**: MED
**Status**: OPEN (mitigated by CLI UX)
**Mitigation strategy**: `kintsugi-models pull` soft-warns when persistence is >80% full; hard-refuses when >95%. `kintsugi-models list --sizes` shows per-model footprint. `kintsugi-models remove <slug> --delete-weights` frees space. Document persistence-overlay sizing in `docs/toolkit-guide.md` and in `manifest/models-recommended.yaml` header (each recommended slug lists its footprint).
**Owner**: Joseph (CLI implementation) + user (usage judgment)
**Trigger / review date**: Revisit if persistence-corruption incidents are reported.

---

## Risks Added 2026-04-20 per ADR-006

### R-19: VS Code telemetry enabled by default
**Category**: Privacy / UX
**Description**: VS Code ships with Microsoft telemetry enabled. Recipients of a wizard-built USB get telemetry on by default unless the wizard / first-boot-setup disables it. This conflicts with the project's privacy posture (no-network-telemetry, no-user-tracking) and with the "rescue USB" trust model (rescue scenarios may surface sensitive filesystem contents to a cloud telemetry service).
**Likelihood**: H (default-on behavior)
**Impact**: M (moderate privacy concern; no direct data-loss risk)
**Severity**: MED (downgraded 2026-05-23 — wizard reliably disables)
**Status**: MONITORING (effectively resolved 2026-05-23 — `build-custom-iso.sh` writes `telemetry.telemetryLevel: "off"` as skel default; `usb-test-harness.sh` asserts it; watch only for upstream VS Code default changes)
**Mitigation strategy**: (1) Wizard prompts at IDE setup step with a clearly-worded recommendation to disable telemetry. (2) `first-boot-setup.sh` writes `telemetry.telemetryLevel: "off"` to `/etc/skel/.config/Code/User/settings.json` as the default. (3) `docs/toolkit-guide.md` documents the opt-in pattern for users who want telemetry enabled.
**Owner**: Joseph
**Trigger / review date**: Revisit if VS Code changes telemetry defaults or if a privacy-sensitive recipient reports unwanted data emission.

---

### R-20: Copilot extension preinstalled but inert without GitHub sign-in + subscription
**Category**: UX
**Description**: ADR-006 §D3 preinstalls the GitHub Copilot extension in the base ISO. Activation requires a paid Copilot subscription and GitHub sign-in. Recipients without either get a confusing UX — the extension is present but nothing works — and may not understand the gating.
**Likelihood**: M (depends on recipient distribution; could be H for non-dev users)
**Impact**: L (confusion, not failure; no functional rescue-tool impact)
**Severity**: MED
**Status**: MITIGATING (doc-level mitigation planned)
**Mitigation strategy**: (1) Wizard prompts with a clear explanation at IDE setup step. (2) `docs/flash-image.md` has a "Post-flash activation steps" section explaining the Copilot sign-in flow + the "it costs money" message. (3) First-boot banner in VS Code points users at activation docs if Copilot is detected as installed but unauthenticated. (4) Recipients who don't want Copilot can remove the extension with one `code --uninstall-extension github.copilot` command; wizard offers the opt-out at build time.
**Owner**: Joseph
**Trigger / review date**: Revisit after first non-maintainer recipient feedback on Copilot UX.

---

### R-21: Agentic framework install failures during build
**Category**: Operational / UX
**Description**: The new `kintsugi-frameworks` CLI runs install recipes for third-party CLIs (Aider via pipx, Claude Code via curl-bash, Codex via npm, etc.). Any of these installers can fail — broken mirrors, upstream install-script changes, pipx/npm version drift, network flake. Failures mid-build corrupt the build state or leave a partially-populated master USB.
**Likelihood**: M
**Impact**: M
**Severity**: MED
**Status**: MITIGATING (updated 2026-05-23 — `kintsugi-frameworks` CLI shipped #27 with per-framework transactional installs; resumable wizard profile #26)
**Mitigation strategy**: `kintsugi-frameworks install` is transactional per-framework (succeed fully, or report failure and leave no partial install). Failure exits non-zero with the upstream stderr for diagnosis. Wizard `--resumable` profile tracks which frameworks succeeded; rerun skips completed ones. Recommend recipes exercise `--dry-run` mode where the upstream installer supports it.
**Owner**: Joseph
**Trigger / review date**: Revisit after first iteration-1 end-to-end wizard run; framework upstream changes quickly.

---

### R-22: Copilot extension version drift
**Category**: Technical
**Description**: The Copilot extension preinstalled at ISO build time ages against the upstream marketplace. Recipients booting the USB 6–12 months later get a stale extension. VS Code usually auto-updates extensions on startup if the user is signed into the marketplace and online — but offline recipients keep the baked-in version.
**Likelihood**: M
**Impact**: L (stale ≠ broken; Copilot usually remains functional)
**Severity**: LOW
**Status**: ACCEPTED
**Mitigation strategy**: Document the auto-update behavior in `docs/toolkit-guide.md`. No wizard-level mitigation required. If significant drift becomes a problem, update recipe fetches the latest marketplace version at build time (default is "latest" already).
**Owner**: Joseph
**Trigger / review date**: Revisit if a breaking Copilot update leaves stale-base-image recipients stranded.
