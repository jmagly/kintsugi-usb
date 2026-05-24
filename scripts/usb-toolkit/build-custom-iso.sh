#!/bin/bash
# Build custom Ubuntu 24.04 ML-Support Live ISO
# Uses live-build for reproducible, scriptable ISO creation
# Usage: sudo ./build-custom-iso.sh [BUILD_DIR]

set -uo pipefail

BUILD_DIR="${1:-/tmp/usb-iso-build}"
ISO_NAME="ubuntu-24.04-ml-support"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Building ${ISO_NAME} ==="
echo "Build directory: ${BUILD_DIR}"
echo "Scripts source: ${SCRIPTS_DIR}"

# Clean previous build
if [ -d "${BUILD_DIR}" ]; then
    echo "Cleaning previous build..."
    cd "${BUILD_DIR}" && lb clean --purge 2>/dev/null || true
    cd /
    rm -rf "${BUILD_DIR}"
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# --- Configure live-build ---
lb config \
    --distribution noble \
    --archive-areas "main restricted universe multiverse" \
    --architectures amd64 \
    --binary-images iso-hybrid \
    --bootloader grub \
    --debian-installer false \
    --memtest none \
    --iso-application "${ISO_NAME}" \
    --iso-volume "${ISO_NAME}" \
    --apt-recommends false \
    --security true \
    --cache true \
    --compression xz

# --- Package lists ---

# Kernel and boot essentials
cat > config/package-lists/kernel.list.chroot <<'EOF'
linux-image-generic
linux-headers-generic
initramfs-tools
live-boot
live-boot-initramfs-tools
live-tools
live-config
live-config-systemd
squashfs-tools
EOF

# Core rescue tools
cat > config/package-lists/rescue.list.chroot <<'EOF'
# Filesystem tools
e2fsprogs
xfsprogs
btrfs-progs
dosfstools
ntfs-3g
parted
gdisk
smartmontools
nvme-cli
hdparm
lvm2
mdadm
cryptsetup

# Data recovery
testdisk
gddrescue
extundelete
fsarchiver

# Boot repair
grub-efi-amd64-bin
grub-pc-bin
efibootmgr
os-prober

# Network
nmap
netcat-openbsd
tcpdump
iperf3
mtr-tiny
dnsutils
curl
wget
openssh-client
openssh-server
arp-scan
whois
traceroute
ethtool
bridge-utils
iproute2

# Monitoring & diagnostics
htop
iotop
lsof
sysstat
strace
ltrace
dmidecode
inxi
lshw
pciutils
usbutils
procps
psmisc
acpi

# Editors & shell
vim
nano
tmux
screen
rsync
pv
tree
jq
git
bc
file
less
ncdu
zip
unzip
p7zip-full
pigz

# System management
sudo
systemd-timesyncd
cron
at
man-db
bash-completion
locales

# Python
python3
python3-pip
python3-venv
python3-dev

# Build essentials (for compiling tools on-the-fly)
build-essential
cmake
EOF

# Lightweight desktop
cat > config/package-lists/desktop.list.chroot <<'EOF'
xfce4
xfce4-terminal
xfce4-taskmanager
gparted
firefox
thunar
ristretto
mousepad
xdg-utils
x11-xserver-utils
xinit
lightdm
lightdm-gtk-greeter
network-manager
network-manager-gnome
pulseaudio
fonts-ubuntu
EOF

# --- Custom hooks (run inside chroot during build) ---
mkdir -p config/hooks/normal

# Configure system
cat > config/hooks/normal/01-configure-system.hook.chroot <<'HOOK'
#!/bin/bash
set -e

# Set hostname
echo "ml-support" > /etc/hostname

# Configure locale
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Enable SSH but don't start by default (user can start it)
systemctl enable ssh 2>/dev/null || true

# Set root password to 'usb' for emergency console access
echo "root:usb" | chpasswd

# Create live user
useradd -m -s /bin/bash -G sudo,adm,cdrom,plugdev live 2>/dev/null || true
echo "live:live" | chpasswd
echo "live ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/live

# Auto-login for live session
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<LIGHTDM
[Seat:*]
autologin-user=live
autologin-user-timeout=0
LIGHTDM

