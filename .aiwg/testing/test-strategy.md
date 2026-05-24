# Test Strategy — Kintsugi USB

**Version**: 1.0
**Date**: 2026-04-20
**Status**: BASELINED (amended 2026-04-20)
**Owner**: Joseph Magly (roctinam)

---

## 0. Amendment Log

### 2026-04-20 Amendment — ADR-005 alignment

This amendment reflects `.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md` (ACCEPTED 2026-04-20) and the porting of three substantial harness scripts from sysops. Substantive changes:

- **Harness elevation** — `scripts/usb-toolkit/usb-test-harness.sh` (527 lines, ported) is now a present-tense first-class automated harness with a native PASS/FAIL/SKIP/WARN taxonomy and JSON result emission. References throughout have been reframed from "future automated" to "automated via the harness". `scripts/benchmark-inference.sh` (450 lines, ported) powers NFR-1.3/1.4 measurement. `scripts/check-drive-health.sh` (518 lines, ported) covers USB-level reliability tests.
- **Dual runtime** — §3.3 now reflects both llama.cpp (:8080) and Ollama (:11434) as runtimes requiring independent health checks.
- **User-driven models** — NFR-1.3 and NFR-1.4 inference-speed tests are conditional on a user having pulled a model and are reported as WARN/SKIP when no model is present. NFR verification table amended accordingly.
- **Model Toolkit Testing** — new §3.6 covers the `kintsugi-models` CLI, manifest schema validation, registry-pull smoke tests, storage-limit enforcement, and user-model shadowing semantics.
- **Build pipeline** — §3.4 no longer references bundled model weights; the base image is OS + tools + llama.cpp + Ollama + manifest, and the payload tarball may collapse to scripts/docs only.
- **Acceptance gate** — new §6.1 defines the minimal-passing test set using the harness's native taxonomy.
- **CI/CD** — §5 notes that `usb-test-harness.sh` is written and runner-ready today.

---

## 1. Purpose & Scope

### 1.1 Purpose

This document formalizes the test strategy for Kintsugi USB at the Elaboration baseline. It supersedes the informal `docs/test-strategy.md` by integrating it with the formal use-case specification (`use-cases.md`), the NFR register (`nfr-register.md`), and the verification hooks defined in SAD §5.4. The strategy covers both **Tier A** (the runtime artifact: the flashed USB and its boot/persistence/AI behavior) and **Tier B** (the build and distribution pipeline: prep, image, sign, publish, flash, field-update).

The strategy describes how we establish confidence that a released image boots, runs, and survives in the field — on fleet hardware today and on recipient hardware in the near future — without shipping secrets or broken ISOs.

### 1.2 In Scope

- **Tier A — runtime artifact**: boot (UEFI + Legacy BIOS + Secure Boot via MOK), Ventoy menu presentation, persistence overlay survival, rescue tool presence, AI stack (online via `claude`, offline via `llama.cpp`), cross-platform exFAT data-partition access.
- **Tier B — build and distribution pipeline**: `prep-master.sh` secret-scrubbing, `create-image.sh` compression and signing, `update-payload.sh` idempotent field updates, recipient flash verification.
- Physical-hardware acceptance on the four fleet hosts (`ref-host-1`, `ref-host-2`, `ref-host-3`, `ref-host-4`).
- Secret-leak and signature-verification audits on every release candidate.

### 1.3 Out of Scope for v1.0

- Load or stress testing beyond single-operator use (no multi-user concurrency; single-operator appliance).
- Fuzz testing of bundled third-party binaries (we trust upstream signatures; our surface is scripts).
- Multi-architecture support (x86_64 only; ARM64 deferred).
- Bit-for-bit reproducible-build verification (builder is live-build per ADR-007; reproducibility flags out of scope for v1.0 — R-03).
- Formal mutation testing or coverage gates (no CI yet; see §5).
- Quality evaluation of LLM outputs (model correctness is not a gate — see R-15 in §10).

---

## 2. Test Levels

### 2.1 Unit (Scripts)

Unit testing applies to Bash scripts as they are authored. Several substantial scripts already exist (ported from sysops): `scripts/usb-toolkit/usb-test-harness.sh` (527 lines), `scripts/benchmark-inference.sh` (450 lines), `scripts/check-drive-health.sh` (518 lines), plus `start-ai.sh`, `build-custom-iso.sh`, and `first-boot-setup.sh`. Pipeline scripts (`prep-master.sh`, `create-image.sh`, `kintsugi-models`) are iteration-1 deliverables.

