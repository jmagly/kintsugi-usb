#!/bin/bash
# flash-image.sh — recipient-facing USB flasher with safety rails.
#
# Takes a Kintsugi release artifact (.img.zst or .iso) and writes it to a
# target block device. Verifies sha256 before flashing; refuses to write to
# anything that looks like a system disk unless --yes-really is passed.
#
# Usage:
#   sudo ./scripts/flash-image.sh <image> <device>
#                                 [--skip-verify]
#                                 [--yes-really]
#                                 [--dry-run]
#
# Arguments:
#   <image>       .img.zst (decompressed on the fly) or .iso / .img
#   <device>      Target block device (e.g. /dev/sdX, /dev/mmcblk0).
#                 MUST be a whole disk — partition paths like /dev/sdb1
#                 are refused.
#
# Options:
#   --skip-verify   Skip sha256 check (NOT recommended; use only when the
#                   checksum file is unavailable)
#   --yes-really    Bypass the "looks like a system disk" safety check.
#                   REQUIRED when flashing the host's own USB adapter.
#   --dry-run       Print the plan; do not write anything.
#
# Exit codes:
#   0  flash succeeded + post-flash sanity check passed
#   1  usage error
#   2  sha256 verification failed
#   3  target device rejected (safety check)
#   4  flash (dd) failed
#   5  post-flash read-back failed

set -euo pipefail

VERSION="0.1.0"

IMG=""
DEV=""
SKIP_VERIFY=0
YES_REALLY=0
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-verify) SKIP_VERIFY=1; shift ;;
        --yes-really)  YES_REALLY=1; shift ;;
        --dry-run)     DRY_RUN=1; shift ;;
        -h|--help)     sed -n '2,28p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*)            echo "Unknown flag: $1" >&2; exit 1 ;;
        *)
            if [ -z "$IMG" ]; then IMG=$1; shift
            elif [ -z "$DEV" ]; then DEV=$1; shift
            else echo "Unexpected arg: $1" >&2; exit 1; fi ;;
    esac
done

[ -z "$IMG" ] || [ -z "$DEV" ] && {
    echo "Usage: sudo $0 <image> <device> [--skip-verify] [--yes-really] [--dry-run]" >&2
    exit 1
}
[ -r "$IMG" ] || { echo "ERROR: image not readable: $IMG" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Device sanity
# ---------------------------------------------------------------------------

# Refuse partition paths (e.g. /dev/sdb1). We want /dev/sdb, not /dev/sdb1.
case "$DEV" in
    /dev/sd[a-z][0-9]*|/dev/nvme[0-9]*p[0-9]*|/dev/mmcblk[0-9]*p[0-9]*)
        echo "ERROR: $DEV looks like a partition, not a whole disk." >&2
        echo "       Flash must target the whole disk (e.g. /dev/sdb, not /dev/sdb1)." >&2
        exit 3 ;;
esac
[ -b "$DEV" ] || { echo "ERROR: $DEV is not a block device." >&2; exit 3; }

# Walk mount table; refuse to flash a device that has a mounted partition
# currently serving /, /boot, /home, /usr, /var.
if [ "$YES_REALLY" != "1" ]; then
    if lsblk -nlo NAME,MOUNTPOINT "$DEV" 2>/dev/null | \
       awk '$2 ~ /^(\/|\/boot|\/home|\/usr|\/var|\/etc)$/ {exit 1}'; then
        :
    else
        echo "ERROR: $DEV hosts a system-critical mount point (/, /boot, /home, /usr, /var, /etc)." >&2
        echo "       Refusing. If this really is the intended target, re-run with --yes-really." >&2
        exit 3
    fi
    # Extra heuristic: if the device is the same as the root filesystem's underlying disk, refuse.
    ROOT_SRC=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/[0-9]*$//')
    if [ -n "$ROOT_SRC" ] && [ "$ROOT_SRC" = "$DEV" ]; then
        echo "ERROR: $DEV is the root filesystem's underlying disk. Refusing." >&2
        echo "       --yes-really bypasses this, but you almost certainly don't want to." >&2
        exit 3
    fi
fi

# ---------------------------------------------------------------------------
# Report + confirm
# ---------------------------------------------------------------------------

