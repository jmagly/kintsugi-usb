# NFR Register — Kintsugi USB

**Project**: Kintsugi USB
**Version**: 1.0
**Date**: 2026-04-20
**Phase**: Elaboration
**Status**: Baselined

---

## Purpose

This register formalizes the non-functional requirements (NFRs) for Kintsugi USB: the qualities, constraints, and thresholds that the distributable rescue boot USB and its supporting build/distribution pipeline must satisfy. It supersedes and extends the informal NFR list in `docs/requirements.md` §2 (NFR-1 through NFR-6), adding coverage for portability, compatibility, observability, and compliance/licensing that the original document did not address.

## Scope

In scope:

- The physical distributable artifact (flashed USB drive) and its boot/runtime behavior
- The build pipeline (master → compressed image → flashed copy) and its tooling
- The field-update path for deployed USBs
- The public repository and its supply-chain posture

Out of scope: enterprise compliance frameworks (no regulatory driver), running-service NFRs (no service), multi-user concurrency (single-operator appliance), and multi-architecture support (x86_64 only for v1.0).

## How to read an NFR

Each NFR carries the following attributes:

- **ID** — Stable identifier in the form `NFR-<category>.<index>`.
- **Requirement** — Short statement of the quality.
- **Target / Acceptance Threshold** — Measurable value or concrete criterion.
- **Measurement / Verification** — How we prove the target is met.
- **Priority** — `CRITICAL`, `HIGH`, `MEDIUM`, or `LOW`.
- **Source** — `docs/requirements.md NFR-X.Y` for migrated items, or `new` for additions introduced in this register.

Priority definitions:

- **CRITICAL** — Release-blocking; failure makes the USB unusable or unsafe to distribute.
- **HIGH** — Strongly expected; failure significantly degrades the primary recovery workflow or trust model.
- **MEDIUM** — Desired quality; a workaround exists if unmet.
- **LOW** — Nice to have; tracked but not blocking.

---

## NFR-1: Performance

| ID | Requirement | Target / Threshold | Measurement / Verification | Priority | Source |
|----|-------------|--------------------|----------------------------|----------|--------|
| NFR-1.1 | Boot from power-on to shell prompt | < 60 seconds on reference hardware (i7-12700H, USB 3.x) | Stopwatch during `physical-test-guide.md` execution; log in test report | HIGH | requirements.md NFR-1.1 |
| NFR-1.2 | `llama-server` ready for first inference query | < 90 seconds from `start-ai.sh` invocation | `start-ai.sh` logs readiness timestamp; compared to invocation time | HIGH | requirements.md NFR-1.2 |
| NFR-1.3 | Phi-4-mini inference throughput | > 15 tokens/second on i7-12700H | `llama-cli` benchmark output captured in test report | MEDIUM | requirements.md NFR-1.3 |
| NFR-1.4 | Qwen2.5-Coder 7B inference throughput | > 8 tokens/second on i7-12700H | `llama-cli` benchmark output captured in test report | MEDIUM | requirements.md NFR-1.4 |
| NFR-1.5 | End-user flash time (write distributable image to a 64 GB USB 3.x) | < 25 minutes on a typical laptop with USB 3.0 host and Class-10-equivalent target | Documented benchmark on reference host in `docs/flash-image.md`; recipients can compare | MEDIUM | new |
| NFR-1.6 | Published distributable image download size | <= 30 GB compressed (`.img.zst`) | `stat` on published release; tracked in release notes | HIGH | new |

## NFR-2: Storage

| ID | Requirement | Target / Threshold | Measurement / Verification | Priority | Source |
|----|-------------|--------------------|----------------------------|----------|--------|
| NFR-2.1 | Total USB utilization on a 64 GB drive | < 95% of 59 GB usable | `df` on flashed USB after first boot | HIGH | requirements.md NFR-2.1 |
| NFR-2.2 | Persistence overlay size | >= 10 GB | Inspect `persistence/ubuntu-ml-persist.dat` size | HIGH | requirements.md NFR-2.2 |
| NFR-2.3 | Free-space buffer on VENTOY partition after imaging | >= 2 GB | `df` on VENTOY partition after flash | MEDIUM | requirements.md NFR-2.3 |

## NFR-3: Reliability

