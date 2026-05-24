#!/bin/bash
# verify-image.sh — recipient-facing wrapper around sha256 (v1.0) and
# minisign (v1.1+, deferred per ADR-006 §D5).
#
# Usage:
#   ./scripts/verify-image.sh <image> [--sha <sha-file>]
#
# Arguments:
#   <image>         path to .img.zst / .iso / .img
#
# Options:
#   --sha FILE      explicit sha256sum file (default: <image>.sha256)
#
# Behavior:
#   v1.0 — runs `sha256sum -c` against the .sha256 file. sha mismatch
#          prints a clear tamper/corruption message.
#   v1.1 — will also verify minisign signature (not yet wired up;
#          issue #19 in iteration-2).
#
# Exit codes:
#   0  image verified
#   1  usage error
#   2  sha256 mismatch
#   3  sha file missing

set -euo pipefail

VERSION="0.1.0"

IMG=""
SHA_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --sha)     SHA_FILE=$2; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*)        echo "Unknown flag: $1" >&2; exit 1 ;;
        *)         if [ -z "$IMG" ]; then IMG=$1; shift
                   else echo "Unexpected arg: $1" >&2; exit 1; fi ;;
    esac
done

[ -z "$IMG" ] && { echo "Usage: $0 <image> [--sha FILE]" >&2; exit 1; }
[ -r "$IMG" ] || { echo "ERROR: image not readable: $IMG" >&2; exit 1; }

[ -z "$SHA_FILE" ] && SHA_FILE="${IMG}.sha256"

if [ ! -f "$SHA_FILE" ]; then
    cat >&2 <<EOF
ERROR: sha256 file not found: $SHA_FILE

Kintsugi releases ship a companion .sha256 alongside the image. If you
don't have it, re-download from the official release channel. Do NOT
flash an image you cannot verify.

v1.0 ships sha256-only (ADR-006 §D5). Full minisign verification arrives
in v1.1 and will be wired into this script at that time.
EOF
    exit 3
fi

echo "[verify-image] v${VERSION}"
echo "  image:  $IMG"
echo "  sha256: $SHA_FILE"
echo ""

if ( cd "$(dirname "$SHA_FILE")" && sha256sum -c "$(basename "$SHA_FILE")" 2>&1 ); then
    echo ""
    echo "✓ sha256 verified — image integrity confirmed."
    echo ""
    echo "(Note: v1.0 does NOT include cryptographic signature verification."
    echo " That protects against transit corruption and accidental substitution,"
    echo " but not against a sophisticated attacker who can tamper with both"
    echo " the image and its .sha256 on the same server. Iteration-2 adds"
    echo " minisign signatures that close this gap.)"
    echo ""
    echo "Next step: flash with scripts/flash-image.sh"
    exit 0
else
    cat >&2 <<EOF

✗ sha256 MISMATCH

The downloaded image does not match its published checksum. Possible causes,
in order of likelihood:

  1. Incomplete download — re-download the image and try again.
  2. Disk corruption at rest — copy the file from a different source.
  3. Storage media with bad sectors — try a different drive.
  4. Intentional tampering — report via SECURITY.md.

DO NOT flash this image.
EOF
    exit 2
fi
