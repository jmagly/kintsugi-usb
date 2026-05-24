# User Stories Backlog — Kintsugi USB

**Project**: Kintsugi USB — AI-assisted rescue boot USB
**Owner**: Joseph Magly (`roctinam`)
**Phase**: Elaboration
**Version**: 0.2 (amended 2026-04-20 per ADR-005)
**Date**: 2026-04-20

## 2026-04-20 Amendment — ADR-005 Alignment

ADR-005 ("Toolkit Product Surface, Ollama Coexistence, and User-Driven Model Loading") introduces three scope shifts that materially change this backlog:

1. **Dual product surface** — Kintsugi USB is both a toolkit (SDK of scripts + docs for external builders) and a maintainer-signed distributed image. A new persona (**External Builder**) has been added.
2. **Ollama coexistence** — the booted USB runs both `llama.cpp` (:8080) and `ollama` (:11434) as local runtimes; users pick either endpoint.
3. **User-driven model loading** — the maintainer does **not** bundle model weights. Users pull models themselves via a new `kintsugi-models` CLI, at build-time or boot-time. The maintainer publishes a signed `manifest/models-recommended.yaml` only.

### Changes in this amendment

- **New persona**: External Builder (see Personas section).
- **New cluster**: *Toolkit for External Builders* — US-015, US-016, US-017.
- **New cluster**: *User-Driven Model Loading* — US-018, US-019, US-020.
- **New cluster**: *AI Runtime — Dual Local* — US-021.
- **Amended**: US-002 (image no longer bundles weights; payload re-scoped).
- **Amended**: US-003 (manifest now enumerates scripts/docs/binaries + references the separate `manifest/models-recommended.yaml`; does not list bundled model weights).
- **Amended**: US-012 (signed-release mechanism now explicitly covers base image + manifests + recommended-models file; weights are user-responsibility).
- **Amended**: US-013 (SBOM scope excludes user-pulled weights; covers shipped binaries, ISOs, and the recommended-models manifest).

Existing IDs US-001..US-014 are **not** renumbered. Revised stories retain their ID with a "(Revised 2026-04-20 per ADR-005)" tag.

## Purpose

This backlog translates the gaps identified in the project intake and option matrix into prioritized, testable user stories. The physical master USB is mature and already meets its functional requirements (see `docs/requirements.md`). What remains unbuilt is the **build/imaging/distribution/field-update pipeline** — the empty `scripts/` and `manifest/` directories, the TBD `LICENSE`, and the recipient-facing flash/update documentation. Each story below targets one of those gaps.

Stories are grouped by theme, each mapped back to the relevant Use Case (UC-*), Functional Requirement (FR-*), or Non-Functional Requirement (NFR-*) in `docs/requirements.md` where a mapping exists. Stories for new pipeline work (imaging, flashing, updates, licensing, CI) introduce scope not yet present in `docs/requirements.md`; those will need corresponding FR/NFR entries added in a later iteration.

## Prioritization Legend

- **P0** — Blocks the first public release. No v1.0 artifact can ship without this.
- **P1** — Desired in v1.0. Ships with the first release if capacity allows; otherwise slips to v1.1.
- **P2** — Post-v1.0. Stretch, nice-to-have, or dependent on evidence of broader audience.

**Size estimates** (scope, not time): XS (single file or script stub), S (one focused script/doc), M (multi-script workflow or cross-cutting doc), L (multi-artifact pipeline with review cycle).

## Personas

- **Maintainer** — Joseph Magly. Builds the master, images it, publishes releases, writes the docs.
- **Operator** — Anyone using a flashed USB in anger. Could be the maintainer in the field, a trusted fleet user, or a peer systems engineer.
- **Non-technical recipient** — A family member or light-touch fleet user who receives a flashed USB. Reads `flash-image.md`; must succeed without outside help.
- **External Builder** *(added 2026-04-20 per ADR-005)* — A technically capable third party who clones this repo as a toolkit to build their own Kintsugi-like USB. They are **not** flashing the maintainer's signed image; they are running the toolkit scripts to produce their own master (possibly with a different model set, different recovery ISOs, or their own signing key). They expect the repo to function as a reusable SDK — documented, parameterised, and decoupled from the maintainer's specific infrastructure.

---

## Imaging Pipeline

