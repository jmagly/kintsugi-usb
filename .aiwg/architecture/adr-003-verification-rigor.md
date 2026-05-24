# ADR-003: Release Verification Rigor (Signing & Checksums)

**Status**: ACCEPTED — but **v1.0 SIGNING DEFERRED to v1.1** per ADR-006 (2026-04-20)
**Date**: 2026-04-20
**Deciders**: Joseph Magly
**Consulted**: SAD §9.1, sad-review-security.md, R-02, ADR-006

## Amendment 2026-04-20 (per ADR-006 §D5)

The v1.0 minisign signing commitment made in the original acceptance of this ADR is **rolled back**. Iteration-1 priorities pivot to the build toolkit (wizard-first UX, agentic-framework user-driven loading, model user-driven loading) rather than distribution infrastructure. For v1.0:

- **v1.0**: sha256 verification ONLY. `.sha256` file published alongside any maintainer-produced `.img.zst` on the warehouse NFS mount per ADR-006 §D4.
- **v1.0**: no minisign keypair; no `verify-release.sh`; no per-OS minisign one-liners in `docs/flash-image.md`.
- **v1.0**: SECURITY.md (reduced scope) documents the sha256 expectation + the explicit commitment that signing lands in v1.1.
- **v1.1**: full content of this ADR applies — minisign keypair generation, `kintsugi.pub` commit, `verify-release.sh` wrapper, recipient per-OS one-liners, manifest hash-chain.

Trade-off accepted: v1.0 maintainer-produced images carry weaker supply-chain guarantees against malicious substitution. Mitigations:
- NFS-internal distribution is a more-trusted channel than public download (limits exposure during v1.0)
- The **primary** v1.0 product is the **wizard-driven self-build** — users produce their own images from inspectable scripts they fork; maintainer signing is secondary to code-level trust
- Iteration-2 lands signing before any broader public distribution

Risk R-02 (supply-chain) severity **temporarily bumped** for v1.0 maintainer-images; will be downgraded again in v1.1 when signing lands. See `.aiwg/risks/risk-list.md` amendment.

The full v1.1+ signing content below is preserved unchanged — it remains the target posture.

---

## Context

Kintsugi USB distributes a bootable rescue image containing ISOs, LLM model weights, `claude` CLI binaries, and host-specific recovery runbooks. The Security review (`sad-review-security.md`) escalated release verification from "checksums only" to **signed releases**, and SAD §9.1 commits v1.0 to that posture. Recipients of the image are explicitly modeled as potentially non-technical (family members, fleet users who did not build the drive) per the team directives in CLAUDE.md.

Checksums alone prove that a download was not corrupted in transit, but they do not prove the artifact came from the maintainer. An attacker who compromises the hosting endpoint can publish a tampered image together with a matching `sha256sum` file, and a recipient running `shasum -c` will see a green check. Authenticity requires a second factor — a signature verified against a public key the recipient has out-of-band reason to trust.

This ADR selects the signing tool and the recipient verification UX. It does not re-open the question of *whether* to sign; that is settled in SAD §9.1.

## Decision Drivers

- **Non-technical recipient.** Verification must be a one-line copy-paste, not a keyring workflow.
- **Solo, manual release cadence.** No Gitea Actions CI pipeline exists yet; the maintainer signs on a local workstation.
- **Cross-platform recipients.** Linux, macOS, and Windows must all have a first-class verification path.
- **Public repository, no third-party keyserver.** Pubkey distribution must be self-hosted and tamper-evident.
- **Forward compatibility.** v1.0 choice must not block a later migration to CI-driven signing (cosign/sigstore) once release automation exists.
- **R-02 supply-chain provenance.** The risk register lists supply-chain integrity as a priority mitigation.

## Considered Options

### Option 1 — sha256sum only (baseline, rejected)
- **Pros**: Zero new tooling; `shasum`/`sha256sum`/`Get-FileHash` are universal.
- **Cons**: Proves integrity but not authenticity. A compromised release endpoint publishes matching tampered checksums. Rejected by the Security review.

