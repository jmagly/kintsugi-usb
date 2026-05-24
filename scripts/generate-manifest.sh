#!/bin/bash
# generate-manifest.sh — produce release manifest.json for a built artifact set.
#
# Per ADR-002 amendment + ADR-003, each release carries a manifest enumerating
# every artifact with its sha256. In v1.0 (sha256-only, no minisign per
# ADR-006 §D5) this is the primary integrity anchor for recipients.
#
# Usage:
#   ./scripts/generate-manifest.sh <primary-artifact> [extra-artifacts...]
#                                  [--version X.Y.Z]
#                                  [--output PATH]
#                                  [--dry-run]
#
# Emits JSON (single doc) with:
#   schema_version, version, generated_at, generator, primary, artifacts[]
#
# Each `artifacts[]` entry: { name, size_bytes, sha256, role }
#   role = "image" | "checksum" | "manifest" | "signature" | "doc"

set -euo pipefail

VERSION_TAG=""
OUTPUT=""
DRY_RUN=0
ARTIFACTS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION_TAG=$2; shift 2 ;;
        --output)  OUTPUT=$2; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*)        echo "Unknown flag: $1" >&2; exit 1 ;;
        *)         ARTIFACTS+=("$1"); shift ;;
    esac
done

[ ${#ARTIFACTS[@]} -eq 0 ] && { echo "Usage: $0 <primary-artifact> [extras...] [--version X.Y.Z] [--output PATH]" >&2; exit 1; }
command -v sha256sum &>/dev/null || { echo "ERROR: sha256sum missing" >&2; exit 1; }

# Validate all artifact paths are readable
for a in "${ARTIFACTS[@]}"; do
    [ -r "$a" ] || { echo "ERROR: not readable: $a" >&2; exit 1; }
done

PRIMARY="${ARTIFACTS[0]}"
PRIMARY_DIR="$(dirname "$PRIMARY")"

# Default output alongside the primary artifact
[ -z "$OUTPUT" ] && OUTPUT="${PRIMARY_DIR}/manifest.json"

# Classify an artifact by extension
classify() {
    local f=$1
    case "$f" in
        *.img.zst|*.iso|*.img) echo "image" ;;
        *.sha256|*.sha256sum)  echo "checksum" ;;
        *.minisig|*.sig|*.asc) echo "signature" ;;
        *.json)                echo "manifest" ;;
        *.md|*.txt)            echo "doc" ;;
        *)                     echo "other" ;;
    esac
}

json_entry() {
    local path=$1
    local name size sha role
    name=$(basename "$path")
    size=$(stat --format=%s "$path" 2>/dev/null || echo 0)
    sha=$(sha256sum "$path" | awk '{print $1}')
    role=$(classify "$path")
    cat <<ENTRY
    {
      "name": "$name",
      "size_bytes": $size,
      "sha256": "$sha",
      "role": "$role"
    }
ENTRY
}

echo "[generate-manifest] building manifest for:"
for a in "${ARTIFACTS[@]}"; do
    echo "  - $a ($(classify "$a"))"
done

# Build manifest JSON
TS=$(date -Iseconds)
HOST=$(hostname 2>/dev/null || echo unknown)

# Compute entries
ENTRIES=""
for a in "${ARTIFACTS[@]}"; do
    entry=$(json_entry "$a")
    if [ -z "$ENTRIES" ]; then
        ENTRIES="$entry"
    else
        ENTRIES="${ENTRIES},${entry}"
    fi
done

# Use yq to produce compact-sane JSON; fall back to literal string construction
# if yq absent (still valid JSON either way).
MANIFEST_JSON=$(cat <<MANIFEST
{
  "schema_version": 1,
  "generator": "generate-manifest.sh v0.1.0",
  "generated_at": "$TS",
  "generated_on_host": "$HOST",
  "version": "$VERSION_TAG",
  "primary": "$(basename "$PRIMARY")",
  "artifacts": [
$ENTRIES
  ]
}
MANIFEST
)

if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] would write: $OUTPUT"
    echo "---"
    echo "$MANIFEST_JSON"
    exit 0
fi

mkdir -p "$(dirname "$OUTPUT")"
echo "$MANIFEST_JSON" > "$OUTPUT"

echo ""
echo "✓ manifest written: $OUTPUT"
echo ""
echo "Next step (v1.0 sha256-only):"
echo "  scripts/publish-release.sh \"$PRIMARY\" $VERSION_TAG"
