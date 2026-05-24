#!/bin/bash
# prep-master.sh — pre-imaging sanitization + hygiene pass on a built master
# (either the live-build chroot or a mounted Ventoy master partition).
#
# Implements docs/sanitization-checklist.md (Rules 1-9). The script scans for
# secrets (refuses to proceed if any found), wipes caches/history/logs,
# zero-fills free space (optional), and validates the keep-list is intact.
#
# Usage:
#   sudo ./scripts/prep-master.sh <build-root> [--zero-free-space|--no-zero]
#                                              [--dry-run]
#
# <build-root> must contain a directory tree consistent with the output of
# scripts/usb-toolkit/build-custom-iso.sh — e.g. /tmp/kintsugi-iso-build
# after `lb build`, or /mnt/master if you manually mounted a Ventoy partition.
#
# Exits:
#   0  clean; ready for create-image.sh
#   1  error (missing tooling, bad path)
#   2  secrets detected; refuses to proceed
#   3  keep-list item missing (build is incomplete)

set -euo pipefail

VERSION="0.1.0"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERN_FILE="${SELF_DIR}/secret-patterns.txt"

# --- args ---
BUILD_ROOT=""
DRY_RUN=0
ZERO_FREE_SPACE="${KINTSUGI_SKIP_ZEROFILL:-0}"
# Default: zero-fill ON; override with --no-zero or KINTSUGI_SKIP_ZEROFILL=1
[ "$ZERO_FREE_SPACE" = "1" ] && ZERO_FREE_SPACE=0 || ZERO_FREE_SPACE=1

while [ $# -gt 0 ]; do
    case "$1" in
        --zero-free-space) ZERO_FREE_SPACE=1; shift ;;
        --no-zero)         ZERO_FREE_SPACE=0; shift ;;
        --dry-run)         DRY_RUN=1; shift ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*)
            echo "Unknown flag: $1" >&2; exit 1 ;;
        *)
            if [ -z "$BUILD_ROOT" ]; then BUILD_ROOT=$1; shift
            else echo "Unexpected arg: $1" >&2; exit 1; fi ;;
    esac
done

[ -z "$BUILD_ROOT" ] && { echo "Usage: $0 <build-root> [--zero-free-space|--no-zero] [--dry-run]" >&2; exit 1; }
[ -d "$BUILD_ROOT" ] || { echo "ERROR: build-root does not exist: $BUILD_ROOT" >&2; exit 1; }

# live-build chroot layout puts the filesystem under chroot/
if [ -d "${BUILD_ROOT}/chroot" ]; then
    FS_ROOT="${BUILD_ROOT}/chroot"
    echo "Detected live-build chroot at: $FS_ROOT"
else
    FS_ROOT="$BUILD_ROOT"
    echo "Using build-root as filesystem root: $FS_ROOT"
fi

# --- helpers ---
say()  { echo "[prep-master] $*"; }
warn() { echo "[prep-master] WARN: $*" >&2; }
run()  {
    if [ "$DRY_RUN" = "1" ]; then
        echo "[dry-run] $*"
    else
        # Intentionally use a string argument so shell constructs (globs,
        # `|| true`, etc.) are honored per call. shellcheck disagrees; we
        # accept it.
        bash -c "$*"
    fi
}

# --- Rule 1 + 2: secret scan (REFUSES to proceed on match) ---
say "Scanning for secrets (Rules 1-2)…"
[ -f "$PATTERN_FILE" ] || { echo "ERROR: pattern file missing: $PATTERN_FILE" >&2; exit 1; }

# Build a cleaned pattern file (strip comments + blank lines) — we pass it
# to `grep -f` so leading-dash lines like `-----BEGIN ...` are not mistaken
# for flags, and no shell-escaping concerns arise.
CLEAN_PATTERNS=$(mktemp)
grep -vE '^\s*(#|$)' "$PATTERN_FILE" > "$CLEAN_PATTERNS"
trap 'rm -f "$CLEAN_PATTERNS"' EXIT

# Directories commonly holding personal auth under a freshly-built chroot
SEARCH_DIRS=()
for d in /root/.ssh /home /etc/skel /etc/kintsugi/secrets /var/lib/kintsugi; do
    [ -d "${FS_ROOT}${d}" ] && SEARCH_DIRS+=("${FS_ROOT}${d}")
done
# Plus a lightweight pass over /root (shell rc files, .cache)
[ -d "${FS_ROOT}/root" ] && SEARCH_DIRS+=("${FS_ROOT}/root")

