#!/bin/bash
# verify-image.sh — recipient-facing wrapper around sha256 (always) and
# minisign (Ed25519, activates automatically once kintsugi.pub + a .minisig
# are present — v1.1 signing, issue #19).
#
# Usage:
#   ./scripts/verify-image.sh <image> [--sha FILE] [--sig FILE] [--pubkey FILE]
#
# Arguments:
#   <image>         path to .img.zst / .iso / .img
#
# Options:
#   --sha FILE      explicit sha256sum file   (default: <image>.sha256)
#   --sig FILE      explicit minisign sig     (default: <image>.minisig)
#   --pubkey FILE   explicit public key       (default: kintsugi.pub next to
#                   the image, else next to this script / repo root)
#
# Behavior:
#   Stage 1 (always): sha256 integrity check against the .sha256 file.
#   Stage 2 (when available): if a .minisig signature AND a kintsugi.pub are
#           found, verify the minisign signature. Requires the `minisign`
#           binary. If no signature is present, this stage is skipped (v1.0
#           sha256-only releases per ADR-006 §D5).
#
# Exit codes:
#   0  image verified (sha256, plus signature if one was present)
#   1  usage error
#   2  sha256 mismatch
#   3  sha file missing
#   4  signature present but verification failed / minisign unavailable

set -euo pipefail

VERSION="0.2.0"

IMG=""
SHA_FILE=""
SIG_FILE=""
PUBKEY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --sha)     SHA_FILE=$2; shift 2 ;;
        --sig)     SIG_FILE=$2; shift 2 ;;
        --pubkey)  PUBKEY=$2; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*)        echo "Unknown flag: $1" >&2; exit 1 ;;
        *)         if [ -z "$IMG" ]; then IMG=$1; shift
                   else echo "Unexpected arg: $1" >&2; exit 1; fi ;;
    esac
done

[ -z "$IMG" ] && { echo "Usage: $0 <image> [--sha FILE] [--sig FILE] [--pubkey FILE]" >&2; exit 1; }
[ -r "$IMG" ] || { echo "ERROR: image not readable: $IMG" >&2; exit 1; }

[ -z "$SHA_FILE" ] && SHA_FILE="${IMG}.sha256"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# ---- Stage 1: sha256 (always) ----
if [ ! -f "$SHA_FILE" ]; then
    cat >&2 <<EOF
ERROR: sha256 file not found: $SHA_FILE

Kintsugi releases ship a companion .sha256 alongside the image. If you
don't have it, re-download from the official release channel. Do NOT
flash an image you cannot verify.

v1.0 ships sha256-only (ADR-006 §D5). Full minisign verification arrives
in v1.1 and activates here automatically once a .minisig + kintsugi.pub
are present.
EOF
    exit 3
fi

echo "[verify-image] v${VERSION}"
echo "  image:  $IMG"
echo "  sha256: $SHA_FILE"
echo ""

if ! ( cd "$(dirname "$SHA_FILE")" && sha256sum -c "$(basename "$SHA_FILE")" 2>&1 ); then
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

echo ""
echo "✓ sha256 verified — image integrity confirmed."

# ---- Stage 2: minisign signature (when available) ----
[ -z "$SIG_FILE" ] && SIG_FILE="${IMG}.minisig"

# Resolve pubkey: explicit flag > next to image > repo root (next to scripts/)
if [ -z "$PUBKEY" ]; then
    if [ -f "$(dirname "$IMG")/kintsugi.pub" ]; then
        PUBKEY="$(dirname "$IMG")/kintsugi.pub"
    elif [ -f "${SCRIPT_DIR}/../kintsugi.pub" ]; then
        PUBKEY="${SCRIPT_DIR}/../kintsugi.pub"
    fi
fi

if [ -f "$SIG_FILE" ]; then
    echo ""
    echo "  signature: $SIG_FILE"

    if ! command -v minisign >/dev/null 2>&1; then
        cat >&2 <<EOF

✗ A signature ($SIG_FILE) is present but \`minisign\` is not installed.
  This release is signed — you should verify it. Install minisign:
    Debian/Ubuntu:  sudo apt install minisign
    macOS:          brew install minisign
  then re-run this script. Do NOT flash a signed release you have not
  signature-verified.
EOF
        exit 4
    fi

    if [ -z "$PUBKEY" ] || [ ! -f "$PUBKEY" ]; then
        cat >&2 <<EOF

✗ A signature is present but no public key (kintsugi.pub) was found.
  Fetch the maintainer's key out-of-band (pinned in README.md), place it at
  kintsugi.pub next to the image, or pass --pubkey FILE. Do NOT flash without
  verifying the signature.
EOF
        exit 4
    fi

    echo "  pubkey:    $PUBKEY"
    if minisign -V -p "$PUBKEY" -m "$IMG" -x "$SIG_FILE"; then
        echo ""
        echo "✓ minisign signature verified — image is authentic."
        echo ""
        echo "Next step: flash with scripts/flash-image.sh"
        exit 0
    else
        cat >&2 <<EOF

✗ minisign signature verification FAILED.

The image's sha256 matched, but its signature does not verify against the
pinned public key. This is exactly the tampering an attacker who controls both
the image and its checksum cannot forge. DO NOT flash. Report via SECURITY.md.
EOF
        exit 4
    fi
else
    # No signature present — v1.0 sha256-only path (behavior unchanged).
    echo ""
    echo "(No signature found alongside this image. v1.0 releases ship sha256-only"
    echo " per ADR-006 §D5 — integrity is confirmed but authenticity is not"
    echo " cryptographically attested. That protects against transit corruption and"
    echo " accidental substitution, but not against an attacker who can tamper with"
    echo " both the image and its .sha256 on the same server. v1.1+ releases add a"
    echo " minisign .minisig that this script verifies automatically when present.)"
    echo ""
    echo "Next step: flash with scripts/flash-image.sh"
    exit 0
fi
