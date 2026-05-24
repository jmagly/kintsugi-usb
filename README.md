# Kintsugi USB

> *Rescue your fleet. Honor the break.*

AI-assisted rescue boot media for broken systems. A Ventoy-based live USB that boots almost any UEFI machine into a full Ubuntu desktop with rescue tooling, offline LLM inference, and host-specific recovery runbooks ready to hand to an AI agent.

Built for home-lab and small-fleet operators who need a "final level of recovery" — one USB that works whether the internet is up or down, whether you know what's broken or not, and whether the person holding it is the one who built the fleet or not.

## What's on it

- **Ventoy multi-boot loader** — pick your ISO at boot
- **Ubuntu 24.04 Desktop** with persistence — full desktop OS, state survives reboots
- **Rescue ISOs** — SystemRescue, Clonezilla, GParted Live, Memtest86+
- **Offline AI stack** — `llama.cpp` + Ollama, both available as local runtimes. No model weights ship with the image — you load your own via the `kintsugi-models` CLI either at build-time or at first boot on a trusted network. Start with the maintainer's tested recommendations in [`manifest/models-recommended.yaml`](manifest/models-recommended.yaml) or choose anything from the Ollama registry or HuggingFace.
- **Online AI stack** — `claude` / `codex` / `aider` CLIs for when you have internet
- **Recovery runbooks** — host-specific AGENT-CONTEXT and RUNBOOK packs an AI can consume directly
- **Fleet scripts** — inventory, drive health, SSH keychain, build tools
- **Toolkit/SDK** — this repo is also a toolkit. External builders can fork it to roll their own Kintsugi-like USB with their own model set, their own signing key, their own runbooks. See [`docs/toolkit-guide.md`](docs/toolkit-guide.md).

## About the name

See [docs/about-the-name.md](docs/about-the-name.md) for the etymology and philosophy behind *Kintsugi*.

## Documentation

| Doc | Purpose |
|-----|---------|
| [docs/about-the-name.md](docs/about-the-name.md) | Name origin, meaning, why it fits |
| [docs/requirements.md](docs/requirements.md) | Project requirements |
| [docs/architecture.md](docs/architecture.md) | Design: Ventoy + persistence + AI layer |
| [docs/build-guide.md](docs/build-guide.md) | Build a master USB from scratch |
| [docs/physical-test-guide.md](docs/physical-test-guide.md) | Testing on physical hardware |
| [docs/test-strategy.md](docs/test-strategy.md) | Test strategy |
| [docs/toolkit-guide.md](docs/toolkit-guide.md) | External-builder walkthrough: fork → choose models → build → sign → release |
| [docs/wizard-guide.md](docs/wizard-guide.md) | `kintsugi-build` wizard reference: prompts, flags, profile YAML schema, troubleshooting |
| [docs/update-strategy.md](docs/update-strategy.md) | Post-flash refresh model — `git pull` + `kintsugi-models pull`; reflash only for base-image changes |
| [docs/sanitization-checklist.md](docs/sanitization-checklist.md) | Pre-imaging secret scan + hygiene rules (consumed by `prep-master.sh`) |

**SDLC artifacts** ([`.aiwg/`](.aiwg/)): full intake, requirements, architecture (SAD + ADRs 001–006), risks, test strategy, iteration-1 plan, and [roadmap](.aiwg/planning/roadmap.md). Start at [`.aiwg/reports/construction-ready-brief.md`](.aiwg/reports/construction-ready-brief.md).

## Status

**v2026.5.0** — first tagged release. The wizard-first build toolkit is feature-complete: `./scripts/kintsugi-build` takes a fresh clone to a flashable, personalized `.img.zst` + sha256. Images are integrity-verified by sha256 over NFS-internal distribution; cryptographic signing (minisign) lands in a later release. See [`.aiwg/planning/roadmap.md`](.aiwg/planning/roadmap.md) for what's next.