HITS=""
if [ ${#SEARCH_DIRS[@]} -gt 0 ]; then
    HITS=$(grep -rEIl --binary-files=without-match -f "$CLEAN_PATTERNS" "${SEARCH_DIRS[@]}" 2>/dev/null || true)
fi

if [ -n "$HITS" ]; then
    warn "SECRET MATCHES FOUND — refusing to proceed."
    echo ""
    echo "Files containing patterns from $PATTERN_FILE:"
    # shellcheck disable=SC2001  # per-line indent transform; readability > terseness
    echo "$HITS" | sed 's/^/  /'
    echo ""
    echo "Remove the offending files/lines, then re-run prep-master."
    echo "See docs/sanitization-checklist.md Rules 1-2."
    exit 2
fi
say "  clean: no secret patterns detected."

# --- Rule 3: shell history + command caches ---
say "Wiping shell histories + REPL caches (Rule 3)…"
for f in .bash_history .zsh_history .python_history .node_repl_history .mysql_history .psql_history .lesshst .viminfo; do
    run "find '$FS_ROOT' -maxdepth 4 -name '$f' -delete 2>/dev/null || true"
done

# --- Rule 4: persistence scratch ---
say "Wiping on-master persistence scratch (Rule 4)…"
run "rm -rf '$FS_ROOT/var/lib/kintsugi/persistence-test-'* 2>/dev/null || true"
# /data only wiped if present at build time (shouldn't be)
if [ -d "${FS_ROOT}/data" ]; then
    warn "/data directory found at build time — unusual. Wiping contents (preserving dir)."
    run "find '${FS_ROOT}/data' -mindepth 1 -delete 2>/dev/null || true"
fi

# --- Rule 5: installer caches ---
say "Cleaning apt + pip caches (Rule 5)…"
run "rm -rf '${FS_ROOT}/var/cache/apt/archives/'*.deb 2>/dev/null || true"
run "rm -rf '${FS_ROOT}/var/cache/apt/archives/partial/'* 2>/dev/null || true"
run "rm -rf '${FS_ROOT}/root/.cache/pip' '${FS_ROOT}/root/.cache/pipx' 2>/dev/null || true"
run "rm -rf '${FS_ROOT}/tmp/'* '${FS_ROOT}/var/tmp/'* 2>/dev/null || true"

# --- Rule 6: logs ---
say "Truncating logs (Rule 6)…"
for pattern in \
    "${FS_ROOT}/var/log/auth.log*" \
    "${FS_ROOT}/var/log/syslog*" \
    "${FS_ROOT}/var/log/messages*" \
    "${FS_ROOT}/var/log/kern.log*" \
    "${FS_ROOT}/root/.xsession-errors" \
    "${FS_ROOT}/home/live/.xsession-errors" \
    "${FS_ROOT}/var/log/kintsugi/start-ai.log" \
    "${FS_ROOT}/var/log/kintsugi/llama-server.log"
do
    for f in $pattern; do
        [ -f "$f" ] && run "rm -f '$f'"
    done
done
# Journal: truncate but don't remove (systemd needs /var/log/journal)
if [ -d "${FS_ROOT}/var/log/journal" ]; then
    run "find '${FS_ROOT}/var/log/journal' -type f -name '*.journal' -delete 2>/dev/null || true"
fi
# Test harness results from build-time runs
run "rm -rf '${FS_ROOT}/var/log/kintsugi/test-'* 2>/dev/null || true"

# --- Rule 7: verify keep-list ---
say "Verifying keep-list (Rule 7)…"
MISSING=()
for path in \
    /opt/kintsugi-usb/manifest/models-recommended.yaml \
    /opt/kintsugi-usb/manifest/agentic-frameworks-recommended.yaml \
    /etc/kintsugi/build-info.conf \
    /usr/local/bin/start-ai.sh \
    /usr/local/bin/kintsugi-models \
    /usr/local/bin/kintsugi-frameworks \
    /usr/local/bin/usb-test-harness.sh
do
    full="${FS_ROOT}${path}"
    if [ ! -e "$full" ]; then
        MISSING+=("$path")
    fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
    warn "Keep-list items missing:"
    for m in "${MISSING[@]}"; do echo "  - $m" >&2; done
    echo "Build may be incomplete. See docs/sanitization-checklist.md Rule 7." >&2
    exit 3
fi
say "  all keep-list items present."

# --- Rule 9: validate manifest schemas ---
say "Validating manifest schemas (Rule 9)…"
if command -v yq &>/dev/null && yq --version 2>&1 | grep -qi mikefarah; then
    for m in models-recommended agentic-frameworks-recommended; do
        path="${FS_ROOT}/opt/kintsugi-usb/manifest/${m}.yaml"
        [ -f "$path" ] || continue
        v=$(yq eval '.schema_version' "$path" 2>/dev/null)
        if [ "$v" != "1" ]; then
            warn "manifest $m.yaml has schema_version=$v (expected 1)"
        else
            say "  ${m}.yaml: schema v1"
        fi
    done
else
    warn "mikefarah yq not available on host; skipping schema validation (will be re-checked at runtime)"
fi

# --- Rule 8: zero-fill free space (optional) ---
if [ "$ZERO_FREE_SPACE" = "1" ]; then
    say "Zero-filling free space (Rule 8)… this may take a while"
    if [ "$DRY_RUN" = "1" ]; then
        say "  [dry-run] would: dd if=/dev/zero of=${FS_ROOT}/ZEROFILL …"
    else
        # Write zeros to a file until disk is full, then remove it
        dd if=/dev/zero of="${FS_ROOT}/ZEROFILL" bs=1M status=progress 2>&1 | tail -5 || true
        sync
        rm -f "${FS_ROOT}/ZEROFILL"
        sync
    fi
else
    say "Skipping zero-fill (set --zero-free-space to enable)"
fi

# --- Record sanitization receipt ---
RECEIPT="${FS_ROOT}/etc/kintsugi/sanitization-receipt.txt"
if [ "$DRY_RUN" != "1" ]; then
    mkdir -p "$(dirname "$RECEIPT")"
    cat > "$RECEIPT" <<EOF
# Sanitization receipt — generated by prep-master.sh v${VERSION}
timestamp: $(date -Iseconds)
build_root: ${BUILD_ROOT}
fs_root: ${FS_ROOT}
zero_free_space: ${ZERO_FREE_SPACE}
secret_scan: clean
keep_list: complete
EOF
fi

say ""
say "✓ prep-master complete. Ready for create-image.sh."
say "  Receipt: ${RECEIPT}"