# NetworkManager auto-connect
cat > /etc/NetworkManager/conf.d/10-globally-managed-devices.conf <<NM
[keyfile]
unmanaged-devices=none
NM

echo "System configuration complete"
HOOK
chmod +x config/hooks/normal/01-configure-system.hook.chroot

# Configure shell environment
cat > config/hooks/normal/02-configure-shell.hook.chroot <<'HOOK'
#!/bin/bash
set -e

# Custom bashrc additions for root
cat >> /root/.bashrc <<'BASHRC'

# USB Toolkit ML-Support Environment
export PS1='\[\033[01;31m\]ml-support\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# AI tool aliases (set up by start-ai.sh)
alias ai-start='/usr/local/bin/start-ai.sh'
alias ai-status='/usr/local/bin/start-ai.sh --status'
alias ai-stop='/usr/local/bin/start-ai.sh --stop'
alias test-usb='/usr/local/bin/usb-test-harness.sh'
alias test-usb-quick='/usr/local/bin/usb-test-harness.sh --quick'

# Source AI keys if available (from persistence)
[ -f ~/.config/ai-keys.env ] && source ~/.config/ai-keys.env

# Common rescue aliases
alias lsblk='lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL'
alias dmesg='dmesg -T'
alias ports='ss -tulnp'
alias netinfo='ip -br addr; echo "---"; ip route; echo "---"; cat /etc/resolv.conf'
alias diskinfo='lsblk; echo "---"; df -hT | grep -v tmpfs'
alias smartcheck='for d in /dev/sd?; do echo "=== $d ==="; smartctl -H "$d" 2>/dev/null || echo "N/A"; done'
alias chroot-target='mount --bind /dev /mnt/target/dev && mount --bind /proc /mnt/target/proc && mount --bind /sys /mnt/target/sys && chroot /mnt/target'
alias usb-data='ls /cdrom/ 2>/dev/null || ls /media/*/Ventoy/ 2>/dev/null || echo "USB data partition not found"'

# Fleet hosts — operator-provided; the public toolkit bakes in none.
# Populate via config/includes.chroot/etc/kintsugi/fleet-hosts (see config/fleet-hosts.example).
export FLEET_HOSTS=""

# MOTD
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ML-Support USB Toolkit v1.0                    ║"
echo "║                                                 ║"
echo "║  ai-start    → Launch AI stack (auto-detects)   ║"
echo "║  ai-status   → Show AI tool availability        ║"
echo "║  test-usb    → Run full test suite              ║"
echo "║  usb-data    → Access USB data partition        ║"
echo "║  chroot-target → Chroot into mounted system     ║"
echo "║                                                 ║"
echo "║  Desktop: startx (or auto via lightdm)          ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
BASHRC

# Same for live user
cp /root/.bashrc /home/live/.bashrc 2>/dev/null || true
chown live:live /home/live/.bashrc 2>/dev/null || true

# Fleet hosts in /etc/hosts — operator-provided, optional. The public toolkit
# bakes in no fleet topology. Drop your entries at
# config/includes.chroot/etc/kintsugi/fleet-hosts (git-ignored; see
# config/fleet-hosts.example) and live-build copies it to /etc/kintsugi/fleet-hosts.
if [ -f /etc/kintsugi/fleet-hosts ]; then
    { echo "# Fleet hosts (kintsugi optional config)"; cat /etc/kintsugi/fleet-hosts; } >> /etc/hosts
fi

echo "Shell configuration complete"
HOOK
chmod +x config/hooks/normal/02-configure-shell.hook.chroot

# Boot timestamp for test harness timing
cat > config/hooks/normal/03-boot-timestamp.hook.chroot <<'HOOK'
#!/bin/bash
set -e

# Create systemd unit to record boot timestamp
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

echo "Boot timestamp service configured"
HOOK
chmod +x config/hooks/normal/03-boot-timestamp.hook.chroot

