# Use-Case Specification: Kintsugi USB

**Project**: Kintsugi USB — AI-assisted rescue boot media
**Document Type**: Formal Use-Case Specification
**Version**: 1.0 (Elaboration baseline)
**Date**: 2026-04-20
**Source**: Derived from `docs/requirements.md` §3 (UC-1..UC-5), `docs/architecture.md`, and `.aiwg/intake/project-intake.md`

---

## 1. Scope

This specification formalizes the five use cases established for the current Elaboration baseline. Each describes a scenario in which a human operator interacts with a flashed Kintsugi USB to recover, diagnose, image, or reinstall a target host system. The use cases assume the physical master USB already exists and boots correctly (the pre-MVP state). They do **not** cover the imaging/distribution/field-update pipeline, which is tracked separately as future use cases (see §7).

## 2. Actors

| Actor | Type | Description |
|-------|------|-------------|
| **Operator** | Primary (human) | The person holding the USB. In the current baseline this is the maintainer; in future variants may be a non-technical recipient. |
| **Target Host** | Secondary (system) | Any x86_64 UEFI or legacy BIOS machine, typically a fleet member (ref-host-1, ref-host-2, ref-host-3, ref-host-4) or a family member's PC. |
| **Local LLM (llama.cpp)** | Secondary (system) | Offline inference runtime on the USB exposing an OpenAI-compatible API at `localhost:8080`. |
| **Remote LLM Provider** | Secondary (external) | Anthropic API (for `claude` CLI) or OpenAI API (for `codex`, `aider`), used only when network is available. |
| **Fleet Network / NAS** | Secondary (external) | 10.0.0.x LAN and SMB/NFS backup targets, reachable when the target host is on-site. |

## 3. Stakeholders and Interests (global)

| Stakeholder | Interest |
|-------------|----------|
| Maintainer (Joseph / roctinam) | Every fleet host is recoverable; the drive works offline as reliably as online. |
| Fleet hosts (owners of ref-host-1, ref-host-2, ref-host-3, ref-host-4) | Minimized downtime; data preserved through failures. |
| Family / non-technical recipients | Can boot the drive and follow a runbook or hand the session to an AI agent. |
| Anthropic / OpenAI | API keys used only from properly-permissioned persistence files; never leaked to exFAT or squashfs. |

---

## 4. Use Cases

### UC-001: Boot Fleet Host from USB for Rescue

**Primary actor**: Operator
**Secondary actors**: Target Host
**Stakeholders & interests**:
- Operator — wants a reliable, deterministic boot into a known-good rescue environment on any fleet host.
- Target Host owner — wants the original disk left untouched until the operator explicitly mounts or writes to it.

**Preconditions**:
- Kintsugi USB is flashed and physically inserted into the target host.
- Target host hardware is functional enough to POST and reach firmware.
- Operator has physical access and can enter the firmware boot-select menu.

**Postconditions (success guarantee)**:
- Operator reaches a shell (or optionally `startx` xfce4 desktop) in the custom Ubuntu ML-Support live environment or a selected rescue ISO.
- All rescue tools listed in FR-6 are present on PATH without any additional package installation.
- The target system's root filesystem is available for inspection; no write has occurred unless the operator explicitly mounted read-write and issued a write.

**Minimal guarantee (failure)**:
- If the custom Ubuntu ISO fails to boot, the Ventoy menu remains reachable so the operator can fall back to SystemRescue, Clonezilla, or GParted Live.

**Trigger**: A fleet host is unbootable, misbehaving, or requires offline maintenance that cannot be performed from its installed OS.

**Main success scenario**:
1. Operator inserts the USB into the target host.
2. Operator powers on the host and enters the firmware boot-select menu (typically F12 or F2).
3. Operator selects the USB device as the boot source.
4. Ventoy bootloader displays the ISO menu with descriptive labels (FR-1.3).
5. Operator selects "Ubuntu ML-Support 24.04 (AI + Rescue)".
6. Ventoy prompts for persistence; operator accepts (default).
7. The custom Ubuntu environment boots to a shell within 60 seconds (NFR-1.1); `start-ai.sh` runs and reports tool status.
8. Operator mounts the target host's root filesystem (e.g., `mount /dev/nvme0n1p2 /mnt/target`).
9. Operator bind-mounts `/dev`, `/proc`, `/sys` and `chroot`s into the target to perform repairs (FR-6.9).

