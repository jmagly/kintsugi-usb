# SPDX-License-Identifier: MIT
# Shared bats helpers for the kintsugi-build wizard test suite.
#
# These tests exercise the wizard's `--non-interactive <profile> --dry-run`
# surface ONLY. They run fully offline, with no root and no real ISO build.
#
# Design notes:
#   * We prepend a PATH stub dir holding fake `lb` and `whiptail` binaries so
#     check_prerequisites' have_lb passes and whiptail is never actually
#     invoked (non-interactive mode never calls the prompt helpers anyway).
#   * We do NOT stub `yq`. The wizard's read_profile() calls the real
#     mikefarah `yq eval` to parse profiles, so the real binary must stay on
#     PATH. We keep /usr/local/bin (where the mikefarah yq lives) reachable.
#   * KINTSUGI_BUILDS_ROOT points at a throwaway temp dir so build-profile.yaml
#     and the build dir land somewhere we can inspect and delete.

# Absolute path to the repo root (tests/wizard/ -> repo root is two levels up).
WIZARD_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WIZARD_BIN="${WIZARD_REPO_ROOT}/scripts/kintsugi-build"
WIZARD_FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures" && pwd)"

setup() {
    # Per-test scratch space.
    WIZARD_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kintsugi-wizard.XXXXXX")"
    WIZARD_STUB_BIN="${WIZARD_TMP}/stub-bin"
    WIZARD_BUILDS_ROOT="${WIZARD_TMP}/builds"
    mkdir -p "$WIZARD_STUB_BIN" "$WIZARD_BUILDS_ROOT"

    # Fake `lb` — only needs to exist on PATH and exit 0 so have_lb() passes.
    cat > "${WIZARD_STUB_BIN}/lb" <<'STUB'
#!/bin/sh
exit 0
STUB

    # Fake `whiptail` — present so the wizard does not warn about it falling
    # back to plain prompts. Non-interactive mode never calls it, but a stub
    # keeps the environment hermetic and the output clean.
    cat > "${WIZARD_STUB_BIN}/whiptail" <<'STUB'
#!/bin/sh
exit 0
STUB

    chmod +x "${WIZARD_STUB_BIN}/lb" "${WIZARD_STUB_BIN}/whiptail"

    # Locate the real mikefarah yq so we can guarantee its dir stays on PATH
    # even after we prepend the stub dir. The wizard requires real yq to parse.
    local real_yq yq_dir
    real_yq="$(command -v yq || true)"
    if [ -n "$real_yq" ]; then
        yq_dir="$(cd "$(dirname "$real_yq")" && pwd)"
    else
        yq_dir="/usr/local/bin"
    fi

    # Stub dir first (overrides lb/whiptail), then the real yq's dir, then the
    # rest of the inherited PATH (df, sudo, find, etc. still resolve).
    export PATH="${WIZARD_STUB_BIN}:${yq_dir}:${PATH}"

    # Redirect all wizard output dirs into the scratch area.
    export KINTSUGI_BUILDS_ROOT="$WIZARD_BUILDS_ROOT"
}

teardown() {
    if [ -n "${WIZARD_TMP:-}" ] && [ -d "$WIZARD_TMP" ]; then
        rm -rf "$WIZARD_TMP"
    fi
}

# write_fixture <dest-path> <fixture-name>
# Copy a checked-in fixture profile into a writable location (handy when a test
# wants to mutate it). Most tests can reference the fixtures dir directly.
write_fixture() {
    local dest=$1 name=$2
    cp "${WIZARD_FIXTURES}/${name}" "$dest"
}

# fixture_path <fixture-name> — echo the absolute path to a checked-in fixture.
fixture_path() {
    echo "${WIZARD_FIXTURES}/$1"
}