# --- mikefarah/yq (manifest parsing for kintsugi-models + kintsugi-frameworks) ---
# Ubuntu's apt 'yq' is python-yq (Kislyuk, jq-based, incompatible). We install
# mikefarah's Go-based yq to /usr/local/bin so it shadows /usr/bin/yq.
# Pin version for build reproducibility via KINTSUGI_YQ_VERSION (default: v4.44.3).
YQ_VERSION="${KINTSUGI_YQ_VERSION:-v4.44.3}"
export YQ_VERSION
cat > config/hooks/normal/06-install-yq.hook.chroot <<HOOK_HEADER
#!/bin/bash
# Install mikefarah/yq (Go-based) to /usr/local/bin per ADR-006 Q6.
set -e
YQ_VERSION="${YQ_VERSION}"
HOOK_HEADER
cat >> config/hooks/normal/06-install-yq.hook.chroot <<'HOOK'

apt-get update
apt-get install -y --no-install-recommends curl ca-certificates

# Download the amd64 binary. ARM users must override with a different URL
# — multi-arch is out of scope for v1.0 per SAD out-of-scope list.
curl -fsSL -o /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
chmod +x /usr/local/bin/yq

# Verify it's the Go binary (not the python wrapper).
if ! /usr/local/bin/yq --version 2>&1 | grep -qi mikefarah; then
    echo "ERROR: downloaded yq does not look like mikefarah/yq:"
    /usr/local/bin/yq --version 2>&1 | head -1
    exit 1
fi

# Ensure /usr/local/bin is early in PATH so this shadows the apt-installed
# python-yq if it's ever also installed. Ubuntu's default PATH already does this.

echo "yq install complete: $(/usr/local/bin/yq --version 2>&1 | head -1)"
HOOK
chmod +x config/hooks/normal/06-install-yq.hook.chroot

# --- Ollama runtime (ADR-005 §D2) ---
# Ollama doesn't publish an apt repo; official install is a curl-bash script
# that drops a binary at /usr/local/bin/ollama. We pin the version and
# disable auto-update so we manage the cadence.
# Override with KINTSUGI_OLLAMA_VERSION env var (e.g. "0.5.7"); "latest" by
# default. Set KINTSUGI_SKIP_OLLAMA=1 to omit Ollama entirely.
if [ "${KINTSUGI_SKIP_OLLAMA:-0}" != "1" ]; then
    OLLAMA_VERSION="${KINTSUGI_OLLAMA_VERSION:-latest}"
    echo "Ollama opt-in: version=${OLLAMA_VERSION}"
    export OLLAMA_VERSION_EXPORT="$OLLAMA_VERSION"
    cat > config/hooks/normal/05-install-ollama.hook.chroot <<HOOK_HEADER
#!/bin/bash
# Install Ollama per ADR-005 §D2. Second local LLM runtime alongside llama.cpp.
# Binary lives at /usr/local/bin/ollama; data dir redirected to
# /data/ollama on first boot (via first-boot-setup.sh); auto-update disabled.
set -e
OLLAMA_VERSION="${OLLAMA_VERSION_EXPORT}"
# Pinned sha256 of ollama's install.sh (supply-chain hardening, issue #40).
# Override with KINTSUGI_OLLAMA_INSTALLER_SHA256 after reviewing a new script.
OLLAMA_INSTALLER_SHA256="${KINTSUGI_OLLAMA_INSTALLER_SHA256:-25f64b810b947145095956533e1bdf56eacea2673c55a7e586be4515fc882c9f}"
HOOK_HEADER
    cat >> config/hooks/normal/05-install-ollama.hook.chroot <<'HOOK'

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates

# Fetch the official install script, VERIFY its sha256 against the pinned
# value (issue #40 — no unverified curl|bash), then run it. Ollama's script
# honors OLLAMA_VERSION env var for version pinning.
INSTALL_SH=$(mktemp --suffix=.sh)
curl -fsSL https://ollama.com/install.sh -o "$INSTALL_SH"
GOT_SHA=$(sha256sum "$INSTALL_SH" | awk '{print $1}')
if [ "$GOT_SHA" != "$OLLAMA_INSTALLER_SHA256" ]; then
    echo "ERROR: ollama install.sh sha256 mismatch — refusing to execute."
    echo "  expected: $OLLAMA_INSTALLER_SHA256"
    echo "  got:      $GOT_SHA"
    echo "  The upstream installer changed. Review the new script, then update the"
    echo "  pin (KINTSUGI_OLLAMA_INSTALLER_SHA256 or the default in build-custom-iso.sh)."
    rm -f "$INSTALL_SH"
    exit 1
