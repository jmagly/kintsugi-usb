# System Architecture: ML-Augmented Boot & Support USB

**Project**: Kintsugi USB (formerly USB-TOOLKIT)
**Version**: 1.0 (amended 2026-04-20 per ADR-005 — see banner below)
**Date**: 2026-03-03 (original), 2026-04-20 (amendment)
**Phase**: Elaboration

> **AMENDMENT BANNER — 2026-04-20 (ADR-005)**
>
> This document predates the formal SDLC baseline. The authoritative architecture reference is now `.aiwg/architecture/software-architecture-doc.md` (baselined v1.0, amended 2026-04-20). This document remains useful for the **physical USB layout** (§2) and **boot flow** (§3), which are unchanged. The following sections are superseded:
>
> - **§4 AI Stack Architecture** — Ollama coexists with llama.cpp; models are user-loaded not bundled. See ADR-005 + formal SAD §4.2.
> - **§4 model-auto-select pseudocode** — superseded by manifest-driven discovery in the refactored `start-ai.sh` (tracked in issue #14).
> - **§6 Component Dependencies** — now includes Ollama; no GGUF weights shipped; `kintsugi-models` CLI + `manifest/models-recommended.yaml` added.
> - **§8 Tech Decisions "Primary model" / "Fast model"** — superseded by ADR-005 (user-driven loading with recommended-list starter).
>
> Issue #22 tracks the cleanup. Until then, treat `.aiwg/` artifacts as authoritative on any conflict.

---

## 1. System Context

```
                    ┌─────────────────────────────┐
                    │     Target Host System       │
                    │  (any x86_64 UEFI/BIOS PC)  │
                    │                              │
                    │   ┌─────────────────────┐   │
                    │   │   USB Boot Device    │   │
                    │   │   (59GB USB 3.x)     │   │
                    │   │                      │   │
                    │   │  Ventoy Bootloader   │   │
                    │   │        │              │   │
                    │   │   ┌────┴────┐        │   │
                    │   │   │ ISO Menu │        │   │
                    │   │   └────┬────┘        │   │
                    │   │        │              │   │
                    │   │  ┌─────┴──────┐      │   │
                    │   │  │Custom Ubuntu│      │   │
                    │   │  │ + AI Stack  │      │   │
                    │   │  └─────┬──────┘      │   │
                    │   │        │              │   │
                    │   └────────┼──────────────┘   │
                    │            │                   │
                    │     ┌──────┴──────┐            │
                    │     │ Host Hardware│            │
                    │     │ CPU, RAM,    │            │
                    │     │ Disks, NIC   │            │
                    │     └──────┬──────┘            │
                    └────────────┼───────────────────┘
                                 │
                    ┌────────────┴───────────────┐
                    │   Network (when available)  │
                    │                             │
                    │  ┌──────────┐ ┌──────────┐ │
                    │  │Anthropic │ │ OpenAI   │ │
                    │  │   API    │ │   API    │ │
                    │  └──────────┘ └──────────┘ │
                    └─────────────────────────────┘
```

---

## 2. USB Physical Layout

### Partition Table (GPT)

```
 Offset    Size     Type                 Filesystem  Label/Purpose
 ───────── ──────── ──────────────────── ─────────── ────────────────────────
 0         1 MB     BIOS Boot (EF02)     (none)      GRUB i386-pc stage 1.5
 1 MB      ~37 GB   Linux filesystem     exFAT       VENTOY (ISOs + data)
 ~37 GB    32 MB    EFI System (EF00)    FAT16       Ventoy EFI bootloader
 ~37 GB    20 GB    (Reserved)           (future)    Expansion space
 ~57 GB    ~2 GB    (Unallocated)        —           Buffer
```

### Ventoy Data Partition Layout (`/dev/sda1`, exFAT)

```
/
├── ISO/
│   ├── custom/
│   │   └── ubuntu-24.04-ml-support.iso        (~5 GB)
│   ├── rescue/
│   │   ├── systemrescue-11.03-amd64.iso       (~1 GB)
│   │   ├── clonezilla-live-3.2.0-amd64.iso    (~500 MB)
│   │   └── gparted-live-1.8.0-2-amd64.iso     (~600 MB)
│   ├── install/
│   │   └── ubuntu-24.04.2-desktop-amd64.iso   (~5 GB)
│   └── windows/
│       └── hirens-bootcd-pe-x64.iso           (~1.5 GB)
│
├── ventoy/
│   ├── ventoy.json                             (plugin config)
│   └── theme/                                  (GRUB2 theme assets)
│
├── persistence/
│   └── ubuntu-ml-persist.dat                   (~12 GB ext4)
│
├── tools/
│   ├── bin/
│   │   ├── llama-cli                           (~25 MB)
│   │   ├── llama-server
│   │   ├── claude                              (~100 MB)
│   │   ├── codex                               (~80 MB)
│   │   └── aider                               (Python package)
│   ├── node/
│   │   └── node-v24.14.0-linux-x64/            (~60 MB)
│   └── pip-cache/                              (pre-downloaded wheels)
│
├── models/
│   ├── qwen2.5-coder-7b-instruct-q4_k_m.gguf  (~5 GB)
│   └── phi-4-mini-instruct-q4_k_m.gguf        (~2.8 GB)
│
└── data/
    ├── scripts/                                (sysops fleet scripts)
    ├── ssh/                                    (SSH keys + configs)
    ├── docs/                                   (fleet reference docs)
    └── recovery/                               (recovery runbooks)
```

---

## 3. Boot Flow

```
Power On
  │
  ├─[UEFI]──────────────────────────────────────────────┐
  │  │                                                    │
  │  ├─[Secure Boot ON]──► Ventoy Shim ──► MOK Check     │
  │  │                         │                          │
  │  │                    ┌────┴────┐                     │
  │  │                    │Enrolled?│                     │
  │  │                    └────┬────┘                     │
  │  │                    Yes  │  No                      │
  │  │                    │    └──► MOK Manager Enrollment│
  │  │                    │            └──► Reboot        │
  │  │                    ▼                               │
  │  └─[Secure Boot OFF]─► Ventoy GRUB2 EFI             │
  │                              │                        │
  ├─[Legacy BIOS]───────────────┐│                        │
  │  │                          ││                        │
  │  └──► Ventoy MBR ─► GRUB2  ││                        │
  │                     │       ││                        │
  │                     ▼       ▼▼                        │
  │              ┌──────────────────┐                     │
  │              │  Ventoy ISO Menu │                     │
  │              ├──────────────────┤                     │
  │              │ 1. Ubuntu ML-Support (custom)         │
  │              │ 2. SystemRescue 11.03                 │
  │              │ 3. Clonezilla 3.2.0                   │
  │              │ 4. GParted Live 1.8.0                 │
  │              │ 5. Ubuntu 24.04 Installer             │
  │              │ 6. Hiren's BootCD PE                  │
  │              │ 7. Memtest86+                         │
  │              └────────┬─────────┘                     │
  │                       │                               │
  │              ┌────────┴─────────┐                     │
  │              │ Selection: #1    │                     │
  │              └────────┬─────────┘                     │
  │                       │                               │
  │         ┌─────────────┴──────────────┐                │
  │         │ Ventoy Persistence Prompt  │                │
  │         │ "Use persistence? [Y/n]"   │                │
  │         └─────────────┬──────────────┘                │
  │                       │                               │
  │              ┌────────┴─────────┐                     │
  │              │ Mount squashfs + │                     │
  │              │ overlayfs .dat   │                     │
  │              └────────┬─────────┘                     │
  │                       │                               │
  │              ┌────────┴─────────┐                     │
  │              │ Ubuntu Live Env  │                     │
  │              │ Shell Ready      │                     │
  │              └────────┬─────────┘                     │
  │                       │                               │
  │              ┌────────┴─────────┐                     │
  │              │ /etc/rc.local or │                     │
  │              │ systemd unit:    │                     │
  │              │ start-ai.sh      │                     │
  │              └──────────────────┘                     │
  │                                                       │
```

---

## 4. AI Stack Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   AI Stack Runtime                       │
│                                                          │
│  ┌──────────────────────────────────────────────┐       │
│  │           start-ai.sh (entrypoint)            │       │
│  │                                                │       │
│  │  1. Detect available RAM                       │       │
│  │  2. Select model (7B if >=16GB, 3.8B if <16GB)│       │
│  │  3. Check network connectivity                 │       │
│  │  4. Start llama-server on :8080                │       │
│  │  5. Source API keys from persistence           │       │
│  │  6. Report available tools                     │       │
│  └──────────────┬───────────────────────────────┘       │
│                  │                                       │
│   ┌──────────────┼──────────────────────────┐           │
│   │              │                           │           │
│   ▼              ▼                           ▼           │
│ ┌──────┐   ┌──────────┐              ┌───────────┐     │
│ │Tier 1│   │ Tier 1   │              │  Tier 2   │     │
│ │Local │   │ Bridge   │              │  Online   │     │
│ │      │   │          │              │           │     │
│ │llama │   │  Aider   │              │Claude Code│     │
│ │-cli  │   │          │              │Codex CLI  │     │
│ │      │   │ Uses     │              │           │     │
│ │Direct│   │ local or │              │ Uses      │     │
│ │GGUF  │   │ remote   │              │ Anthropic/│     │
│ │model │   │ API      │              │ OpenAI API│     │
│ └──┬───┘   └────┬─────┘              └─────┬─────┘     │
│    │             │                          │            │
│    │        ┌────┴──────────┐               │            │
│    │        │  Network?     │               │            │
│    │        ├───────────────┤               │            │
│    │        │ No  → :8080   │               │            │
│    │        │ Yes → Remote  │───────────────┘            │
│    │        │      API      │                            │
│    │        └───────────────┘                            │
│    │                                                     │
│    ▼                                                     │
│ ┌────────────────────────────┐                          │
│ │    llama-server :8080      │                          │
│ │    OpenAI-compatible API   │                          │
│ │                            │                          │
│ │  GET  /v1/models           │                          │
│ │  POST /v1/chat/completions │                          │
│ │  POST /v1/completions      │                          │
│ └────────────┬───────────────┘                          │
│              │                                           │
│   ┌──────────┴───────────┐                              │
│   │    GGUF Model File   │                              │
│   │  (from USB /models/) │                              │
│   └──────────────────────┘                              │
└─────────────────────────────────────────────────────────┘
```

### AI Tool Routing Logic

```bash
# Pseudocode for start-ai.sh
RAM_GB=$(free -g | awk '/Mem:/{print $2}')
if [ "$RAM_GB" -ge 16 ]; then
    MODEL="qwen2.5-coder-7b-instruct-q4_k_m.gguf"
else
    MODEL="phi-4-mini-instruct-q4_k_m.gguf"
fi

llama-server -m "/models/$MODEL" --port 8080 --ctx-size 4096 &

if ping -c1 -W2 api.anthropic.com &>/dev/null; then
    source ~/.config/ai-keys.env 2>/dev/null
    echo "Online: Claude Code, Codex CLI, Aider (remote)"
else
    export OPENAI_API_BASE="http://localhost:8080/v1"
    export OPENAI_API_KEY="none"
    echo "Offline: llama-cli, Aider (local), llama-server API"
fi
```

---

## 5. Security Architecture

```
┌────────────────────────────────────────────┐
│            Security Boundaries             │
│                                            │
│  ┌────────────────────────────────────┐    │
│  │  squashfs (READ-ONLY)             │    │
│  │  ┌──────────────────────────────┐ │    │
│  │  │ OS + Tools + AI Binaries     │ │    │
│  │  │ NO secrets, NO API keys      │ │    │
│  │  │ NO SSH private keys          │ │    │
│  │  └──────────────────────────────┘ │    │
│  └────────────────────────────────────┘    │
│                                            │
│  ┌────────────────────────────────────┐    │
│  │  Persistence Overlay (READ-WRITE) │    │
│  │  ┌──────────────────────────────┐ │    │
│  │  │ ~/.config/ai-keys.env (600)  │ │    │
│  │  │ ~/.ssh/id_ed25519 (600)      │ │    │
│  │  │ Shell history, custom scripts│ │    │
│  │  │ Installed packages           │ │    │
│  │  └──────────────────────────────┘ │    │
│  │                                    │    │
│  │  Optional: LUKS encryption        │    │
│  └────────────────────────────────────┘    │
│                                            │
│  ┌────────────────────────────────────┐    │
│  │  Data Partition (exFAT, no crypt) │    │
│  │  ┌──────────────────────────────┐ │    │
│  │  │ Models, scripts, docs        │ │    │
│  │  │ NO secrets (cross-platform   │ │    │
│  │  │ readable, no permissions)    │ │    │
│  │  └──────────────────────────────┘ │    │
│  └────────────────────────────────────┘    │
└────────────────────────────────────────────┘
```

**Key principles**:
- Secrets exist only in the persistence overlay (ext4, proper UNIX permissions)
- exFAT data partition has no file permissions — never store secrets there
- API keys loaded at runtime via environment variables, never hardcoded
- Optional LUKS on persistence for physical security if USB is lost

---

## 6. Component Dependencies

```
ventoy.json ──► Ventoy Bootloader
    │
    ├──► Custom Ubuntu ISO
    │       │
    │       ├──► Ubuntu 24.04 Server (base)
    │       ├──► xfce4 (GUI layer)
    │       ├──► Rescue tool packages (apt)
    │       ├──► Python 3 + pip packages
    │       └──► start-ai.sh (systemd unit)
    │               │
    │               ├──► llama-server (binary on USB)
    │               │       └──► GGUF models (files on USB)
    │               ├──► Claude Code (binary on USB)
    │               ├──► Codex CLI (binary on USB)
    │               └──► Aider (Python on USB)
    │
    ├──► Persistence .dat file
    │       └──► ai-keys.env (API credentials)
    │
    ├──► SystemRescue ISO (standalone)
    ├──► Clonezilla ISO (standalone)
    ├──► GParted Live ISO (standalone)
    ├──► Hiren's BootCD PE ISO (standalone)
    └──► Ubuntu Desktop ISO (standalone)
```

---

## 7. ventoy.json Configuration

```json
{
    "control": [
        { "VTOY_DEFAULT_SEARCH_ROOT": "/ISO" },
        { "VTOY_MENU_TIMEOUT": 0 }
    ],
    "persistence": [
        {
            "image": "/ISO/custom/ubuntu-24.04-ml-support.iso",
            "backend": "/persistence/ubuntu-ml-persist.dat",
            "autosel": 1,
            "timeout": 3
        }
    ],
    "menu_alias": [
        { "image": "/ISO/custom/ubuntu-24.04-ml-support.iso", "alias": "Ubuntu ML-Support 24.04 (AI + Rescue)" },
        { "image": "/ISO/rescue/systemrescue-11.03-amd64.iso", "alias": "SystemRescue 11.03" },
        { "image": "/ISO/rescue/clonezilla-live-3.2.0-amd64.iso", "alias": "Clonezilla 3.2.0 (Disk Imaging)" },
        { "image": "/ISO/rescue/gparted-live-1.8.0-2-amd64.iso", "alias": "GParted Live 1.8.0 (Partitioning)" },
        { "image": "/ISO/install/ubuntu-24.04.2-desktop-amd64.iso", "alias": "Ubuntu 24.04 Installer" },
        { "image": "/ISO/windows/hirens-bootcd-pe-x64.iso", "alias": "Hiren's BootCD PE (Windows Repair)" }
    ],
    "menu_class": [
        { "image": "/ISO/custom/", "class": "ubuntu" },
        { "image": "/ISO/rescue/systemrescue", "class": "archlinux" },
        { "image": "/ISO/rescue/clonezilla", "class": "clonezilla" },
        { "image": "/ISO/rescue/gparted", "class": "gparted" },
        { "image": "/ISO/install/", "class": "ubuntu" },
        { "image": "/ISO/windows/", "class": "windows" }
    ]
}
```

---

## 8. Key Technology Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Boot manager | Ventoy v1.1.10 (GPT + Secure Boot) | No-extraction ISO boot, persistence plugin, active development |
| ISO builder | Cubic (Ubuntu) | GUI chroot customization, QEMU testing, low learning curve |
| Base distro | Ubuntu 24.04 Server | Small footprint, fleet-aligned, Claude Code supported |
| Offline AI | llama.cpp (llama-server + llama-cli) | Zero dependencies, OpenAI-compatible API, ~25MB binary |
| Online AI | Claude Code + Aider | Most capable agentic tool + offline/online bridge |
| Primary model | Qwen2.5-Coder 7B Q4_K_M | Best code quality per GB for CPU inference |
| Fast model | Phi-4-mini Q4_K_M | Strong reasoning, runs on 8GB RAM systems |
| Data filesystem | exFAT | Cross-platform (Win/Mac/Linux), no 4GB limit |
| Persistence | Ventoy .dat file (ext4) | Simpler than separate partition, Ventoy-managed |
| Secret storage | Persistence overlay only | Separation from read-only squashfs |