### US-001: Prepare master USB for imaging
**As a** Maintainer
**I want** a `scripts/prep-master.sh` that sanitizes a mounted master USB
**So that** the captured image carries no secrets, no stale caches, and no per-host state

**Acceptance criteria:**
- Given a mounted master USB, when `prep-master.sh` runs, then it removes `~/.config/ai-keys.env`, shell history, SSH known_hosts, and any `*.env` files from the persistence overlay.
- Given the script completes, when I inspect the persistence overlay, then free space has been zero-filled (for compressibility) and caches are flushed.
- Given any sanitization step fails, when the script exits, then it exits non-zero with a clear error and leaves the USB untouched where possible.
- Given the script finishes, when I re-run it idempotently, then it succeeds without error and produces the same result.

**Priority**: P0
**Size**: M
**Maps to**: NFR-4.1, NFR-4.2, CLAUDE.md §"Public Repo Security"

### US-002: Capture a distributable image from the master *(Revised 2026-04-20 per ADR-005)*
**As a** Maintainer
**I want** a `scripts/create-image.sh` that produces a compressed `.img.zst` artifact from a prepped master USB — **containing the OS, toolkit scripts, `llama.cpp` and `ollama` binaries, rescue ISOs, and the signed `manifest/models-recommended.yaml`, but NOT model weights**
**So that** I have a small, license-clean, publishable file that reaches either llama.cpp or Ollama endpoints and loads models the user pulls themselves