DEV_SIZE=$(blockdev --getsize64 "$DEV" 2>/dev/null || echo 0)
DEV_HUMAN=$(numfmt --to=iec "$DEV_SIZE" 2>/dev/null || echo "?")
IMG_SIZE=$(stat --format=%s "$IMG" 2>/dev/null || echo 0)
IMG_HUMAN=$(numfmt --to=iec "$IMG_SIZE" 2>/dev/null || echo "?")

echo "[flash-image] v${VERSION}"
echo "  image:       $IMG ($IMG_HUMAN)"
echo "  target:      $DEV ($DEV_HUMAN)"
echo "  device info: $(lsblk -nlo NAME,SIZE,MODEL "$DEV" 2>/dev/null | head -1 || echo 'unknown')"
echo ""

# sha256 verify (unless --skip-verify)
SHA_FILE="${IMG}.sha256"
if [ "$SKIP_VERIFY" != "1" ] && [ -f "$SHA_FILE" ]; then
    echo "[flash-image] Verifying sha256 against $SHA_FILE ..."
    if ! ( cd "$(dirname "$SHA_FILE")" && sha256sum -c "$(basename "$SHA_FILE")" >/dev/null 2>&1 ); then
        echo "ERROR: sha256 verification FAILED." >&2
        echo "       The image is either corrupted or tampered. Re-download." >&2
        exit 2
    fi
    echo "[flash-image]   sha256 OK"
elif [ "$SKIP_VERIFY" = "1" ]; then
    echo "[flash-image] WARN: skipping sha256 (--skip-verify)"
else
    echo "[flash-image] WARN: no .sha256 file found for $IMG; skipping verify"
fi

# Final confirmation before destructive write
if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] Would run: zstdcat (if .zst) or cat | dd of=$DEV bs=4M status=progress conv=fsync"
    exit 0
fi

echo ""
echo "============================================================"
echo " ABOUT TO ERASE: $DEV ($DEV_HUMAN)"
echo " All existing data on this device will be destroyed."
echo "============================================================"
read -rp "Type the device path ($DEV) to confirm: " typed
if [ "$typed" != "$DEV" ]; then
    echo "Did not match; aborting."
    exit 1
fi

# ---------------------------------------------------------------------------
# Flash
# ---------------------------------------------------------------------------

echo ""
echo "[flash-image] Writing to $DEV (this may take several minutes)..."

case "$IMG" in
    *.img.zst|*.iso.zst)
        command -v zstd &>/dev/null || { echo "ERROR: zstd required for .zst images." >&2; exit 1; }
        if ! zstdcat "$IMG" | dd of="$DEV" bs=4M status=progress conv=fsync; then
            echo "ERROR: dd failed." >&2
            exit 4
        fi ;;
    *.img|*.iso)
        if ! dd if="$IMG" of="$DEV" bs=4M status=progress conv=fsync; then
            echo "ERROR: dd failed." >&2
            exit 4
        fi ;;
    *)
        echo "ERROR: unsupported image extension: $IMG" >&2
        exit 1 ;;
esac

sync

# ---------------------------------------------------------------------------
# Post-flash sanity check: read the first MiB back; verify it's a known
# partition-table signature (MBR 0x55AA at offset 0x1FE; GPT "EFI PART" at LBA 1).
# ---------------------------------------------------------------------------

echo ""
echo "[flash-image] Running post-flash sanity check..."
FIRST_SECTOR=$(dd if="$DEV" bs=512 count=1 2>/dev/null | xxd -s 510 -l 2 -p 2>/dev/null || echo "")
if [ "$FIRST_SECTOR" = "55aa" ]; then
    echo "[flash-image]   MBR signature OK (0x55AA)"
else
    LBA1=$(dd if="$DEV" bs=512 skip=1 count=1 2>/dev/null | head -c 8 2>/dev/null || echo "")
    if [ "$LBA1" = "EFI PART" ]; then
        echo "[flash-image]   GPT signature OK (EFI PART)"
    else
        echo "WARN: no MBR/GPT signature found — flash may have failed silently." >&2
        echo "      Try reading the first 512 bytes: dd if=$DEV bs=512 count=1 | xxd | head" >&2
        exit 5
    fi
fi

echo ""
echo "✓ Flash complete."
echo ""
echo "Next steps:"
echo "  1. Physically eject the USB cleanly: sudo eject $DEV"
echo "  2. Plug it into the target host and boot from USB"
echo "  3. Post-first-boot: pull a model"
echo "       kintsugi-models pull qwen3.5:4b"
echo ""
