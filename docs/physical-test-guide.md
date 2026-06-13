# Physical Test Guide: Kintsugi USB

Use this guide when plugging the drive into a test machine. Results can be saved
to persistence for later analysis.

---

## Quick Start

1. **Insert USB** into the test machine.
2. **Boot from USB** (F12/F2/Esc for the one-time boot menu; select the USB).
3. **Ventoy menu appears** — select **Kintsugi**.
4. **Kintsugi (Xubuntu / XFCE) live session boots** — choose the **Try / Live**
   option, NOT Install. Persistence is bound automatically (`ventoy.json`).
5. **Open a terminal** and continue below.

---

## First Boot Setup

The Kintsugi runtime scripts are installed **inside the image** and are on
`PATH` (no `/cdrom/...` hunting). On first boot you can run the setup helper:

```bash
first-boot-setup        # configures the live session / AI stack wiring
```

Rescue tooling (gdisk, testdisk, ddrescue, smartmontools, cryptsetup, etc.) and
the 32-bit runtime are already baked into the image — nothing to install.

---

## Run Tests

```bash
sudo usb-test-harness --full      # full suite (recommended on each new machine)
sudo usb-test-harness --quick     # quick boot + tool check
sudo usb-test-harness --ai-only   # AI stack only
```

### Where Results Go

1. **Live filesystem**: `/var/log/kintsugi/test-YYYYMMDD-HHMMSS/`
2. **Persistence** (survives reboot): copy results into your home or `/data`:

```bash
LATEST=$(ls -td /var/log/kintsugi/test-* | head -1)
cp -r "$LATEST" ~/    # persists via the Ventoy overlay
```

---

## Test the AI Stack

> Models are **not** baked into the image. Pull at least one first (needs network
> the first time; the weights then live in persistence at `/data/ollama/models`).

```bash
kintsugi-models pull qwen3.5:4b     # or: ollama pull qwen3.5:4b
```

### Offline (no internet)

```bash
start-ai                            # launches Ollama (ships stopped) + reports tools
ollama list                         # confirm the model is present
ollama run qwen3.5:4b "Write a bash one-liner to check disk SMART health"

# OpenAI-compatible endpoint (Ollama default port 11434):
curl -s http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.5:4b","messages":[{"role":"user","content":"hello"}]}' \
  | python3 -m json.tool
```

### Online (with internet) — agentic CLIs

Auth is **never baked**; sign in with your own credentials post-flash, per CLI:

```bash
claude            # follow the sign-in prompt (or the CLI's documented login)
claude --version
# codex / opencode / copilot / openclaw / omnius / aider are likewise available
```

---

## Persistence Test

```bash
echo "persist-test-$(hostname)-$(date -Iseconds)" > ~/persist-marker.txt
sudo apt install -y cowsay          # install a test package into the overlay
sudo reboot

# After reboot, re-enter the Kintsugi live session and verify:
cat ~/persist-marker.txt            # should show previous content
cowsay "persistence works"          # should still be installed
ollama list                         # pulled model should still be present
```

---

## What to Bring Back

1. **Test results** — from `/var/log/kintsugi/` (and whatever you copied to persistence).
2. **Error screenshots** — if boot fails, photograph the screen.
3. **Notes on**:
   - Did the Ventoy menu appear?
   - Did Secure Boot prompt for MOK enrollment?
   - Did the **Kintsugi (Xubuntu) live session** boot successfully?
   - Approx boot time?
   - Did persistence survive a reboot (marker file + pulled model)?
   - Did the AI stack run (Ollama offline; agentic CLIs online after sign-in)?

---

## Troubleshooting Boot Issues

### Ventoy menu doesn't appear
- Check BIOS boot order — USB must be first.
- Try a different USB port (USB 3.0 blue port preferred).
- Temporarily disable Secure Boot in BIOS.

### Secure Boot blocks Ventoy
- Ventoy shows a MOK enrollment screen on first boot.
- Select "Enroll key" → "Continue" → reboot; the second boot works with Secure
  Boot enabled.

### Live session is slow to start
- Normal for USB — the session loads from USB 3 into RAM.
- First boot is slowest (~60–90 s); subsequent boots with persistence are faster.

### USB data partition not found
```bash
lsblk -o NAME,LABEL,FSTYPE,MOUNTPOINT
blkid | grep -i KINTSUGI
sudo mount /dev/sdXN /mnt/ventoy-data   # replace sdXN (the exFAT KINTSUGI partition)
```

---

## Per-Host Test Checklist

### ref-host-1 (i9-14900KF, 64GB RAM)
- [ ] UEFI boot from Ventoy menu
- [ ] Secure Boot MOK enrollment (if prompted)
- [ ] Kintsugi (Xubuntu) live session boots (Try / Live)
- [ ] `first-boot-setup` completes
- [ ] `usb-test-harness --full` passes
- [ ] A user-pulled model loads via Ollama (e.g. a 9B on 64 GB RAM)
- [ ] Ollama responds to an API query
- [ ] An agentic CLI works after sign-in (if internet available)
- [ ] Persistence survives reboot (marker + model)

### ref-host-2 (i7-12700H, 32GB RAM)
- [ ] UEFI boot from Ventoy menu
- [ ] Secure Boot MOK enrollment (if prompted)
- [ ] Kintsugi (Xubuntu) live session boots
- [ ] `first-boot-setup` completes
- [ ] `usb-test-harness --full` passes
- [ ] A user-pulled model loads via Ollama
- [ ] Persistence survives reboot

### ref-host-3 (i7-8700K, 32GB RAM)
- [ ] UEFI boot
- [ ] `usb-test-harness --quick` passes
- [ ] Ollama inference works (with a pulled model)

---

## File Locations on the Drive

```
Data partition (exFAT, label: KINTSUGI)
├── kintsugi-v2026.5.0.iso        the single bootable Kintsugi system
├── README.txt                    plain-language recipient guide
├── ventoy/
│   ├── ventoy.json               persistence plugin config
│   └── persistence/
│       └── kintsugi.dat          32 GiB ext4 persistence (bound to the ISO)
└── (optional) systemrescue-*.iso / clonezilla-*.iso / gparted-*.iso / memtest86plus-*.iso

Inside persistence (kintsugi.dat, mounted at runtime as the RW overlay)
├── /data/ollama/models           user-loaded model weights (post-flash)
├── agentic-CLI auth / tokens      (post-flash sign-in)
└── ~/ home, installed packages, shell history, custom scripts

Inside the Kintsugi ISO squashfs (read-only)
└── Xubuntu Minimal + XFCE, rescue tools, i386 runtime, Ollama, agentic CLIs,
    and the Kintsugi scripts on PATH (start-ai, first-boot-setup,
    usb-test-harness, kintsugi-models/-frameworks/-install-hermes, kintsugi-eject)
```