- **Static analysis**: `shellcheck` on every script under `scripts/` as a pre-merge gate.
- **`bats` unit tests** for pure-logic helpers:
  - `prep-master.sh` secret-pattern matcher — given a fixture tree with seeded tokens (`sk-…`, `ANTHROPIC_…`, private-key blocks), assert the matcher finds each and exits non-zero.
  - SHA-256 and `minisign` verification helpers — given a known-good and a tampered `.img.zst`, assert the verifier accepts the first and rejects the second.
  - Manifest union / shadowing logic inside `start-ai.sh` (post ADR-005 refactor) — given fixture `manifest/models-recommended.yaml` + `/data/models/user/models.yaml`, assert the correct merged slug set and that user entries shadow defaults on collision.
  - `kintsugi-models` CLI subcommand helpers — manifest parsing, slug validation, storage-limit thresholds (see §3.6).

### 2.2 Component / Integration

Component tests exercise a single script or subsystem end-to-end with realistic inputs but in a controlled environment (usually a QEMU VM or a scratch directory on the build host).

- **`start-ai.sh`** — mock online/offline state via `/etc/hosts` or `-nic none`; assert correct branching, `llama-server` lifecycle (start, health-check on `GET /v1/models`, clean shutdown on signal).
- **`ventoy.json`** — schema validation against Ventoy's documented schema; assert every menu entry has a `menu_alias` (NFR-5.1) and references an ISO that actually exists in the master tree.
- **Persistence overlay**: install a package (`apt install -y cowsay`), write a marker file, reboot the VM, assert both survive (NFR-3.5).
- **`update-payload.sh`** (when written) — run `--dry-run` then real run, then second real run; assert the third is a no-op (NFR-6.5 idempotency contract from SAD §5.4).

### 2.3 System / End-to-End

- **`scripts/usb-toolkit/usb-test-harness.sh`** — the canonical automated end-to-end harness on a booted USB. Already written (527 lines, ported from sysops); invocable as `usb-test-harness.sh [--full|--quick|--ai-only|--boot-only]`. Collects hardware info (CPU/mem/storage/PCI/USB/DMI/boot-mode/Secure-Boot), executes boot-timing, tool-presence (TC-3), persistence, AI-stack, and drive-health checks, and writes structured results to `/var/log/usb-toolkit/test-YYYYMMDD-HHMMSS/` (`results.json`, `summary.txt`, `full.log`, per-subsystem artifacts). Uses a native **PASS / FAIL / SKIP / WARN** taxonomy that is the basis for the §6.1 acceptance gate.
- **QEMU UEFI boot** via `ovmf` — assert Ventoy menu visible within 30 seconds (SAD §5.4 QEMU smoke contract), selected ISO boots to a shell within 60 seconds (NFR-1.1).
- **QEMU Legacy BIOS boot** via SeaBIOS — same assertions without MOK enrollment.
- **Physical boot** on each fleet host — the authoritative acceptance gate (see §2.4 and `docs/physical-test-guide.md`). The harness runs on the booted USB and its `results.json` is attached to the per-release test report.
- **Full UC walkthroughs** — see §6 for the UC-to-test-case map.
- **Distribution round-trip** — build master → `prep-master.sh` → `create-image.sh` → upload to a staging Gitea release → download to a second machine → `sha256sum -c` + `minisign -V` → flash a fresh stick with Etcher → boot on a fleet host → run `usb-test-harness.sh --full` (NFR-3.4, NFR-4.4, NFR-8.2).

### 2.4 Acceptance

`docs/physical-test-guide.md` is the **canonical pre-release acceptance gate**. A release candidate is not releasable until its per-host checklist passes on at least two fleet hosts (§8). A separate **recipient flash test** — a non-maintainer flashes a published release on a non-fleet machine and follows `docs/flash-image.md` unaided — exercises the documentation's plain-language quality (NFR-5.4) and serves as a release-blocker for any documentation regression reported by the recipient.

### 2.5 Security Testing

Security tests run on every release candidate and on every merge to `main`:

