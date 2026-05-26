#!/bin/bash
# USB Toolkit First Boot Setup
# Run this once after booting the Ubuntu Desktop ISO with persistence enabled.
# It installs all rescue tools, configures the AI stack, and sets up the environment.
# Usage: sudo ./first-boot-setup.sh
#
# This script is idempotent — safe to run multiple times.

set -uo pipefail

MARKER="/root/.usb-toolkit-setup-complete"
LOG="/var/log/usb-toolkit/first-boot-setup.log"
USB_DATA=""  # Will be detected

# Colors
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
step() { echo -e "\n${GREEN}==>${NC} $*" | tee -a "$LOG"; }
warn() { echo -e "${YELLOW}WARNING:${NC} $*" | tee -a "$LOG"; }
fail() { echo -e "${RED}ERROR:${NC} $*" | tee -a "$LOG"; }

# --- Detect USB data partition ---
detect_usb() {
    for mnt in /cdrom /isodevice /media/*/Ventoy /media/*/VENTOY; do
        if [ -d "$mnt/tools" ] && [ -d "$mnt/models" ]; then
            USB_DATA="$mnt"
            log "USB data partition found at: ${USB_DATA}"
            return 0
        fi
    done
    # Try to mount manually
    for dev in /dev/sd??; do
        local label=$(blkid -s LABEL -o value "$dev" 2>/dev/null)
        if [ "$label" = "Ventoy" ]; then
            mkdir -p /mnt/ventoy-data
            mount -o ro "$dev" /mnt/ventoy-data 2>/dev/null
            if [ -d /mnt/ventoy-data/tools ]; then
                USB_DATA="/mnt/ventoy-data"
                log "USB data partition mounted at: ${USB_DATA}"
                return 0
            fi
        fi
    done
    warn "USB data partition not found — AI tools won't be installed from USB"
    return 1
}

# --- Install packages ---
install_packages() {
    step "Installing rescue tool packages..."

    # Update package lists
    apt-get update -qq

    # Critical rescue tools
    local packages=(
        # Filesystem
        e2fsprogs xfsprogs btrfs-progs dosfstools ntfs-3g parted gdisk
        smartmontools nvme-cli hdparm lvm2 mdadm cryptsetup
        # Data recovery
        testdisk gddrescue fsarchiver
        # Boot repair
        grub-efi-amd64-bin grub-pc-bin efibootmgr os-prober
        # Network
        nmap netcat-openbsd tcpdump iperf3 mtr-tiny dnsutils
        openssh-server arp-scan whois traceroute ethtool bridge-utils
        # Monitoring
        htop iotop lsof sysstat strace dmidecode inxi lshw
        pciutils usbutils
        # Shell tools
        vim tmux screen rsync pv tree jq git bc ncdu
        zip unzip p7zip-full pigz
        # Python
        python3-pip python3-venv python3-dev
        # Build essentials
        build-essential cmake
    )

    apt-get install -y --no-install-recommends "${packages[@]}" 2>&1 | tee -a "$LOG"

    log "Package installation complete"
}

# --- Install AI tools from USB ---
install_ai_tools() {
    step "Installing AI tools from USB..."

    if [ -z "$USB_DATA" ]; then
        warn "Skipping AI tool installation (USB data not found)"
        return
    fi

    # Copy llama.cpp binaries
    if [ -f "${USB_DATA}/tools/bin/llama-cli" ]; then
        cp "${USB_DATA}/tools/bin/llama-cli" /usr/local/bin/
        cp "${USB_DATA}/tools/bin/llama-server" /usr/local/bin/
        cp "${USB_DATA}/tools/bin/llama-completion" /usr/local/bin/ 2>/dev/null || true
        cp "${USB_DATA}/tools/bin/llama-bench" /usr/local/bin/ 2>/dev/null || true
        chmod +x /usr/local/bin/llama-*
        log "llama.cpp binaries installed"
    fi

    # Copy Claude Code
    if [ -f "${USB_DATA}/tools/bin/claude" ]; then
        cp "${USB_DATA}/tools/bin/claude" /usr/local/bin/
        chmod +x /usr/local/bin/claude
        log "Claude Code installed"
    fi

    # Copy start-ai.sh and test harness
    if [ -f "${USB_DATA}/tools/bin/start-ai.sh" ]; then
        cp "${USB_DATA}/tools/bin/start-ai.sh" /usr/local/bin/
        chmod +x /usr/local/bin/start-ai.sh
        log "start-ai.sh installed"
    fi
    if [ -f "${USB_DATA}/tools/bin/usb-test-harness.sh" ]; then
        cp "${USB_DATA}/tools/bin/usb-test-harness.sh" /usr/local/bin/
        chmod +x /usr/local/bin/usb-test-harness.sh
        log "usb-test-harness.sh installed"
    fi

    # Create symlinks to USB model directory (don't copy — too large)
    if [ -d "${USB_DATA}/models" ]; then
        ln -sfn "${USB_DATA}/models" /opt/models
        log "Models directory linked: /opt/models -> ${USB_DATA}/models"
    fi

    # Install aider via pip
    step "Installing Aider via pip..."
    pip3 install --break-system-packages aider-chat 2>&1 | tail -5 | tee -a "$LOG" || warn "Aider installation failed (may need internet)"
}

