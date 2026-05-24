# CI/CD Scaffold — Kintsugi USB

**Version**: 1.0 (initial scaffold; Iteration 1 deliverable)
**Target platform**: Gitea Actions (self-hosted at git.integrolabs.net)
**Last updated**: 2026-04-20

## Scope for v1.0

**Minimal** pre-merge quality gate + repo-hygiene checks. Full release automation (build → image → sign → publish) is deferred; v1.0 releases are built and published manually by the maintainer per ADR-002 / ADR-003 / iteration-001-plan.md.

## Pipeline Stages (v1.0 scope)

```
push/PR → [lint] → [unit tests] → [markdown lint] → [secret scan] → DONE
                                                                        ↓
                                                          (manual release steps)
```

### Stage 1: Lint
- **shellcheck** on all `.sh` files under `scripts/` once they exist
- Fail build on any error-level finding; warn-level is informational

### Stage 2: Unit Tests
- **bats** on any `tests/*.bats` files
- Prep-master secret-pattern matcher, checksum helper, version parser, etc.

### Stage 3: Markdown Lint
- **markdownlint-cli** with a `.markdownlint.json` at repo root
- Key rules: MD013 line length (loose), MD033 inline HTML (disabled), MD041 first-line-h1 (enforced)

### Stage 4: Secret Scan
- **gitleaks** or **trufflehog** full-repo scan on every push
- Baseline file committed to track accepted low-risk matches (e.g., example `kintsugi.pub` content)
- FAIL on any match outside the baseline — this protects R-07 (API keys in repo) and enforces CLAUDE.md public-repo rules

## Stretch for v1.0 (best-effort)

### QEMU UEFI Smoke Test (stretch)
- On tag push (release candidate), boot a pre-built `kintsugi-base.img.zst` in QEMU with OVMF
- Assert: Ventoy menu renders; the "Ubuntu ML-Support" entry is present by string match
- Out of scope if runner can't supply >10 GB scratch disk or nested virt

## Deferred to Iteration 2+

- CI-driven release publishing (build-image → sign → upload to Gitea)
- Reproducible-build attestation (requires Cubic alternative per R-03)
- Hardware-in-the-loop tests on fleet hosts
- Payload-tarball regeneration CI job
- SBOM generation (CycloneDX)

## Gitea Actions Workflow Scaffold

File: `.gitea/workflows/ci.yml` (to be committed during Iteration 1)

```yaml
# .gitea/workflows/ci.yml
# Minimal CI for Kintsugi USB — v1.0 scope
# Self-hosted runner on integrolabs infrastructure

name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest  # self-hosted label can be swapped in
    steps:
      - uses: actions/checkout@v4

      - name: shellcheck
        run: |
          if find scripts -name '*.sh' | read; then
            shellcheck scripts/*.sh
          else
            echo "No scripts yet; skipping shellcheck"
          fi

      - name: markdownlint
        run: |
          npx markdownlint-cli '**/*.md' --ignore node_modules

      - name: gitleaks
        run: |
          gitleaks detect --source . --verbose

  test:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4

      - name: bats
        run: |
          if find tests -name '*.bats' 2>/dev/null | read; then
            bats tests/
          else
            echo "No bats tests yet; skipping"
          fi
```

### Runner Requirements (Gitea Actions self-hosted)

- Ubuntu 22.04 or 24.04
- Installed: `bash`, `shellcheck`, `bats`, `node` (for markdownlint-cli), `gitleaks` (or `trufflehog`)
- For QEMU stretch job: `qemu-system-x86_64`, `ovmf`, at least 16 GB free disk

### Runner Setup Playbook (manual for v1.0)

1. Provision a Gitea runner on a workstation Joseph controls
2. Install the above toolchain via apt: `sudo apt-get install -y shellcheck bats nodejs qemu-system-x86 ovmf`
3. Install gitleaks via binary download from official release (verify sha256)
4. Register runner against `git.integrolabs.net` per Gitea Actions docs
5. Test with a dummy PR

## Release Workflow (manual for v1.0; future CI job)

The manual release steps (to be automated in Iteration 2+):

```
1. scripts/prep-master.sh        # sanitize live master USB
2. scripts/create-base-image.sh  # dd | zstd → kintsugi-base-vX.Y.Z.img.zst
3. scripts/create-payload-tarball.sh  # tar | zstd → kintsugi-payload-vX.Y.Z.tar.zst
4. sha256sum and minisign each artifact
5. Upload base + payload + manifest.json + signatures + kintsugi.pub to Gitea release
6. Update CHANGELOG.md
7. Announce in README (or dedicated RELEASES.md) with verification one-liners
```

All steps eventually move into a `release.yml` Gitea Actions workflow triggered by tag push.

## Monitoring & Observability of the Pipeline

- Gitea Actions UI for build history
- Email notifications to maintainer on build failure
- Quarterly review of workflow run duration and failure patterns (lightweight retrospective)

## References

- test-strategy.md §5
- SAD §4.3, §5.4
- adr-002-imaging-strategy.md
- adr-003-verification-rigor.md
- CLAUDE.md (Distribution Workflow section)