### Option 2 — GPG / OpenPGP
- **Pros**: Widely understood; `gpg --verify` is well-documented; compatible with existing maintainer keys.
- **Cons**: Requires recipient to import a pubkey into a keyring, manage trust levels, and navigate `gpg` output that includes "WARNING: This key is not certified with a trusted signature" even on successful verification. Keyserver dependency (pgp.mit.edu, keys.openpgp.org) adds third-party trust. High UX friction for non-technical recipients. Windows UX (Gpg4win) is an additional install.

### Option 3 — minisign (Ed25519)
- **Pros**: Single-file pubkey (no keyring); Ed25519 signatures; trivial verification one-liner; native packages on Linux, macOS (brew), and Windows (scoop/direct); designed specifically for the "sign a release artifact" use case. No keyserver dependency.
- **Cons**: Less widely known than GPG; recipient must install minisign (one-time). No web-of-trust; TOFU model only.

### Option 4 — cosign / sigstore
- **Pros**: Keyless signing via OIDC; Rekor transparency log provides public auditability; industry direction for CI-signed releases.
- **Cons**: Designed around CI pipelines with OIDC identity tokens; overkill and awkward for a solo manual release workflow. Recipient must install cosign (heavier than minisign). Keyless mode depends on sigstore infrastructure availability. Better fit *after* Gitea Actions automates releases.

### Option 5 — Composite: sha256 + minisign (recommended)
- **Pros**: Two-stage verification matches recipient mental model — "did my download arrive intact?" (cheap, no new tool) then "is it authentic?" (signature check). sha256 catches the overwhelmingly common case (transport corruption, incomplete download) cheaply; minisign catches the rare but high-impact case (tampered release).
- **Cons**: Two commands instead of one. Mitigated by a per-OS one-liner script in `docs/flash-image.md`.

## Decision

**Adopt Option 5: sha256 + minisign composite verification for v1.0.**

### Release artifact layout

Each release (Gitea release page) ships:

- `kintsugi-vX.Y.Z.img.zst` — compressed image
- `kintsugi-vX.Y.Z.img.zst.sha256` — single-line checksum file
- `kintsugi-vX.Y.Z.img.zst.minisig` — detached Ed25519 signature
- `manifest.json` — SBOM-lite listing every component (ISO, model, binary) with individual SHA-256
- `manifest.json.sha256`, `manifest.json.minisig` — manifest is independently verifiable
- `kintsugi.pub` — minisign public key (also committed to repo root and pinned in `README.md` and `SECURITY.md`)

### Hash chain (per SAD §9.1)

The top-level image is signed; the image contains `manifest.json`; `manifest.json` lists per-component SHA-256. One signature transitively authenticates every component. A recipient who verifies the top-level signature and then trusts the manifest hashes has end-to-end provenance without N signatures.

### Recipient flow

Documented in `docs/flash-image.md` with copy-paste blocks per OS:

1. Download `image.img.zst`, `image.img.zst.sha256`, `image.img.zst.minisig`, and `kintsugi.pub` (or copy the pubkey from `README.md`).
2. Verify checksum:
   - Linux: `sha256sum -c image.img.zst.sha256`
   - macOS: `shasum -a 256 -c image.img.zst.sha256`
   - Windows PowerShell: `(Get-FileHash image.img.zst -Algorithm SHA256).Hash`, compare against the `.sha256` file contents
3. Verify signature: `minisign -V -p kintsugi.pub -m image.img.zst -x image.img.zst.minisig`
4. Only after **both** checks pass, flash with Etcher, `dd`, or Rufus.

A wrapper `scripts/verify-release.sh` will automate steps 2–3 for Linux/macOS users.

## Key Management

