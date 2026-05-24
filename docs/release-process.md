# Release Process

**Audience**: maintainer (and future co-maintainers). This is the playbook for cutting a Kintsugi USB release.
**Versioning**: CalVer `YYYY.M.PATCH` (no leading zeros), per `.claude/rules/versioning.md`.
**Target release**: `v2026.5.0` (first tagged release; supersedes the earlier `v0.1.0` framing in Gitea [#7](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/7)).

## Prerequisites (one-time setup)

On the build host (dedicated VM or clean Ubuntu 24.04; **not** your daily-driver laptop):

```bash
sudo apt-get update
sudo apt-get install -y live-build whiptail zstd git curl ca-certificates
# mikefarah/yq (the Ubuntu apt 'yq' is a different tool)
sudo wget -O /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Warehouse NFS mount (where v1.0 images publish per ADR-006 §D4)
sudo mkdir -p /mnt/warehouse
sudo mount -t nfs <nfs-server>:/exports/warehouse /mnt/warehouse
# Verify writable
ls /mnt/warehouse/releases/kintsugi-usb/ || sudo mkdir -p /mnt/warehouse/releases/kintsugi-usb/
```

Confirm environment once before every release:

```bash
live-build --version
yq --version                      # must say 'mikefarah'
test -w /mnt/warehouse/releases/kintsugi-usb/ && echo NFS writable
df -BG /home | tail -1            # need ≥20 GB free
```

## Release checklist

### 1. Pre-release housekeeping

```bash
cd /home/roctinam/dev/kintsugi-usb
git checkout main
git pull --ff-only
git status     # must be clean
```

Run the linters and the harness smoke test:

```bash
for s in scripts/*.sh scripts/usb-toolkit/*.sh scripts/usb-toolkit/kintsugi-models scripts/usb-toolkit/kintsugi-frameworks scripts/kintsugi-build; do
    shellcheck "$s" || echo "WARN: $s"
done

KINTSUGI_LOG_BASE=/tmp/kintsugi-release-preflight \
    scripts/usb-toolkit/usb-test-harness.sh --smoke

# Runbook review gate (R-15, #33): no unreviewed runbook ships. Must exit 0.
scripts/check-runbooks.sh
```

Expected: shellcheck clean on all v1.0-scope scripts (pre-existing warnings in ported code are documented in the issues that close them). `--smoke` exits 0 or 1 depending on this host's tool inventory. `check-runbooks.sh` must exit 0 — any runbook tagged `<!-- runbook -->` without a `reviewed-by:` marker blocks the release (see `docs/runbook-review-checklist.md`).

### 2. Decide and bump the version

Bump the release version (CalVer `YYYY.M.PATCH`) and update the default build-name prefix in `scripts/kintsugi-build` (`default_name="kintsugi-v<VERSION>-$(date +%Y%m%d)"`) so self-builds track the current release. Also edit `scripts/kintsugi-build` (`VERSION`) + `scripts/usb-toolkit/usb-test-harness.sh` (`VERSION`) if bumping the wizard or harness tool version (separate semver). Update `CHANGELOG.md` (create it the first time) with:

- Release date
- Gitea issues closed
- ADRs that landed in this release
- Known limitations

Commit the bump:

```bash
git add CHANGELOG.md scripts/kintsugi-build scripts/usb-toolkit/usb-test-harness.sh
git commit -m "chore(release): prepare v2026.5.0"
```

### 3. Run the wizard with a release profile

Use a reproducible profile instead of the interactive flow for releases. Create `release-profiles/v2026.5.0.yaml`:

```yaml
schema_version: 1
generated_by: "manual release-profile v2026.5.0"
generated_at: "<ISO-timestamp>"
build_name: "kintsugi-v2026.5.0"
include_vscode: true
include_ollama: true
ollama_version: "latest"
yq_version: "v4.44.3"
frameworks: ["aider", "claude-code", "codex-cli"]
models_post_flash: ["qwen3.5:4b", "qwen3.5:9b"]
signing:
  enabled: false  # v1.0 per ADR-006 §D5; minisign returns in v1.1
```

Run:

```bash
KINTSUGI_BUILDS_ROOT=/var/lib/kintsugi-release-builds \
    scripts/kintsugi-build --non-interactive release-profiles/v2026.5.0.yaml
```

Expect 15–30 minutes. The wizard writes `build-profile.yaml`, `build.log`, and an `.iso` (or `.hybrid.iso`) under `$KINTSUGI_BUILDS_ROOT/kintsugi-v2026.5.0/`.

### 4. Sanitize

```bash
sudo scripts/prep-master.sh \
    /var/lib/kintsugi-release-builds/kintsugi-v2026.5.0 \
    --zero-free-space
```

This runs the sanitization checklist (secret scan, cache wipe, log truncation, keep-list verify, manifest schema validation, zero-fill free space). Exit 0 means ready. Exit 2 or 3 means **stop** — the build is not ready to ship.

### 5. Image

```bash
scripts/create-image.sh \
    /var/lib/kintsugi-release-builds/kintsugi-v2026.5.0/kintsugi-v2026.5.0.iso \
    --output-dir ./dist \
    --name kintsugi-v2026.5.0 \
    --level 19
```

Produces `./dist/kintsugi-v2026.5.0.img.zst` + `./dist/kintsugi-v2026.5.0.sha256`. Capture the compressed size — it feeds back into the ADR-002 spike verification gate:

```bash
ls -lh ./dist/kintsugi-v2026.5.0.img.zst
```

If >6 GB, revisit ADR-002 collapse decision before shipping.

### 6. Generate manifest

```bash
scripts/generate-manifest.sh \
    ./dist/kintsugi-v2026.5.0.img.zst \
    ./dist/kintsugi-v2026.5.0.sha256 \
    --version v2026.5.0 \
    --output ./dist/manifest.json
```

### 7. Verify locally before publishing

```bash
scripts/verify-image.sh ./dist/kintsugi-v2026.5.0.img.zst
```

Must exit 0. This is the same script recipients will run.

### 8. Publish to NFS

```bash
scripts/publish-release.sh \
    ./dist/kintsugi-v2026.5.0.img.zst \
    v2026.5.0 \
    ./dist/kintsugi-v2026.5.0.sha256 \
    ./dist/manifest.json
```

Default target is `/mnt/warehouse/releases/kintsugi-usb/v2026.5.0/`. The script does pre- and post-upload sha256 checks. On success: per-version `release.json` lands alongside the artifact and the global `releases.json` index is updated.

### 9. Tag + push the git release

```bash
git tag -a v2026.5.0 -m "v2026.5.0 — first release; see CHANGELOG.md"
git push origin main v2026.5.0
```

### 10. Create a lightweight Gitea release entry

```bash
TOKEN=$(cat ~/.config/gitea/roctibot-token)
API="https://git.integrolabs.net/api/v1"

curl -s -X POST \
    -H "Authorization: token $TOKEN" \
    -H "Content-Type: application/json" \
    "$API/repos/roctinam/kintsugi-usb/releases" \
    -d '{
      "tag_name": "v2026.5.0",
      "name": "v2026.5.0 — First release",
      "body": "Image hosted on warehouse NFS at /mnt/warehouse/releases/kintsugi-usb/v2026.5.0/\n\nSee CHANGELOG.md for full notes.\n\nVerification:\n```\nscripts/verify-image.sh kintsugi-v2026.5.0.img.zst\n```",
      "draft": false,
      "prerelease": false
    }'
```

**Do NOT upload the `.img.zst` as a Gitea release attachment** for v1.0 (ADR-006 §D4 — NFS is the v1.0 publish target; Gitea releases only carry tags + changelog).

### 11. Acceptance test on a clean machine

The v1.0 acceptance gate (per `.aiwg/planning/iteration-001-plan.md`):

- A non-fleet machine downloads the release from NFS
- Runs `scripts/verify-image.sh` — passes
- Flashes the USB via `scripts/flash-image.sh`
- Boots the USB
- Runs `start-ai.sh --status` — llama-server + Ollama both reachable
- Runs `kintsugi-models pull qwen3.5:4b` — succeeds
- Runs `usb-test-harness.sh --quick` — all PASS or expected SKIP

Record the acceptance test in the Gitea release comment when complete.

### 12. Close the iteration-1 tracking issues

```bash
# Close #7 (this release), confirm #25 (ADR-005 tracking umbrella) can close
```

## Rollback procedure

If a release turns out to be broken after acceptance:

1. **Mark the Gitea release as prerelease** (flips visibility) but don't delete it — recipients may already have the image.
2. **Delete or rename the NFS path**: `mv /mnt/warehouse/releases/kintsugi-usb/v2026.5.0 /mnt/warehouse/releases/kintsugi-usb/v2026.5.0.WITHDRAWN-<date>`.
3. **Publish a terse advisory** via SECURITY.md reporting channel (for any recipient who may have flashed the bad release).
4. **File the root-cause issue** with `priority-p0` and a `regression` label.
5. **Re-run the full release process from step 1** for the next version (e.g. v2026.5.1).

## Known limitations for v1.0

- sha256-only verification (minisign arrives in v1.1 per ADR-006 §D5)
- NFS-internal distribution only (no public-facing release channel yet)
- 3 bundled agentic-framework install recipes (Aider, Claude Code, Codex CLI); 6 more follow in iteration-2 per ADR-006 §D2
- No CI (Gitea Actions deferred to iteration-2 #28)

## References

- [Iteration-1 plan](`.aiwg/planning/iteration-001-plan.md`)
- [ADR-002 — Imaging Strategy (single-artifact)](`.aiwg/architecture/adr-002-imaging-strategy.md`)
- [ADR-003 — Verification (sha256-only in v1.0)](`.aiwg/architecture/adr-003-verification-rigor.md`)
- [ADR-006 — Wizard + NFS publish + signing-deferred](`.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md`)
- [Sanitization Checklist](sanitization-checklist.md)
- [Wizard Guide](wizard-guide.md)
- [Toolkit Guide](toolkit-guide.md)
