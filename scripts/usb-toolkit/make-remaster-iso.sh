#!/bin/bash
# make-remaster-iso.sh — build the custom Kintsugi ISO by remastering a stock,
# already-bootable Ubuntu/Xubuntu live ISO with livefs-editor (ADR-008).
#
# Supersedes the live-build approach (build-custom-iso.sh): the Ubuntu-shipped
# live-build (3.0~a57) cannot build a bootable noble ISO. Remastering starts
# from Ubuntu's known-good UEFI+BIOS-bootable image and injects our content,
# preserving the boot structure. Non-interactive (no Cubic).
#
# Usage:
#   sudo ./scripts/usb-toolkit/make-remaster-iso.sh \
#        --base <stock.iso> [--output <iso>] [--scripts-dir <dir>]
#        [--packages "pkg1 pkg2 ..."] [--dry-run]
#
# Options:
#   --base <iso>        REQUIRED. Stock bootable Ubuntu/Xubuntu live ISO.
#   --output <iso>      Output ISO (default: ./dist/kintsugi-v2026.5.0.iso).
#   --scripts-dir <dir> usb-toolkit runtime scripts to inject (default: this dir).
#   --packages "..."    Override the injected rescue-package set.
#   --livefs-edit <bin> Path to the livefs-edit entry point (default: the venv
#                       at ~/kintsugi-builds/_tools/livefs-venv/bin/livefs-edit).
#   --with-agentic      Pre-install the agentic CLI platforms in-chroot
#                       (claude-code, codex, opencode, copilot, openclaw + aider).
#   --with-ai-stack     Pre-install the offline AI core in-chroot (Ollama + the
#                       mikefarah yq that kintsugi-models/-frameworks need). #43.
#   --dry-run           Print the livefs-edit invocation; do not run it.
#
# Pass 1 (this script) injects the reliable content: rescue packages + the
# Kintsugi runtime scripts. The AI stack (Ollama, VS Code/Copilot, agentic
# frameworks) is layered in a follow-up pass once the boot/Ventoy chain is
# validated on hardware (#37).
#
# Exit codes: 0 ok / 1 usage / 2 remaster failed / 3 not root

set -euo pipefail
VERSION="0.1.0"

c_bold="\033[1m"; c_red="\033[31m"; c_reset="\033[0m"
err()  { echo -e "${c_red}ERROR:${c_reset} $*" >&2; }
info() { echo "$*"; }
head1() { echo -e "\n${c_bold}== $* ==${c_reset}"; }
die()  { err "$*"; exit "${2:-1}"; }

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE=""
OUTPUT="./dist/kintsugi-v2026.5.0.iso"
SCRIPTS_DIR="$SELF_DIR"
LIVEFS_EDIT="${LIVEFS_EDIT:-$HOME/kintsugi-builds/_tools/livefs-venv/bin/livefs-edit}"
DRY_RUN=0
WITH_AGENTIC=0          # --with-agentic: also pre-install the agentic CLI platforms
WITH_AI_STACK=0         # --with-ai-stack: also pre-install the offline AI core (Ollama + yq), #43
# Curated, apt-installable rescue set (proven installable on noble during the
# live-build investigation). The full catalog stays manifest-driven elsewhere.
PACKAGES="e2fsprogs xfsprogs btrfs-progs dosfstools ntfs-3g exfatprogs parted gdisk \
smartmontools nvme-cli hdparm lvm2 mdadm cryptsetup testdisk gddrescue \
nmap netcat-openbsd tcpdump dnsutils curl wget openssh-client rsync \
htop iotop lsof dmidecode lshw pciutils usbutils \
vim nano tmux jq git pv tree ncdu p7zip-full"

# Runtime scripts injected into the live filesystem's /usr/local/bin.
RUNTIME_SCRIPTS="start-ai.sh usb-test-harness.sh first-boot-setup.sh kintsugi-models kintsugi-frameworks kintsugi-install-hermes kintsugi-eject"

while [ $# -gt 0 ]; do
    case "$1" in
        --base)        BASE=$2; shift 2 ;;
        --output)      OUTPUT=$2; shift 2 ;;
        --scripts-dir) SCRIPTS_DIR=$2; shift 2 ;;
        --packages)    PACKAGES=$2; shift 2 ;;
        --livefs-edit) LIVEFS_EDIT=$2; shift 2 ;;
        --dry-run)      DRY_RUN=1; shift ;;
        --with-agentic) WITH_AGENTIC=1; shift ;;
        --with-ai-stack) WITH_AI_STACK=1; shift ;;
        -h|--help)     sed -n '2,40p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*)            die "Unknown flag: $1" ;;
        *)             die "Unexpected argument: $1" ;;
    esac
done

[ -n "$BASE" ] || die "Missing required --base <stock.iso>"
[ -r "$BASE" ] || die "Base ISO not readable: $BASE"
[ -x "$LIVEFS_EDIT" ] || die "livefs-edit not found/executable: $LIVEFS_EDIT (install per ADR-008)"
[ -d "$SCRIPTS_DIR" ] || die "scripts dir not found: $SCRIPTS_DIR"