- Maintainer generates the minisign keypair one-time using a passphrase-protected secret key stored on an offline USB hardware token or on a non-network-connected machine.
- `kintsugi.pub` is committed to the repo root and pinned in `README.md` and `SECURITY.md`. Any change to the pubkey is a signal of key rotation (or compromise) and produces a visible git diff.
- Rotation procedure: generate a new keypair; sign a transition statement (`KEY-ROTATION-YYYY-MM-DD.txt`) with the **old** key that names the new pubkey; publish both in the repo; update `README.md`. Not required for v1.0.

## Defer to Future

- **Cosign / sigstore migration.** Re-evaluate once Gitea Actions is wired for releases. The minisign pubkey and the cosign identity can coexist during a transition window.
- **SBOM generation (CycloneDX).** Out of scope for v1.0 per SAD §12; `manifest.json` serves as SBOM-lite.
- **Reproducible build attestation.** The base-OS builder is `live-build` (ADR-007 — supersedes the earlier Cubic assumption); it is not bit-reproducible without reproducibility flags, which R-03 acknowledges and defers.
- **Third-party pubkey mirror.** See Open Questions.

## Consequences

### Positive
- Recipients can authenticate releases against a single committed pubkey with no keyserver or web-of-trust ceremony.
- Two-stage UX (cheap integrity check, then cryptographic authenticity check) matches recipient mental model and makes the common failure (corrupt download) fast to diagnose.
- Ed25519 signatures are small (~100 bytes) and verification is fast (<50 ms) even on the recipient's rescue boot.
- Hash-chained manifest means one signature covers the entire payload — linear signing cost in release count, not in component count.
- Forward-compatible with cosign migration; minisign does not paint us into a corner.

### Negative
- Recipients must install `minisign` once (Linux package, macOS brew, Windows scoop/direct). Mitigated by per-OS install instructions in `docs/flash-image.md`.
- No web-of-trust; initial pubkey distribution relies on TOFU — the recipient trusts the first `kintsugi.pub` they see because it is pinned in a public repo. If the repo itself is compromised, the pubkey can be swapped. Mitigated by git history visibility, by the Open Question below on third-party mirror, and by publishing the pubkey fingerprint in out-of-band channels (README badge, Gitea release notes).
- Maintainer must manage an offline secret key; loss of the key forces a rotation ceremony.

## Implementation Plan

1. Generate minisign keypair one-time; store secret key offline.
2. Commit `kintsugi.pub` to repo root; pin fingerprint in `README.md`.
3. Author `SECURITY.md` documenting the verification process, the pubkey fingerprint, and a tamper-reporting channel (referenced by SAD §6 and §9.1).
4. Extend `scripts/publish-release.sh` (per ADR-002) to compute `.sha256` and run `minisign -S` on every release artifact, including `manifest.json`.
5. Author `scripts/verify-release.sh` as a one-shot verifier for recipients on Linux/macOS.
6. Author `docs/flash-image.md` with per-OS verification one-liners and the "both must pass before flashing" guardrail.
7. Add a verification smoke-test to the physical-test guide: on every release, a second machine with only `kintsugi.pub` must verify successfully before the release is announced.

## Open Questions

- **Third-party pubkey mirror.** Should `kintsugi.pub` also be published as a Gitea release attachment, an HTTPS-served static file on a separate domain, and/or a DNS TXT record, to give a defense-in-depth cross-check against a repo compromise? Lean yes for v1.1; not blocking v1.0.
- **minisign install friction.** If recipient feedback shows install-and-verify friction is too high, consider bundling a statically-linked minisign verifier in the release assets for Linux/macOS/Windows so verification requires zero install (only download + run).
- **Signature expiry.** minisign supports untrusted comments but no built-in expiry. Should release notes state an explicit "valid-until" date for each signature? Deferred pending recipient feedback.

## Links

- SAD §9.1 (Security cross-cutting — signing commitment)
- SAD §4.3 (Release artifact structure)
- SAD §6 (Security architecture overview)
- `sad-review-security.md` (review that escalated this requirement)
- R-02 (Supply-chain provenance risk)
- ADR-002 (Release artifact structure — consumed by this ADR's implementation plan)