**Extensions / alternate flows**:
- **1a. USB not detected by firmware**: Operator verifies the USB is fully inserted, tries a different port, or toggles firmware settings (USB legacy support, XHCI handoff). If still not detected, falls back to another host or another drive.
- **5a. Secure Boot enabled**: Ventoy shim prompts for MOK enrollment (FR-1.5). Operator enrolls the key via MOK Manager and reboots; flow continues at step 3.
- **5b. Operator needs a different tool**: Instead of custom Ubuntu, operator selects SystemRescue (step 5), Clonezilla, or GParted Live, and the flow continues inside that ISO's own shell.
- **7a. Persistence overlay corrupt or unreadable**: Ventoy falls back to non-persistent boot; operator continues with an ephemeral session and accepts that installed packages will not persist.
- **8a. Target disk encrypted (LUKS)**: Operator unlocks the LUKS volume with the recovery passphrase before mounting.

**Special requirements / NFR refs**: NFR-1.1 (boot < 60s), NFR-3.1 (100% fleet compatibility), NFR-4.1 (no secrets in squashfs), FR-1.*, FR-2.*, FR-5.*, FR-6.*.

**Frequency of use**: Low but critical — expected a few times per year per host, but must work every time.

**Open issues**:
- No automated smoke test confirming boot behaviour across all four fleet hosts after each master rebuild.
- Behaviour on hosts with aggressive Secure Boot policies (locked MOK) is not yet documented.

---

### UC-002: AI-Assisted Log Analysis (Online)

**Primary actor**: Operator
**Secondary actors**: Target Host, Remote LLM Provider (Anthropic), Local LLM (as fallback)
**Stakeholders & interests**:
- Operator — wants a fast, competent second opinion on unfamiliar failures.
- Anthropic — requires that the API key remain confidential and that requests originate from a client the operator controls.

**Preconditions**:
- UC-001 has succeeded (custom Ubuntu live session active).
- Network connectivity is available and reachable to `api.anthropic.com`.
- `~/.config/ai-keys.env` exists in persistence with a valid `ANTHROPIC_API_KEY` at mode 600 (FR-3.2, NFR-4.2).
- Target host's `/var/log/` (or equivalent) is mountable for read.

**Postconditions (success guarantee)**:
- Operator has a natural-language diagnosis and a concrete next action derived from the target's logs.
- No API key value is written to disk outside the persistence overlay.
- No secrets from the target host are uploaded to the LLM unless the operator explicitly passed them.

**Trigger**: Operator suspects a software/config fault on the target and needs help interpreting log output.

**Main success scenario**:
1. Custom Ubuntu live environment is running (from UC-001).
2. `start-ai.sh` detects internet, sources API keys from persistence, and prints "Online: Claude Code, Codex CLI, Aider (remote)" (FR-3.5).
3. Operator mounts the target filesystem read-only (e.g., `mount -o ro /dev/sda2 /mnt/target`).
4. Operator runs `claude "analyze these syslog entries for the root cause of the boot failure" < /mnt/target/var/log/syslog`.
5. Claude Code returns a diagnosis and a recommended remediation.
6. Operator reviews the recommendation, chroots into the target (as in UC-001), and applies the fix.
7. Operator verifies the fix (reboot target, re-check logs).

**Extensions / alternate flows**:
- **2a. Network detected but Anthropic unreachable** (captive portal, egress block): `start-ai.sh` reports online but `claude` fails on first call. Operator either authenticates the captive portal and retries, or falls back to UC-003 (offline workflow).
- **2b. API key missing or invalid**: `claude` prompts for authentication. Operator either populates the key in `~/.config/ai-keys.env` (mode 600) and retries, or falls back to local inference.
- **4a. Logs contain secrets the operator does not want uploaded**: Operator filters/redacts the input (e.g., via `grep -v`) before piping to `claude`, or switches to UC-003 to keep the analysis local.
- **5a. Model response is wrong or incomplete**: Operator re-prompts with additional context, or cross-checks against the local model via Aider for a second opinion.

