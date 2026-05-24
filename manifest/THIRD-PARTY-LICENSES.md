# Third-Party Licenses

The Kintsugi USB repository is licensed under **MIT** (see [`LICENSE`](../LICENSE)). That license applies only to this repository's own authored contents (scripts, docs, YAML manifests, configs).

The following third-party components are **bundled** in the custom Ubuntu ISO produced by this toolkit, or are dependencies the toolkit's scripts reference at build time. Each retains its own license. The user running the build is responsible for respecting each component's license terms.

## Components Bundled in the Base ISO

| Component | Version (at v1.0 target) | License | Source | Notes |
|-----------|--------------------------|---------|--------|-------|
| **Ventoy** | v1.1.x | GPL-3.0-or-later | https://www.ventoy.net/ | Multi-boot USB loader. GPLv3 copyleft — our scripts and docs *invoke* Ventoy, they do not link with or embed it, so our MIT licensing of the repo is compatible. |
| **Ubuntu 24.04 LTS Server** | 24.04.x | Aggregated (primarily GPL/LGPL/MIT/BSD) | https://ubuntu.com/ | Base OS for the custom ML-Support ISO. Canonical aggregates hundreds of per-package licenses; built with Cubic from the official ISO. |
| **Xfce4** | per-Ubuntu | GPL-2.0 / LGPL-2.1 / BSD (per-component) | Ubuntu repo | Lightweight desktop environment layer in the custom ISO. |
| **llama.cpp** | per-release | MIT | https://github.com/ggerganov/llama.cpp | Offline LLM inference runtime. Binary bundled at `/tools/bin/llama-server` and `/tools/bin/llama-cli`. |
| **Ollama** | per-release (pinned in wizard) | MIT | https://github.com/ollama/ollama | Second local LLM runtime alongside llama.cpp. Installed via Ollama's published install script in the Cubic chroot; pinned version, auto-update disabled. |
| **Visual Studio Code** | per-wizard-build | [Microsoft Software License Terms — VS Code](https://code.visualstudio.com/license) | Microsoft apt repo (`packages.microsoft.com`) | IDE installed by default in v1.0 per ADR-006 §D3. Permissive for personal and commercial use; Microsoft telemetry is **disabled by default** via `/etc/skel/.config/Code/User/settings.json` (R-19 mitigation). Opt-out available via wizard. |
| **GitHub Copilot extension** | per-marketplace-fetch | [GitHub Copilot Business Terms](https://docs.github.com/en/github/copilot) | VS Code Marketplace | Extension is preinstalled; the extension installer is freely redistributable. Functionality requires a Copilot subscription and GitHub sign-in, which the user provides post-flash (R-20). |
| **GitHub CLI (`gh`)** | per-release | MIT | https://github.com/cli/cli | Installed to assist post-flash Copilot and GitHub workflows. |
| **SystemRescue** | 11.x | GPL-2.0-or-later | https://www.system-rescue.org/ | Bundled as a standalone ISO in the Ventoy menu. |
| **Clonezilla Live** | 3.x | GPL-3.0-or-later | https://clonezilla.org/ | Standalone ISO; disk imaging. |
| **GParted Live** | 1.x | GPL-2.0-or-later | https://gparted.org/ | Standalone ISO; partition management. |
| **Memtest86+** | 6.x | GPL-2.0-or-later | https://www.memtest.org/ | Standalone in the Ventoy menu. |
| **Hiren's BootCD PE** | latest | Mixed; [non-commercial](https://www.hirensbootcd.org/) | https://www.hirensbootcd.org/ | Optional inclusion in the wizard; licensing permits personal/recovery use. Wizard flags the license status when selected. |
| **Rescue tool packages** (fsck family, smartctl, nvme-cli, testdisk, ddrescue, gparted, nmap, tcpdump, grub tools, etc.) | per-Ubuntu | GPL-2.0 / GPL-3.0 / BSD / MIT / LGPL (per-package) | Ubuntu repo | Installed via apt in the custom ISO. Each package retains its own license. |

## Components User-Fetched (NOT Redistributed by this Toolkit)

Per [ADR-005](../.aiwg/architecture/adr-005-toolkit-scope-and-user-driven-models.md) and [ADR-006](../.aiwg/architecture/adr-006-wizard-first-ux-and-user-driven-agentic-frameworks.md), the following are **never redistributed** by Kintsugi USB. Users fetch them at build-time or boot-time; each component's license applies to the user's local copy.

### Model weights (fetched via `kintsugi-models` CLI)

Listed in [`manifest/models-recommended.yaml`](models-recommended.yaml). Examples of licenses the user will encounter:

- **Qwen3.5 family** — [Qwen License](https://huggingface.co/Qwen) (permissive with commercial-threshold notice above 100 M MAU; the user is responsible for threshold compliance)
- **Qwen2.5-Coder** — [Qwen License](https://huggingface.co/Qwen)
- **Phi-4 family** — [MIT](https://huggingface.co/microsoft) (per Microsoft's Phi-4 release)
- **TinyLlama** — Apache-2.0
- **Other GGUFs from HuggingFace** — see each model's HuggingFace repo LICENSE

### Agentic framework binaries (fetched via `kintsugi-frameworks` CLI)

Listed in [`manifest/agentic-frameworks-recommended.yaml`](agentic-frameworks-recommended.yaml). v1.0 ships install recipes for:

- **Aider** — Apache-2.0 (https://github.com/Aider-AI/aider)
- **Claude Code** — [Anthropic Software License](https://www.anthropic.com/legal) (proprietary EULA; user accepts at install time; Anthropic API subscription for usage)
- **Codex CLI** — [OpenAI terms](https://openai.com/policies/) (proprietary; OpenAI API subscription for usage)

v1.1+ recipes for Cursor, Windsurf, Warp, OpenCode, Factory, and Continue.dev carry their own vendor licenses; see `agentic-frameworks-recommended.yaml`.

## Trust Boundary Summary

- **Maintainer of this repo signs (v1.1+; v1.0 ships sha256-only)**:
  - The base image produced by `scripts/publish-release.sh`
  - The scripts and docs as committed in tagged git releases
  - `manifest/models-recommended.yaml` and `manifest/agentic-frameworks-recommended.yaml` as committed
- **Maintainer does NOT sign**:
  - Model weights (user-fetched; carry source-advertised digests)
  - Agentic framework binaries (user-fetched; carry vendor-provided install-time signatures)
  - Bundled third-party binaries listed above (carry their own upstream signing where applicable)

## Notices

- This file is a summary. When in doubt about a specific component's terms, consult the upstream license file.
- Commercial redistribution of any bundled component may carry additional obligations — consult each license.
- If your fork of this repo bundles additional components, update this file with those entries.

## Updates

This file is updated as part of each release. Last updated: 2026-04-20. Tracked via Gitea issue [#30](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/30).
