# System Architecture: Kintsugi USB

**Project**: Kintsugi USB
**Version**: 2.0 (reconciled 2026-06-13 to the current build/design)
**Phase**: Construction / first release builds (#37)

> **Authority note.** The formal, baselined architecture reference is
> `.aiwg/architecture/software-architecture-doc.md`, governed by the ADRs in
> `.aiwg/architecture/`. This document is the **plain-language architecture
> overview** and is kept in sync with the current design:
>
> - **Build approach** — [ADR-008](../.aiwg/architecture/adr-008-build-tooling-remaster-stock-iso.md):
>   the custom ISO is produced by **remastering the stock Xubuntu Minimal 24.04
>   ISO** with `livefs-editor` (squashfs repacked with xz), **not** built from
>   scratch (ADR-007 `live-build` is superseded) and **not** a custom
>   "ML-support" image assembled from Ubuntu Server + a desktop layer.
> - **Models** — [ADR-005](../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md):
>   the offline runtime is **Ollama** (with `llama.cpp` available); **no model
>   weights are baked** into the read-only image — they are user-loaded into
>   persistence (`/data/ollama/models`) post-flash.
> - **Agentic CLIs / auth** — [ADR-006](../.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md):
>   the agentic CLIs are pre-installed **inside the squashfs**; sign-in is a
>   post-flash user step (never baked).

---

## 1. System Context

```
                    ┌─────────────────────────────┐
                    │     Target Host System       │
                    │  (any x86_64 UEFI/BIOS PC)   │
                    │                              │
                    │   ┌─────────────────────┐    │
                    │   │   USB Boot Device    │    │
                    │   │   (≈59 GB USB 3.x)   │    │
                    │   │                      │    │
                    │   │  Ventoy Bootloader   │    │
                    │   │        │             │    │
                    │   │   ┌────┴────┐        │    │
                    │   │   │ ISO Menu │       │    │
                    │   │   └────┬────┘        │    │
                    │   │        │             │    │
                    │   │  ┌─────┴───────────┐ │    │
                    │   │  │ Kintsugi ISO    │ │    │
                    │   │  │ (Xubuntu + AI + │ │    │
                    │   │  │  rescue tools)  │ │    │
                    │   │  └─────┬───────────┘ │    │
                    │   │        │             │    │
                    │   └────────┼─────────────┘    │
                    │            │                  │
                    │     ┌──────┴──────┐           │
                    │     │ Host Hardware│          │
                    │     │ CPU, RAM,    │          │
                    │     │ Disks, NIC   │          │
                    │     └──────┬──────┘           │
                    └────────────┼──────────────────┘
                                 │
                    ┌────────────┴───────────────┐
                    │   Network (when available)  │
                    │   Anthropic / OpenAI / etc. │
                    │   APIs for the agentic CLIs │
                    │   (sign-in is post-flash)   │
                    └─────────────────────────────┘
```

The drive is designed to be useful **offline first**: Ollama + a user-loaded
local model and the rescue toolchain need no network. Network, when present,
adds the online agentic CLIs (Claude Code, Codex, etc.) once the user signs in.

---

## 2. USB Physical Layout

Ventoy owns the drive's partition table and bootloader. `make-ventoy-image.sh`
produces a GPT image with the standard Ventoy two-partition layout:

```
 Partition          Size      Filesystem  Label      Purpose
 ────────────────── ───────── ─────────── ────────── ─────────────────────────
 sdX1               ≈39 GB    exFAT       KINTSUGI   ISOs + persistence + data
 sdX2               32 MB     FAT16       VTOYEFI    Ventoy UEFI bootloader
```

Ventoy installs its own BIOS (MBR) and UEFI boot code; there is no separate
hand-made BIOS-boot partition. The exFAT data partition is what the recipient
sees when they plug the drive into another machine.

### Data partition (exFAT `KINTSUGI`) layout

```
/
├── kintsugi-v2026.5.0.iso          ← the single remastered Kintsugi ISO (~5 GB)
│                                      (Xubuntu Minimal 24.04.4 + XFCE, rescue
│                                       tools, i386 runtime, Ollama, agentic CLIs)
├── README.txt                      ← plain-language guide for the recipient
│
├── ventoy/
│   ├── ventoy.json                 ← persistence plugin config (see §7)
│   └── persistence/
│       └── kintsugi.dat            ← 32 GiB ext4 persistence, bound to the ISO
│
└── (optional rescue ISOs, dropped alongside — catalog in progress, #35)
    ├── systemrescue-*.iso
    ├── clonezilla-live-*.iso
    ├── gparted-live-*.iso
    └── memtest86plus-*.iso
```

**What is NOT on the data partition** (a change from earlier designs):

- **No baked model weights.** GGUF/Ollama model blobs are *not* shipped. They
  live in persistence at `/data/ollama/models`, loaded post-flash via
  `kintsugi-models` / `ollama pull` (ADR-005).
- **No loose tool binaries.** Ollama, `llama.cpp`, and the agentic CLIs are
  installed *inside the remastered squashfs* (the Kintsugi ISO), not copied as
  standalone binaries onto the data partition.
- **No secrets.** API keys, SSH keys, and tokens never ship on the drive; auth
  is a post-flash user step and lives only in persistence.

---

## 3. Boot Flow

```
Power On
  │
  ├─[UEFI]───────────────────────────────────────────────┐
  │  ├─[Secure Boot ON]──► Ventoy Shim ──► MOK enrollment │
  │  │                          (one-time, then reboot)   │
  │  └─[Secure Boot OFF]─► Ventoy GRUB2 (EFI)             │
  │                              │                         │
  ├─[Legacy BIOS]──► Ventoy MBR ─► GRUB2                  │
  │                              │                         │
  │                     ┌────────┴─────────┐               │
  │                     │  Ventoy ISO Menu │               │
  │                     ├──────────────────┤               │
  │                     │ • Kintsugi (Xubuntu + AI + rescue)│
  │                     │ • SystemRescue   │  (optional,    │
  │                     │ • Clonezilla     │   per #35      │
  │                     │ • GParted Live   │   catalog)     │
  │                     │ • Memtest86+     │               │
  │                     └────────┬─────────┘               │
  │                              │ select "Kintsugi"        │
  │                     ┌────────┴─────────┐               │
  │                     │ Ventoy binds the │               │
  │                     │ persistence .dat │               │
  │                     │ (ventoy.json)    │               │
  │                     └────────┬─────────┘               │
  │                     ┌────────┴─────────┐               │
  │                     │ casper live boot │               │
  │                     │ squashfs (RO) +  │               │
  │                     │ persistence (RW) │               │
  │                     └────────┬─────────┘               │
  │                     ┌────────┴─────────┐               │
  │                     │ Xubuntu (XFCE)   │               │
  │                     │ live desktop     │               │
  │                     └────────┬─────────┘               │
  │                     ┌────────┴─────────┐               │
  │                     │ first-boot-setup │               │
  │                     │ + start-ai (on   │               │
  │                     │ demand)          │               │
  │                     └──────────────────┘               │
```

The inner Kintsugi ISO is itself UEFI+BIOS bootable (its stock GRUB/isolinux
boot structure is preserved by the remaster, per ADR-008), so Ventoy chainloads
it reliably in both firmware modes.

---

## 4. AI Stack Architecture

> Authoritative detail: `.aiwg/architecture/software-architecture-doc.md` §4 and
> [ADR-005](../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md).

```
┌──────────────────────────────────────────────────────────┐
│                     AI Stack (in the squashfs)            │
│                                                           │
│  start-ai.sh — manifest-driven launcher                   │
│    • discovers user-loaded models in /data/ollama/models  │
│    • starts Ollama on demand (service ships disabled)     │
│    • reports which agentic CLIs are available             │
│                                                           │
│  ┌─────────────┐   ┌──────────────┐   ┌────────────────┐ │
│  │ Offline     │   │ Bridge       │   │ Online         │ │
│  │ runtime     │   │              │   │ (post sign-in) │ │
│  │             │   │ aider        │   │ claude-code    │ │
│  │ Ollama      │   │ (local or    │   │ codex          │ │
│  │ (+llama.cpp │   │  remote API) │   │ opencode       │ │
│  │  if present)│   │              │   │ copilot        │ │
│  │             │   │              │   │ openclaw       │ │
│  │ models from │   │              │   │ omnius         │ │
│  │ persistence │   │              │   │ (+hermes on    │ │
│  │             │   │              │   │  demand)       │ │
│  └──────┬──────┘   └──────────────┘   └────────────────┘ │
│         │                                                 │
│         ▼                                                 │
│   Ollama API (OpenAI-compatible) for local inference      │
└──────────────────────────────────────────────────────────┘
```

Key points (current design):

- **Ollama is the offline runtime**, pre-installed in the squashfs but shipped
  **stopped and not-enabled**; `start-ai.sh` launches it on demand. `llama.cpp`
  is used if present but is not the primary path.
- **Models are user-loaded post-flash** into persistence (`/data/ollama/models`)
  via `kintsugi-models` / `ollama pull`. The image ships **no weights** and does
  **no RAM-based auto-select of a baked GGUF** (the old `start-ai.sh` pseudocode
  is retired).
- **Agentic CLIs** (claude-code, codex, opencode, copilot, openclaw, omnius,
  aider) are pre-installed; **Hermes** installs on demand via
  `kintsugi-install-hermes`. **Auth is never baked** — the user signs in
  post-flash (ADR-006).

---

## 5. Security Architecture

```
┌────────────────────────────────────────────┐
│            Security Boundaries              │
│                                             │
│  squashfs (READ-ONLY, inside the ISO)       │
│    • OS + XFCE + rescue tools               │
│    • Ollama + agentic CLIs (binaries only)  │
│    • NO secrets, NO API keys, NO SSH keys   │
│    • NO model weights                       │
│                                             │
│  Persistence overlay (READ-WRITE, ext4)     │
│    • /data/ollama/models (user-loaded)      │
│    • agentic CLI auth / tokens (post-flash) │
│    • ~/.ssh, shell history, custom scripts  │
│    • Optional LUKS for physical security    │
│                                             │
│  Data partition (exFAT KINTSUGI)            │
│    • ISO(s), ventoy config, README          │
│    • NO secrets (no UNIX permissions)       │
└────────────────────────────────────────────┘
```

**Key principles** (unchanged):

- Secrets exist only in the persistence overlay (ext4, proper UNIX permissions),
  never in the read-only squashfs and never on the exFAT data partition.
- API keys / agentic-CLI auth are provided at runtime by the user post-flash,
  never hardcoded or baked into the image.
- No model weights ship in the read-only image (ADR-005).
- Optional LUKS on persistence protects data at rest if the drive is lost.

---

## 6. Component Dependencies

```
Ventoy bootloader (UEFI + BIOS)
  │
  ├──► Kintsugi ISO  (remastered stock Xubuntu Minimal 24.04.4)
  │       ├──► Xubuntu Minimal base + XFCE desktop session (casper live)
  │       ├──► Rescue tool packages (apt: gdisk, testdisk, ddrescue, …)
  │       ├──► 32-bit (i386) runtime: libc6:i386 for legacy vendor unlockers (#45)
  │       ├──► Ollama (+ llama.cpp if present) — offline runtime, ships stopped
  │       ├──► Agentic CLIs (claude-code/codex/opencode/copilot/openclaw/omnius/aider)
  │       ├──► Removable-media desktop UX (udiskie/udisks2, eject helper)
  │       └──► Kintsugi runtime scripts (start-ai, first-boot-setup,
  │              kintsugi-models/-frameworks/-install-hermes, kintsugi-eject)
  │
  ├──► ventoy.json  ──► binds persistence to the Kintsugi ISO
  │       └──► kintsugi.dat (ext4 persistence)
  │              ├──► /data/ollama/models  (user-loaded weights, post-flash)
  │              └──► agentic-CLI auth + user state (post-flash)
  │
  └──► (optional) SystemRescue / Clonezilla / GParted / Memtest86+ ISOs (#35)
```

The base distro is **Xubuntu Minimal 24.04.4 (XFCE)** — a desktop edition with
the XFCE session already present — not "Ubuntu Server + a desktop layer." There
is no separate custom "ML-support" image and no standalone Ubuntu Desktop
installer ISO in the design; the single Kintsugi ISO is the bootable system.

---

## 7. ventoy.json Configuration

The persistence plugin binds the `kintsugi.dat` backend to the Kintsugi ISO so
the live session is read-write across reboots:

```json
{
    "persistence": [
        {
            "image": "/kintsugi-v2026.5.0.iso",
            "backend": "/ventoy/persistence/kintsugi.dat"
        }
    ]
}
```

`make-ventoy-image.sh` writes this file; the exact ISO filename matches the
image assembled for the build. Optional rescue ISOs added to the data partition
(per #35) appear in the Ventoy menu automatically — no `ventoy.json` entry
required for plain bootable ISOs.

---

## 8. Key Technology Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Boot manager | Ventoy (GPT, UEFI + BIOS, Secure Boot capable) | No-extraction ISO boot, persistence plugin, active development |
| ISO builder | Remaster stock **Xubuntu Minimal** ISO via `livefs-editor` ([ADR-008](../.aiwg/architecture/adr-008-build-tooling-remaster-stock-iso.md)) | Starts from a known-good UEFI+BIOS-bootable image; scriptable/non-interactive; preserves the casper live session. Supersedes ADR-007 `live-build`. |
| Base distro | **Xubuntu Minimal 24.04.4 LTS (XFCE)** | Lightweight desktop edition; XFCE session present; small footprint for a rescue drive |
| Offline AI | **Ollama** (with `llama.cpp` available) | OpenAI-compatible local API; on-demand start; ships disabled |
| Models | **User-loaded post-flash** into persistence ([ADR-005](../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md)) | No weights baked into the read-only image; operator chooses the model set |
| Agentic CLIs | claude-code / codex / opencode / copilot / openclaw / omnius / aider (+ Hermes on demand) | Pre-installed in the squashfs; auth is a post-flash user step (ADR-006) |
| Legacy-device support | 32-bit (`i386`) runtime baked in (#45) | Runs legacy vendor unlockers (e.g. IronKey) offline, out of the box |
| Data filesystem | exFAT | Cross-platform (Win/Mac/Linux), no 4 GB file limit |
| Persistence | Ventoy `.dat` file (ext4) | Ventoy-managed; simpler than a separate partition |
| Secret storage | Persistence overlay only | Separation from the read-only squashfs; never on exFAT |