| ID | Requirement | Target / Threshold | Measurement / Verification | Priority | Source |
|----|-------------|--------------------|----------------------------|----------|--------|
| NFR-3.1 | USB boots successfully on every fleet x86_64 host | 100% on `ref-host-1`, `ref-host-2`, `ref-host-3`, `ref-host-4` | Physical boot test recorded per host in test report | CRITICAL | requirements.md NFR-3.1 |
| NFR-3.2 | Flash-wear mitigation for persistence | ext4 with `noatime`, `commit=60`, minimal journaling | Mount-option inspection documented in build guide; verified on first boot | MEDIUM | requirements.md NFR-3.2 |
| NFR-3.3 | Persistence data survives unclean shutdown | ext4 journal recovery brings overlay to a consistent state with no data loss of committed writes | Power-pull test during physical-test-guide; `dmesg` post-recovery review | HIGH | requirements.md NFR-3.3 |
| NFR-3.4 | End-user flash success rate | >= 95% of documented-tool flashes (Etcher, `dd`, Rufus) succeed first time on documented target USB models | Self-reported recipient test results; released image is re-flashed >= 3 times successfully before publication | HIGH | new |
| NFR-3.5 | Persistence contents survive clean shutdown + reboot | 100% of writes (configs, installed packages, shell history, API keys) present after a normal `systemctl poweroff` + reboot cycle | Persistence reboot test (TC-6) recorded in test report | CRITICAL | new |

## NFR-4: Security

| ID | Requirement | Target / Threshold | Measurement / Verification | Priority | Source |
|----|-------------|--------------------|----------------------------|----------|--------|
| NFR-4.1 | No API keys or other secrets present in the shipped squashfs ISO | Zero credentials in the base image | Pre-publish scan: `grep` for known key prefixes (`sk-`, `ANTHROPIC_`) across extracted squashfs + manifest file-listing review | CRITICAL | requirements.md NFR-4.1 |
| NFR-4.2 | API key files in persistence carry least-privilege UNIX permissions | Mode `600`, owner `root` | `stat` check on `~/.config/ai-keys.env` during post-boot smoke test | HIGH | requirements.md NFR-4.2 |
| NFR-4.3 | Persistence encryption (optional LUKS) | Documented procedure exists; not required for v1.0 | Presence of the procedure in `docs/` (stretch goal — see "Out of scope for v1.0") | LOW | requirements.md NFR-4.3 |
| NFR-4.4 | Supply-chain integrity: published image is verifiable | Every Gitea release carries a `SHA-256SUMS` file covering the compressed image and every bundled third-party artifact manifest entry | `sha256sum -c` on recipient side; release workflow fails if checksum file missing | CRITICAL | new |
| NFR-4.5 | No secrets, tokens, SSH private keys, or `.env` files in the public repository | Zero secrets; enforced by `.gitignore` and pre-publish scan | `gitleaks`/manual `grep` scan on `main` before each tagged release | CRITICAL | new |
| NFR-4.6 | Persistence overlay UNIX permissions protect user-scoped secrets | Secret directories (`~/.config`, `~/.ssh`) are mode `700`; private keys are mode `600` | `stat`-based smoke test run automatically on first boot; failures logged | HIGH | new |
| NFR-4.7 | No secrets on the exFAT data partition | Zero secret material under `/data/` (cross-platform partition has no UNIX permissions) | Pre-publish scan of the master `/data/` tree; documented as a hard rule in build guide | CRITICAL | new |

## NFR-5: Usability

| ID | Requirement | Target / Threshold | Measurement / Verification | Priority | Source |
|----|-------------|--------------------|----------------------------|----------|--------|
| NFR-5.1 | Ventoy boot menu labels are descriptive | Every ISO entry has a human-readable alias (no raw filenames) | Visual inspection of Ventoy menu during physical test | MEDIUM | requirements.md NFR-5.1 |
| NFR-5.2 | AI tools are discoverable at runtime | `start-ai.sh` prints available tools, online/offline state, and next-step commands | First-boot test captures stdout of `start-ai.sh` for review | HIGH | requirements.md NFR-5.2 |
| NFR-5.3 | Help command exists for rescue workflows | `usb-help` alias lists common rescue procedures with one-line descriptions | Smoke test invokes `usb-help` and checks output length and exit code | MEDIUM | requirements.md NFR-5.3 |
| NFR-5.4 | Flash documentation readable by a non-technical recipient | `docs/flash-image.md` passes a plain-language review: no unexplained acronyms on first use, numbered steps, screenshot or ASCII diagram of the expected tool UI, verification step at the end | Peer-review checklist by a non-maintainer reader before publication | HIGH | new |
| NFR-5.5 | Host-specific recovery runbooks are discoverable after boot | `/data/recovery/` contains per-host Markdown runbooks; `usb-help` references them by hostname | Smoke test: `ls /data/recovery/` and verify one entry per fleet host | MEDIUM | new |

