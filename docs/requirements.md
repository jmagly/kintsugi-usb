# Requirements Specification: ML-Augmented Boot & Support USB

**Project**: Kintsugi USB (formerly USB-TOOLKIT)
**Version**: 1.0 (amended 2026-04-20 per ADR-005 — see banner below)
**Date**: 2026-03-03 (original), 2026-04-20 (amendment)
**Phase**: Elaboration

> **AMENDMENT BANNER — 2026-04-20 (ADR-005)**
>
> This document predates the SDLC baseline and the ADR-005 scope amendment. Several FRs in §1.4 (FR-4, AI-Assisted Diagnostics) are **stale** as written and are superseded by:
>
> - `.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md`
> - `.aiwg/architecture/software-architecture-doc.md` §4.2 (AI Stack, amended)
> - `.aiwg/requirements/nfr-register.md` NFR-11 (Toolkit UX) + NFR-12 (Dynamic Storage)
>
> **Specifically**:
> - Bundled model weights (FR-4.2 Qwen2.5-Coder 7B, FR-4.3 Phi-4-mini) — **no longer bundled**. Users load their own via `kintsugi-models` CLI at build-time or boot-time.
> - AI runtimes (FR-4.1 llama.cpp) — **Ollama coexists** as a second local runtime on :11434.
> - Model auto-selection (FR-4.7) — reframed as manifest-driven discovery over the recommended-list + user manifest.
>
> **Issue #22** (`[docs] Correct docs/requirements.md FR-4.x for Ollama + user-driven models`) tracks the deeper rewrite as an iteration-1 deliverable. Until that merges, treat the `.aiwg/` artifacts as authoritative where they conflict with this document.

---

## 1. Functional Requirements

### FR-1: Multi-Boot Capability

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-1.1 | USB boots via UEFI on x86_64 systems | CRITICAL |
| FR-1.2 | USB boots via Legacy BIOS on x86_64 systems | HIGH |
| FR-1.3 | Ventoy boot menu displays all ISOs with descriptive labels | CRITICAL |
| FR-1.4 | User can select any ISO from boot menu and boot into it | CRITICAL |
| FR-1.5 | Secure Boot enrollment works via MOK manager on first boot | HIGH |
| FR-1.6 | Boot menu includes Memtest86+ as standalone entry | MEDIUM |

### FR-2: Custom Ubuntu Environment

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-2.1 | Custom ISO boots to functional shell with all tools pre-installed | CRITICAL |
| FR-2.2 | Lightweight desktop (xfce4) available via `startx` | MEDIUM |
| FR-2.3 | All rescue tool packages present at first boot (no apt install needed) | CRITICAL |
| FR-2.4 | SSH server enabled by default with key-based auth | HIGH |
| FR-2.5 | Network auto-configured via DHCP (NetworkManager or netplan) | HIGH |
| FR-2.6 | Root shell accessible without password in live session | CRITICAL |

### FR-3: AI-Assisted Diagnostics (Online)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-3.1 | Claude Code binary present and executable from PATH | HIGH |
| FR-3.2 | Claude Code authenticates via ANTHROPIC_API_KEY from persistence | HIGH |
| FR-3.3 | Codex CLI binary present and executable from PATH | MEDIUM |
| FR-3.4 | Aider installed and configured to use available API endpoint | HIGH |
| FR-3.5 | `start-ai.sh` script detects internet and reports available tools | HIGH |

### FR-4: AI Runtimes, Tooling, and User-Driven Loading

Amended 2026-04-21 per ADR-005 + ADR-006. See `.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md` and `.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md` for rationale. Cross-references: NFR-11 (Toolkit UX) and NFR-12 (Dynamic Storage) in `.aiwg/requirements/nfr-register.md`.

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-4.1 | llama.cpp (llama-cli + llama-server) binary present at /usr/local/bin/ or /tools/bin/ | CRITICAL |
| FR-4.2 | Ollama runtime present and reachable on :11434 post-boot (start-ai.sh manages lifecycle) | HIGH |
| FR-4.3 | Dual-runtime support — both :8080 (llama-server) and :11434 (ollama) are simultaneously available | HIGH |
| FR-4.4 | start-ai.sh reads `manifest/models-recommended.yaml` (at /opt/kintsugi-usb/manifest/) + `/data/models/user/models.yaml` (if present); user entries shadow recommended on slug collision | HIGH |
| FR-4.5 | NO model weights are bundled in the distributed image (ADR-005 user-driven loading) | CRITICAL |
| FR-4.6 | kintsugi-models CLI present at /usr/local/bin/kintsugi-models; subcommands list/add/pull/remove/verify | HIGH |
| FR-4.7 | kintsugi-frameworks CLI present at /usr/local/bin/kintsugi-frameworks | HIGH |
| FR-4.8 | start-ai.sh --status reports health of both runtimes + manifest discovery + env status | MEDIUM |
| FR-4.9 | start-ai.sh auto-selects a GGUF based on available RAM (prefers 9b-slug when ≥16 GB, else 4b-slug) from the union-manifest | MEDIUM |
| FR-4.10 | Aider can be configured to use either llama-server (:8080) or Ollama (:11434) via OPENAI_API_BASE | MEDIUM |
| FR-4.11 | Cloud CLIs (claude, codex, aider) are installable via kintsugi-frameworks install; auth is POST-FLASH user responsibility | HIGH |
| FR-4.12 | mikefarah/yq present at /usr/local/bin/yq for manifest parsing (distinct from apt python-yq) | CRITICAL |
| FR-4.13 | API keys are NEVER baked into the image; loaded at runtime from /root/.config/ai-keys.env or ~/.config/ai-keys.env with mode 600 | CRITICAL |