**Acceptance criteria:**
- Given a prepped master USB at a known block device, when I run `create-image.sh /dev/sdX`, then it produces `kintsugi-usb-<version>.img.zst` in a configurable output directory.
- Given the script runs, when it completes, then a `.sha256` sidecar file is generated alongside the image.
- Given the wrong target is specified (e.g. the host's root disk), when the script parses arguments, then it refuses and prints the anti-pattern warning required by CLAUDE.md §"Documentation Principles".
- Given a companion `docs/create-image.md` exists, when a new maintainer reads it, then every step from "insert master" to "artifact ready" is reproducible.
- Given `create-image.sh` prepares the source partition, when it scans `/payload/models/` and `/data/models/user/`, then it refuses to proceed (or emits a loud warning requiring `--allow-bundled-weights`) if any GGUF or Ollama blob is present — the distributed base image does not ship weights per ADR-005 D3.

**Priority**: P0
**Size**: L
**Maps to**: ADR-005 §D1, §D2, §D3; CLAUDE.md §"Distribution Workflow" step 3

### US-003: Generate a manifest for each released image *(Revised 2026-04-20 per ADR-005)*
**As a** Maintainer
**I want** `manifest/kintsugi-usb-<version>.manifest.json` listing the bundled ISOs, binaries, scripts, docs, and a pointer to the signed `manifest/models-recommended.yaml` — but **NOT** listing model weights (which are user-pulled and not shipped)
**So that** recipients and future-me can see exactly what is inside a given release, with a clean separation between maintainer-shipped content and user-responsibility content

**Acceptance criteria:**
- Given `create-image.sh` has run, when the manifest generator runs, then it emits a JSON file listing each bundled artifact (ISO, binary, shipped scripts/docs) with its name, version, source URL, license, and SHA-256.
- Given the manifest is emitted, when it enumerates AI runtimes, then both `llama.cpp` and `ollama` appear as separate entries with their respective versions and licenses.
- Given the manifest is emitted, when it references models, then it records the SHA-256 of the shipped `manifest/models-recommended.yaml` and explicitly states that model weights are user-pulled (not bundled).
- Given the manifest exists, when I diff two versions' manifests, then the changes (added, removed, upgraded components) are legible.
- Given an artifact cannot be identified (unknown version), when the generator runs, then it records `"version": "unknown"` rather than silently omitting the entry.

**Priority**: P1
**Size**: M
**Maps to**: ADR-005 §D3, §D4; CLAUDE.md §"Distribution Workflow" step 4, intake "supply-chain considerations"

### US-004: Publish a release to Gitea with checksum
**As a** Maintainer
**I want** a `scripts/publish-release.sh` that uploads the image, manifest, and checksums to a Gitea release
**So that** recipients have one canonical download URL per version

**Acceptance criteria:**
- Given a built image and manifest, when I run `publish-release.sh v<version>`, then it creates a Gitea release on `roctinam/kintsugi-usb` with the image, `.sha256`, and manifest attached.
- Given the `roctibot-token` is present at `~/.config/gitea/roctibot-token`, when the script authenticates, then it does not write the token into any log or artifact.
- Given the release already exists, when the script runs, then it aborts rather than silently overwriting (safety default).
- Given the release body is generated, when a recipient views it, then it includes the SHA-256, the image size, and a one-paragraph "what changed" pulled from `CHANGELOG.md` or the git tag message.

**Priority**: P0
**Size**: M
**Maps to**: CLAUDE.md §"Distribution Workflow" step 4, CLAUDE.md §"Issue Tracking (Gitea)"

### US-005: Tag, changelog, and version the release
**As a** Maintainer
**I want** a documented release procedure covering version scheme, git tag, and changelog entry
**So that** each published image ties to a specific, inspectable commit of this repo

**Acceptance criteria:**
- Given I am preparing a release, when I follow `docs/release-procedure.md`, then the steps produce a signed git tag, a `CHANGELOG.md` entry, and a consistent `v<MAJOR>.<MINOR>.<PATCH>` version string.
- Given the procedure is followed, when the release lands on Gitea, then the release's git ref, the tag, and the version embedded in the image filename all match.

**Priority**: P1
**Size**: S
**Maps to**: CLAUDE.md §"Git Commit Conventions", §"Distribution Workflow" step 4

---

## Flashing & Distribution

### US-006: Flash a USB from the published image (end-user friendly)
**As a** Non-technical recipient
**I want** a `docs/flash-image.md` with platform-specific instructions (Windows, macOS, Linux)
**So that** I can put the Kintsugi USB onto my own USB drive without breaking my computer

**Acceptance criteria:**
- Given I have never used `dd`, when I follow `flash-image.md` on my platform, then the steps use widely available GUI tools (Rufus, balenaEtcher, Raspberry Pi Imager) as the primary path.
- Given the doc references destructive commands, when I read it, then each destructive step is preceded by the anti-pattern warning required by CLAUDE.md §"Documentation Principles" (explicit "do NOT do this" callout).
- Given I reach the end of the procedure, when I verify my USB, then the doc walks me through a boot test on my own machine as the final verification step.

**Priority**: P0
**Size**: M
**Maps to**: CLAUDE.md §"Documentation Principles" (end-user first, verification always)

### US-007: Verify the downloaded image checksum (non-technical)
**As a** Non-technical recipient
**I want** copy-paste checksum verification instructions in `flash-image.md` for my platform
**So that** I know the image I downloaded has not been tampered with before I flash it

**Acceptance criteria:**
- Given I am on Windows, macOS, or Linux, when I follow the "Verify your download" section, then the commands are single-line and copy-pasteable with no editing.
- Given my computed hash matches the published `.sha256`, when I proceed, then the doc tells me clearly "you're good, go on."
- Given my hash does **not** match, when I consult the troubleshooting note, then the doc tells me to stop, re-download, and (if it still fails) open a Gitea issue.

**Priority**: P0
**Size**: S
**Maps to**: CLAUDE.md §"Documentation Principles" (verification always)

---

## Field Update

### US-008: Update docs and scripts on a deployed USB without reflashing
**As an** Operator
**I want** a `scripts/update-payload.sh` that rsyncs the latest `docs/` and `scripts/` onto a mounted Ventoy partition
**So that** my deployed USB's runbooks do not go stale every time this repo changes

**Acceptance criteria:**
- Given a deployed USB mounted at a known path, when I run `update-payload.sh /media/$USER/Ventoy`, then `docs/` and `scripts/` on the USB are updated from the running clone of this repo.
- Given the script runs, when it completes, then it writes a `VERSION.txt` (or equivalent) on the Ventoy partition recording the source commit SHA and timestamp.
- Given the partition is not a Ventoy Kintsugi USB, when the script inspects the target, then it refuses to write and exits with an explanatory error.

**Priority**: P1
**Size**: M
**Maps to**: CLAUDE.md §"Distribution Workflow" step 6

### US-009: Know what is updatable in place vs requires a reflash
**As an** Operator
**I want** a `docs/update-payload.md` boundary document
**So that** I know when `update-payload.sh` is enough and when I need to re-flash from a new release

**Acceptance criteria:**
- Given I read `update-payload.md`, when I look up any on-USB component (docs, scripts, models, llama.cpp binary, ISOs, Ventoy itself), then the doc states clearly "updatable in place" or "requires reflash."
- Given a component is in-place updatable, when the doc describes the procedure, then it ends with a verification step (boot test, checksum, or smoke check).
- Given a component requires reflash, when the doc explains why, then the reasoning (boot chain, squashfs, partition layout) is briefly stated.

**Priority**: P1
**Size**: S
**Maps to**: NFR-6.1 through NFR-6.4, CLAUDE.md §"Distribution Workflow" step 6

---

## Licensing & Provenance

### US-010: Choose and apply a project LICENSE
**As a** Maintainer
**I want** to select, apply, and document a LICENSE compatible with bundled third-party artifacts
**So that** I can publish the first image without legal ambiguity

**Acceptance criteria:**
- Given I review the bundled artifacts (Ventoy GPLv3, Ubuntu, llama.cpp MIT, Qwen/Phi model licenses, Claude Code EULA), when I pick a repo license, then an ADR in `.aiwg/architecture/adrs/` records the choice and its compatibility rationale.
- Given the license is chosen, when it is applied, then a `LICENSE` file exists at the repo root and `README.md` replaces "TBD" with the chosen license.
- Given the image bundles third-party artifacts with differing licenses, when a recipient inspects the release, then a `THIRD-PARTY-NOTICES.md` (or equivalent in the manifest) surfaces each bundled artifact's license.

**Priority**: P0
**Size**: M
**Maps to**: Intake §"Licensing", option matrix §"Phase-1 blocker"

---

## Test & CI (Stretch)

### US-011: Smoke-test a freshly flashed USB in QEMU
**As a** Maintainer
**I want** a `scripts/qemu-smoke.sh` that boots a flashed image in QEMU and checks for a login prompt
**So that** I can catch obvious image corruption before publishing a release

**Acceptance criteria:**
- Given a `.img` or `.img.zst` artifact, when I run `qemu-smoke.sh <path>`, then QEMU boots the image with UEFI firmware and asserts a login prompt appears within the NFR-1.1 budget (60s).
- Given the smoke test fails, when the script exits, then it prints the last 50 lines of the serial console to aid diagnosis.
- Given the smoke test passes, when I proceed to publish, then the release notes can reference "QEMU smoke test: PASS (commit <sha>)".

**Priority**: P2
**Size**: L
**Maps to**: NFR-1.1, test-strategy.md

### US-012: Sign releases so recipients can verify provenance *(Revised 2026-04-20 per ADR-005)*
**As a** Maintainer
**I want** to sign the released `.img.zst`, the release manifest, and the `manifest/models-recommended.yaml` file with `minisign` (or `cosign`) and publish the public key
**So that** recipients can verify that the base image, toolkit, and recommended-models list originated from me — while model weights themselves remain the user's integrity responsibility (per ADR-005 §D3)

**Acceptance criteria:**
- Given a release is being published, when the publish script runs, then it produces a detached signature alongside the image, the manifest, and `manifest/models-recommended.yaml`.
- Given the public key is available in the repo and on a long-lived out-of-band channel (e.g. my Gitea profile), when a recipient runs the documented verify command, then the signature validates against the published key.
- Given the signing key is stored, when I audit my setup, then the key is never present in repo, image, or persistence overlay.
- Given a recipient fetches user-pulled model weights via `kintsugi-models pull`, when they read the release documentation, then it is clearly stated that the maintainer's signature does **not** attest to weights retrieved from Ollama registry or HuggingFace (those carry their own integrity story per ADR-005 §D3).

**Priority**: P2
**Size**: M
**Maps to**: ADR-005 §D3, §D5 (ADR-003 unchanged); Intake §"supply-chain considerations", option matrix Step 4 question #3

### US-013: Generate an SBOM for each release *(Revised 2026-04-20 per ADR-005)*
**As a** Maintainer
**I want** a CycloneDX or SPDX SBOM generated as part of `create-image.sh`
**So that** I can answer "what's inside this release?" with a machine-readable document if an endpoint-protection tool ever flags a bundled binary

**Acceptance criteria:**
- Given an image is built, when the SBOM step runs, then a `kintsugi-usb-<version>.sbom.json` is produced listing bundled ISOs, binaries (llama.cpp, ollama, `claude`/`codex` CLIs, Ventoy), shipped scripts, and the `manifest/models-recommended.yaml` file — **excluding** user-pulled model weights, which are not shipped in the base image per ADR-005 §D3.
- Given the SBOM exists, when it is published to the Gitea release, then it sits alongside the image, manifest, and checksum.
- Given the generator cannot identify a component, when it runs, then the SBOM entry is flagged "unverified" rather than omitted.
- Given the SBOM is inspected, when a reviewer looks for model entries, then the SBOM clearly records that model weights are out-of-scope (user-loaded) and points to `manifest/models-recommended.yaml` for the recommended set.

**Priority**: P2
**Size**: M
**Maps to**: ADR-005 §D3; Intake §"supply-chain considerations"

### US-014: Lint and validate scripts in CI
**As a** Maintainer
**I want** a Gitea Actions workflow that runs `shellcheck` on `scripts/` and renders `docs/` markdown
**So that** obvious shell bugs and broken docs get caught before they land in a release

**Acceptance criteria:**
- Given a pull request or push to `main`, when the Gitea Actions workflow runs, then `shellcheck` fails the build on any error-level finding.
- Given the workflow runs, when markdown lint runs, then any broken internal link under `docs/` or `README.md` fails the build.
- Given the workflow finishes, when I view the Gitea UI, then the status check appears on the PR/commit.

**Priority**: P2
**Size**: S
**Maps to**: Option matrix §"Planned Framework Evolution" (6-month horizon)

---

## Toolkit for External Builders *(new cluster, 2026-04-20 per ADR-005)*

### US-015 — External builder produces their own master USB from a fresh clone
**Persona**: External Builder
**As an** External Builder
**I want** to clone this repo on a fresh Ubuntu host and follow `docs/toolkit-guide.md` to produce a working master USB with my chosen model set
**So that** I can operate Kintsugi USB as a reusable SDK without depending on the maintainer's infrastructure, keys, or model choices

**Acceptance criteria** (Given/When/Then):
- Given a fresh clone of `roctinam/kintsugi-usb` on a fresh Ubuntu 24.04 host with no prior Kintsugi state, when I follow `docs/toolkit-guide.md` end-to-end, then I end with a bootable master USB that runs `start-ai.sh` successfully against a model *I* selected.
- Given `docs/toolkit-guide.md` walks through the toolkit flow, when I read it, then no step hard-codes `roctinam`-specific hostnames, Gitea URLs, or signing keys — all maintainer-specific values are either documented as configurable or clearly flagged as "maintainer-only, skip if external builder."
- Given the guide references `kintsugi-models`, `build-custom-iso.sh`, `first-boot-setup.sh`, and `prep-master.sh`, when I execute them on the fresh host, then they run to completion without prompting for the maintainer's secrets.
- Given I reach the end, when I verify the result, then the guide ends with a boot test and a `start-ai.sh` smoke check on the new master USB.

**Priority**: P1
**Size**: L
**Cluster**: Toolkit for External Builders
**Maps to**: ADR-005 §D1, new FR (toolkit-usability); new NFR category (toolkit-UX)

### US-016 — External builder signs their own release with their own key
**Persona**: External Builder
**As an** External Builder
**I want** the signed-release mechanism (`publish-release.sh`, manifest signing, verify docs) to be parameterised by signing key and public-key URL — not hard-coded to the maintainer's `minisign` key
**So that** I can publish my own signed images to my own release channel (Gitea, GitHub, HTTP mirror) without forking the scripts

**Acceptance criteria** (Given/When/Then):
- Given I provide my own `minisign` secret key path via env var or config file, when I run `publish-release.sh`, then the release is signed with my key and the output documents reference *my* public-key URL — not the maintainer's.
- Given the repo's verify docs (`docs/flash-image.md` or equivalent) describe signature verification, when an external builder adapts them, then the public-key URL, key fingerprint, and verify command are template variables (or clearly marked replaceable), not hard-coded strings.
- Given I have not configured a signing key, when I run `publish-release.sh` in unsigned mode (`--unsigned` or equivalent), then it publishes without a signature and prints a loud warning rather than silently omitting the signature.
- Given the scripts are inspected, when a reviewer searches for hard-coded minisign fingerprints or key URLs, then none are found outside of `docs/` example blocks and `manifest/` maintainer-release files.

**Priority**: P2
**Size**: M
**Cluster**: Toolkit for External Builders
**Maps to**: ADR-005 §D1, §D5 (amends ADR-003 applicability); US-012

### US-017 — External builder adds a non-recommended model slug at build-time
**Persona**: External Builder
**As an** External Builder
**I want** to run `kintsugi-models add <my-specialised-slug>` (e.g. a domain-specific fine-tune or a local-only experimental model) and have it ship in my built image
**So that** I can produce a Kintsugi-like USB tuned for my use case without editing the maintainer's `models-recommended.yaml`

**Acceptance criteria** (Given/When/Then):
- Given I run `kintsugi-models add <slug> --runtime <ollama|llama-cpp> --source <ollama|huggingface|url> --target /mnt/usb-build-root`, when the command completes, then the slug is appended to a *user* manifest (not the shipped `manifest/models-recommended.yaml`) under the build root.
- Given I then run `kintsugi-models pull <slug> --target /mnt/usb-build-root`, when the pull completes, then the weights are written under `/payload/models/` (or the Ollama store) on the build root and `kintsugi-models verify` reports the slug as present and checksum-matched.
- Given the build root is imaged via `create-image.sh`, when the image is flashed, then the user-added slug is discoverable by `start-ai.sh` on first boot without any further user action.
- Given I did not mark my slug as "recommended," when `manifest/models-recommended.yaml` is inspected, then my slug is absent — the recommended list is untouched and only the user manifest records my addition.

**Priority**: P1
**Size**: M
**Cluster**: Toolkit for External Builders
**Maps to**: ADR-005 §D3, §D4

---

## User-Driven Model Loading *(new cluster, 2026-04-20 per ADR-005)*

### US-018 — Operator pulls a recommended model on a booted USB over a trusted network
**Persona**: Operator
**As an** Operator running a flashed (maintainer-signed) Kintsugi USB on a host with internet access
**I want** to run `kintsugi-models pull qwen3.5:4b` (or any slug from `manifest/models-recommended.yaml`) and have the model available to `start-ai.sh`
**So that** I can populate my USB on first boot without having to flash a larger image containing weights

**Acceptance criteria** (Given/When/Then):
- Given a booted Kintsugi USB with persistence and network, when I run `kintsugi-models pull qwen3.5:4b`, then the model is downloaded into `/data/models/user/` (or Ollama's `/data/ollama/` store for Ollama-source slugs) and survives reboot.
- Given the pull completes, when I run `start-ai.sh`, then the pulled model appears in the discovered-models list and can be selected without further configuration.
- Given the pull is interrupted (network drop, user Ctrl-C), when I re-run `kintsugi-models pull qwen3.5:4b`, then it resumes or redownloads cleanly without leaving a corrupt partial file that `verify` misses.
- Given the slug is in the signed `manifest/models-recommended.yaml` and that manifest ships with a SHA-256 (where applicable), when `pull` completes for a non-Ollama source, then `kintsugi-models verify <slug>` checks the downloaded file against the manifest SHA-256 and reports pass/fail.
- Given persistence storage is above the soft-warn threshold (80%), when I invoke `pull`, then the CLI warns; at hard-refuse threshold (95%), it refuses the pull per ADR-005 R-18 mitigation.

**Priority**: P0
**Size**: L
**Cluster**: User-Driven Model Loading
**Maps to**: ADR-005 §D3 (boot-time path), R-18; FR-4.x (to be added)

### US-019 — Operator lists, removes, and verifies user-pulled models
**Persona**: Operator
**As an** Operator on a booted Kintsugi USB
**I want** `kintsugi-models list`, `kintsugi-models remove <slug>`, and `kintsugi-models verify [slug]` to report and manage my local model set
**So that** I can keep persistence tidy, reclaim space, and confirm downloaded weights have not been corrupted

**Acceptance criteria** (Given/When/Then):
- Given I run `kintsugi-models list`, when the command runs, then it prints each configured slug with columns for: source (ollama/hf/url), runtime (llama-cpp/ollama), quant, on-disk size, sha256 status (verified/pending/mismatch/n/a), and origin (recommended-manifest vs user-manifest).
- Given I run `kintsugi-models remove <slug>`, when the slug is a user-added entry, then the weights are deleted (after interactive confirmation, or `--yes` flag) and the user manifest entry is removed; the recommended-manifest file is never modified.
- Given I run `kintsugi-models verify` with no arguments, when the command runs, then every slug with a recorded SHA-256 is checksummed and a pass/fail summary is printed; Ollama-source slugs (which have no manifest SHA-256) are reported as "managed by ollama — run `ollama verify`."
- Given a verify mismatch is detected, when the command exits, then it exits non-zero and the mismatching slug is flagged in the summary with remediation guidance (`kintsugi-models remove && pull`).

**Priority**: P0
**Size**: M
**Cluster**: User-Driven Model Loading
**Maps to**: ADR-005 §D3, §D4

### US-020 — Builder pulls models at build-time into an in-progress master
**Persona**: Maintainer *or* External Builder
**As a** builder preparing a master USB for imaging
**I want** `kintsugi-models add <slug>` and `kintsugi-models pull <slug> --target <build-root-path>` to write to the in-progress master's `/payload/models/` (not the host's persistence, not Ollama's default user store)
**So that** the models I choose ship inside the image and the flashed USB can operate fully offline from first boot

**Acceptance criteria** (Given/When/Then):
- Given I mount my in-progress master at `/mnt/usb-build-root`, when I run `kintsugi-models pull qwen3.5:4b --target /mnt/usb-build-root`, then the weights land under `/mnt/usb-build-root/payload/models/` (or the target's Ollama store) — not in my host user's `~/.ollama` or `/data/models/user/`.
- Given `--target` points at a path that is not a Kintsugi master (no expected layout markers), when the command inspects the target, then it refuses to write and exits with an explanatory error.
- Given build-time pulls succeeded and the image is then captured, when the flashed USB boots, then `start-ai.sh` discovers the build-time-bundled slug with no further network action required.
- Given the builder is the maintainer producing the signed release, when they attempt a build-time pull into the about-to-be-imaged master, then `create-image.sh` refuses (per US-002's revised acceptance criteria) unless `--allow-bundled-weights` is passed — protecting the default "no weights in signed image" invariant.

**Priority**: P1
**Size**: M
**Cluster**: User-Driven Model Loading
**Maps to**: ADR-005 §D3 (build-time path)

---

## AI Runtime — Dual Local *(new cluster, 2026-04-20 per ADR-005)*

### US-021 — Operator routes AI clients to either llama.cpp or Ollama via env var
**Persona**: Operator
**As an** Operator on a booted Kintsugi USB
**I want** to point `aider`, `claude` (where applicable), `codex`, or a custom client at either the llama.cpp endpoint (`:8080`) or the Ollama endpoint (`:11434`) by setting `OPENAI_API_BASE` (or an equivalent documented env var)
**So that** I can use each runtime for what it is good at — llama.cpp for scripted/embedded direct-GGUF work, Ollama for model-management convenience — without reconfiguring the client's config files

**Acceptance criteria** (Given/When/Then):
- Given `start-ai.sh` has run, when I check service status, then both `llama-server` (on `:8080`) and `ollama serve` (on `:11434`) are reported and their reachability tested by the script.
- Given I set `OPENAI_API_BASE=http://localhost:8080/v1` and run `aider` (or equivalent), when the client issues a completion, then the response comes from llama.cpp against the discovered GGUF model.
- Given I set `OPENAI_API_BASE=http://localhost:11434/v1` and run the same client, when the client issues a completion, then the response comes from Ollama against an Ollama-managed slug.
- Given the docs (`docs/ai-runtime.md` or equivalent) describe the runtime-selection pattern, when an operator reads it, then a table of env-var values for at least `aider`, `codex`, and a generic `curl` test is provided with copy-paste examples.
- Given one of the two runtimes is not running (user stopped it, or weights are missing for that runtime), when the operator tries to use the corresponding endpoint, then the client error is clearly distinguishable and `docs/ai-runtime.md` points at the diagnostic (`start-ai.sh --status`).

**Priority**: P1
**Size**: M
**Cluster**: AI Runtime — Dual Local
**Maps to**: ADR-005 §D2; FR-4.x (to be added)

---

## Notes

- Stories that introduce new components (imaging, flashing, update, signing, SBOM, toolkit docs, model CLI, dual runtime) imply new FR/NFR entries in `docs/requirements.md`. That follow-up is tracked as a separate backlog item and is out of scope for this document.
- Every P0 story ends with a verification step (boot test, checksum match, manifest diff, or operator-run smoke test) per CLAUDE.md §"Documentation Principles".
- No story requires commits on GitHub; all issue tracking and releases are Gitea-only per CLAUDE.md §"Issue Tracking (Gitea)".
