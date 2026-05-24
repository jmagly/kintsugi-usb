# ADR-001: License Selection for Kintsugi USB Repository

**Status**: **ACCEPTED** — MIT selected (2026-04-20)
**Date**: 2026-04-20
**Deciders**: Joseph Magly (maintainer)
**Consulted**: SAD §9.5, Risk R-01, ADR-005, ADR-006

## Decision (2026-04-20)

**MIT License** for the repository. `LICENSE` file committed at repo root. Copyright 2026 Joseph Magly.

Rationale: With ADR-005 (user-driven models) and ADR-006 (user-driven agentic frameworks, wizard-first UX), the maintainer's redistributable surface reduces to **scripts + docs + YAML manifests** — essentially no binaries, no weights, no proprietary content. MIT minimizes forker friction, which is the explicit product promise of the wizard-first toolkit. Apache-2.0 was considered (patent grant + NOTICE convention) but rejected on forker-friction grounds; dual MIT/Apache-2.0 was considered (Rust-ecosystem pattern) but rejected as unnecessary complexity. AGPL was considered and rejected because its distinguishing network-copyleft clause (§13) does not fire for a local-USB toolkit.

`manifest/THIRD-PARTY-LICENSES.md` (iteration-1 deliverable) will enumerate bundled binaries with their own licenses: Ventoy (GPLv3), Ubuntu 24.04 (aggregated), llama.cpp (MIT), Ollama (Apache-2.0), VS Code (Microsoft EULA), GitHub Copilot extension (Microsoft EULA), GitHub CLI (MIT), rescue ISOs (various). No model weights, no agentic-framework binaries — those are user-fetched, not redistributed.

R-01 (license risk) can be **CLOSED** once LICENSE file + THIRD-PARTY-LICENSES.md are both committed.

## Amendment 2026-04-20 (per ADR-005)

Model weights are no longer redistributed by the maintainer — ADR-005 moves model loading to end-users. Therefore the model-license complications (Qwen Tongyi Qianwen commercial threshold; Anthropic Claude Code EULA redistribution of weights) **drop out of scope** for this ADR. ADR-006 extended the same pattern to agentic-framework binaries (Aider, Claude Code, Codex CLI, Cursor, Windsurf, Warp, etc.) — also user-fetched, not redistributed.

Risk R-01 severity downgraded from CRITICAL to HIGH as a result (see risk-list.md amendment). With MIT acceptance + THIRD-PARTY-LICENSES.md delivery, R-01 is on track to CLOSED.

---

## Context

Kintsugi USB has no top-level `LICENSE` file. `README.md` marks it "TBD" and the Software Architecture Document (§9.5) and risk register (R-01, CRITICAL) both block the first public Gitea release until licensing is reconciled. Without an explicit license, the repository is effectively "all rights reserved" by default — a posture that contradicts the project's public-distribution intent and that will discourage downstream forks, audits, and recipient trust.

The decision has two distinct surfaces that must not be conflated:

1. **The repository** — the Gitea source tree at `roctinam/kintsugi-usb`. This is the maintainer's original work: `docs/`, forthcoming `scripts/` and `manifest/`, and the assembly recipe that ties third-party components together. A top-level LICENSE applies here.
2. **The deployed USB image** — a composite artifact that bundles upstream third-party binaries, ISOs, and model weights. The maintainer is a **redistributor**, not the licensor, of those components. Their licenses (GPLv3, MIT, Apache-2.0, Anthropic EULA, Tongyi Qianwen, and others) continue to govern each bundled component under its own terms. No repository LICENSE can override them.

The project is solo, non-commercial, and small-audience (family + fleet operators). The license must therefore be simple to comply with, legible to non-lawyer recipients, and compatible with the widest feasible set of bundled-component licenses so that the shipped image remains legally distributable.

## Decision Drivers