- **Secret-leak audit** — run the authoritative patterns from `scripts/secret-patterns.txt` (per SAD §5.4 `prep-master.sh` contract) against the extracted `squashfs`, the exFAT `/data/` tree, and the public git tree. Any match aborts fail-closed (NFR-4.1, NFR-4.5, NFR-4.7).
- **Signature verification** — produce a tampered `.img.zst` by flipping a byte; assert `minisign -V` rejects it and `sha256sum -c` rejects it. Both rejections must be visible in the recipient-facing output (NFR-4.4, NFR-9.4).
- **Persistence permission audit** — post-boot `stat` check on `~/.config/ai-keys.env` (mode 600), `~/.ssh/` (mode 700), private keys (mode 600). Automated on first boot; failures logged to `/var/log/kintsugi/permissions.log` (NFR-4.2, NFR-4.6).

---

## 3. Test Approach by Component

### 3.1 Boot Layer

- **UEFI**: QEMU with `OVMF_CODE.fd` for automation; at least one fleet host (ref-host-1, ref-host-2) for pre-release acceptance (NFR-7.2).
- **Legacy BIOS**: QEMU with default SeaBIOS; one legacy-configured fleet host for pre-release (NFR-7.3).
- **Secure Boot + MOK**: physical hardware only. QEMU's Secure Boot + MOK enrollment UX is incomplete and cannot substitute for a real firmware flow. Tested on `ref-host-1` and `ref-host-2` (NFR-7.4).

### 3.2 Persistence Overlay

- **Reboot survival**: install `cowsay`, write `~/persist-marker.txt`, reboot, assert both survive (NFR-3.5, TC-6).
- **Unclean shutdown**: QEMU `system_powerdown -f` mid-write; reboot; assert ext4 journal recovers and committed writes are intact (NFR-3.3).
- **Permissions**: automated `stat` check after first source of `~/.config/ai-keys.env` (NFR-4.2).

### 3.3 AI Stack

Per ADR-005, the booted USB runs **two** local model runtimes side-by-side. Both are exercised by `scripts/usb-toolkit/usb-test-harness.sh`, and `start-ai.sh` is expected to report status for both.

- **Dual-runtime health check**:
  - **llama.cpp**: harness asserts `GET http://localhost:8080/v1/models` returns 200 when `llama-server` is running. If no model is loaded (user has not yet pulled one), the harness emits `SKIP` with guidance to run `kintsugi-models pull <slug>`.
  - **Ollama**: harness asserts `ollama serve` is active on :11434 and `GET http://localhost:11434/api/tags` returns 200. If no pulled models are listed, the harness emits `WARN` (Ollama is up, but the user has pulled nothing yet) rather than `FAIL`.
- **`start-ai.sh` manifest-driven selection** (post ADR-005 refactor): reads `manifest/models-recommended.yaml` and `/data/models/user/models.yaml`, reports the resolved slug set for both runtimes, and prints a user-facing status matrix (NFR-5.2). Harness asserts presence of each runtime line in stdout.
- **Online/offline branching**: with `-nic none`, assert `start-ai.sh` selects local inference and does not call out; with network up and a stubbed `ANTHROPIC_API_KEY`, assert `claude --version` succeeds.
- **Performance (NFR-1.3, NFR-1.4)** — **conditional test**: `scripts/benchmark-inference.sh` (ported from sysops, 450 lines) captures tokens/second on the reference host (i7-12700H / ref-host-2). Thresholds: Qwen3.5 4B > 15 tok/s; Qwen3.5 9B > 8 tok/s (updated from the stale Phi-4-mini / Qwen2.5-Coder inventory per ADR-005). **Because no model weights are bundled**, these benchmarks can only run **after** the tester has executed `kintsugi-models pull <slug>` (or equivalent). When no model is present, the harness reports `WARN` with message "pull a recommended model first (e.g., `kintsugi-models pull qwen3.5:4b`); inference-speed NFRs cannot be measured without weights." Results, when produced, are captured in the per-release test report; referenced from SAD §5.4.

### 3.4 Build Pipeline

Per ADR-005, the base image is OS + rescue tools + llama.cpp + Ollama + `manifest/models-recommended.yaml` (signed). **No model weights are bundled.** The separate payload tarball (if retained) contains docs and scripts only and may collapse entirely during Iteration 1 once sizes are measured.

