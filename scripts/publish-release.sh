#!/bin/bash
# publish-release.sh — upload a release artifact set to the warehouse NFS mount.
#
# Per ADR-006 §D4: v1.0 images publish to /mnt/warehouse/releases/kintsugi-usb/
# (overridable via KINTSUGI_PUBLISH_NFS). Gitea releases carry source tags +
# changelog + small artifacts (manifests, pubkey when signing lands); NOT the
# multi-GB images.
#
# Usage:
#   ./scripts/publish-release.sh <primary-artifact> <version> [extras...]
#                                [--publish-nfs PATH]
#                                [--dry-run]
#                                [--force]
#
# Example:
#   ./scripts/publish-release.sh ./dist/kintsugi-v2026.5.0.img.zst v2026.5.0 \\
#       ./dist/kintsugi-v2026.5.0.sha256 ./dist/manifest.json
#
# Exit codes:
#   0  success
#   1  usage / bad input
#   2  NFS target missing or not writable
#   3  version already exists (without --force)
#   4  copy failed

set -euo pipefail

VERSION="0.1.0"

NFS_ROOT="${KINTSUGI_PUBLISH_NFS:-/mnt/warehouse/releases/kintsugi-usb}"
PRIMARY=""
VERSION_TAG=""
EXTRAS=()
DRY_RUN=0
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --publish-nfs) NFS_ROOT=$2; shift 2 ;;
        --dry-run)     DRY_RUN=1; shift ;;
        --force)       FORCE=1; shift ;;
        -h|--help)     sed -n '2,19p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*)            echo "Unknown flag: $1" >&2; exit 1 ;;
        *)
            if [ -z "$PRIMARY" ]; then PRIMARY=$1; shift
            elif [ -z "$VERSION_TAG" ]; then VERSION_TAG=$1; shift
            else EXTRAS+=("$1"); shift; fi ;;
    esac
done

[ -z "$PRIMARY" ] || [ -z "$VERSION_TAG" ] && {
    echo "Usage: $0 <primary-artifact> <version> [extras...] [--publish-nfs PATH] [--dry-run] [--force]" >&2
    exit 1
}
[ -r "$PRIMARY" ] || { echo "ERROR: primary not readable: $PRIMARY" >&2; exit 1; }
for e in "${EXTRAS[@]}"; do
    [ -r "$e" ] || { echo "ERROR: extra not readable: $e" >&2; exit 1; }
done

# NFS preflight: target must exist and be writable (unless --dry-run).
VERSION_DIR="${NFS_ROOT}/${VERSION_TAG}"
echo "[publish-release] v${VERSION}"
echo "  primary:     $PRIMARY"
echo "  version:     $VERSION_TAG"
echo "  target:      $VERSION_DIR"
echo "  extras:      ${#EXTRAS[@]} file(s)"

if [ "$DRY_RUN" != "1" ]; then
    if ! mkdir -p "$NFS_ROOT" 2>/dev/null; then
        echo "ERROR: NFS root not writable: $NFS_ROOT" >&2
        echo "Hint: verify the warehouse NFS is mounted, or pass --publish-nfs /local/dir" >&2
        echo "      Environment override: export KINTSUGI_PUBLISH_NFS=/path" >&2
        exit 2
    fi
    if [ -d "$VERSION_DIR" ] && [ "$FORCE" != "1" ]; then
        echo "ERROR: version directory already exists: $VERSION_DIR" >&2
        echo "Pass --force to overwrite, or choose a new version." >&2
        exit 3
    fi
fi

# Verify the sha256 file (if present) matches the primary artifact.
PRIMARY_DIR="$(dirname "$PRIMARY")"
SHA_FILE="${PRIMARY_DIR}/$(basename "$PRIMARY").sha256"
# Also accept a companion .sha256 file in EXTRAS
for e in "${EXTRAS[@]}"; do
    case "$e" in *.sha256) SHA_FILE="$e" ;; esac
done
if [ -f "$SHA_FILE" ]; then
    echo "[publish-release] Verifying sha256 against $SHA_FILE..."
    ( cd "$(dirname "$SHA_FILE")" && sha256sum -c "$(basename "$SHA_FILE")" >/dev/null 2>&1 ) || {
        echo "ERROR: sha256 verification FAILED for $PRIMARY" >&2
        echo "This means the artifact does not match its checksum. Aborting." >&2
        exit 4
    }
    echo "[publish-release]   sha256 OK"
else
    echo "[publish-release] WARN: no companion .sha256 file found; skipping pre-upload verify"
fi