# Build the livefs-edit action chain.
ACTIONS=()
# shellcheck disable=SC2206  # word-splitting the package list is intended
ACTIONS+=( --install-packages $PACKAGES )
for s in $RUNTIME_SCRIPTS; do
    src="$SCRIPTS_DIR/$s"
    if [ -r "$src" ]; then
        ACTIONS+=( --cp "$src" "\$LAYERS[0]/usr/local/bin/$s" )
    else
        info "  (skip: $s not found in $SCRIPTS_DIR)"
    fi
done

# Always provision the removable-media desktop UX (automount + easy/safe eject).
# Core to the drive's purpose (rescue + airgapped, non-technical operators), so it
# runs unconditionally — not behind a flag. Same chroot-exec mechanism as the
# agentic/AI provisioners below.
DESKTOP_SRC="$SCRIPTS_DIR/desktop-provision.sh"
if [ -r "$DESKTOP_SRC" ]; then
    ACTIONS+=( --cp "$DESKTOP_SRC" "\$LAYERS[0]/tmp/desktop-provision.sh" )
    ACTIONS+=( --python "base = ctxt.edit_squashfs(get_squash_names(ctxt)[0]); ctxt.run(['chroot', base, 'bash', '/tmp/desktop-provision.sh'])" )
else
    info "  (skip: desktop-provision.sh not found in $SCRIPTS_DIR)"
fi

# Always provision the 32-bit (i386) runtime for legacy vendor recovery tools
# (Imation/IronKey CLI unlocker et al.). Core to a rescue drive — these are often
# old 32-bit binaries and must run OFFLINE out of the box; clean 24.04 ships no
# i386 runtime. Tiny footprint (~MB), purely additive. Same chroot-exec mechanism
# as desktop-provision. See docs/legacy-device-unlock.md (#45).
LEGACY_SRC="$SCRIPTS_DIR/legacy-tools-provision.sh"
if [ -r "$LEGACY_SRC" ]; then
    ACTIONS+=( --cp "$LEGACY_SRC" "\$LAYERS[0]/tmp/legacy-tools-provision.sh" )
    ACTIONS+=( --python "base = ctxt.edit_squashfs(get_squash_names(ctxt)[0]); ctxt.run(['chroot', base, 'bash', '/tmp/legacy-tools-provision.sh'])" )
else
    info "  (skip: legacy-tools-provision.sh not found in $SCRIPTS_DIR)"
fi

# Optionally pre-install the agentic CLI platforms inside the squashfs chroot.
if [ "$WITH_AGENTIC" = "1" ]; then
    AGENTIC_SRC="$SCRIPTS_DIR/agentic-provision.sh"
    [ -r "$AGENTIC_SRC" ] || die "agentic provisioner not found: $AGENTIC_SRC"
    ACTIONS+=( --cp "$AGENTIC_SRC" "\$LAYERS[0]/tmp/agentic-provision.sh" )
    # livefs-edit --python: mount the base squashfs, then chroot-run the provisioner
    # (claude-code, codex, opencode, copilot, aider). Mirrors install_packages' chroot-exec.
    ACTIONS+=( --python "base = ctxt.edit_squashfs(get_squash_names(ctxt)[0]); ctxt.run(['chroot', base, 'bash', '/tmp/agentic-provision.sh'])" )
fi

# Optionally pre-install the offline AI core (Ollama + mikefarah yq) — the drive's
# headline feature (#43, ADR-005 §D2). Same chroot-exec mechanism as --with-agentic.
if [ "$WITH_AI_STACK" = "1" ]; then
    AISTACK_SRC="$SCRIPTS_DIR/ai-stack-provision.sh"
    [ -r "$AISTACK_SRC" ] || die "AI-stack provisioner not found: $AISTACK_SRC"
    ACTIONS+=( --cp "$AISTACK_SRC" "\$LAYERS[0]/tmp/ai-stack-provision.sh" )
    ACTIONS+=( --python "base = ctxt.edit_squashfs(get_squash_names(ctxt)[0]); ctxt.run(['chroot', base, 'bash', '/tmp/ai-stack-provision.sh'])" )
fi