Versioning follows **CalVer** (`YYYY.M.PATCH`).

## Issues

Issues are tracked in Gitea: https://git.integrolabs.net/roctinam/kintsugi-usb/issues

## License

**MIT** — see [LICENSE](LICENSE). The repository (scripts, docs, YAML manifests) is MIT-licensed. Bundled third-party binaries retain their own licenses — see `manifest/THIRD-PARTY-LICENSES.md` (iteration-1 deliverable). Model weights and agentic-framework binaries are user-fetched at build-time or boot-time and carry their own licenses; the user is responsible for reviewing those before use.

## Release signing & public key

> **Reserved — populated when v1.1 signing lands ([issue #19](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/19)).** v2026.5.0 ships sha256-only verification per [ADR-006 §D5](.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md). Until a key is published here, treat any file claiming to be `kintsugi.pub` as untrusted.

From v1.1, maintainer-produced release artifacts carry a [minisign](https://jedisct1.github.io/minisign/) (Ed25519) signature. Pin the maintainer's public key from this block — verifying against a key you fetched out-of-band (here, over HTTPS from the canonical repo) is what makes a signature meaningful:

```text
untrusted comment: kintsugi-usb release signing key (Ed25519)
<PUBKEY-PENDING-v1.1>
```

Verify a signed release with the bundled wrapper (it checks sha256 first, then the signature if a `.minisig` and `kintsugi.pub` are present):

```bash
./scripts/verify-image.sh kintsugi-vX.Y.Z.img.zst
```

Rotation history and the secret-key custody model are documented in [SECURITY.md](SECURITY.md#release-signing-key).

## Quick start for recipients

You received a Kintsugi USB image file. Here's how to use it.

### 1. Verify before you flash

Every release ships with a companion `.sha256` file. Check it:

```bash
# Linux / macOS
./scripts/verify-image.sh kintsugi-v2026.5.0.img.zst

# Equivalent manual check
( cd /path/to/download && sha256sum -c kintsugi-v2026.5.0.img.zst.sha256 )
```

If the checksum does not match, **do not flash**. Re-download or report via [SECURITY.md](SECURITY.md).

### 2. Flash to a USB

⚠ This destroys everything on the target device. Pick carefully.

```bash
# Guided flasher (recommended — safety checks for system disks, post-flash sanity check)
sudo ./scripts/flash-image.sh kintsugi-v2026.5.0.img.zst /dev/sdX

# Or directly with dd (if you already know what you're doing)
zstdcat kintsugi-v2026.5.0.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

`lsblk` or `sudo dmesg | tail` will help identify the correct `/dev/sdX` for your USB.

### 3. Boot and populate

1. Plug the flashed USB into the target machine, enter the BIOS/UEFI boot menu, select the USB.
2. On first boot, connect to a trusted network if you want AI features.
3. Pull your chosen local models:
   ```bash
   kintsugi-models list                 # see what's recommended
   kintsugi-models pull qwen3.5:4b      # or qwen3.5:9b on ≥16 GB hosts
   ```
4. Install any agentic CLIs you want on the drive:
   ```bash
   kintsugi-frameworks list
   sudo kintsugi-frameworks install aider
   ```
5. Check the AI stack is live:
   ```bash
   start-ai.sh --status
   ```

See [`docs/update-strategy.md`](docs/update-strategy.md) for keeping the USB current over time.

## Build your own

This repo is wizard-first: a single command walks you from fresh clone + blank USB to a flashable personalized image:

```bash
./scripts/kintsugi-build         # interactive TUI
./scripts/kintsugi-build --help  # all modes
```

Full external-builder walkthrough: [`docs/toolkit-guide.md`](docs/toolkit-guide.md). Wizard reference: [`docs/wizard-guide.md`](docs/wizard-guide.md).

Track open work in the [roadmap](.aiwg/planning/roadmap.md) and at https://git.integrolabs.net/roctinam/kintsugi-usb/issues
