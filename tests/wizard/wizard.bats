#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# Offline test suite for scripts/kintsugi-build (US-WIZ-003, issue #38).
#
# Exercises the wizard's `--non-interactive <profile> --dry-run` surface only:
# no root, no real ISO build, no network. `lb`/`whiptail` are stubbed; the real
# mikefarah `yq` is used to parse profiles (see helpers.bash).

load helpers

@test "minimal profile: dry-run succeeds, no frameworks, IDE+Ollama off" {
    run "$WIZARD_BIN" --non-interactive "$(fixture_path minimal.yaml)" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run"* ]]
    [[ "$output" == *"KINTSUGI_SKIP_IDE=1"* ]]
    [[ "$output" == *"KINTSUGI_SKIP_OLLAMA=1"* ]]
    # The resumable profile is written before the build is dispatched.
    [ -f "${WIZARD_BUILDS_ROOT}/kintsugi-test-minimal/build-profile.yaml" ]
}

@test "happy profile: aider framework, IDE+Ollama on, builder invoked" {
    run "$WIZARD_BIN" --non-interactive "$(fixture_path happy.yaml)" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"aider"* ]]
    [[ "$output" == *"KINTSUGI_SKIP_IDE=0"* ]]
    [[ "$output" == *"KINTSUGI_SKIP_OLLAMA=0"* ]]
    [[ "$output" == *"build-custom-iso.sh"* ]]
}

@test "full profile: all three frameworks + both runtimes" {
    run "$WIZARD_BIN" --non-interactive "$(fixture_path full.yaml)" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"aider"* ]]
    [[ "$output" == *"claude-code"* ]]
    [[ "$output" == *"codex-cli"* ]]
    [[ "$output" == *"KINTSUGI_SKIP_IDE=0"* ]]
    [[ "$output" == *"KINTSUGI_SKIP_OLLAMA=0"* ]]
}

@test "unsupported schema_version is rejected (non-zero exit)" {
    run "$WIZARD_BIN" --non-interactive "$(fixture_path bad-schema.yaml)" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"schema_version"* ]]
}
