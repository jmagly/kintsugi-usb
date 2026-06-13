<div align="center">

# Kintsugi USB

**Rescue your fleet. Honor the break.**

AI-assisted rescue boot media for broken systems. A Ventoy multi-boot USB on Xubuntu Minimal 24.04 (XFCE, with persistence) carrying rescue ISOs, an **offline LLM stack** (Ollama + llama.cpp), **seven pre-installed agentic CLIs**, and host-specific recovery runbooks ready to hand to an AI agent — built from a fresh clone with one command.

```bash
./scripts/kintsugi-build        # fresh clone + blank USB → a flashable, personalized .img.zst
```

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Version](https://img.shields.io/badge/version-2026.5.0--pre-orange?style=flat-square)](.aiwg/planning/roadmap.md)
[![Boot](https://img.shields.io/badge/boot-UEFI%20%2B%20BIOS-brightgreen?style=flat-square)](#whats-on-it)
[![Base](https://img.shields.io/badge/base-Xubuntu%20Minimal%2024.04-0E63B6?style=flat-square&logo=ubuntu&logoColor=white)](#whats-on-it)
[![Offline AI](https://img.shields.io/badge/offline%20AI-Ollama%20%2B%20llama.cpp-blueviolet?style=flat-square)](#whats-on-it)

[**What's on it**](#whats-on-it) · [**Quick Start**](#quick-start-for-recipients) · [**Build Your Own**](#build-your-own) · [**Documentation**](#documentation) · [**Issues**](#issues)

</div>

---

## What Kintsugi USB Is

A "final level of recovery" for home-lab and small-fleet operators: **one USB that works whether the internet is up or down, whether you know what's broken or not, and whether the person holding it built the fleet or not.** It boots almost any UEFI or BIOS machine into a lightweight Xubuntu (XFCE) desktop with rescue tooling and a local AI assistant that can read host-specific runbooks and help drive the repair.

This repo is also the **toolkit** that produces the drive: a wizard remasters a stock Xubuntu Minimal ISO into a personalized, flashable image. Fork it to roll your own Kintsugi-like USB with your own model set, agentic tools, runbooks, and (from v1.1) signing key.

## What's on it

- **Ventoy multi-boot loader** — UEFI + BIOS; pick your ISO at boot, with persistence so state survives reboots.
- **Xubuntu Minimal 24.04.4 (XFCE)** — lightweight desktop OS for hands-on rescue.
- **Rescue ISOs** — SystemRescue, Clonezilla, GParted Live, Memtest86+ *(catalog in progress, [#35](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/35))*.
- **Legacy encrypted-drive unlock** — the 32-bit (`i386`) runtime needed by legacy vendor unlockers is baked in, so older Imation/IronKey secure USB drives unlock **offline, out of the box**. See [`docs/legacy-device-unlock.md`](docs/legacy-device-unlock.md).
- **Offline AI stack** — Ollama (with `llama.cpp` available) as a local runtime, pre-installed and wired to a persistence-backed model store (`/data/ollama/models`) so models pulled in the field survive reboots. No model weights ship in the read-only image by default ([ADR-005](.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md)); the operator loads their own via `kintsugi-models` / `ollama pull`, or pre-loads them into the drive's persistence at build time. Start from [`manifest/models-recommended.yaml`](manifest/models-recommended.yaml).
- **Agentic CLIs (pre-installed)** — Claude Code, Codex, OpenCode, Copilot, OpenClaw, omnius, and Aider, baked in and offline-available. You sign in with your own credentials post-flash — no auth is ever baked. Add or manage more via `kintsugi-frameworks`; the heavier Hermes agent installs on demand via `kintsugi-install-hermes`.
- **Recovery runbooks** — host-specific AGENT-CONTEXT and RUNBOOK packs an AI can consume directly (operator-provided from the fleet repos; not in this public repo).
- **Fleet scripts** — inventory, drive health, build/imaging pipeline, and the `kintsugi-build` wizard.

## How it's built

`kintsugi-build` **remasters the stock Xubuntu Minimal 24.04 ISO** ([ADR-008](.aiwg/architecture/adr-008-build-tooling-remaster-stock-iso.md)) — starting from a known-good UEFI+BIOS-bootable image and injecting the rescue tools, agentic CLIs, and offline AI stack into the squashfs — then assembles a Ventoy disk image with persistence and packages a distributable `.img.zst`. The whole pipeline runs unattended from one command.

## Quick Start for recipients

You received a Kintsugi USB image. Here's how to use it.

### 1. Verify before you flash

Every release ships a companion `.sha256`. Check it — if it does not match, **do not flash** (re-download or report via [SECURITY.md](SECURITY.md)):

```bash
./scripts/verify-image.sh kintsugi-v2026.5.0.img.zst
# manual equivalent:
( cd /path/to/download && sha256sum -c kintsugi-v2026.5.0.img.zst.sha256 )
```

### 2. Flash to a USB

> ⚠ This destroys everything on the target device. Identify it with `lsblk` and pick carefully.

```bash
# Guided flasher (recommended — guards against system disks, verifies after)
sudo ./scripts/flash-image.sh kintsugi-v2026.5.0.img.zst /dev/sdX

# Or directly:
zstdcat kintsugi-v2026.5.0.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync && sync
```

### 3. Boot and use

1. Plug in the USB, enter the boot menu, select it, and pick the Kintsugi entry in the Ventoy menu.
2. The agentic CLIs are already installed — sign in with your own credentials when you have a network.
3. Local inference (offline):
   ```bash
   start-ai.sh                       # start Ollama against the persistence model store
   ollama list                       # models pre-loaded on the drive (if any)
   kintsugi-models pull qwen3.5:4b   # or pull more on a trusted network
   ```

See [`docs/update-strategy.md`](docs/update-strategy.md) for keeping the USB current over time.

## Build Your Own

Wizard-first: one command walks you from fresh clone + blank USB to a flashable personalized image.

```bash
./scripts/kintsugi-build          # interactive TUI (defaults give a working build)
./scripts/kintsugi-build --help   # all modes (--from-profile, --dry-run, …)
```

Full external-builder walkthrough: [`docs/toolkit-guide.md`](docs/toolkit-guide.md). Per-screen reference: [`docs/wizard-guide.md`](docs/wizard-guide.md).

## Documentation

| Doc | Purpose |
|-----|---------|
| [docs/about-the-name.md](docs/about-the-name.md) | Name origin, meaning, why it fits |
| [docs/requirements.md](docs/requirements.md) | Project requirements |
| [docs/architecture.md](docs/architecture.md) | Design: Ventoy + persistence + AI layer |
| [docs/build-guide.md](docs/build-guide.md) | Manual / reference build (Ventoy mechanics, stock-ISO acquisition) |
| [docs/wizard-guide.md](docs/wizard-guide.md) | `kintsugi-build` reference: prompts, flags, profile schema, troubleshooting |
| [docs/toolkit-guide.md](docs/toolkit-guide.md) | External-builder walkthrough: fork → choose models/tools → build → release |
| [docs/legacy-device-unlock.md](docs/legacy-device-unlock.md) | Unlocking legacy IronKey / Imation encrypted USB drives (offline, 32-bit runtime) |
| [docs/physical-test-guide.md](docs/physical-test-guide.md) | Testing on physical hardware |
| [docs/test-strategy.md](docs/test-strategy.md) | Test strategy |
| [docs/update-strategy.md](docs/update-strategy.md) | Post-flash refresh model — `git pull` + `ollama pull`; reflash only for base-image changes |
| [docs/sanitization-checklist.md](docs/sanitization-checklist.md) | Pre-imaging secret scan + hygiene rules |

**SDLC artifacts** ([`.aiwg/`](.aiwg/)): intake, requirements, architecture (SAD + ADRs 001–008), risks, test strategy, iteration plan, and the [roadmap](.aiwg/planning/roadmap.md). Start at [`.aiwg/reports/construction-ready-brief.md`](.aiwg/reports/construction-ready-brief.md).

See [docs/about-the-name.md](docs/about-the-name.md) for the etymology and philosophy behind *Kintsugi*.

## Status

**v2026.5.0 — pre-release.** The wizard-first toolkit auto-chains end-to-end ([#36](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/36)): `./scripts/kintsugi-build` takes a fresh clone to a flashable `.img.zst` + sha256 via the ADR-008 remaster pipeline, with the offline AI stack and agentic CLIs baked in. The tag is **gated on the hardware-acceptance round-trip** ([#37](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/37)) — build → flash → boot → persistence verified on real hardware. See the [roadmap](.aiwg/planning/roadmap.md) for what's next.

Versioning follows **CalVer** (`YYYY.M.PATCH`). Distribution is sha256-verified; cryptographic signing (minisign) lands in v1.1 ([#19](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/19)).

## Release signing & public key

> **Reserved — populated when v1.1 signing lands ([#19](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/19)).** v2026.5.0 ships sha256-only verification per [ADR-006 §D5](.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md). Until a key is published here, treat any file claiming to be `kintsugi.pub` as untrusted.

From v1.1, maintainer-produced artifacts carry a [minisign](https://jedisct1.github.io/minisign/) (Ed25519) signature; pin the key from this block (verifying against a key fetched out-of-band is what makes a signature meaningful):

```text
untrusted comment: kintsugi-usb release signing key (Ed25519)
<PUBKEY-PENDING-v1.1>
```

Rotation history and the secret-key custody model are documented in [SECURITY.md](SECURITY.md#release-signing-key).

## Issues

Tracked in Gitea: https://git.integrolabs.net/roctinam/kintsugi-usb/issues

## License

**MIT** — see [LICENSE](LICENSE). The repository (scripts, docs, YAML manifests) is MIT-licensed. Bundled third-party binaries retain their own licenses — see [`manifest/THIRD-PARTY-LICENSES.md`](manifest/THIRD-PARTY-LICENSES.md). Model weights and agentic-framework binaries are user-fetched at build- or boot-time and carry their own licenses; the user is responsible for reviewing those before use.