- **Legal unblock for first public release** — R-01 is a CRITICAL blocker.
- **Solo maintainer, minimal compliance overhead** — no legal team exists to interpret edge cases.
- **Bundled-artifact heterogeneity** — copyleft (GPLv3), permissive (MIT, Apache-2.0), proprietary EULA (Claude Code, Codex CLI), and restricted-commercial (Qwen2.5-Coder Tongyi Qianwen) components coexist on one drive.
- **Public-repo security posture** — the LICENSE must not inadvertently encourage users to redistribute components that forbid redistribution.
- **Downstream forkability** — a competent operator should be able to rebuild the USB from `docs/build-guide.md` under the chosen terms (see R-15 succession mitigation).
- **Patent exposure** — even for a small project, an explicit patent grant is cheap insurance.
- **Alignment with ecosystem norms** — Ubuntu, `llama.cpp`, and most AI tooling the project touches are permissively licensed.

## Considered Options

### 1. MIT
**Pros**: Shortest license text, universally understood, compatible with every other bundled component (GPLv3 projects can consume MIT code).
**Cons**: No explicit patent grant. No NOTICE mechanism, so bundled-attribution strategy relies entirely on a separate manifest file. No trademark protection.
**Fit**: Good. Low friction, widely recognized by non-lawyer recipients.

### 2. Apache-2.0
**Pros**: Permissive like MIT, with an explicit patent grant and a formal `NOTICE` file convention that pairs naturally with `manifest/THIRD-PARTY-LICENSES.md`. Compatible with GPLv3 (one-way: Apache-2.0 code can be incorporated into GPLv3 works). Well-understood by enterprise downstreams if the audience ever grows.
**Cons**: Longer license text than MIT. Slightly more ceremony (NOTICE file upkeep).
**Fit**: Strong. The NOTICE convention directly models the bundled-attribution problem this project has.

### 3. GPL-3.0
**Pros**: Aligns with Ventoy's own GPLv3 license; ensures downstream forks of the *repository* must remain free. "Honors the break" aesthetic — copyleft as a preservation commitment.
**Cons**: Copyleft applies only to the repository's own code; it does not and cannot make the bundled proprietary CLIs (Claude Code, Codex) or restricted-commercial models (Qwen2.5-Coder) GPL-compatible. Ventoy's GPLv3 applies to Ventoy, not to the image containing it — aggregation on a filesystem is not a combined work under the FSF's own interpretation. GPL-3.0 on this repo therefore buys alignment *aesthetics* but not actual compatibility uplift, while adding friction for downstream recipients who want to reuse `scripts/` or `docs/` in permissively licensed projects.
**Fit**: Plausible but over-rotated on a Ventoy-alignment argument that does not survive scrutiny.

### 4. CC0 / Unlicense
**Pros**: Minimum friction; dedicates work to public domain.
**Cons**: Legally uncertain in some jurisdictions. No patent grant. No warranty disclaimer in Unlicense (CC0 has one). Sends a "don't bother attributing me" signal that conflicts with the project's documentation-as-product identity.
**Fit**: Poor for a documentation-heavy project the maintainer wants recognized as theirs.

### 5. No license (status quo)
**Pros**: Zero effort.
**Cons**: Legally "all rights reserved" — blocks forks, republishing, redistribution, and recipient trust. Unblocks nothing. Violates public-repo intent.
**Fit**: Unacceptable. This is the status R-01 exists to retire.

## Decision (recommended)

**Apache-2.0 for the repository**, paired with a `NOTICE` file and a `manifest/THIRD-PARTY-LICENSES.md` enumerating every bundled component's separate license.

**Rationale**: Apache-2.0 is the best match for a solo, public, documentation-and-scripts project whose deployed artifact is a bundle of externally licensed components. The explicit patent grant gives cheap legal hygiene. The `NOTICE` convention is exactly the mechanism needed to surface bundled-artifact attribution without claiming to relicense those components. It is compatible (one-way) with GPLv3 so Ventoy and any other copyleft component continues to ship under its own terms inside the image. It avoids the GPL-3.0 aesthetic trap of claiming alignment that aggregation does not actually deliver. It is short enough for a non-lawyer to read and verify.

## Bundled-Artifact License Strategy