- **`prep-master.sh`**: `--dry-run` lists the secrets it would scrub without mutating the master; real run produces `PREP OK <master-id> <timestamp>` on stdout (SAD §5.4 contract). Must tolerate a build-root that already has user-pulled weights under `/payload/models/` (per ADR-005 Implementation Plan item 7).
- **`create-image.sh`**: round-trip via flash → boot; produces `.img.zst`, `.sha256`, `.sig`, and a per-release manifest; failure moves partial artifacts to `work/failed/` (SAD §5.4). Base-image size assertion: significantly smaller than the earlier ~5 GB target (post-weight removal); a hard ceiling will be set in iteration-1 once a real build is measured.
- **`update-payload.sh`**: **deferred** per ADR-005 — field update may now be just `git pull` in `/data/scripts/` + `kintsugi-models pull` for any new recommended slugs. If retained, the idempotency contract still holds: `--dry-run` prints planned deltas; real run applies them; a third run is a no-op (NFR-6.5).

### 3.5 Distribution

- **Recipient verification UX**: walkthrough of the `sha256sum -c` and `minisign -V` commands on Linux (native), macOS (Homebrew `minisign`), and Windows (WSL or published `minisign.exe`). Commands must match those printed in `docs/flash-image.md` exactly (NFR-9.4).
- **Flash-tool compatibility matrix**: Etcher (all three OSes), `dd` (Linux/macOS), Rufus in DD-image mode (Windows). Each exercised at least once against the published image per release (NFR-8.2).
- **USB-level reliability** — `scripts/check-drive-health.sh` (ported from sysops, 518 lines) is run against the recipient's flashed USB as part of the physical-test harness: SMART attribute snapshot (if exposed), partition-table sanity, filesystem error scan on exFAT `/data/` and the persistence ext4 overlay, and bad-block sampling. Emits PASS/WARN/FAIL per subcheck; feeds into §6 acceptance.

### 3.6 Model Toolkit Testing

Introduced by ADR-005. The `scripts/usb-toolkit/kintsugi-models` CLI and the manifest schema are new test surfaces for v1.0.

- **CLI integration tests** (`bats` under `tests/integration/kintsugi-models/`): cover happy-path and error-path for each subcommand.
  - `list` — lists entries from `manifest/models-recommended.yaml`; with a user manifest present, asserts user entries shadow defaults on slug collision.
  - `add <slug>` — appends to user manifest; rejects duplicates; rejects malformed slugs.
  - `pull <slug>` — happy path against a mocked Ollama/HF endpoint; error path on 404; error path on interrupted transfer (resume or clean-abort).
  - `remove <slug>` — removes from user manifest; `--purge` deletes weights; refuses to remove a slug still in use by a running runtime.
  - `verify` — sha256 + license check across configured slugs; reports any entry missing a `sha256` when `source != ollama` as `WARN`.
- **Manifest schema validation**: YAML-schema check (e.g., `yq` + a JSON-schema validator or a dedicated `bats` test) on `manifest/models-recommended.yaml` and on any user manifest the CLI writes. Required fields: `schema_version`, `recommended[*].slug`, `recommended[*].runtime`, `recommended[*].source`. Conditional requirement: `sha256` when `source` is `huggingface` or `url`.
- **Ollama registry pull smoke test** — **gated (requires network)**: pulls a small tested slug (e.g., `qwen3.5:4b`) via `kintsugi-models pull`; asserts the blob appears under `/data/ollama/` and `ollama list` shows it. Skipped with `SKIP` when `registry.ollama.ai` is unreachable.
- **HuggingFace pull smoke test** — **gated (requires network)**: pulls a small GGUF via the `huggingface` source path; asserts the file lands under the configured target dir and its sha256 matches the manifest. Skipped with `SKIP` when `huggingface.co` is unreachable.
- **Storage-limit enforcement**: with a test-root sized to known capacity, assert `kintsugi-models pull` emits `WARN` at ≥80% full and hard-refuses with `FAIL` at ≥95% full (mitigates R-18).
- **User-model shadowing (manifest union logic)**: fixture with a default entry for slug `X` and a user entry for slug `X`; assert `list` shows a single merged entry and `start-ai.sh` resolves to the user copy. Collision on `runtime`/`source` mismatch is reported as a `WARN` (not a failure) with a clear operator message.