## NFR-6: Maintainability

| ID | Requirement | Target / Threshold | Measurement / Verification | Priority | Source |
|----|-------------|--------------------|----------------------------|----------|--------|
| NFR-6.1 | Adding a new ISO is a file-copy operation | Drop ISO into `/ISO/` subdirectory; entry appears in Ventoy menu without any other change | Manual test during build | MEDIUM | requirements.md NFR-6.1 |
| NFR-6.2 | Updating a model is a file-swap operation | Replace `.gguf` in `/models/`; `start-ai.sh` picks up the new file on next boot | Manual test | MEDIUM | requirements.md NFR-6.2 |
| NFR-6.3 | Updating an AI tool is a binary-swap operation | Replace binary under `/tools/bin/`; no rebuild of the custom ISO required | Manual test | MEDIUM | requirements.md NFR-6.3 |
| NFR-6.4 | Rebuilding the custom Ubuntu ISO is documented | `docs/build-guide.md` contains a complete live-build walkthrough sufficient for the maintainer to rebuild from a fresh Ubuntu 24.04 host | Dry-run walkthrough against a clean VM before each major release | HIGH | requirements.md NFR-6.4 |
| NFR-6.5 | Field-update path for deployed USBs | `scripts/update-payload.sh` refreshes `/data/`, `/tools/bin/`, `/models/`, and `docs/` on a flashed USB without reflashing; idempotent and safe against a mounted live session | Update-then-diff test: run the script twice and assert the second run is a no-op; run after a simulated payload drift and assert convergence | HIGH | new |
| NFR-6.6 | Repo docs vs deployed-USB drift is measurable | Every distributable image embeds a snapshot of `docs/` and `scripts/` keyed by a git SHA; `usb-help --version` reports the SHA | Smoke test invokes `usb-help --version` and verifies SHA is present and matches release manifest | MEDIUM | new |

## NFR-7: Portability

| ID | Requirement | Target / Threshold | Measurement / Verification | Priority | Source |
|----|-------------|--------------------|----------------------------|----------|--------|
| NFR-7.1 | Data partition is readable on Windows, macOS, and Linux | exFAT filesystem; no file exceeds 4 GB individually unless the model file itself (exFAT supports this) | Manual mount test on one host per OS family | HIGH | new |
| NFR-7.2 | USB boots on UEFI x86_64 systems | Boots on all fleet hosts and the reference laptop | Physical boot test | CRITICAL | new (generalizes FR-1.1) |
| NFR-7.3 | USB boots on Legacy BIOS x86_64 systems | Boots in QEMU with `-machine pc` and on at least one fleet host configured for legacy boot | Physical + QEMU test | HIGH | new (generalizes FR-1.2) |
| NFR-7.4 | Secure Boot compatibility via MOK enrollment | First-boot MOK enrollment completes without manual shim patching on at least two distinct UEFI firmwares | Physical test on two hosts with Secure Boot ON | HIGH | new |

## NFR-8: Compatibility

| ID | Requirement | Target / Threshold | Measurement / Verification | Priority | Source |
|----|-------------|--------------------|----------------------------|----------|--------|
| NFR-8.1 | Tested-host compatibility matrix | Boot + persistence verified on `ref-host-1`, `ref-host-2`, `ref-host-3`, `ref-host-4` | Per-host row in `docs/physical-test-guide.md` result table | CRITICAL | new |
| NFR-8.2 | Flash-tool compatibility | Published image flashes successfully using balenaEtcher (all three OSes), `dd` on Linux/macOS, and Rufus on Windows (DD-image mode) | Each tool listed in `docs/flash-image.md` has been exercised at least once against the published image | HIGH | new |
| NFR-8.3 | Target USB stick compatibility | Documented list of known-working USB 3.x models with >= 64 GB capacity; a caveats list for USBs known to mis-enumerate | Maintained compatibility table in `docs/flash-image.md` | MEDIUM | new |

## NFR-9: Observability