fi
OLLAMA_VERSION="${OLLAMA_VERSION}" bash "$INSTALL_SH" || {
    echo "WARN: Ollama install script failed; continuing without Ollama bundled"
    rm -f "$INSTALL_SH"
    exit 0
}
rm -f "$INSTALL_SH"

# Disable the systemd service the install script enables — we want
# Ollama under user control (start-ai.sh decides when to launch).
if systemctl is-enabled ollama.service &>/dev/null; then
    systemctl disable ollama.service 2>/dev/null || true
fi

# Remove the 'ollama' system user's service auto-update path so the binary
# stays at the version we installed.
# (Ollama's install.sh creates /etc/systemd/system/ollama.service; we leave
#  the unit file in place for users who want to enable it manually.)

# Record installed version for the test harness
mkdir -p /etc/kintsugi
ollama --version 2>/dev/null | head -1 > /etc/kintsugi/ollama-version.txt || true

# /data/ollama doesn't exist at build time (persistence overlay); first-boot
# setup creates it and symlinks ~/.ollama/models into it. Drop a marker so
# first-boot-setup.sh knows to do that.
mkdir -p /etc/kintsugi
cat > /etc/kintsugi/ollama-first-boot.conf <<CONF
# Consumed by first-boot-setup.sh
OLLAMA_DATA_DIR=/data/ollama
OLLAMA_MODELS_SYMLINK_TARGET=/data/ollama/models
CONF

echo "Ollama install complete: $(ollama --version 2>/dev/null | head -1 || echo 'ollama present')"
HOOK
    chmod +x config/hooks/normal/05-install-ollama.hook.chroot
else
    echo "Ollama opt-out (KINTSUGI_SKIP_OLLAMA=1): skipping Ollama install"
fi

# --- IDE: VS Code + GitHub Copilot extension + gh CLI (ADR-006 §D3) ---
# Wizard can set KINTSUGI_SKIP_IDE=1 before invoking this script to opt out.
if [ "${KINTSUGI_SKIP_IDE:-0}" != "1" ]; then
    echo "IDE opt-in: installing VS Code + Copilot extension + gh CLI in chroot"
    cat > config/hooks/normal/04-install-ide.hook.chroot <<'HOOK'
#!/bin/bash
# Install VS Code (Microsoft apt repo) + GitHub Copilot extension + gh CLI
# per ADR-006 §D3. Telemetry disabled by default per R-19 mitigation.

set -e

export DEBIAN_FRONTEND=noninteractive

# Dependencies for secure apt-key + gh install
apt-get update
apt-get install -y --no-install-recommends \
    wget gpg apt-transport-https ca-certificates curl

# --- Microsoft apt repo (VS Code) ---
install -d -m 0755 /etc/apt/keyrings
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg
chmod 0644 /etc/apt/keyrings/packages.microsoft.gpg

cat > /etc/apt/sources.list.d/vscode.sources <<VSCODE_APT
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /etc/apt/keyrings/packages.microsoft.gpg
VSCODE_APT

# --- GitHub CLI apt repo ---
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg

cat > /etc/apt/sources.list.d/github-cli.sources <<GH_APT
Types: deb
URIs: https://cli.github.com/packages
Suites: stable
Components: main
Architectures: amd64,arm64
Signed-By: /etc/apt/keyrings/githubcli-archive-keyring.gpg
GH_APT

apt-get update

# Pin VS Code version at build time. apt-mark hold prevents auto-upgrades
# post-boot; the Kintsugi team bumps this via a new release build.
apt-get install -y --no-install-recommends code gh
apt-mark hold code

# --- Preinstall GitHub Copilot extension into a system location for new users ---
# Strategy: install as the 'live' user's VS Code extensions dir, then copy
# into /etc/skel so every new user gets it on first login.
mkdir -p /etc/skel/.vscode/extensions
sudo -u live -H code --install-extension github.copilot --force 2>/dev/null || \
    echo "WARN: live user not yet present; installing extension at root-equivalent path"

# If the above failed (no live user at this hook point), fall back: cache the
# VSIX at /usr/share/kintsugi so VS Code can install it on first launch per
# user (or the user runs: code --install-extension <path>).
copilot_installed=false
for d in /home/live/.vscode/extensions/github.copilot-*; do
    [ -e "$d" ] && copilot_installed=true && break