#### Obsolete / superseded

- **Old FR-4.2** (Qwen2.5-Coder 7B Q4_K_M bundled) — **REMOVED**. No bundled weights per ADR-005.
- **Old FR-4.3** (Phi-4-mini Q4_K_M bundled) — **REMOVED**. No bundled weights per ADR-005.
- **Old FR-4.4** (llama-server on 8080 at boot) — **amended**. Now: llama-server starts only if a model is present in the manifest union.
- **Old FR-4.5** (Aider against llama-server when no internet) — **amended**. Still valid, but Aider now routes based on detection (Anthropic key > Ollama > llama-server).
- **Old FR-4.7** (auto-select 7B for 16 GB, 3.8B for 8 GB) — **amended**. Selection now manifest-driven with same heuristic (see FR-4.9).

### FR-5: Persistence

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-5.1 | Changes to custom Ubuntu environment persist across reboots | HIGH |
| FR-5.2 | Persistence uses Ventoy persistence plugin with .dat file | HIGH |
| FR-5.3 | Persistence overlay is at least 10GB | HIGH |
| FR-5.4 | Installed packages persist (apt install survives reboot) | HIGH |
| FR-5.5 | Shell history, configs, and generated scripts persist | HIGH |

### FR-6: Rescue & Troubleshooting Tools

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-6.1 | Filesystem check tools: fsck.ext4, xfs_repair, btrfs check, ntfsfix, fsck.fat | CRITICAL |
| FR-6.2 | Partition management: gparted, parted, fdisk, gdisk | CRITICAL |
| FR-6.3 | Drive health: smartctl, nvme-cli, hdparm | CRITICAL |
| FR-6.4 | Data recovery: testdisk, photorec, ddrescue | HIGH |
| FR-6.5 | Network diagnostics: nmap, tcpdump, mtr, dig, iperf3, curl, arp-scan | HIGH |
| FR-6.6 | Boot repair: grub-install, efibootmgr, os-prober, update-grub | HIGH |
| FR-6.7 | System info: lshw, dmidecode, inxi | MEDIUM |
| FR-6.8 | Monitoring: htop, iotop, lsof, strace, sysstat | MEDIUM |
| FR-6.9 | Chroot capability: bind mounts for /dev, /proc, /sys into target root | CRITICAL |
| FR-6.10 | Terminal multiplexer: tmux | HIGH |

### FR-7: Fleet Integration

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-7.1 | SSH authorized_keys pre-loaded for all fleet hosts | HIGH |
| FR-7.2 | Fleet scripts from sysops repo available at `/data/scripts/` | MEDIUM |
| FR-7.3 | `/etc/hosts` entries for fleet hostnames (10.0.0.x) | MEDIUM |
| FR-7.4 | Fleet network topology reference accessible from USB | LOW |

### FR-8: Supplementary ISOs

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-8.1 | SystemRescue ISO boots from Ventoy menu | HIGH |
| FR-8.2 | Clonezilla ISO boots from Ventoy menu | MEDIUM |
| FR-8.3 | GParted Live ISO boots from Ventoy menu | MEDIUM |
| FR-8.4 | Hiren's BootCD PE boots from Ventoy menu | MEDIUM |
| FR-8.5 | Ubuntu 24.04 Desktop installer ISO boots from Ventoy menu | MEDIUM |

### FR-9: Data Partition

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-9.1 | Data partition readable from Windows, macOS, and Linux | HIGH |
| FR-9.2 | Data partition contains organized directory structure | MEDIUM |
| FR-9.3 | Data partition accessible from booted live environments | HIGH |

---

## 2. Non-Functional Requirements

### NFR-1: Performance

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-1.1 | Boot to shell prompt | < 60 seconds |
| NFR-1.2 | llama-server ready for first query | < 90 seconds from script start |
| NFR-1.3 | Phi-4-mini inference speed | > 15 tokens/second on i7-12700H |
| NFR-1.4 | Qwen2.5-Coder 7B inference speed | > 8 tokens/second on i7-12700H |

