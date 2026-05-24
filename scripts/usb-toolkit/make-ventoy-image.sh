#!/bin/bash
# make-ventoy-image.sh — assemble a full Ventoy multi-boot disk image (.img).
#
# Produces a single loopback disk image containing:
#   1. Ventoy bootloader (UEFI + legacy), installed to the image.
#   2. A Ventoy persistence .dat (default 32 GiB) wired to the Kintsugi ISO via
#      the Ventoy `persistence` plugin (ventoy/ventoy.json).
#   3. The rescue ISOs + the custom Kintsugi live ISO, copied into the Ventoy
#      data partition so they appear in the boot menu.
#
# The resulting <output>.img is handed to create-image.sh to become a
# distributable <name>.img.zst + .sha256.
#
# Implements Gitea issues #42 (this assembly stage), #34 (persistence), and the
# imaging half of #35 (Ventoy multi-boot). Boot + persistence *validation* on
# real hardware is owned by #37 — this script BUILDS the image; it does not and
# cannot prove the image boots from a dev shell.
#
# Usage:
#   sudo ./scripts/usb-toolkit/make-ventoy-image.sh \
#        --kintsugi-iso <iso> [--rescue-iso <iso> ...] [--rescue-dir <dir>] \
#        [--output <img>] [--size <GiB>] [--persistence-size <GiB>] \
#        [--ventoy-bin <Ventoy2Disk.sh>] [--dry-run]
#
# Options:
#   --kintsugi-iso <iso>     REQUIRED. The custom Kintsugi live ISO (from
#                            build-custom-iso.sh). Persistence is bound to this.
#   --rescue-iso <iso>       A rescue ISO to include. Repeatable.
#   --rescue-dir <dir>       Directory of *.iso rescue images to include.
#   --output <img>           Output image path (default: ./dist/kintsugi-ventoy.img)
#   --size <GiB>             Total image size. Default: auto (sum of ISOs +
#                            persistence + 1 GiB slack), minimum 8.
#   --persistence-size <GiB> Persistence .dat size (default: 32; per #34).
#   --ventoy-bin <path>      Path to Ventoy2Disk.sh (default: search PATH /
#                            VENTOY_DIR). Required for the real build.
#   --dry-run                Validate inputs, compute the layout, print the
#                            plan, and exit WITHOUT any privileged operation.
#
# Exit codes:
#   0  success (or dry-run plan printed)
#   1  usage / missing input / missing tool
#   2  privileged operation failed
#   3  not run as root (real build requires root for losetup/mkfs/mount)

set -euo pipefail

VERSION="0.1.0"

# --- output helpers (mirror kintsugi-build) --------------------------------
c_bold="\033[1m"; c_red="\033[31m"; c_reset="\033[0m"
err()  { echo -e "${c_red}ERROR:${c_reset} $*" >&2; }
warn() { echo -e "${c_red}WARN:${c_reset}  $*" >&2; }
info() { echo "$*"; }
head1() { echo -e "\n${c_bold}== $* ==${c_reset}"; }
die()  { err "$*"; exit "${2:-1}"; }

# --- defaults --------------------------------------------------------------
KINTSUGI_ISO=""
RESCUE_ISOS=()
RESCUE_DIR=""
OUTPUT="./dist/kintsugi-ventoy.img"
SIZE_GIB=0            # 0 = auto
PERSIST_GIB=32        # #34 default
VENTOY_BIN="${VENTOY_BIN:-}"
DRY_RUN=0

# --- arg parsing -----------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --kintsugi-iso)     KINTSUGI_ISO=$2; shift 2 ;;
        --rescue-iso)       RESCUE_ISOS+=("$2"); shift 2 ;;
        --rescue-dir)       RESCUE_DIR=$2; shift 2 ;;
        --output)           OUTPUT=$2; shift 2 ;;
        --size)             SIZE_GIB=$2; shift 2 ;;
        --persistence-size) PERSIST_GIB=$2; shift 2 ;;
        --ventoy-bin)       VENTOY_BIN=$2; shift 2 ;;
        --dry-run)          DRY_RUN=1; shift ;;
        -h|--help)          sed -n '2,40p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*)                 die "Unknown flag: $1" ;;
        *)                  die "Unexpected argument: $1" ;;
    esac