These tests are included in the pre-merge `bats` gate (§8) once `tests/integration/kintsugi-models/` lands.

---

## 4. Test Environments

| Environment | Purpose | CI-eligible |
|-------------|---------|-------------|
| QEMU UEFI (OVMF) | Automated boot smoke tests, AI-stack branching, persistence reboot | Yes |
| QEMU Legacy BIOS (SeaBIOS) | Boot smoke test on legacy firmware | Yes |
| Physical fleet hosts (`ref-host-1`, `ref-host-2`, `ref-host-3`, `ref-host-4`) | Pre-release acceptance; Secure Boot + MOK; performance benchmarks | No (physical) |
| Recipient hardware (non-fleet) | Post-release real-world validation; compatibility feedback via `docs/compatibility.md` and `SECURITY.md` | No |

---

## 5. CI/CD Integration

**Current state**: no CI exists for this repo. Note that `scripts/usb-toolkit/usb-test-harness.sh` is **already written and runner-ready today** — as soon as a Gitea Actions runner with QEMU + OVMF is available, the harness can be invoked against a booted image with no additional authoring. `scripts/benchmark-inference.sh` and `scripts/check-drive-health.sh` are likewise present and invocable.

**Target state for v1.0**: a minimal Gitea Actions workflow triggered on push to `main` and on release tag, executing:

- `shellcheck` across `scripts/` (fail on any warning).
- `bats` unit tests under `tests/unit/` and integration tests under `tests/integration/kintsugi-models/` (§3.6).
- Markdown lint across `docs/` and `.aiwg/` (fail on broken links and malformed front-matter).
- Secret-leak scan (`gitleaks` or equivalent) across the git tree (NFR-4.5).
- Manifest schema validation on `manifest/models-recommended.yaml` (§3.6).
- **Stretch**: a QEMU UEFI smoke test that boots the Ventoy menu, grep-asserts a known `menu_alias` on the serial console within 30 seconds (SAD §5.4 QEMU smoke contract), then invokes `usb-test-harness.sh --quick` inside the guest and uploads `results.json` as a job artifact.

**Out of scope for v1.0**: hardware-in-the-loop CI, mutation testing, coverage gates, performance regression CI. These are tracked for post-v1.0 once the pipeline scripts stabilize.

---

## 6. Use Case Test Coverage

Each use case in `use-cases.md` maps to at least one test type and a test case identifier. Test cases are authored in the file tree under `tests/cases/<id>.md` when they are executed; those not yet executed are documented here.

| UC | Title | Test Type | Test Case ID | Notes |
|----|-------|-----------|--------------|-------|
| UC-001 | Boot for rescue | E2E manual + QEMU smoke | TC-UC001 | `docs/physical-test-guide.md` is the acceptance artifact |
| UC-002 | AI log analysis (online) | Integration | TC-UC002 | Requires real API key in persistence; runs on ref-host-2 |
| UC-003 | AI script generation (offline) | Integration | TC-UC003 | Runs on airgapped QEMU (`-nic none`) |
| UC-004 | Disk imaging | Manual | TC-UC004 | Clonezilla menu boot + checksum recording |
| UC-005 | Fresh OS install | Manual | TC-UC005 | Ubuntu installer menu boot on a scratch disk |
| UC-006 (future) | Distribute to recipient | Manual | TC-UC006 | Non-maintainer flashes a fresh download |
| UC-007 (future) | Field update | Manual | TC-UC007 | Apply payload tarball; verify `usb-help --version` SHA changes |

### 6.1 Acceptance Gate using `usb-test-harness.sh`

The harness emits one of four outcomes per test using its native taxonomy:

- **PASS** — criterion met; counts toward the release.
- **FAIL** — criterion violated; a release-blocker unless explicitly waived with rationale in the per-release test report.
- **SKIP** — test could not run due to a missing precondition (e.g., no boot timestamp, Secure Boot unavailable on host). Informational; does **not** block the release, but every `SKIP` must have a one-line justification in the test report.
- **WARN** — test ran but the result is outside the "ideal" band while still inside the "acceptable" band (e.g., boot between 60s and 90s; Ollama up but no models pulled yet). Informational by default; three or more `WARN` results on a single host triggers a review.

