# Security Policy — Kintsugi USB

## Scope

This document covers the security posture of the Kintsugi USB project: what we attest to, what we don't, and how to report concerns.

**This is a community rescue-USB toolkit, not a commercial product.** Response is best-effort by a solo maintainer. There is no paid support, no formal SLA, and no bounty program. Reports are welcome and will be taken seriously.

## Supported versions

Only the most recent tagged release receives security fixes. Older releases are historical. The wizard-first build model means most users run their own custom builds — those are not "versions" we maintain.

| Version line | Status |
|--------------|--------|
| `main` branch | Development; most recent changes, pre-release |
| Latest tagged release (`v1.0.x` when it ships) | Security fixes applied |
| Earlier tags | Not maintained; upgrade to latest |

## Verification — what v1.0 provides

For v1.0, any maintainer-produced images (published to the warehouse NFS mount per [ADR-006 §D4](.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md)) ship with a **SHA-256 checksum** alongside the image file. Recipients verify integrity with:

```bash
# Linux / macOS
shasum -a 256 -c kintsugi-v2026.5.0.img.zst.sha256

# Windows PowerShell
Get-FileHash kintsugi-v2026.5.0.img.zst -Algorithm SHA256
```

SHA-256 protects against **accidental corruption in transit**. It does **not**, on its own, protect against malicious substitution if an attacker can modify both the image and the checksum on the host serving them.

### Signing lands in v1.1

A full cryptographic signing flow (minisign, Ed25519) is scheduled for v1.1. At that point:

- Every release artifact will carry a `.minisig` signature
- The maintainer's public key `kintsugi.pub` will be committed to this repo and pinned in `README.md`
- `scripts/verify-image.sh` wraps the sha256 + minisign verification in a single command (the sha256 stage is live today; the minisign stage activates automatically once a `.minisig` and `kintsugi.pub` are present)
- `docs/flash-image.md` will gain per-OS one-liners for the full verify flow

This deferral is an explicit trade-off to let iteration-1 focus on the build toolkit (the wizard is the product). See [ADR-003](.aiwg/architecture/adr-003-verification-rigor.md) (amended) and [ADR-006 §D5](.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md).

## Release signing key