done

# --- input validation (runs in dry-run too) --------------------------------
[ -n "$KINTSUGI_ISO" ] || die "Missing required --kintsugi-iso <iso>"
[ -r "$KINTSUGI_ISO" ] || die "Kintsugi ISO not readable: $KINTSUGI_ISO"

# Collect rescue ISOs from --rescue-dir as well.
if [ -n "$RESCUE_DIR" ]; then
    [ -d "$RESCUE_DIR" ] || die "Rescue dir not found: $RESCUE_DIR"
    while IFS= read -r f; do RESCUE_ISOS+=("$f"); done \
        < <(find "$RESCUE_DIR" -maxdepth 1 -type f -name '*.iso' | sort)
fi
for iso in "${RESCUE_ISOS[@]:-}"; do
    [ -z "$iso" ] && continue
    [ -r "$iso" ] || die "Rescue ISO not readable: $iso"
done

# Numeric sanity.
case "$PERSIST_GIB" in (''|*[!0-9]*) die "--persistence-size must be an integer GiB";; esac
case "$SIZE_GIB"    in (''|*[!0-9]*) die "--size must be an integer GiB";; esac

# --- compute layout --------------------------------------------------------
iso_bytes() { stat -c %s "$1"; }
total_iso_bytes=$(iso_bytes "$KINTSUGI_ISO")
for iso in "${RESCUE_ISOS[@]:-}"; do
    [ -z "$iso" ] && continue
    total_iso_bytes=$(( total_iso_bytes + $(iso_bytes "$iso") ))
done
iso_gib=$(( (total_iso_bytes + (1024*1024*1024 - 1)) / (1024*1024*1024) ))

if [ "$SIZE_GIB" -eq 0 ]; then
    SIZE_GIB=$(( iso_gib + PERSIST_GIB + 1 ))   # +1 GiB slack for Ventoy + FS overhead
fi
[ "$SIZE_GIB" -lt 8 ] && SIZE_GIB=8

kintsugi_iso_name="$(basename "$KINTSUGI_ISO")"

# --- plan output -----------------------------------------------------------
head1 "make-ventoy-image v${VERSION}"
info "  Kintsugi ISO:       $KINTSUGI_ISO ($(du -h "$KINTSUGI_ISO" | cut -f1))"
info "  Rescue ISOs:        ${#RESCUE_ISOS[@]}"
for iso in "${RESCUE_ISOS[@]:-}"; do [ -n "$iso" ] && info "    - $(basename "$iso")"; done
info "  Output image:       $OUTPUT"
info "  Total size:         ${SIZE_GIB} GiB  (ISOs ~${iso_gib} GiB + persistence ${PERSIST_GIB} GiB + slack)"
info "  Persistence .dat:   ${PERSIST_GIB} GiB, bound to: $kintsugi_iso_name  (issue #34)"
info "  Persistence plugin: ventoy/ventoy.json -> { \"persistence\": [ { \"image\": \"/$kintsugi_iso_name\", \"backend\": \"/ventoy/persistence/kintsugi.dat\" } ] }"

if [ "$DRY_RUN" = "1" ]; then
    info ""
    info "[dry-run] Inputs validated, layout computed. No privileged operations performed."
    info "[dry-run] Rerun as root without --dry-run to build the image."
    exit 0
fi

# ===========================================================================
# Privileged build path.
#
# NOTE (#37): the steps below perform real disk operations (losetup, mkfs,
# mount, Ventoy install). They CANNOT be exercised from a dev shell without
# root + the Ventoy tooling, and the resulting image's boot/persistence
# behaviour is validated on real hardware under issue #37 — not here.
# ===========================================================================
[ "$(id -u)" -eq 0 ] || die "Real build requires root (losetup/mkfs/mount). Re-run with sudo, or use --dry-run." 3

# Locate Ventoy install tool.
if [ -z "$VENTOY_BIN" ]; then
    VENTOY_BIN="$(command -v Ventoy2Disk.sh 2>/dev/null || true)"
    [ -z "$VENTOY_BIN" ] && [ -n "${VENTOY_DIR:-}" ] && VENTOY_BIN="${VENTOY_DIR}/Ventoy2Disk.sh"