done
if [ "$copilot_installed" = "false" ]; then
    # Copilot extension version (issue #40). Pinning a reviewed version is
    # preferred for reproducibility; "latest" is accepted as a documented risk
    # (the VSIX is fetched unverified from the marketplace). Set COPILOT_VERSION
    # to pin a specific x.y.z.
    COPILOT_VERSION="${COPILOT_VERSION:-latest}"
    if [ "$COPILOT_VERSION" = "latest" ]; then
        echo "WARN: fetching GitHub Copilot extension at 'latest' (unpinned, unverified)."
        echo "      Set COPILOT_VERSION=<x.y.z> to pin a reviewed version."
    fi
    TMP_VSIX=$(mktemp --suffix=.vsix)
    curl -fsSL -o "$TMP_VSIX" \
        "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/GitHub/vsextensions/copilot/${COPILOT_VERSION}/vspackage" || \
        echo "WARN: failed to fetch Copilot extension VSIX; users can install post-boot"
    if [ -s "$TMP_VSIX" ]; then
        mkdir -p /usr/share/kintsugi/vscode-extensions
        mv "$TMP_VSIX" /usr/share/kintsugi/vscode-extensions/github-copilot.vsix
        echo "Copilot VSIX cached at /usr/share/kintsugi/vscode-extensions/github-copilot.vsix"
        echo "Users can install: code --install-extension /usr/share/kintsugi/vscode-extensions/github-copilot.vsix"
    fi
fi

# --- Default settings: telemetry OFF, recommended rescue-context defaults ---
mkdir -p /etc/skel/.config/Code/User
cat > /etc/skel/.config/Code/User/settings.json <<'SETTINGS'
{
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",
  "extensions.autoUpdate": false,
  "extensions.autoCheckUpdates": false,
  "workbench.startupEditor": "readme",
  "files.associations": {
    "*.gguf": "plaintext"
  }
}
SETTINGS
chmod 0644 /etc/skel/.config/Code/User/settings.json

# Also apply to root and live users directly (for first-boot before re-skel)
for user_home in /root /home/live; do
    [ -d "$user_home" ] || continue
    mkdir -p "$user_home/.config/Code/User"
    cp /etc/skel/.config/Code/User/settings.json "$user_home/.config/Code/User/settings.json"
    if [ "$user_home" = "/home/live" ]; then
        chown -R live:live "$user_home/.config/Code"
    fi
done

echo "IDE install complete: $(code --version 2>/dev/null | head -1 || echo 'code'), gh $(gh --version 2>/dev/null | head -1 || echo '?')"
HOOK
    chmod +x config/hooks/normal/04-install-ide.hook.chroot
else
    echo "IDE opt-out (KINTSUGI_SKIP_IDE=1): skipping VS Code + Copilot + gh install"
fi

# --- Include files to copy into the live filesystem ---
mkdir -p config/includes.chroot/usr/local/bin
mkdir -p config/includes.chroot/etc/kintsugi