- Maintain `manifest/THIRD-PARTY-LICENSES.md` listing, for every bundled component: name, version, upstream source URL, upstream SHA-256, license identifier (SPDX where possible), and any redistribution constraint.
- Note explicit constraints surfaced by SAD §9.5:
  - **Qwen2.5-Coder** — Tongyi Qianwen License has commercial-use thresholds (currently ≥100M MAU). Kintsugi USB is non-commercial and well under any plausible threshold, but the constraint must be surfaced to recipients in case their use shifts that posture.
  - **Claude Code CLI** — Anthropic EULA. Redistribution of the binary in a public image is almost certainly not permitted. Default posture: **do not bake the binary into the image**; ship a post-flash installer script (`scripts/install-cloud-clis.sh`) the recipient runs themselves under their own acceptance of the Anthropic EULA.
  - **Codex CLI** — same posture as Claude Code; post-flash install unless/until redistribution is confirmed permissible.
  - **Ventoy** — GPLv3. Redistributable; no action beyond NOTICE entry.
  - **Ubuntu 24.04** — composite; redistributable as a standard live ISO bundle.
  - **llama.cpp, Aider** — MIT / Apache-2.0; redistributable with NOTICE entry.
  - **Phi-4-mini** — MIT; redistributable with NOTICE entry.
  - **Rescue ISOs** (SystemRescue, Clonezilla, GParted Live) — mostly GPL; redistributable as-is.
  - **Hiren's BootCD PE** — non-free and often not redistributable. Treat as post-flash download unless upstream terms explicitly permit.
- For any component whose license forbids redistribution in a public image, the project ships a **download-on-first-boot** (or post-flash install) pattern rather than the binary itself. This keeps the published `.img.zst` legally clean.

## Consequences

**Positive**:
- Unblocks R-01 and therefore the first public Gitea release.
- Apache-2.0's NOTICE convention gives the bundled-attribution problem a standard, auditable home.
- Patent grant is in place before any potential growth.
- Downstream forks and fleet operators can reuse `scripts/` and `docs/` in their own (including permissively licensed) tooling.
- Aligns with ecosystem norms (llama.cpp, Ubuntu tooling, most of the AI stack).

**Negative**:
- Does not prevent a downstream fork from being proprietized (tradeoff inherent to permissive licensing). Acceptable given the documentation-first nature of the product.
- NOTICE file requires ongoing maintenance as bundled components change. Mitigated by tying it to `manifest/` generation in the imaging pipeline.

**Neutral**:
- Does not change the licensing of any bundled component — each continues under its own terms.
- Does not resolve the cloud-CLI telemetry question (§9.5 item 3, Open Question in SAD); that is a privacy concern separate from redistribution.

## Compliance Actions on Adoption

1. Add top-level `LICENSE` file containing the canonical Apache-2.0 text.
2. Add top-level `NOTICE` file identifying the project, copyright holder, and pointer to `manifest/THIRD-PARTY-LICENSES.md`.
3. Update `README.md` License section to name Apache-2.0 and link to LICENSE, NOTICE, and the third-party manifest.
4. Create `manifest/THIRD-PARTY-LICENSES.md` with an entry per bundled component (see Bundled-Artifact License Strategy above).
5. **Verify Qwen2.5-Coder and Claude Code redistribution policies in writing** (Anthropic Terms of Service and Tongyi Qianwen License text). If either forbids redistribution in a public image, switch that component to the download-on-first-boot pattern before the first Gitea release.
6. Add SPDX headers (`# SPDX-License-Identifier: Apache-2.0`) to every Bash script under `scripts/` as it is authored.
7. Update R-01 status from CRITICAL/OPEN to MITIGATED once LICENSE, NOTICE, and the third-party manifest are merged.

## Open Questions

- Is **Qwen2.5-Coder** redistributable in a free public image under the Tongyi Qianwen License at this scale, or must recipients fetch it themselves? (Default assumption: redistributable at this scale; verify before first release.)
- Does **Anthropic** permit redistribution of the `claude` CLI binary in a community image? (Default assumption: **no**; ship post-flash installer.)
- Does **OpenAI** permit redistribution of the Codex CLI binary? (Default assumption: **no**; ship post-flash installer.)
- Is **Hiren's BootCD PE** redistributable? (Default assumption: **no**; document as recipient-sourced.)

## Links

- SAD §9.5 Licensing — [software-architecture-doc.md](software-architecture-doc.md)
- R-01 — [risk-list.md](../risks/risk-list.md)
- NFR-10.1..10.5 (licensing non-functional requirements) — [nfr-register.md](../requirements/nfr-register.md)
- Apache License 2.0 canonical text — https://www.apache.org/licenses/LICENSE-2.0