fi
if [ -z "$VENTOY_BIN" ] || [ ! -x "$VENTOY_BIN" ]; then
    die "Ventoy2Disk.sh not found. Install Ventoy and pass --ventoy-bin <path> (or set VENTOY_DIR)."
fi

for t in losetup parted sha256sum; do
    command -v "$t" &>/dev/null || die "Required tool missing: $t"
done

LOOPDEV=""
MNT=""
cleanup() {
    if [ -n "$MNT" ] && mountpoint -q "$MNT"; then umount "$MNT" 2>/dev/null || true; fi
    if [ -n "$MNT" ] && [ -d "$MNT" ]; then rmdir "$MNT" 2>/dev/null || true; fi
    if [ -n "$LOOPDEV" ]; then losetup -d "$LOOPDEV" 2>/dev/null || true; fi
}
trap cleanup EXIT

mkdir -p "$(dirname "$OUTPUT")"

head1 "Allocating ${SIZE_GIB} GiB sparse image"
truncate -s "${SIZE_GIB}G" "$OUTPUT" || die "truncate failed" 2

head1 "Attaching loop device"
LOOPDEV="$(losetup --show -f -P "$OUTPUT")" || die "losetup failed" 2
info "  loop: $LOOPDEV"

head1 "Installing Ventoy to $LOOPDEV"
# Ventoy installs the bootloader + lays out the exFAT data partition.
"$VENTOY_BIN" -I -g "$LOOPDEV" || die "Ventoy install failed" 2
partprobe "$LOOPDEV" 2>/dev/null || true

head1 "Mounting Ventoy data partition"
MNT="$(mktemp -d)"
# Ventoy's first partition (exFAT) holds the ISOs + ventoy/ plugin dir.
mount "${LOOPDEV}p1" "$MNT" || die "mount of ${LOOPDEV}p1 failed" 2

head1 "Copying ISOs into Ventoy layout"
cp -v "$KINTSUGI_ISO" "$MNT/" || die "copy of Kintsugi ISO failed" 2
for iso in "${RESCUE_ISOS[@]:-}"; do
    [ -z "$iso" ] && continue
    cp -v "$iso" "$MNT/" || die "copy of $(basename "$iso") failed" 2
done

head1 "Creating persistence .dat (${PERSIST_GIB} GiB) — issue #34"
mkdir -p "$MNT/ventoy/persistence"
# Ventoy ships CreatePersistentImg.sh; fall back to a raw ext4 .dat if absent.
PERSIST_DAT="$MNT/ventoy/persistence/kintsugi.dat"
if [ -x "$(dirname "$VENTOY_BIN")/tool/CreatePersistentImg.sh" ]; then
    "$(dirname "$VENTOY_BIN")/tool/CreatePersistentImg.sh" \
        -s "$(( PERSIST_GIB * 1024 ))" -t ext4 -l casper-rw -c "$PERSIST_DAT" \
        || die "persistence image creation failed" 2
else
    warn "CreatePersistentImg.sh not found; creating a raw ext4 .dat directly."
    truncate -s "${PERSIST_GIB}G" "$PERSIST_DAT" || die "persistence truncate failed" 2
    mkfs.ext4 -F -L casper-rw "$PERSIST_DAT" || die "mkfs.ext4 on persistence failed" 2
fi

head1 "Writing Ventoy persistence plugin (ventoy/ventoy.json)"
# Bind persistence to the Kintsugi ISO so /data survives reboot (#34).
cat > "$MNT/ventoy/ventoy.json" <<JSON
{
  "persistence": [
    {
      "image": "/$kintsugi_iso_name",
      "backend": "/ventoy/persistence/kintsugi.dat"
    }
  ]
}
JSON

sync
head1 "Done"
info "Image: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
info ""
info "Next: package for distribution"
info "  ./scripts/create-image.sh \"$OUTPUT\""
info ""
warn "Boot + persistence behaviour is validated on real hardware under issue #37."