# Copy our scripts into the ISO
cp "${SCRIPTS_DIR}/start-ai.sh"         config/includes.chroot/usr/local/bin/
cp "${SCRIPTS_DIR}/usb-test-harness.sh" config/includes.chroot/usr/local/bin/
cp "${SCRIPTS_DIR}/kintsugi-models"     config/includes.chroot/usr/local/bin/
cp "${SCRIPTS_DIR}/kintsugi-frameworks" config/includes.chroot/usr/local/bin/
chmod +x config/includes.chroot/usr/local/bin/*

# Copy manifests (needed at runtime by start-ai.sh + the two CLIs)
REPO_TOPLEVEL="$(cd "${SCRIPTS_DIR}/../.." && pwd)"
if [ -f "${REPO_TOPLEVEL}/manifest/models-recommended.yaml" ]; then
    mkdir -p config/includes.chroot/opt/kintsugi-usb/manifest
    cp "${REPO_TOPLEVEL}/manifest/models-recommended.yaml" \
       config/includes.chroot/opt/kintsugi-usb/manifest/
fi
if [ -f "${REPO_TOPLEVEL}/manifest/agentic-frameworks-recommended.yaml" ]; then
    mkdir -p config/includes.chroot/opt/kintsugi-usb/manifest
    cp "${REPO_TOPLEVEL}/manifest/agentic-frameworks-recommended.yaml" \
       config/includes.chroot/opt/kintsugi-usb/manifest/
fi

# Record build metadata for the test harness + first-boot banner
cat > config/includes.chroot/etc/kintsugi/build-info.conf <<BUILDINFO
# Generated by build-custom-iso.sh
BUILD_NAME="${ISO_NAME}"
BUILD_DATE="$(date -Iseconds)"
BUILD_HOST="$(hostname)"
KINTSUGI_FRAMEWORKS="${KINTSUGI_FRAMEWORKS:-}"
KINTSUGI_SKIP_IDE="${KINTSUGI_SKIP_IDE:-0}"
KINTSUGI_SKIP_OLLAMA="${KINTSUGI_SKIP_OLLAMA:-0}"
KINTSUGI_OLLAMA_VERSION="${KINTSUGI_OLLAMA_VERSION:-latest}"
KINTSUGI_YQ_VERSION="${KINTSUGI_YQ_VERSION:-v4.44.3}"
BUILDINFO

# --- Framework installation hook (ADR-006 §D2; driven by wizard) ---
# Wizard sets KINTSUGI_FRAMEWORKS="aider claude-code codex-cli" (space-separated).
# Unset/empty = no frameworks installed at build time (user picks post-flash).
if [ -n "${KINTSUGI_FRAMEWORKS:-}" ]; then
    echo "Frameworks to install in chroot: ${KINTSUGI_FRAMEWORKS}"
    export KINTSUGI_FRAMEWORKS_EXPORT="$KINTSUGI_FRAMEWORKS"
    cat > config/hooks/normal/07-install-frameworks.hook.chroot <<HOOK_HEADER
#!/bin/bash
# Install agentic frameworks chosen by the wizard (ADR-006 §D2).
set -e
FRAMEWORKS="${KINTSUGI_FRAMEWORKS_EXPORT}"
HOOK_HEADER
    cat >> config/hooks/normal/07-install-frameworks.hook.chroot <<'HOOK'

if [ -z "$FRAMEWORKS" ]; then
    echo "No frameworks requested; skipping."
    exit 0
fi

if ! command -v kintsugi-frameworks &>/dev/null; then
    echo "ERROR: kintsugi-frameworks not found in chroot (expected in /usr/local/bin)"
    exit 1
fi

# Point the CLI at the manifest we copied into the ISO
export KINTSUGI_REPO_ROOT=/opt/kintsugi-usb

for name in $FRAMEWORKS; do
    echo ""
    echo "=== Installing framework: $name ==="
    # status=recommended doesn't need --yes; include --yes for safety since
    # the wizard already gated on non-recommended in the interactive step.
    kintsugi-frameworks install "$name" --yes || {
        echo "WARN: framework '$name' install failed in chroot; continuing."
    }
done

echo ""
echo "Framework install pass complete."
HOOK
    chmod +x config/hooks/normal/07-install-frameworks.hook.chroot
else
    echo "No frameworks requested (KINTSUGI_FRAMEWORKS unset); skipping framework install hook"
fi

# --- Build the ISO ---
echo ""
echo "=== Starting ISO build ==="
echo "This will take 15-30 minutes..."
echo ""

lb build 2>&1 | tee "${BUILD_DIR}/build.log"

# Find and report the ISO
ISO_PATH=$(find "${BUILD_DIR}" -maxdepth 1 -name "*.iso" -o -name "*.hybrid.iso" | head -1)
if [ -n "$ISO_PATH" ]; then
    echo ""
    echo "=== Build complete ==="
    echo "ISO: ${ISO_PATH}"
    echo "Size: $(du -h "$ISO_PATH" | cut -f1)"
    echo ""
    echo "Copy to USB with:"
    echo "  sudo cp '${ISO_PATH}' /mnt/ventoy/ISO/custom/${ISO_NAME}.iso"
else
    echo ""
    echo "=== Build FAILED ==="
    echo "Check ${BUILD_DIR}/build.log for details"
    exit 1
fi
