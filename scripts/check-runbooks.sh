#!/bin/bash
# check-runbooks.sh — release gate: every doc tagged as a runbook must carry a
# human review sign-off marker (R-15, Gitea #33).
#
# A runbook opts in with:    <!-- runbook -->
# A completed review adds:    <!-- reviewed-by: NAME | YYYY-MM-DD | COMMIT-OR-NA -->
#
# Enforces that the sign-off marker EXISTS. The human review it attests to is
# defined in docs/runbook-review-checklist.md.
#
# Usage:  scripts/check-runbooks.sh [search-dir]   (default: docs)
# Exit:   0 = all tagged runbooks signed off; 1 = one or more unsigned.
#
# SPDX-License-Identifier: MIT
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"
SEARCH_DIR="${1:-docs}"

# Meta-docs that document the marker convention itself contain the literal
# <!-- runbook --> string in prose/examples — they are not runbooks.
is_excluded() {
    case "$1" in
        docs/runbook-review-checklist.md|docs/release-process.md) return 0 ;;
        *) return 1 ;;
    esac
}

mapfile -t ALL_TAGGED < <(grep -rlE '<!--[[:space:]]*runbook[[:space:]]*-->' "$SEARCH_DIR" --include='*.md' 2>/dev/null || true)
RUNBOOKS=()
for f in "${ALL_TAGGED[@]}"; do
    is_excluded "$f" || RUNBOOKS+=("$f")
done

if [ "${#RUNBOOKS[@]}" -eq 0 ]; then
    echo "check-runbooks: no runbook-tagged docs under ${SEARCH_DIR}/ (nothing to gate)"
    exit 0
fi

FAIL=0
for rb in "${RUNBOOKS[@]}"; do
    if marker=$(grep -oE '<!--[[:space:]]*reviewed-by:[^>]+-->' "$rb" | head -1) && [ -n "$marker" ]; then
        echo "  OK        ${rb}  ${marker}"
    else
        echo "  UNSIGNED  ${rb}  — no reviewed-by marker"
        FAIL=1
    fi
done

if [ "$FAIL" -ne 0 ]; then
    echo ""
    echo "✗ check-runbooks: one or more runbooks lack a review sign-off (R-15)."
    echo "  Review against docs/runbook-review-checklist.md, then add near the title:"
    echo "  <!-- reviewed-by: YourName | $(date +%F) | <commit> -->"
    exit 1
fi

echo "✓ check-runbooks: all tagged runbooks carry a review sign-off."
exit 0
