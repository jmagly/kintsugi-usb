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
#   --ollama-models <dir>    Pre-load a staged Ollama store (a dir with blobs/ +
#                            manifests/) into the persistence at /data/ollama/models
#                            so the booted Ollama has the models offline.
#   --label <NAME>           exFAT data-partition label shown to the recipient
#                            (default: KINTSUGI; relabeled post-install).
#   --readme <path>          On-drive README copied to the data-partition root
#                            (default: config/drive-readme.txt).
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
DATA_LABEL="KINTSUGI"   # end-user-facing exFAT data-partition label (friendly names)
README_SRC=""           # on-drive README template (auto-resolved from repo config/ if empty)
OLLAMA_MODELS_SRC=""    # --ollama-models: a staged Ollama store (blobs/ + manifests/) to
                        # pre-load into the persistence .dat at /data/ollama/models
DRY_RUN=0

# --- arg parsing -----------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --kintsugi-iso)     KINTSUGI_ISO=$2; shift 2 ;;
        --rescue-iso)       RESCUE_ISOS+=("$2"); shift 2 ;;
        --rescue-dir)       RESCUE_DIR=$2; shift 2 ;;
        --output)           OUTPUT=$2; shift 2 ;;
        --label)            DATA_LABEL=$2; shift 2 ;;
        --readme)           README_SRC=$2; shift 2 ;;
        --size)             SIZE_GIB=$2; shift 2 ;;
        --persistence-size) PERSIST_GIB=$2; shift 2 ;;
        --ollama-models)    OLLAMA_MODELS_SRC=$2; shift 2 ;;
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

# Ollama pre-load store sanity: must be an Ollama model dir (blobs/ + manifests/).
if [ -n "$OLLAMA_MODELS_SRC" ]; then
    if [ ! -d "$OLLAMA_MODELS_SRC/blobs" ] || [ ! -d "$OLLAMA_MODELS_SRC/manifests" ]; then
        die "--ollama-models must be an Ollama store dir containing blobs/ and manifests/: $OLLAMA_MODELS_SRC"
    fi
fi

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

# Resolve the on-drive README template (repo config/drive-readme.txt by default).
if [ -z "$README_SRC" ]; then
    _self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    README_SRC="${_self_dir}/../../config/drive-readme.txt"
fi

# --- plan output -----------------------------------------------------------
head1 "make-ventoy-image v${VERSION}"
info "  Kintsugi ISO:       $KINTSUGI_ISO ($(du -h "$KINTSUGI_ISO" | cut -f1))"
info "  Rescue ISOs:        ${#RESCUE_ISOS[@]}"
for iso in "${RESCUE_ISOS[@]:-}"; do [ -n "$iso" ] && info "    - $(basename "$iso")"; done
info "  Output image:       $OUTPUT"
info "  Total size:         ${SIZE_GIB} GiB  (ISOs ~${iso_gib} GiB + persistence ${PERSIST_GIB} GiB + slack)"
info "  Persistence .dat:   ${PERSIST_GIB} GiB, bound to: $kintsugi_iso_name  (issue #34)"
info "  Persistence plugin: ventoy/ventoy.json -> { \"persistence\": [ { \"image\": \"/$kintsugi_iso_name\", \"backend\": \"/ventoy/persistence/kintsugi.dat\" } ] }"
info "  Data label:         $DATA_LABEL  (exFAT; what the recipient sees)"
info "  On-drive README:    README.txt at the data-partition root  (from: $README_SRC)"

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
# -I force-install, -g GPT, -s secure-boot support. Ventoy2Disk.sh prompts
# "Continue? (y/n)" twice — feed both for non-interactive use.
printf 'y\ny\n' | "$VENTOY_BIN" -I -g -s "$LOOPDEV" || die "Ventoy install failed" 2
partprobe "$LOOPDEV" 2>/dev/null || true
if command -v udevadm >/dev/null 2>&1; then udevadm settle 2>/dev/null || true; fi
# Loop partition nodes can lag behind the table write; wait for p1 to appear.
for _i in $(seq 1 10); do
    [ -b "${LOOPDEV}p1" ] && break
    sleep 1; partprobe "$LOOPDEV" 2>/dev/null || true
