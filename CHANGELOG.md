# Changelog

All notable changes to Kintsugi USB are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning is **CalVer** (`YYYY.M.PATCH`, no leading zeros).

## [2026.5.0] - 2026-05-23 — "First Release"

First tagged release. Ships the wizard-first build toolkit: clone the repo on an
Ubuntu 24.04 host, run `./scripts/kintsugi-build`, answer a short series of TUI
prompts, and produce a personalized flashable `.img.zst` + sha256.

### Added
- **Build wizard** `scripts/kintsugi-build` — single-command TUI from fresh clone to flashable image; writes a replayable `kintsugi-build-profile.yaml` before building so crashes surface a resume hint (#26). Reference: `docs/wizard-guide.md` (#31).
- **Imaging pipeline** — `prep-master.sh` (sanitize + zero free space), `create-image.sh` (dd → zstd → sha256), `flash-image.sh` (recipient-facing flasher with system-disk guards), `verify-image.sh` (post-flash check), `publish-release.sh` (NFS publish target) (#2, #3, #4, #6, #29).
- **Model toolkit** `kintsugi-models` CLI — list/add/pull/remove/verify; user-driven model loading from Ollama/HuggingFace; `--only-recommended` lockdown; sha256 verify against the manifest (#15, #16, #9, #24).
- **Agentic-framework toolkit** `kintsugi-frameworks` CLI — per-framework transactional installs; recommended set: Aider, Claude Code, Codex CLI (#27).
- **Custom Ubuntu ISO** — VS Code + GitHub Copilot extension + `gh` CLI added; Ollama bundled; manifest-driven `start-ai.sh` with dual-runtime status; VS Code telemetry disabled by default (#28, #14).
- **Acceptance tooling** — `usb-test-harness.sh` adapted as the release acceptance gate (Ollama health, CLI presence, manifest parse, dual-runtime status) (#13).
- **Manifests** — `manifest/<version>.json` (sha256 over bundled ISOs/binaries) + `models-recommended.yaml` + `agentic-frameworks-recommended.yaml` (#9, #27).
- **Docs** — recipient quick-start, `toolkit-guide.md`, `update-strategy.md`, requirements/SAD corrections, sanitization checklist, `SECURITY.md` (#11, #17, #18, #22, #23, #8, #20).
- **Licensing** — MIT `LICENSE` + `manifest/THIRD-PARTY-LICENSES.md` (#1, #30).

### Changed
- Field-update model is now `git pull` on the persistence overlay + `kintsugi-models pull` — no full reflash. `update-payload.sh` removed as superseded (#5).
- Project versioning adopts **CalVer**.

### Security
- sha256 integrity verification over NFS-internal distribution. Cryptographic signing (minisign) is **deferred to a later release** (ADR-006 §D5; tracked #19).

### Known limitations
- sha256-only verification; no minisign signatures yet (R-02).
- NFS-internal distribution only; no public release channel.
- No pre-commit secret scanner yet (R-07; tracked #32).
- No runbook human-review gate yet (R-15; tracked #33).
- No CI (Gitea Actions) yet.
- Three agentic-framework recipes; more follow in a later release.

[2026.5.0]: https://git.integrolabs.net/roctinam/kintsugi-usb/releases/tag/v2026.5.0
