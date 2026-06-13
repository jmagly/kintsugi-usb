# Build Guide: Kintsugi USB (manual Ventoy assembly)

How to assemble a Kintsugi drive from a built Kintsugi ISO — by hand.

> **Scope — manual / advanced reference.** The **supported path** is the toolkit:
> `./scripts/kintsugi-build` builds the custom ISO by **remastering the stock
> Xubuntu Minimal 24.04 ISO** ([ADR-008](../.aiwg/architecture/adr-008-build-tooling-remaster-stock-iso.md),
> supersedes live-build) and auto-chains `scripts/usb-toolkit/make-ventoy-image.sh`
> ([#42](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/42)), which
> automates everything below (Ventoy install, layout, persistence, ISO placement).
> Start with [`toolkit-guide.md`](toolkit-guide.md). Keep this guide for the
> underlying Ventoy mechanics and one-off manual builds. Default rescue bundle +
> pinned versions/sha256 are tracked in `manifest/rescue-isos-recommended.yaml`
> ([#35](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/35)).
>
> **What this drive carries (current design):** a *single* remastered **Kintsugi
> ISO** (Xubuntu Minimal 24.04.4 + XFCE, with the rescue tools, the 32-bit
> runtime, Ollama, and the agentic CLIs already inside its squashfs), plus a
> Ventoy persistence file, plus *optionally* a few stock rescue ISOs. There are
> **no hand-placed model weights or tool binaries** — the AI stack is baked into
> the Kintsugi ISO at remaster time, and **models are loaded post-flash** into
> persistence (`/data/ollama/models`, ADR-005).

---

## Prerequisites

- 59 GB+ USB 3.0 flash drive
- Linux host (Ubuntu 24.04 recommended) with internet access
- A built **Kintsugi ISO** — produce it first with
  `sudo scripts/usb-toolkit/make-remaster-iso.sh --base <stock-xubuntu-minimal.iso> --with-agentic --with-ai-stack`
  (see [`toolkit-guide.md`](toolkit-guide.md))
- ~10 GB free disk space (more if you also stage rescue ISOs)

## Step 1: Install Ventoy

```bash
cd /tmp && curl -sL "https://github.com/ventoy/Ventoy/releases/download/v1.1.05/ventoy-1.1.05-linux.tar.gz" -o ventoy.tar.gz
tar xzf ventoy.tar.gz && cd ventoy-1.1.05

# Install with GPT + Secure Boot support.
# WARNING: this wipes /dev/sdX — confirm the correct device (check the serial!).
echo -e "y\ny" | sudo bash Ventoy2Disk.sh -I -g -s /dev/sdX
```

Ventoy creates the two-partition layout itself: `sdX1` (exFAT data partition) and
`sdX2` (`VTOYEFI`, the 32 MB UEFI bootloader). You only touch `sdX1`.

## Step 2: Mount the data partition

```bash
sudo mkdir -p /mnt/ventoy
sudo mount /dev/sdX1 /mnt/ventoy
sudo mkdir -p /mnt/ventoy/ventoy/persistence
```

No elaborate directory tree is needed — Ventoy boots any `.iso` it finds on the
data partition. The Kintsugi ISO sits at the partition root.

## Step 3: Place the Kintsugi ISO (and optional rescue ISOs)

```bash
# The single bootable Kintsugi system (from make-remaster-iso.sh):
sudo cp ~/kintsugi-builds/dist/kintsugi-v2026.5.0.iso /mnt/ventoy/

# OPTIONAL: stock rescue ISOs — Ventoy lists them in the boot menu automatically.
# Pin versions/sha256 per manifest/rescue-isos-recommended.yaml (#35).
# sudo cp systemrescue-*.iso clonezilla-live-*.iso gparted-live-*.iso memtest86plus-*.iso /mnt/ventoy/
```

> There is **no** custom "ML-support" ISO and **no** standalone Ubuntu Desktop
> installer in the current design — the Kintsugi ISO is the bootable system.

## Step 4: AI tools and models — nothing to hand-place

The offline runtime (Ollama, optionally `llama.cpp`) and the agentic CLIs
(claude-code, codex, opencode, copilot, openclaw, omnius, aider) are already
**inside the Kintsugi ISO's squashfs** — installed at remaster time by
`make-remaster-iso.sh --with-ai-stack --with-agentic`. Do **not** copy llama
binaries, GGUF files, or CLI binaries onto the drive.

**Model weights are loaded post-flash**, not baked: after first boot, run
`kintsugi-models pull <model>` (or `ollama pull`) to populate
`/data/ollama/models` in persistence (ADR-005).

## Step 5: Create the persistence image

```bash
cd /tmp/ventoy-1.1.05
# 32 GiB default (per #34; size to your stick). make-ventoy-image.sh exposes this
# as --persistence-size.
sudo bash CreatePersistentImg.sh -s 32768 -l casper-rw -o /mnt/ventoy/ventoy/persistence/kintsugi.dat
```

## Step 6: Configure Ventoy persistence

Create `/mnt/ventoy/ventoy/ventoy.json` binding the persistence backend to the
Kintsugi ISO (match the ISO filename you copied in Step 3):

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

## Step 7: Friendly label + on-drive README (recommended)

So recipients aren't confused by the default `Ventoy` label, give the data
partition a friendly label and drop a plain-text README at its root — exactly
what `make-ventoy-image.sh` does automatically:

```bash
sudo cp config/drive-readme.txt /mnt/ventoy/README.txt
sudo umount /mnt/ventoy
sudo exfatlabel /dev/sdX1 KINTSUGI          # partition must be unmounted
```

## Step 8: Sync and unmount

```bash
sudo sync
sudo umount /mnt/ventoy 2>/dev/null || true
```

## First Use

1. Boot from the USB on the target machine (one-time boot menu key).
2. Select **Kintsugi** from the Ventoy menu.
3. Choose the **Try / Live** session (NOT Install).
4. Persistence is bound automatically via `ventoy.json` — your changes,
   downloaded models, and sign-ins survive reboots.
5. The Kintsugi runtime scripts are on `PATH` (installed in the squashfs). Pull a
   model and start the AI stack:

   ```bash
   kintsugi-models pull qwen3.5:4b     # populates /data/ollama/models (persistence)
   start-ai                            # launches Ollama + reports available CLIs
   ```

6. Sign in to the agentic CLIs with your own credentials (post-flash; never
   baked).
