# Build Guide: ML-Augmented Boot & Support USB

How to reproduce this USB from scratch.

---

## Prerequisites

- 59GB+ USB 3.0 flash drive
- Ubuntu 24.04 host with internet access
- ~30GB free disk space for downloads

## Step 1: Install Ventoy

```bash
# Download Ventoy
cd /tmp && curl -sL "https://github.com/ventoy/Ventoy/releases/download/v1.1.05/ventoy-1.1.05-linux.tar.gz" -o ventoy.tar.gz
tar xzf ventoy.tar.gz && cd ventoy-1.1.05

# Install with GPT + Secure Boot + 20GB reserved
# WARNING: This wipes /dev/sdX — confirm correct device!
echo -e "y\ny" | sudo bash Ventoy2Disk.sh -I -g -s -r 20480 /dev/sdX
```

## Step 2: Create Directory Structure

```bash
sudo mount /dev/sdX1 /mnt/ventoy
sudo mkdir -p /mnt/ventoy/{ISO/custom,ISO/rescue,ISO/install,ISO/windows,ventoy,persistence,tools/bin,models,data/{scripts,ssh,docs,recovery,test-results}}
```

## Step 3: Download ISOs

```bash
cd ~/Downloads/usb-toolkit/iso

# Ubuntu Desktop 24.04 (primary environment)
curl -L -o ubuntu-24.04-desktop-amd64.iso "https://releases.ubuntu.com/24.04.2/ubuntu-24.04.2-desktop-amd64.iso"

# SystemRescue
curl -L -o systemrescue-12.03-amd64.iso "https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/12.03/systemrescue-12.03-amd64.iso/download"

# Clonezilla
curl -L -o clonezilla-amd64.iso "https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/3.2.0-5/clonezilla-live-3.2.0-5-amd64.iso/download"

# GParted
curl -L -o gparted-live-amd64.iso "https://sourceforge.net/projects/gparted/files/gparted-live-stable/1.7.0-1/gparted-live-1.7.0-1-amd64.iso/download"

# Memtest86+
curl -sL "https://www.memtest.org/download/v7.00/mt86plus_7.00_64.iso.zip" -o memtest.zip && unzip memtest.zip

# Copy to USB
sudo cp ubuntu-24.04-desktop-amd64.iso /mnt/ventoy/ISO/install/
sudo cp systemrescue-12.03-amd64.iso clonezilla-amd64.iso gparted-live-amd64.iso /mnt/ventoy/ISO/rescue/
sudo cp mt86plus_7.00_64.iso /mnt/ventoy/ISO/rescue/memtest86plus.iso
```

## Step 4: Download AI Tools

```bash
# llama.cpp
curl -L -o llama-cpp.tar.gz "https://github.com/ggml-org/llama.cpp/releases/download/b8192/llama-b8192-bin-ubuntu-x64.tar.gz"
tar xzf llama-cpp.tar.gz
sudo cp llama-b8192/llama-{cli,server,completion,bench} /mnt/ventoy/tools/bin/

# Qwen3.5 models
curl -L -o /mnt/ventoy/models/qwen3.5-9b-q4_k_m.gguf "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf"
curl -L -o /mnt/ventoy/models/qwen3.5-4b-q4_k_m.gguf "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf"

# Claude Code (copy from host installation)
sudo cp ~/.local/share/claude/versions/$(claude --version | head -1 | awk '{print $1}') /mnt/ventoy/tools/bin/claude
```

## Step 5: Copy Scripts

```bash
sudo cp scripts/usb-toolkit/{first-boot-setup.sh,start-ai.sh,usb-test-harness.sh} /mnt/ventoy/tools/bin/
sudo chmod +x /mnt/ventoy/tools/bin/*.sh
```

## Step 6: Create Persistence Image

```bash
cd /tmp/ventoy-1.1.05
sudo bash CreatePersistentImg.sh -s 12288 -l casper-rw -o /mnt/ventoy/persistence/ubuntu-ml-persist.dat
```

## Step 7: Configure Ventoy

Copy `ventoy.json` to `/mnt/ventoy/ventoy/ventoy.json` (see architecture.md for contents).

## Step 8: Copy payload data

```bash
# Scripts ship as payload:
sudo cp scripts/*.sh /mnt/ventoy/data/scripts/
# Operator-provided fleet docs / recovery packs are optional and live outside
# this public repo (in your fleet repos). Copy your own if you maintain them:
# sudo cp -r /path/to/your/fleet-docs/ /mnt/ventoy/data/docs/fleet/
```

## Step 9: Sync and Unmount

```bash
sudo sync
sudo umount /mnt/ventoy
```

## First Use

1. Boot from USB on target machine
2. Select "Ubuntu ML-Support 24.04" from Ventoy menu
3. Choose "Try Ubuntu" (NOT Install)
4. Accept persistence when prompted
5. Open terminal, run: `sudo bash /cdrom/tools/bin/first-boot-setup.sh`
6. After setup: `sudo start-ai.sh` to launch AI stack
