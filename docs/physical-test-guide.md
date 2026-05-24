# Physical Test Guide: USB Toolkit

Use this guide when plugging the USB into a test machine. Results are stored on the USB for later analysis.

---

## Quick Start

1. **Insert USB** into test machine
2. **Boot from USB** (F12/F2 for boot menu, select USB)
3. **Ventoy menu appears** — select "Ubuntu ML-Support 24.04"
4. **Persistence prompt** — select "Yes" (should auto-select in 3s)
5. **Ubuntu boots** — "Try Ubuntu" at the installer prompt (NOT Install)
6. **Open terminal** and run setup

---

## First Boot Setup

On the FIRST boot, run the setup script to install rescue tools and configure AI:

```bash
# Find and run the setup script from USB data partition
# The USB data partition is typically at /cdrom or /isodevice
sudo bash /cdrom/tools/bin/first-boot-setup.sh

# If /cdrom doesn't work, try finding it:
find /media /cdrom /isodevice -name "first-boot-setup.sh" 2>/dev/null
```

This installs ~500MB of rescue tools into the persistence layer. Takes ~5-10 minutes.

---

## Run Tests

After setup, run the test harness:

```bash
# Full test suite (recommended for first test on each machine)
sudo usb-test-harness.sh --full

# Quick boot + tool check only
sudo usb-test-harness.sh --quick

# AI stack only
sudo usb-test-harness.sh --ai-only
```

### Where Results Go

Results are stored in TWO locations:
1. **Live filesystem**: `/var/log/usb-toolkit/test-YYYYMMDD-HHMMSS/`
2. **USB data partition** (persists): The script auto-copies to USB if writable

To manually copy results to USB:
```bash
# Find the latest test results
LATEST=$(ls -td /var/log/usb-toolkit/test-* | head -1)

# Copy to USB data partition
USB=$(find /media /cdrom /isodevice -name "test-results" -type d 2>/dev/null | head -1)
cp -r "$LATEST" "$USB/"
```

---

## Test the AI Stack

### Offline (no internet)

```bash
# Start AI stack (auto-detects offline mode)
sudo start-ai.sh

# Interactive chat with local model
llama-cli -m /opt/models/qwen3.5-4b-q4_k_m.gguf -cnv

# API test
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"default","messages":[{"role":"user","content":"Write a bash one-liner to check disk SMART health"}]}' \
  | python3 -m json.tool
```

### Online (with internet)

```bash
# Set up API keys first
sudo nano /root/.config/ai-keys.env
# Uncomment and fill in ANTHROPIC_API_KEY

# Source the keys
source /root/.config/ai-keys.env

# Test Claude Code
claude --version
echo "What command checks if a LUKS partition is encrypted?" | claude
```

---

## Persistence Test

```bash
# Write a marker file
echo "persist-test-$(hostname)-$(date -Iseconds)" > /root/persist-marker.txt
apt install -y cowsay  # Install a test package

# Reboot
sudo reboot

# After reboot, verify:
cat /root/persist-marker.txt   # Should show previous content
cowsay "persistence works"      # Should work
```

---

## What to Bring Back

When you bring the USB back, I need:

1. **Test results** — automatically saved to `/data/test-results/` on USB
2. **Any error screenshots** — if boot fails, photo the screen
3. **Notes on**:
   - Did Ventoy menu appear?
   - Did Secure Boot prompt (MOK enrollment)?
   - Did "Try Ubuntu" boot successfully?
   - How long did boot take (approx)?
   - Did persistence work after reboot?
   - Did AI tools run (offline/online)?

---

## Troubleshooting Boot Issues

### Ventoy menu doesn't appear
- Check BIOS boot order — USB must be first
- Try different USB port (USB 3.0 blue port preferred)
- Disable Secure Boot temporarily in BIOS

### Secure Boot blocks Ventoy
- Ventoy will show MOK enrollment screen on first boot
- Select "Enroll key" → "Continue" → reboot
- Second boot should work with Secure Boot enabled

### "Try Ubuntu" is slow
- Normal for USB — desktop loads from USB3 into RAM
- First boot is slowest (~60-90 seconds)
- Subsequent boots with persistence are faster

### USB data partition not found
```bash
# List block devices
lsblk

# Look for Ventoy partition
blkid | grep Ventoy

# Mount manually
sudo mount /dev/sdXN /mnt/ventoy-data  # Replace sdXN
```

---

## Per-Host Test Checklist

### ref-host-1 (i9-14900KF, 64GB RAM)
- [ ] UEFI boot from Ventoy menu
- [ ] Secure Boot MOK enrollment (if prompted)
- [ ] Ubuntu Desktop boots to "Try Ubuntu"
- [ ] first-boot-setup.sh completes
- [ ] test-usb --full passes
- [ ] Qwen3.5-9B model loads (64GB RAM = should use 9B)
- [ ] llama-server responds to API query
- [ ] Claude Code works (if internet available)
- [ ] Persistence survives reboot

### ref-host-2 (i7-12700H, 32GB RAM)
- [ ] UEFI boot from Ventoy menu
- [ ] Secure Boot MOK enrollment (if prompted)
- [ ] Ubuntu Desktop boots
- [ ] first-boot-setup.sh completes
- [ ] test-usb --full passes
- [ ] Qwen3.5-9B model loads (32GB RAM = should use 9B)
- [ ] Persistence survives reboot

### ref-host-3 (i7-8700K, 32GB RAM)
- [ ] UEFI boot
- [ ] test-usb --quick passes
- [ ] AI inference works

---

## File Locations on USB

```
/                          USB root (exFAT, label: Ventoy)
├── ISO/
│   ├── install/
│   │   └── ubuntu-24.04-desktop-amd64.iso     (6.0 GB, primary)
│   └── rescue/
│       ├── systemrescue-12.03-amd64.iso       (1.2 GB)
│       ├── clonezilla-amd64.iso               (436 MB)
│       ├── gparted-live-amd64.iso             (562 MB)
│       └── memtest86plus.iso                  (6 MB)
├── models/
│   ├── qwen3.5-9b-q4_k_m.gguf                (5.3 GB)
│   └── qwen3.5-4b-q4_k_m.gguf                (2.6 GB)
├── tools/bin/
│   ├── llama-cli, llama-server                (AI inference)
│   ├── claude                                 (Claude Code)
│   ├── first-boot-setup.sh                    (run once)
│   ├── start-ai.sh                            (AI launcher)
│   └── usb-test-harness.sh                    (test suite)
├── persistence/
│   └── ubuntu-ml-persist.dat                  (12 GB ext4)
├── data/
│   ├── scripts/          (fleet scripts from sysops repo)
│   ├── docs/             (fleet documentation)
│   ├── recovery/         (recovery runbooks)
│   └── test-results/     (test harness output)
└── ventoy/
    └── ventoy.json       (boot menu config)
```