**Minimum passing set (must be PASS for release)**:

| Harness test ID | Subject | NFR/UC |
|-----------------|---------|--------|
| `TC-BOOT-TIME` | Boot to shell ≤ 60s (WARN band 60–90s) | NFR-1.1, UC-001 |
| `TC-3` (tool-presence critical tier) | All filesystem/partition/drive-health/network/boot-repair/shell/runtime critical tools present | UC-001, UC-004, UC-005 |
| `TC-PERSIST-REBOOT` | Persistence cowsay + marker survives reboot | NFR-3.5, TC-6 |
| `TC-PERSIST-PERMS` | `ai-keys.env` mode 600, `~/.ssh/` mode 700 | NFR-4.2, NFR-4.6 |
| `TC-SECRETS-AUDIT` | Zero matches from `secret-patterns.txt` in squashfs + `/data/` | NFR-4.1, NFR-4.5 |
| `TC-SIG-VERIFY` | `minisign -V` accepts clean image, rejects tampered | NFR-4.4 |
| `TC-VENTOY-MENU` | Ventoy menu renders with all configured `menu_alias` entries | NFR-5.1 |
| `TC-START-AI-STATUS` | `start-ai.sh` reports llama.cpp **and** Ollama runtime status lines | NFR-5.2, ADR-005 D2 |
| `TC-DRIVE-HEALTH` | `check-drive-health.sh` PASS on SMART + partition-table + FS-error subchecks (bad-block sample may WARN) | USB reliability |
| `TC-KM-LIST` | `kintsugi-models list` renders merged manifest with no parse errors | ADR-005 D3, D4 |
| `TC-KM-VERIFY` | `kintsugi-models verify` returns 0 (all bundled-slug sha256 + license checks pass) | ADR-005 D4 |

**Informational (PASS/WARN/SKIP acceptable, reported not blocking)**:

- `TC-BENCH-SMALL` — `benchmark-inference.sh` small-model throughput. `SKIP` if no model pulled; `WARN` if < 15 tok/s on reference host; `PASS` otherwise. (NFR-1.3)
- `TC-BENCH-MID` — mid-model throughput. Same disposition. (NFR-1.4)
- `TC-TOOL-HIGH` — high-priority tool tier from §3.6 of the harness (btrfs, nvme, photorec, etc.). Missing high-tier tools emit `WARN`, not `FAIL`.
- `TC-OLLAMA-PULL-SMOKE` / `TC-HF-PULL-SMOKE` — gated on network (see §3.6); `SKIP` when offline.

A release candidate passes the acceptance gate when **every test in the minimum passing set reports PASS on at least two fleet hosts** (one UEFI + Secure Boot, one other), and the test report for the release includes the `results.json` from each host.

---

## 7. NFR Verification Map

The following table maps representative NFRs to their verification method, citing the measurement hook from SAD §5.4 where applicable.

| NFR | Target | Verification Method | SAD §5.4 Hook |
|-----|--------|---------------------|---------------|
| NFR-1.1 (boot < 60s) | Boot to shell on i7-12700H < 60s | Stopwatch during physical-test-guide run; captured in per-release test report | Boot smoke post-flash harness |
| NFR-1.2 (llama-server < 90s) | Ready for first query < 90s | `start-ai.sh` logs readiness timestamp; compared to invocation | Integrated in harness |
| NFR-1.3 (small-model throughput) | > 15 tok/s on i7-12700H (Qwen3.5 4B, Q4_K_M) | `scripts/benchmark-inference.sh` output in test report. **Conditional**: requires user to have run `kintsugi-models pull qwen3.5:4b` first; harness reports `WARN / SKIP` if no model is present. | — |
| NFR-1.4 (mid-model throughput) | > 8 tok/s on i7-12700H (Qwen3.5 9B, Q4_K_M) | `scripts/benchmark-inference.sh` output in test report. **Conditional**: requires user to have pulled the model; harness reports `WARN / SKIP` if absent. | — |
| NFR-2.1 (usage < 95%) | `df` on flashed USB < 95% of 59 GB | Post-flash `df` captured in harness | Boot smoke |
| NFR-3.1 (fleet boots 100%) | All 4 fleet hosts boot | Per-host row in `physical-test-guide.md` | Boot smoke |
| NFR-3.5 (persistence survives reboot) | 100% of committed writes present | TC-6 in harness (`cowsay` + marker file) | Boot smoke |
| NFR-4.1 (no secrets in squashfs) | Zero matches from `secret-patterns.txt` | `prep-master.sh` scan phase | `prep-master.sh` contract |
| NFR-4.2 (ai-keys.env mode 600) | `stat` returns 0600 owner root | First-boot automated `stat` check | Boot smoke |
| NFR-4.4 (signature verifiable) | `minisign -V` succeeds on clean, fails on tampered | Pre-publish automated test | `create-image.sh` contract |
| NFR-5.2 (AI tools discoverable) | `start-ai.sh` prints tool + state matrix | Harness asserts presence of each field in stdout | Boot smoke |
| NFR-6.5 (update idempotent) | Second `update-payload.sh` run is no-op | Harness runs script twice, asserts second diff empty | `update-payload.sh` contract |