**Special requirements / NFR refs**: FR-3.1..FR-3.5, NFR-4.1, NFR-4.2, NFR-5.2 (AI tools discoverable via `start-ai.sh`).

**Frequency of use**: Moderate — expected on most rescue sessions where internet is available.

**Open issues**:
- No guardrails against accidental upload of host secrets (credentials embedded in logs). Future work: redaction helper script.
- No local rate-limit or cost telemetry visible to the operator.

---

### UC-003: AI-Assisted Script Generation (Offline)

**Primary actor**: Operator
**Secondary actors**: Target Host, Local LLM (llama.cpp + GGUF model)
**Stakeholders & interests**:
- Operator — wants useful AI assistance even when the site has no uplink (disaster scenarios, remote locations, air-gapped hosts).
- Target host owner — wants no outbound network calls containing their system state.

**Preconditions**:
- UC-001 has succeeded.
- The host has at least 8 GB RAM (for Phi-4-mini) or 16 GB+ (for Qwen2.5-Coder 7B) so a model can be loaded (FR-4.7).
- GGUF model files present on the USB (FR-4.2, FR-4.3).
- Network may be absent, unreliable, or explicitly disabled.

**Postconditions (success guarantee)**:
- A diagnostic or remediation script is generated, reviewed by the operator, and ready for execution.
- No data about the target host left the local machine.
- `llama-server` is running and responsive at `localhost:8080` (or a direct `llama-cli` session was used).

**Trigger**: Operator needs AI help but has no internet, or has internet they do not wish to use for policy/trust reasons.

**Main success scenario**:
1. Custom Ubuntu live environment is running.
2. `start-ai.sh` detects no route to `api.anthropic.com`, selects a model based on detected RAM, and starts `llama-server` on port 8080 (FR-4.4).
3. Within 90 seconds of script start, `llama-server` is ready to serve requests (NFR-1.2).
4. Operator describes the problem either interactively (`ai` alias → `llama-cli`, FR-4.6) or through `aider` pointed at `http://localhost:8080/v1`.
5. The local model generates a candidate diagnostic or remediation script.
6. Operator reviews the script line-by-line and edits as needed.
7. Operator executes the script against the target (chroot or mounted filesystem).
8. Script output informs the operator's next action.

**Extensions / alternate flows**:
- **2a. RAM insufficient for any model**: `start-ai.sh` reports the constraint and skips model load. Operator falls back to manual diagnosis using rescue tools, or moves the disk to a more capable host and retries.
- **3a. `llama-server` fails to start** (corrupt GGUF, missing library): Operator runs `llama-cli` directly against the GGUF file as a fallback, or re-imports the model from the data partition backup copy.
- **5a. Generated script is unsafe or wrong**: Operator discards it and re-prompts with stricter constraints, or uses the script as a scaffold and rewrites the dangerous portion manually.
- **6a. Operator later regains internet mid-session**: They may re-run `start-ai.sh` to pick up online tools, then cross-check the offline-generated script against a remote model via UC-002.

**Special requirements / NFR refs**: FR-4.1..FR-4.7, NFR-1.2 (server ready < 90s), NFR-1.3, NFR-1.4 (inference throughput), NFR-2.1 (storage budget respected), NFR-5.2.

**Frequency of use**: Moderate — expected whenever an uplink is absent or untrusted; also used by maintainers who prefer local inference as a default.

**Open issues**:
- No structured evaluation of local model quality against common rescue prompts.
- No mechanism to cache and reuse prior prompts/responses within the persistence overlay.

---

### UC-004: Disk Imaging Before Major Change

**Primary actor**: Operator
**Secondary actors**: Target Host, external drive or Fleet Network / NAS share
**Stakeholders & interests**:
- Operator — wants a safety net before any risky operation (partition resize, OS upgrade, firmware flash).
- Host owner — wants verifiable, restorable backup of current state.