if [ "$DRY_RUN" = "1" ]; then
    echo ""
    echo "[dry-run] Would copy to $VERSION_DIR:"
    echo "  $PRIMARY"
    for e in "${EXTRAS[@]}"; do echo "  $e"; done
    echo "[dry-run] Would update releases.json index at $NFS_ROOT/releases.json"
    exit 0
fi

# Copy artifacts.
mkdir -p "$VERSION_DIR"
echo "[publish-release] Copying to $VERSION_DIR..."
cp -v "$PRIMARY" "$VERSION_DIR/" || { echo "ERROR: copy failed: $PRIMARY" >&2; exit 4; }
for e in "${EXTRAS[@]}"; do
    cp -v "$e" "$VERSION_DIR/" || { echo "ERROR: copy failed: $e" >&2; exit 4; }
done

# Post-copy: verify checksums from the NFS side (detects NFS-transit corruption).
if [ -f "$SHA_FILE" ]; then
    echo "[publish-release] Post-copy sha256 check from NFS..."
    ( cd "$VERSION_DIR" && sha256sum -c "$(basename "$SHA_FILE")" >/dev/null 2>&1 ) || {
        echo "ERROR: post-copy sha256 check FAILED on NFS; the copy is corrupt." >&2
        echo "       Investigate before reporting the release as published." >&2
        exit 4
    }
    echo "[publish-release]   NFS copy verified"
fi

# Maintain a simple releases.json index at the NFS root.
PRIMARY_NAME="$(basename "$PRIMARY")"
PRIMARY_SHA=""
[ -f "$SHA_FILE" ] && PRIMARY_SHA=$(awk '{print $1}' "$SHA_FILE" | head -1)
PRIMARY_SIZE=$(stat --format=%s "$PRIMARY" 2>/dev/null || echo 0)
TS=$(date -Iseconds)

INDEX="${NFS_ROOT}/releases.json"
TMP_INDEX=$(mktemp)
trap 'rm -f "$TMP_INDEX"' EXIT

if [ ! -f "$INDEX" ]; then
    cat > "$INDEX" <<EMPTY
{
  "schema_version": 1,
  "releases": []
}
EMPTY
fi

ENTRY=$(cat <<REL
    {
      "version": "$VERSION_TAG",
      "published_at": "$TS",
      "primary": "$PRIMARY_NAME",
      "size_bytes": $PRIMARY_SIZE,
      "sha256": "$PRIMARY_SHA",
      "path": "$VERSION_DIR"
    }
REL
)

# Append (or replace on --force) the release entry. Simple text edit; no yq
# dependency on the NFS host.
if grep -q "\"version\": \"${VERSION_TAG}\"" "$INDEX" 2>/dev/null; then
    if [ "$FORCE" = "1" ]; then
        echo "[publish-release] Replacing index entry for ${VERSION_TAG}..."
    fi
    # Naive approach: drop existing entry + append (awk is more robust than sed
    # here). For v1.0 we accept the append-only model; iteration-2 improves this.
fi

# Write a per-version shadow index alongside the artifact for immediate lookup
cat > "${VERSION_DIR}/release.json" <<IDX
{
  "schema_version": 1,
  "version": "$VERSION_TAG",
  "published_at": "$TS",
  "primary": "$PRIMARY_NAME",
  "size_bytes": $PRIMARY_SIZE,
  "sha256": "$PRIMARY_SHA",
  "artifacts_count": $((1 + ${#EXTRAS[@]}))
}
IDX

# Best-effort insert into the global index. If this fails for any reason,
# the per-version release.json remains authoritative.
python3 - "$INDEX" <<PY || echo "[publish-release] WARN: could not update releases.json index (per-version release.json still present)"
import json, sys
path = sys.argv[1]
try:
    with open(path) as f: d = json.load(f)
except Exception:
    d = {"schema_version": 1, "releases": []}
d.setdefault("releases", [])
new_entry = $ENTRY
# Drop any existing same-version entry (idempotency on --force)
d["releases"] = [r for r in d["releases"] if r.get("version") != "$VERSION_TAG"]
d["releases"].append(new_entry)
d["releases"].sort(key=lambda r: r.get("published_at", ""))
with open(path, "w") as f: json.dump(d, f, indent=2)
PY

echo ""
echo "✓ publish-release complete"
echo ""
echo "Published:   $VERSION_DIR"
echo "Index:       $INDEX"
echo ""
echo "Recipient access (for warehouse-internal users):"
echo "  # Mount the warehouse NFS at /mnt/warehouse, then:"
echo "  cd $VERSION_DIR"
echo "  sha256sum -c $(basename "${SHA_FILE:-<sha-file-not-provided>}")"
echo "  sudo dd if=${PRIMARY_NAME} of=/dev/sdX bs=4M status=progress conv=fsync"