# Pre-repack chroot-process reaper (MUST be the last action). livefs-edit mounts a
# fresh devtmpfs at <chroot>/dev and, at repack, umounts the dev/pts/proc/sys it set
# up (context.py add_sys_mounts). If a provisioner's apt/postinst left a DAEMON
# running inside the chroot (e.g. dbus/gvfsd/udisksd spawned by the desktop stack),
# that process keeps <chroot>/dev open and livefs's `umount <chroot>/dev` fails
# "target is busy", aborting the repack — no ISO (observed on noble with the full
# agentic+AI stack; there are NO stray /dev submounts — it's a live process).
# This host-side action runs just before livefs's _pre_repack hook. It (a) lazy-
# unmounts any stray submount strictly under <chroot>/dev (keeping livefs's /dev/pts),
# then (b) TERM/KILLs every process still chrooted into the build — selected precisely
# by /proc/PID/root pointing into the chroot, so HOST processes (root=/) are never
# touched. It logs each reaped process so the offending daemon is identifiable.
ACTIONS+=( --python 'import subprocess, os, time
b = ctxt.edit_squashfs(get_squash_names(ctxt)[0])
mounts = subprocess.run(["findmnt", "-rno", "TARGET"], capture_output=True, text=True).stdout.split()
for m in sorted([x for x in mounts if x.startswith(b + "/dev/") and x != b + "/dev/pts"], reverse=True):
    print("kintsugi pre-repack: lazy-umount stray submount", m)
    subprocess.run(["umount", "-l", m])
me = str(os.getpid())
def chrooted(pid):
    try:
        return os.readlink("/proc/%s/root" % pid).startswith(b)
    except OSError:
        return False
for sig in ("-TERM", "-KILL"):
    hit = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or pid == me or not chrooted(pid):
            continue
        hit = True
        try:
            cmd = open("/proc/%s/cmdline" % pid).read().replace(chr(0), " ").strip()
        except OSError:
            cmd = "?"
        print("kintsugi pre-repack: kill %s chrooted pid=%s cmd=%s" % (sig, pid, cmd))
        subprocess.run(["kill", sig, pid])
    if hit and sig == "-TERM":
        time.sleep(2)' )

head1 "make-remaster-iso v${VERSION}"
info "  Base ISO:     $BASE ($(du -h "$BASE" | cut -f1))"
info "  Output:       $OUTPUT"
info "  livefs-edit:  $LIVEFS_EDIT"
info "  Packages:     $(echo "$PACKAGES" | wc -w) rescue packages"
info "  Scripts:      $RUNTIME_SCRIPTS"
info "  Desktop:      udiskie automount + tray eject, gnome-disks, udisks polkit, 'Safely Remove' launcher (always)"
info "  Legacy 32-bit: i386 multiarch + libc6:i386 for vendor unlockers (IronKey CLI, offline) (always) [#45]"
if [ "$WITH_AGENTIC" = "1" ]; then info "  Agentic:      claude-code, codex, opencode, copilot, openclaw, omnius, aider (pre-installed in-chroot)"; fi
if [ "$WITH_AI_STACK" = "1" ]; then info "  AI core:      Ollama + mikefarah yq (offline LLM runtime; models pulled post-flash) [#43]"; fi
info ""
info "  livefs-edit \"$BASE\" \"$OUTPUT\" \\"
printf '    %s\n' "${ACTIONS[@]}"

if [ "$DRY_RUN" = "1" ]; then
    info ""
    info "[dry-run] Not invoking livefs-edit. Rerun as root without --dry-run."
    exit 0
fi

[ "$(id -u)" -eq 0 ] || die "Remaster requires root (mount/chroot/squashfs). Re-run with sudo, or use --dry-run." 3

mkdir -p "$(dirname "$OUTPUT")"

# Force xz squashfs compression so the model/agentic-laden base layer stays under the
# ISO9660 4 GiB per-file ceiling (default gzip overflows it once Ollama + the agentic
# CLIs + omnius are in). livefs-edit calls `mksquashfs` by bare name, so we shim it on
# PATH rather than patch the third-party tool. xz + x86 BCJ + 1M blocks = Ubuntu's own
# livecd-rootfs settings (~25-35% smaller than gzip).
SQUASH_WRAP="$(mktemp -d)"
REAL_MKSQUASHFS="$(command -v mksquashfs || echo /usr/bin/mksquashfs)"
cat > "$SQUASH_WRAP/mksquashfs" <<WRAP
#!/bin/bash
# Kintsugi xz shim — appends -comp xz unless the caller already chose a compressor.
for a in "\$@"; do [ "\$a" = "-comp" ] && exec "$REAL_MKSQUASHFS" "\$@"; done
exec "$REAL_MKSQUASHFS" "\$@" -comp xz -b 1M -Xbcj x86 -no-progress
WRAP
chmod +x "$SQUASH_WRAP/mksquashfs"
trap 'rm -rf "$SQUASH_WRAP"' EXIT

head1 "Remastering (livefs-editor) — this takes several minutes (xz repack)"
if ! PATH="$SQUASH_WRAP:$PATH" "$LIVEFS_EDIT" "$BASE" "$OUTPUT" "${ACTIONS[@]}"; then
    die "livefs-edit remaster failed" 2
fi

head1 "Verifying the output ISO is bootable"
if file "$OUTPUT" | grep -q "(bootable)"; then
    info "  ✓ $(file "$OUTPUT")"
else
    die "Output ISO is NOT bootable — boot structure not preserved" 2
fi
command -v xorriso >/dev/null 2>&1 && \
    xorriso -indev "$OUTPUT" -report_el_torito plain 2>&1 | grep -iE 'El Torito boot img' | sed 's/^/  /'

head1 "Done"
info "Custom ISO: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
info ""
info "Next: assemble the Ventoy image"
info "  sudo ./scripts/usb-toolkit/make-ventoy-image.sh --kintsugi-iso \"$OUTPUT\" \\"
info "       --ventoy-bin \$HOME/kintsugi-builds/_ventoy/ventoy-1.1.05/Ventoy2Disk.sh"
