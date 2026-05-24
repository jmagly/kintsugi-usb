#!/bin/bash
# install-hooks.sh — activate the tracked git hooks in scripts/hooks/.
#
# Points git at the in-repo, version-controlled hooks directory instead of the
# untracked .git/hooks/, so every clone gets the same hooks after one command.
# Run once per clone.
#
# SPDX-License-Identifier: MIT
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

chmod +x scripts/hooks/* 2>/dev/null || true
git config core.hooksPath scripts/hooks

echo "✓ git hooks activated (core.hooksPath = scripts/hooks)"
echo "  active hooks: $(find scripts/hooks -maxdepth 1 -type f -printf '%f ' 2>/dev/null)"
echo "  pre-commit secret scan reuses scripts/secret-patterns.txt (risk R-07, #32)."
echo ""
echo "To deactivate:  git config --unset core.hooksPath"