The signing key is a long-lived Ed25519 minisign keypair. This section is the authoritative record of its custody model and rotation procedure. The procedure is documented now (issue #19); the keypair itself is generated as a separate offline ceremony before the first signed (v1.1) release.

### Secret-key custody

- The **secret key is never committed to this repository** and never stored on a networked build host. It lives on the maintainer's trusted offline machine (or a hardware token). Its location is recorded **privately**, outside this repo.
- Only `kintsugi.pub` is public — committed to repo root and pinned in [`README.md`](README.md#release-signing--public-key). Recipients trust it on first use (TOFU); there is no web-of-trust.
- The build/publish host (`scripts/publish-release.sh`) never holds the secret key. Signing is a deliberate maintainer step performed on the offline machine against the artifact's sha256, not an automated CI action — at least until a hardware-token-backed signer is wired up.

### Rotation procedure

Rotate when: the secret key is suspected compromised, the storage medium is retired, or on a routine cadence (recommended: every 2 years, or per organizational policy).

1. **Generate the replacement keypair offline** — on the trusted/offline machine: `minisign -G -p kintsugi-new.pub -s kintsugi-new.key`. Store the new secret key with the same custody discipline as the old one.
2. **Publish a transition notice** — before retiring the old key, commit the new `kintsugi.pub` alongside the old one in a clearly-labeled `## Key rotation` block in this file, signed-over by the **old** key where possible, so recipients can chain trust from the key they already pinned.
3. **Dual-sign one release** — sign the next release with **both** the old and new keys (`.minisig` and `.minisig.new`) so recipients on either key can verify during the overlap window.
4. **Retire the old key** — after the overlap release, replace `kintsugi.pub` with the new key, update the pinned block in `README.md`, and record the rotation (date, reason, fingerprints — never key material) in the rotation log below.
5. **If compromised** — skip the overlap; revoke immediately, publish a private disclosure, re-sign the current release with the new key, and treat all releases signed by the compromised key as suspect pending re-verification.

### Rotation log

| Date | Action | Reason | Pub-key fingerprint (not key material) |
|------|--------|--------|-----------------------------------------|
| _pending_ | Initial keypair generation | v1.1 signing ceremony | _to be recorded when generated_ |

## Trust boundary

### What the maintainer's release (v1.1+: signature) attests to

- The **base image** produced by `scripts/publish-release.sh` at tag time
- The **scripts** and **docs** as committed in the tagged git release
- `manifest/models-recommended.yaml` and `manifest/agentic-frameworks-recommended.yaml` **as committed**

### What the maintainer does NOT attest to

- **Model weights** — user-fetched via `kintsugi-models pull`. Carry the source's own integrity story (Ollama registry digest, HuggingFace sha256, or user-supplied checksum). See `manifest/models-recommended.yaml` for the recommended list; anything outside it is entirely user-owned.
- **Agentic framework binaries** — user-fetched via `kintsugi-frameworks install`. Carry their vendors' own signing / install-verification.
- **User-pulled anything else** — the wizard's "Other" options and any `--custom-slug` invocations bypass the recommended list; you're the trust anchor for those choices.
- **Your downstream fork** — if you fork this toolkit to build your own distribution, sign with your own key. Don't claim the maintainer's signature.

This boundary is described in more detail in [`manifest/THIRD-PARTY-LICENSES.md`](manifest/THIRD-PARTY-LICENSES.md) and [`docs/toolkit-guide.md`](docs/toolkit-guide.md).

## Reporting a security concern

### Preferred: Gitea issue (for non-sensitive reports)

For bugs, misconfigurations, doc errors, or observations that would benefit from public visibility: https://git.integrolabs.net/roctinam/kintsugi-usb/issues — label with `security` if appropriate.

### Private disclosure (for sensitive reports)

If the issue is sensitive — a suspected tampered image, a compromised credential, evidence of maliciously-modified scripts, a key compromise — contact the maintainer directly:

- **Email**: via GitHub profile for `roctinam` (pgp key on keyserver if available)
- **Gitea DM**: via https://git.integrolabs.net/roctinam

### What to report

Include as much as you can:

- Which release or build (git commit hash, wizard profile if available)
- What you observed (error, suspicious behavior, checksum mismatch, install failure)
- How you observed it (commands run, network conditions, host type)
- Any captured evidence (log snippets, stderr, harness output)

### What to expect

- Acknowledgement within a reasonable best-effort window (this is a solo-maintained project — days, not hours)
- If the report is valid and sensitive, coordinated disclosure: fix first, public advisory later
- If the report is valid and non-sensitive: a Gitea issue and a fix in the next tagged release
- Credit at your discretion — we're happy to thank reporters publicly or keep reports anonymous

## Specific reporting channels by concern type

| Concern | Channel |
|---------|---------|
| Tampered image on NFS mount (v1.0) | Private disclosure first; we'll re-verify via an independent checksum source and revoke the bad release |
| Suspected compromised signing key (v1.1+) | Private disclosure immediately; follow the [key rotation procedure](#rotation-procedure) (compromise path — skip the overlap window) |
| Malicious model slug in `models-recommended.yaml` | Gitea issue with details; we'll pull the entry within the next release |
| Malicious framework install recipe in `agentic-frameworks-recommended.yaml` | Same as above |
| Secret accidentally committed to this repo | Private disclosure — we'll force-rewrite history if caught early, rotate the exposed credential, and audit for further leaks |
| Vulnerability in bundled third-party binary | Report to the upstream project first (Ventoy, llama.cpp, Ollama, Ubuntu, etc.); let us know if we should pin an older version |

## Related

- [ADR-003 — Release Verification Rigor (amended — v1.0 sha256 only; v1.1+ full signing)](.aiwg/architecture/adr-003-verification-rigor.md)
- [ADR-005 — Toolkit scope + user-driven models](.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md)
- [ADR-006 — Wizard-first UX + user-driven agentic frameworks + signing deferred](.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md)
- [Risk register](.aiwg/risks/risk-list.md) — R-02 (supply-chain provenance), R-07 (secrets in repo), R-17 (malicious user-pulled slug), R-19 (VS Code telemetry), R-20 (Copilot subscription dependency)

## Updates

This policy evolves. Last updated: 2026-05-24 (added release-signing-key custody + rotation procedure, issue #19). Next review: when the v1.1 signing keypair is generated.