| ID | Requirement | Target / Threshold | Measurement / Verification | Priority | Source |
|----|-------------|--------------------|----------------------------|----------|--------|
| NFR-9.1 | `start-ai.sh` reports its status clearly | Prints: detected RAM, selected model, online/offline state, each tool's availability (OK/FAIL), and the URL of the local `llama-server` | Smoke test asserts the presence of each field in stdout | HIGH | new |
| NFR-9.2 | Flash-tool failures surface actionable errors | `docs/flash-image.md` lists the top 5 common errors per tool (wrong target, verification mismatch, permission denied, source corruption, write-protected media) with user-readable remediation | Documentation review checklist before publication | MEDIUM | new |
| NFR-9.3 | Persistence load failures are visible | If the Ventoy persistence `.dat` is missing or corrupt, the first-boot banner shows a prominent warning rather than silently falling back to a fresh session | Manual fault-injection test (rename `.dat`, boot, observe) | MEDIUM | new |
| NFR-9.4 | Image integrity can be checked without booting | Published `SHA-256SUMS` file plus `docs/flash-image.md` verification snippet allow a recipient to verify the download on any OS before flashing | Documentation + release asset review | HIGH | new |

## NFR-10: Compliance and Licensing

| ID | Requirement | Target / Threshold | Measurement / Verification | Priority | Source |
|----|-------------|--------------------|----------------------------|----------|--------|
| NFR-10.1 | Repository has a resolved top-level LICENSE | `LICENSE` file present at repo root; compatible with all bundled third-party artifacts (Ventoy GPLv3, Ubuntu, llama.cpp MIT, Qwen/Phi model licenses, Claude Code EULA) | ADR documents the license choice and compatibility analysis; `LICENSE` committed before first tagged release | CRITICAL | new |
| NFR-10.2 | Third-party artifact licenses are enumerated | `manifest/third-party-licenses.md` lists each bundled artifact, its upstream source URL, its license, and the license text location on the flashed USB (`/data/docs/licenses/`) | Pre-publish review against the actual bundled file list | HIGH | new |
| NFR-10.3 | GPL-licensed components ship with corresponding source availability | For each GPL component (notably Ventoy), the published release either bundles source or provides a written offer with an upstream URL and git SHA | Manifest review before each tagged release | HIGH | new |
| NFR-10.4 | Claude Code EULA compliance | Bundled binary is redistributed in accordance with Anthropic's current terms; if redistribution is disallowed, the image ships an installer script that fetches the binary on first online boot | Terms review per release; ADR documents the chosen mode | HIGH | new |
| NFR-10.5 | Model-weight licenses are surfaced to the user | `start-ai.sh --licenses` or equivalent prints the license name and a local path to the full license text for each loaded model | Smoke test asserts the command exists and returns non-empty output | MEDIUM | new |

---

## Out of scope for v1.0

The following are explicitly deferred. They are tracked in this register so that later revisions have a starting point, but they are **not** acceptance criteria for the first distributable release.

- **LUKS-encrypted persistence** (NFR-4.3, stretch goal). The current threat model treats physical loss of the USB as acceptable because no secrets ship with the image and per-user API keys are user-supplied after flashing. Revisit if recipients start storing sensitive material in the overlay or if the audience broadens.
- **Bit-for-bit reproducible-build guarantee for the custom Ubuntu ISO.** The builder is declarative `live-build` (ADR-007), but byte-identical rebuilds still require reproducibility flags (`SOURCE_DATE_EPOCH`, pinned apt snapshots) that are not enabled by default. The project accepts this limitation and documents it (R-03) rather than promising bit-for-bit reproducibility. Revisit if supply-chain demands escalate.
- **SBOM generation.** No SPDX or CycloneDX bill of materials is produced for v1.0. The `manifest/third-party-licenses.md` file (NFR-10.2) serves as the human-readable substitute. Revisit if endpoint-protection flagging, a commercial dimension, or a compliance framework enters scope.
- **Multi-architecture support.** v1.0 is x86_64 only. ARM64 support (for Apple Silicon recovery scenarios or ARM SBCs) would require a second custom ISO, a second set of bundled binaries, and a second set of GGUF builds; it is deferred until there is concrete fleet demand.

---

## Change log

| Date | Version | Change | Author |
|------|---------|--------|--------|
| 2026-04-20 | 1.0 | Initial baseline: migrated NFR-1..NFR-6 from `docs/requirements.md`; added NFR-7 (portability), NFR-8 (compatibility), NFR-9 (observability), NFR-10 (compliance/licensing); documented v1.0 out-of-scope items. | SDLC orchestration |