done
[ -b "${LOOPDEV}p1" ] || die "Ventoy partition ${LOOPDEV}p1 did not appear after install" 2

head1 "Labeling data partition: $DATA_LABEL"
# Friendly, end-user-facing label — the default 'Ventoy' confuses recipients.
if command -v exfatlabel &>/dev/null; then
    exfatlabel "${LOOPDEV}p1" "$DATA_LABEL" || warn "exfatlabel failed; keeping the default 'Ventoy' label"
else
    warn "exfatlabel not found (install exfatprogs); keeping the default 'Ventoy' label"
fi

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

head1 "Writing on-drive README (end-user guidance)"
if [ -r "$README_SRC" ]; then
    cp "$README_SRC" "$MNT/README.txt" && info "  README.txt -> data-partition root"
else
    warn "README template not found at $README_SRC; skipping on-drive README"
fi

head1 "Creating persistence .dat (${PERSIST_GIB} GiB) — issue #34"
mkdir -p "$MNT/ventoy/persistence"
# Ventoy ships CreatePersistentImg.sh at its top level; fall back to a raw ext4 .dat if absent.
# Signature (Ventoy 1.1.x): -s size(MB) -t fstype -l LABEL -c configname -o outputfile.
PERSIST_DAT="$MNT/ventoy/persistence/kintsugi.dat"
VENTOY_PERSIST="$(dirname "$VENTOY_BIN")/CreatePersistentImg.sh"
if [ -x "$VENTOY_PERSIST" ]; then
    "$VENTOY_PERSIST" \
        -s "$(( PERSIST_GIB * 1024 ))" -t ext4 -l casper-rw -c persistence.conf -o "$PERSIST_DAT" \
        || die "persistence image creation failed" 2
else
    warn "CreatePersistentImg.sh not found; creating a raw ext4 .dat directly."
    truncate -s "${PERSIST_GIB}G" "$PERSIST_DAT" || die "persistence truncate failed" 2
    mkfs.ext4 -F -L casper-rw "$PERSIST_DAT" || die "mkfs.ext4 on persistence failed" 2
fi

# Pre-load Ollama models into the persistence overlay. The .dat is labeled casper-rw,
# so its filesystem root unions over / on boot — files at <dat>/data/ollama/models
# appear at /data/ollama/models, which is where OLLAMA_MODELS points (wired in
# first-boot-setup.sh / start-ai.sh). Models live in the writable layer, never the ISO (ADR-005).
if [ -n "$OLLAMA_MODELS_SRC" ]; then
    head1 "Pre-loading Ollama models into persistence (/data/ollama/models)"
    PMNT=$(mktemp -d)
    mount -o loop "$PERSIST_DAT" "$PMNT" || die "could not mount persistence .dat for model pre-load" 2
    mkdir -p "$PMNT/data/ollama/models"
    if cp -a "$OLLAMA_MODELS_SRC/blobs" "$OLLAMA_MODELS_SRC/manifests" "$PMNT/data/ollama/models/"; then
        # Match the casper live user (uid/gid 1000) and keep blobs world-readable so the
        # booted Ollama finds them regardless of which user runs it.
        chown -R 1000:1000 "$PMNT/data/ollama" 2>/dev/null || true
        chmod -R a+rX "$PMNT/data/ollama" 2>/dev/null || true
        local_n=$(find "$PMNT/data/ollama/models/manifests" -type f 2>/dev/null | wc -l)
        info "  loaded ${local_n} model manifest(s), $(du -sh "$PMNT/data/ollama/models" 2>/dev/null | cut -f1) into persistence"
    else
        umount "$PMNT" 2>/dev/null; rmdir "$PMNT" 2>/dev/null
        die "model copy into persistence failed" 2
    fi
    sync
    umount "$PMNT" || warn "umount of persistence .dat failed"
    rmdir "$PMNT" 2>/dev/null || true
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