# --- Configure environment ---
configure_environment() {
    step "Configuring environment..."

    # Create /var/log/usb-toolkit
    mkdir -p /var/log/usb-toolkit

    # Boot timestamp service
    cat > /etc/systemd/system/usb-boot-timestamp.service <<'UNIT'
[Unit]
Description=Record USB boot timestamp
After=sysinit.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'date +%%s > /tmp/usb-boot-timestamp'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
    systemctl enable usb-boot-timestamp.service 2>/dev/null || true

    # Fleet hosts — operator-provided, optional (see config/fleet-hosts.example).
    # The public toolkit ships no fleet topology.
    if [ -f /etc/kintsugi/fleet-hosts ] && ! grep -q "kintsugi optional config" /etc/hosts; then
        { echo ""; echo "# Fleet hosts (kintsugi optional config)"; cat /etc/kintsugi/fleet-hosts; } >> /etc/hosts
        log "Fleet hosts added to /etc/hosts from /etc/kintsugi/fleet-hosts"
    fi

    # Ollama model store on persistence. OLLAMA_MODELS defaults to ~/.ollama, which is
    # ephemeral on a live boot — redirect it to /data (Ventoy persistence) so models
    # pulled in the field, AND any models pre-loaded onto the drive, survive reboots.
    # The read-only ISO stays model-free (ADR-005); models live in the writable layer.
    mkdir -p /data/ollama/models
    cat > /etc/profile.d/kintsugi-ollama.sh <<'PROF'
# Kintsugi: Ollama model store on persistence (/data survives reboots)
export OLLAMA_MODELS=/data/ollama/models
PROF
    chmod 0644 /etc/profile.d/kintsugi-ollama.sh
    # systemd drop-in — honored if ollama.service is ever enabled instead of start-ai.sh
    mkdir -p /etc/systemd/system/ollama.service.d
    cat > /etc/systemd/system/ollama.service.d/10-kintsugi-models.conf <<'OVR'
[Service]
Environment="OLLAMA_MODELS=/data/ollama/models"
OVR
    log "Ollama model store wired to persistence: /data/ollama/models"

    # Custom bashrc for root
    if ! grep -q "ML-Support" /root/.bashrc 2>/dev/null; then
        cat >> /root/.bashrc <<'BASHRC'

# USB Toolkit ML-Support Environment
export PS1='\[\033[01;31m\]ml-support\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# AI tool aliases
alias ai-start='start-ai.sh'
alias ai-status='start-ai.sh --status'
alias ai-stop='start-ai.sh --stop'
alias test-usb='usb-test-harness.sh'
alias test-usb-quick='usb-test-harness.sh --quick'
alias test-usb-ai='usb-test-harness.sh --ai-only'

# Source AI keys if available
[ -f ~/.config/ai-keys.env ] && source ~/.config/ai-keys.env

# Rescue aliases
alias lsblk='lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL'
alias dmesg='dmesg -T'
alias ports='ss -tulnp'
alias netinfo='ip -br addr; echo "---"; ip route; echo "---"; cat /etc/resolv.conf'
alias diskinfo='lsblk; echo "---"; df -hT | grep -v tmpfs'
alias smartcheck='for d in /dev/sd?; do echo "=== $d ==="; smartctl -H "$d" 2>/dev/null || echo "N/A"; done'
alias chroot-target='mount --bind /dev /mnt/target/dev && mount --bind /proc /mnt/target/proc && mount --bind /sys /mnt/target/sys && chroot /mnt/target'

export FLEET_HOSTS=""  # operator-provided; see config/fleet-hosts.example (none baked into the public toolkit)

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ML-Support USB Toolkit v1.0                    ║"
echo "║                                                 ║"
echo "║  ai-start    → Launch AI stack (auto-detects)   ║"
echo "║  ai-status   → Show AI tool availability        ║"
echo "║  test-usb    → Run full test suite              ║"
echo "║  chroot-target → Chroot into mounted system     ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
BASHRC
        log "Custom bashrc configured"
    fi

    # Enable SSH
    systemctl enable ssh 2>/dev/null || true

    log "Environment configuration complete"
}

# --- Create API key template ---
create_api_key_template() {
    step "Creating API key template..."

    mkdir -p /root/.config
    if [ ! -f /root/.config/ai-keys.env ]; then
        cat > /root/.config/ai-keys.env <<'KEYS'
# USB Toolkit API Keys
# Fill in your API keys below. This file persists across reboots.
# NEVER commit this file or include it in any ISO.

# Anthropic (Claude Code, Claude API)
#export ANTHROPIC_API_KEY="sk-ant-..."

# OpenAI (Codex CLI, GPT API)
#export OPENAI_API_KEY="sk-..."
KEYS
        chmod 600 /root/.config/ai-keys.env
        log "API key template created at /root/.config/ai-keys.env"
    fi
}

# --- Main ---
main() {
    mkdir -p /var/log/usb-toolkit

    echo "╔══════════════════════════════════════════════════╗"
    echo "║  USB Toolkit First Boot Setup                   ║"
    echo "║  This installs rescue tools, AI stack, and      ║"
    echo "║  configures the environment.                    ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

    if [ "$(id -u)" -ne 0 ]; then
        fail "Must run as root (sudo ./first-boot-setup.sh)"
        exit 1
    fi

    if [ -f "$MARKER" ]; then
        echo "Setup was already completed on $(cat "$MARKER")."
        echo "Run with --force to redo setup."
        [ "${1:-}" != "--force" ] && exit 0
    fi

    detect_usb
    install_packages
    install_ai_tools
    configure_environment
    create_api_key_template

    # Write completion marker
    date -Iseconds > "$MARKER"

    echo ""
    step "Setup complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Edit /root/.config/ai-keys.env with your API keys"
    echo "  2. Run 'ai-start' to launch the AI stack"
    echo "  3. Run 'test-usb' to validate the installation"
    echo ""
    echo "All changes persist across reboots (Ventoy persistence)."
    echo "Full log: ${LOG}"
}

main "$@"