---

## 2026-04-20 Amendment per ADR-005

ADR-005 (user-driven model loading + toolkit product surface + Ollama coexistence) adds a new NFR category and amends storage-related NFRs. Appended below as NFR-11 (Toolkit UX) and NFR-12 (Dynamic Storage). Some earlier NFRs (e.g., NFR-1.3/1.4 inference speed) are conditional post-amendment — they can only be validated after a user pulls a model. Test strategy §3.3 and §7 reflect that conditionality.

### NFR-11 — Toolkit UX (NEW category)

| ID | Requirement | Target / Acceptance Threshold | Measurement / Verification | Priority | Source |
|----|-------------|------------------------------|----------------------------|----------|--------|
| NFR-11.1 | `kintsugi-models` CLI subcommand coverage | At minimum: `list`, `add`, `pull`, `remove`, `verify` subcommands; each prints `--help` output; exits non-zero on error with a human-readable message | bats integration tests per subcommand | HIGH | ADR-005 |
| NFR-11.2 | Model-pull source transparency | Every `pull` prints source URL + source-advertised digest (when available) + destination path before starting download | Manual observation + bats output-capture test | HIGH | ADR-005, R-17 |
| NFR-11.3 | Persistence storage guardrails | `kintsugi-models pull` soft-warns when persistence >80% full; hard-refuses >95% full; message explains `remove` and `list --sizes` | bats test with simulated df output | HIGH | ADR-005, R-18 |
| NFR-11.4 | Recommended-list integrity | `manifest/models-recommended.yaml` is validated against a YAML schema on every release build; any schema failure blocks release | CI job + `yq` / `check-jsonschema` | HIGH | ADR-005 |
| NFR-11.5 | User-manifest shadowing | Runtime model discovery prefers `/data/models/user/models.yaml` entries over `manifest/models-recommended.yaml` on slug collision | bats integration test with fixture manifests | MEDIUM | ADR-005 |
| NFR-11.6 | Ollama and llama.cpp both reachable after first boot (once models pulled) | `start-ai.sh --status` reports both runtimes with health endpoint, version, and loaded-model list (or "no models pulled yet") | Integration test against running llama-server :8080 and ollama :11434 | HIGH | ADR-005 |
| NFR-11.7 | Builder-facing toolkit docs complete | `docs/toolkit-guide.md` covers: fork repo → choose models → `kintsugi-models add/pull` → `scripts/prep-master.sh` → image → sign → release, with working one-liners | Docs review + walk-through by an external reviewer (or a volunteer non-maintainer) | HIGH | ADR-005 (toolkit surface) |

### NFR-12 — Dynamic Storage (amends NFR-2 category)

| ID | Requirement | Target / Acceptance Threshold | Measurement / Verification | Priority | Source |
|----|-------------|------------------------------|----------------------------|----------|--------|
| NFR-12.1 | Base image size (no model weights bundled) | Compressed base image `.img.zst` ≤ 5 GB (soft target; measured by iteration-1 spike) | Release manifest reports actual size; CI fails on >8 GB hard cap | HIGH | ADR-005, ADR-002 amendment |
| NFR-12.2 | Persistence overlay initial size | ≥ 10 GB (unchanged from NFR-2.2); sized to hold at least one medium GGUF plus OS writes | Measured at image build | HIGH | NFR-2.2 (inherited) |
| NFR-12.3 | Per-model footprint disclosure | Each entry in `models-recommended.yaml` declares its compressed download size and resident disk size | Schema validation + display in `kintsugi-models list --sizes` | MEDIUM | ADR-005 |

### Conditionality notes for earlier NFRs

- **NFR-1.3, NFR-1.4** (inference throughput) — conditional on a user having pulled at least one model. Harness reports SKIP/WARN with "pull a recommended model first" when no weights are present. Per test-strategy §3.3 amendment.
- **NFR-4.1** (no API keys in squashfs) — unchanged, still critical. Reinforced by ADR-005's "no weights in squashfs" principle.
- **NFR-10** category (Compliance/Licensing) — simpler post-ADR-005. Model-weight license compatibility concerns largely drop out; bundled-binaries license work (llama.cpp MIT, Ollama Apache-2.0 **new**, Ventoy GPLv3, rescue ISOs, proprietary CLIs) remains.