### NFR-2: Storage

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-2.1 | Total USB utilization | < 95% of 59GB |
| NFR-2.2 | Persistence overlay size | >= 10 GB |
| NFR-2.3 | Free space buffer | >= 2 GB |

### NFR-3: Reliability

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-3.1 | USB boots on all fleet x86_64 hosts | 100% (ref-host-1, ref-host-2, ref-host-3, ref-host-4) |
| NFR-3.2 | Flash wear mitigation | ext4 noatime, commit=60, minimal journaling |
| NFR-3.3 | Persistence data survives unclean shutdown | ext4 journal recovery |

### NFR-4: Security

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-4.1 | API keys never in squashfs ISO | Zero keys in base image |
| NFR-4.2 | API key file permissions | 600 (owner read/write only) |
| NFR-4.3 | Persistence encryption | Optional LUKS support (stretch goal) |

### NFR-5: Usability

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-5.1 | Boot menu labels descriptive | All ISOs have human-readable names |
| NFR-5.2 | AI tools discoverable | `start-ai.sh` prints available tools and status |
| NFR-5.3 | Help command available | `usb-help` alias lists common rescue procedures |

### NFR-6: Maintainability

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-6.1 | Add new ISO | Copy file to USB, appears in menu |
| NFR-6.2 | Update model | Replace .gguf file on USB |
| NFR-6.3 | Update AI tools | Replace binary on USB |
| NFR-6.4 | Rebuild custom ISO | Documented Cubic procedure |

---

## 3. Use Cases

### UC-1: Boot Fleet Host from USB for Rescue

**Actor**: Operator (roctinam)
**Precondition**: Fleet host is unbootable or needs offline maintenance
**Steps**:
1. Insert USB into host
2. Enter BIOS/UEFI boot menu (F12/F2)
3. Select USB device
4. Ventoy menu appears with ISO list
5. Select "Custom Ubuntu ML-Support" or "SystemRescue"
6. Environment boots with all tools ready
7. Mount target system's root filesystem
8. Chroot into target and perform repairs

### UC-2: AI-Assisted Log Analysis (Online)

**Actor**: Operator
**Precondition**: Host booted from USB, internet available
**Steps**:
1. Boot into custom Ubuntu from USB
2. `start-ai.sh` detects internet, reports Claude Code available
3. Mount target system's `/var/log/`
4. `claude "analyze these syslog entries for the root cause of the boot failure" < /mnt/target/var/log/syslog`
5. Claude Code provides diagnosis and recommended fix
6. Operator applies fix in chroot

### UC-3: AI-Assisted Script Generation (Offline)

**Actor**: Operator
**Precondition**: Host booted from USB, no internet
**Steps**:
1. Boot into custom Ubuntu from USB
2. `start-ai.sh` detects no internet, starts llama-server with Phi-4-mini
3. Operator describes problem to Aider or llama-cli
4. Local model generates a diagnostic script
5. Operator reviews and executes the script
6. Script output helps identify the issue

### UC-4: Disk Imaging Before Major Change

**Actor**: Operator
**Precondition**: Need full disk backup before risky operation
**Steps**:
1. Boot into Clonezilla from Ventoy menu
2. Select disk-to-image backup
3. Target: external drive or NAS share via SMB/NFS
4. Clonezilla creates compressed image
5. Proceed with risky operation on target system
6. If operation fails, restore from Clonezilla image

### UC-5: Fresh OS Installation

**Actor**: Operator
**Precondition**: Need to install Ubuntu on new or wiped system
**Steps**:
1. Boot Ubuntu Desktop installer ISO from Ventoy menu
2. Proceed through standard Ubuntu installation
3. Post-install: boot from USB again into custom environment
4. Run fleet setup scripts to configure the new host

---

## 4. Traceability Matrix

| Requirement | Objective | Test Case |
|-------------|-----------|-----------|
| FR-1.1 | OBJ-1 | TC-1: UEFI boot on ref-host-1 |
| FR-1.2 | OBJ-1 | TC-2: Legacy BIOS boot in QEMU |
| FR-2.1 | OBJ-2 | TC-3: Tool presence verification |
| FR-3.1-3.4 | OBJ-3 | TC-4: Claude Code functional test |
| FR-4.1–FR-4.13 | OBJ-4 | TC-5: Offline inference + runtime/tooling test |
| FR-5.1-5.5 | OBJ-5 | TC-6: Persistence reboot test |
| FR-6.1-6.10 | OBJ-2 | TC-7: Tool category coverage check |
| FR-7.1-7.4 | OBJ-6 | TC-8: Fleet integration validation |
| FR-8.1-8.5 | OBJ-7, OBJ-8 | TC-9: Supplementary ISO boot tests |
| FR-9.1-9.3 | OBJ-7 | TC-10: Cross-platform data access |
