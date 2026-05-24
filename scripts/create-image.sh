#!/bin/bash
# create-image.sh — package a built Kintsugi master ISO for release.
#
# Takes a built master (typically from `live-build` — an .iso or a raw disk
# image) and produces a distributable `.img.zst` + `.sha256`. Per ADR-002
# amendment (2026-04-21 spike), single artifact; no separate payload tarball.
#
# Usage:
#   ./scripts/create-image.sh <source-image> [--output-dir DIR]
#                                            [--name NAME] [--level N]
#                                            [--dry-run]
#
# Arguments:
#   <source-image>   Either an .iso produced by build-custom-iso.sh, or a
#                    raw disk image from a prep-mastered USB.
#
# Options:
#   --output-dir DIR   Where to write artifacts (default: ./dist/)
#   --name NAME        Artifact base name (default: <source-basename>)
#   --level N          zstd compression level 1-22 (default: 19; long-form)
#   --dry-run          Print the plan; do not write artifacts.
#
# Outputs:
#   <output>/<name>.img.zst    Compressed image
#   <output>/<name>.sha256     Checksum line (sha256 of <name>.img.zst)
#
# Exit codes:
#   0  success
#   1  usage / missing tool / unreadable source
#   2  compression or hashing failed

set -euo pipefail

VERSION="0.1.0"

SRC=""
OUTPUT_DIR="./dist"
NAME=""
LEVEL=19
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --output-dir) OUTPUT_DIR=$2; shift 2 ;;
        --name)       NAME=$2; shift 2 ;;
        --level)      LEVEL=$2; shift 2 ;;
        --dry-run)    DRY_RUN=1; shift ;;
        -h|--help)    sed -n '2,25p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*)           echo "Unknown flag: $1" >&2; exit 1 ;;
        *)            if [ -z "$SRC" ]; then SRC=$1; shift
                      else echo "Unexpected arg: $1" >&2; exit 1; fi ;;
    esac
done

[ -z "$SRC" ] && { echo "Usage: $0 <source-image> [--output-dir DIR] [--name NAME] [--level N] [--dry-run]" >&2; exit 1; }
[ -r "$SRC" ] || { echo "ERROR: source not readable: $SRC" >&2; exit 1; }

command -v zstd     &>/dev/null || { echo "ERROR: zstd not installed. sudo apt-get install zstd" >&2; exit 1; }
command -v sha256sum &>/dev/null || { echo "ERROR: sha256sum missing (coreutils)" >&2; exit 1; }

[ -z "$NAME" ] && NAME="$(basename "$SRC" | sed 's/\.\(iso\|img\|hybrid\.iso\)$//')"

OUT_IMG="${OUTPUT_DIR}/${NAME}.img.zst"
OUT_SHA="${OUTPUT_DIR}/${NAME}.sha256"

echo "[create-image] v${VERSION}"
echo "  source:    $SRC ($(du -h "$SRC" | cut -f1))"
echo "  output:    $OUT_IMG"
echo "  sha256:    $OUT_SHA"
echo "  zstd lvl:  $LEVEL (long-form)"

if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] Not writing artifacts. Rerun without --dry-run to apply."
    exit 0
fi

mkdir -p "$OUTPUT_DIR"

# Compress with zstd, using --long for better ratio on large sparse images.
echo "[create-image] Compressing (this may take several minutes)..."
if ! zstd --long=27 "-${LEVEL}" --threads=0 \
         -f -o "$OUT_IMG" "$SRC"; then
    echo "ERROR: zstd failed" >&2
    exit 2
fi

# Compute sha256 of the compressed artifact + record in a one-line file
# compatible with `sha256sum -c`.
echo "[create-image] Computing sha256..."
( cd "$OUTPUT_DIR" && sha256sum "$(basename "$OUT_IMG")" > "$(basename "$OUT_SHA")" ) || {
    echo "ERROR: sha256sum failed" >&2
    exit 2
}

echo ""
echo "✓ create-image complete"
echo ""
echo "Artifact:   $OUT_IMG ($(du -h "$OUT_IMG" | cut -f1))"
echo "Checksum:   $OUT_SHA"
echo ""
echo "Next steps:"
echo "  scripts/generate-manifest.sh \"$OUT_IMG\"         # produce release manifest.json"
echo "  scripts/publish-release.sh   \"$OUT_IMG\" vX.Y.Z  # upload to warehouse NFS"
echo ""
echo "Recipient verification one-liner:"
echo "  ( cd \"$OUTPUT_DIR\" && sha256sum -c \"$(basename "$OUT_SHA")\" )"