**Preconditions**:
- Target host is booted from the Kintsugi USB.
- A destination for the image exists with sufficient free space: either an external USB/SSD attached, or a reachable SMB/NFS share on the fleet LAN.
- Operator knows which source disk maps to the intended target (verified via `lsblk`, `smartctl -i`, or label).

**Postconditions (success guarantee)**:
- A compressed disk image has been written to the chosen destination.
- A SHA-256 (or equivalent) checksum has been recorded so the image's integrity can be verified before restore.
- The source disk is unchanged.

**Minimal guarantee (failure)**:
- If imaging fails mid-run, the operator is notified and the source disk remains untouched; partial image artifacts on the destination are clearly marked incomplete.

**Trigger**: Operator is about to perform a destructive or risky change and wants a rollback point.

**Main success scenario**:
1. Operator boots Clonezilla from the Ventoy menu (FR-8.2).
2. Operator selects "device-image" → backup mode.
3. Operator selects source disk (the target's system disk) and destination (mounted external drive or SMB/NFS share).
4. Clonezilla creates a compressed image (default: zstd or gzip).
5. Operator records the resulting image path and SHA-256 checksum.
6. Operator proceeds with the risky operation on the target system.
7. If the operation fails, operator reboots into Clonezilla and restores from the saved image.

**Extensions / alternate flows**:
- **2a. Operator prefers raw image over Clonezilla's partclone format**: Operator boots the custom Ubuntu ML-Support ISO instead and uses `dd` or `ddrescue` piped through `zstd` to write a raw compressed image, recording a SHA-256 at the end.
- **3a. Destination is a network share that requires credentials**: Operator mounts the share (CIFS or NFS) before launching the backup, ensuring credentials come from persistence rather than being typed in scrollback.
- **3b. Source disk has bad sectors**: Operator aborts Clonezilla and switches to `ddrescue` from the custom Ubuntu ISO, which tolerates read errors and produces a recovery log.
- **4a. Destination fills before imaging completes**: Clonezilla aborts; operator frees space or switches destination and restarts the backup.

**Special requirements / NFR refs**: FR-6.4 (ddrescue), FR-8.2 (Clonezilla), FR-9.3 (data partition usable for small backup artifacts if needed), implicit "verification always" directive (checksum step).

**Frequency of use**: Low but recurring — expected before any OS upgrade, partition change, or experimental operation.

**Open issues**:
- No pre-canned helper script for the `dd | zstd` + checksum workflow; today it is a manual recipe.
- No integration with fleet NAS beyond documented hostnames in `/etc/hosts`.

---

### UC-005: Fresh OS Installation

**Primary actor**: Operator
**Secondary actors**: Target Host, Fleet Network (for post-install setup)
**Stakeholders & interests**:
- Operator — wants a repeatable path from "new/wiped machine" to "fleet-integrated host".
- Fleet — wants new hosts configured consistently (SSH keys, hostname, network, monitoring).

**Preconditions**:
- Target host is a new machine, a decommissioned machine being repurposed, or a host whose prior OS is being discarded.
- Operator has any necessary data backed up (UC-004 recommended if the disk was previously in use).
- Ubuntu 24.04 Desktop installer ISO is present on the Kintsugi USB (FR-8.5).

**Postconditions (success guarantee)**:
- Ubuntu 24.04 is installed on the target's disk.
- Post-install fleet configuration scripts have been applied, bringing the host into parity with the rest of the fleet (SSH authorized keys, hostname, `/etc/hosts`, monitoring agent where applicable).
- The host is reachable over the fleet LAN.

**Trigger**: A new or wiped host must be brought onto the fleet, or an existing host needs a clean reinstall.

**Main success scenario**:
1. Operator boots Ubuntu 24.04 Desktop installer from the Ventoy menu.
2. Operator proceeds through the standard Ubuntu installation (disk layout, user, locale).
3. Operator reboots the host; Ubuntu now runs from the host's internal disk.
4. Operator boots the Kintsugi USB again and selects the custom Ubuntu ML-Support ISO to access fleet tooling.
5. Operator runs fleet setup scripts from `/data/scripts/` (FR-7.2) against the freshly installed host (over SSH or via a mounted root).
6. Fleet scripts configure SSH (FR-7.1), add fleet host entries (FR-7.3), and perform any host-specific setup.
7. Operator verifies network reachability and SSH key-based access from another fleet host.

**Extensions / alternate flows**:
- **1a. Operator prefers Ubuntu Server over Desktop**: Server ISO is not currently bundled (FR-8 enumerates Desktop only); operator either downloads Server separately to the exFAT partition or uses Desktop with a minimal-installation option.
- **2a. Installer cannot see the target disk**: Operator drops to a shell, inspects with `lsblk`/`smartctl`, and may need to clean a stale partition table (`wipefs`, `sgdisk --zap-all`) before resuming.
- **4a. Fleet scripts are out of date on the USB** (migration gap): Operator pulls current scripts from the sysops repo before running them; this is a known pre-MVP gap until the field-update mechanism (future UC-007) exists.
- **5a. New host has a non-fleet use (family machine, one-off)**: Operator skips fleet setup steps 5–7 and instead applies a simpler personal-machine checklist.

**Special requirements / NFR refs**: FR-7.*, FR-8.5, NFR-3.1, implicit "scripted and idempotent" directive from CLAUDE.md §Documentation Principles.

**Frequency of use**: Low — a few times per year when adding or repurposing hardware.

**Open issues**:
- No documented, idempotent "join fleet" script yet — the step is narrative in `docs/build-guide.md`.
- No Ubuntu Server ISO bundled; decision deferred.

---

## 5. Traceability Stub: Use Cases → Functional Requirements

| Use Case | Primary FRs | Supporting FRs |
|----------|-------------|----------------|
| UC-001 Boot for Rescue | FR-1.1–1.6, FR-2.1–2.6, FR-5.1–5.5, FR-6.1–6.10 | FR-8.* (fallback ISOs), FR-7.3 (hosts file for network ops) |
| UC-002 AI Log Analysis (Online) | FR-3.1–3.5 | FR-2.5 (DHCP for network), FR-5.5 (persistence for API keys), NFR-4.1, NFR-4.2 |
| UC-003 AI Script Gen (Offline) | FR-4.1–4.7 | FR-2.3, FR-5.4 (persistence), NFR-1.2–1.4 |
| UC-004 Disk Imaging | FR-8.2 (Clonezilla), FR-6.4 (ddrescue) | FR-7.3 (fleet NAS reachable), FR-9.3 (data partition) |
| UC-005 Fresh OS Install | FR-8.5 (Ubuntu installer), FR-7.1–7.4 | FR-2.1 (custom Ubuntu for post-install tooling) |

## 6. Cross-Cutting Notes

- Every use case that touches secrets relies on **persistence-only secret storage** (NFR-4.1, NFR-4.2). Operators must never write API keys or SSH private keys to the exFAT data partition.
- Every use case ends with an implicit verification step (checksum, smoke test, or confirmation) per the CLAUDE.md "verification always" principle.
- All use cases in this baseline assume the USB was flashed from a trusted source (the maintainer). Supply-chain provenance for recipient-flashed USBs is out of scope for Elaboration and tracked against future UC-006.

---

## 7. Out of Scope for Elaboration Baseline

The following use cases are clearly needed for the project's end-state but are **not implemented** at the current pre-MVP stage. Scripts, docs, and pipeline do not yet exist. They are placeholders here so the traceability structure can absorb them once work begins:

- **UC-006 (future): Distribute a Flashed USB to a Non-Technical Recipient** — covers the maintainer producing a compressed, checksummed, signed distributable image; publishing it via Gitea releases; and a non-technical recipient flashing their own USB using recipient-facing instructions. Depends on `scripts/create-image.sh`, `scripts/flash-image.sh`, `docs/create-image.md`, `docs/flash-image.md`, and a licensing decision.
- **UC-007 (future): In-Field Payload Update Without Reflashing** — covers a deployed-USB holder syncing updated `docs/`, `scripts/`, and (optionally) model weights from a published payload without rebuilding the whole drive. Depends on `scripts/update-payload.sh`, `docs/update-payload.md`, and a signed-payload manifest.

These two use cases will be promoted to UC-006/UC-007 with full formal structure when their supporting artifacts enter Construction.

---

*End of document.*