---

## 8. Quality Gates

**Pre-merge** (applies to every PR to `main`):

- `shellcheck` passes on all changed scripts.
- `bats` unit tests pass.
- Markdown lint passes on changed docs.
- Secret-leak scan passes on the working tree.

**Pre-release** (applies to every tagged release):

- `docs/physical-test-guide.md` walkthrough passes on at least **two** fleet hosts (one UEFI + Secure Boot, one other).
- Secret-leak audit passes on the built image (extracted `squashfs` + `/data/` tree).
- Signed release verifies end-to-end on a clean Linux machine (`sha256sum -c` + `minisign -V` + Etcher flash + boot).
- Non-maintainer recipient successfully flashes a release candidate following `docs/flash-image.md` unaided (NFR-5.4).

---

## 9. Defect Management

- Issues tracked in Gitea at https://git.integrolabs.net/roctinam/kintsugi-usb/issues.
- Severity labels: `critical`, `high`, `medium`, `low`.
- Phase labels: `phase: imaging`, `phase: distribution`, `phase: payload`.
- No SLA is defined (solo maintainer project). Critical defects found during pre-release gating block the release until resolved or explicitly waived with a documented rationale.
- Tamper reports and suspected secret leaks go through `SECURITY.md`, not the public issue tracker.

---

## 10. Risks to Test Coverage

Cross-referenced with SAD §11 risks.

- **R-08 (flash hardware variance)** — We cannot test every USB make/model on the market. Mitigation: a maintained compatibility table in `docs/flash-image.md` (NFR-8.3) fed by recipient feedback; a caveats list for USBs known to mis-enumerate.
- **R-12 (non-fleet hardware coverage)** — Boot behavior on hardware beyond the four fleet hosts is unknown. Mitigation: `SECURITY.md` and the issue tracker provide incident-reporting channels; `docs/compatibility.md` is a living document.
- **R-15 (AI hallucinated runbooks)** — No automated quality test for LLM outputs is in scope for v1.0. Mitigation: any runbook content committed to the repo is a human-authored artifact; AI-generated text used in rescue sessions is reviewed by the operator before execution (see UC-002 and UC-003 extension flows).
- **ISO non-reproducibility (live-build, ADR-007)** — The custom Ubuntu ISO cannot be byte-identically rebuilt without reproducibility flags. Mitigation: every release's `manifest/<version>.json` records the ISO's SHA-256 and the `build-custom-iso.sh` (live-build recipe) git SHA; we test the produced artifact rather than the build process.

---

## 11. Glossary & References

- **SAD §5.4 Verification Hooks** — `.aiwg/architecture/software-architecture-doc.md`: authoritative pipeline-step success contracts.
- **Physical Test Guide** — `docs/physical-test-guide.md`: per-host acceptance checklist.
- **NFR Register** — `.aiwg/requirements/nfr-register.md`: full NFR catalog with targets and verification methods.
- **Use Cases** — `.aiwg/requirements/use-cases.md`: UC-001..UC-005 formal specifications and UC-006/UC-007 placeholders.
- **Informal test strategy (superseded)** — `docs/test-strategy.md`: original TC-1..TC-12 inventory preserved for historical reference and reused as scaffolding for `tests/cases/`.

---

*End of document.*
