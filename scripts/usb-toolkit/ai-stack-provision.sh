#!/bin/bash
# ai-stack-provision.sh — install the offline LLM runtime + manifest tooling into
# the Kintsugi live filesystem. The headline feature of the drive (repo purpose:
# "Offline LLM inference stack"; ADR-005 §D2).
#
# Runs INSIDE the chroot during remaster (make-remaster-iso.sh --with-ai-stack,
# via `livefs-edit --python` chroot-exec) — the same mechanism agentic-provision.sh
# uses. Ports the non-optional AI-core content the ADR-008 pivot dropped (#43):
#   - Ollama        : offline LLM runtime (sha256-pinned installer, #40; service
#                     left disabled — start-ai.sh launches it on demand).
#   - mikefarah yq  : Go-based YAML processor that kintsugi-models / kintsugi-
#                     frameworks require at runtime (Ubuntu's apt 'yq' is the
#                     incompatible python-yq).
#
# NOT handled here (by design):
#   - llama.cpp/llama-server : never auto-installed (start-ai.sh finds-if-present
#                              and degrades gracefully) — not a regression.
#   - XFCE desktop           : provided by the xubuntu-minimal base ISO.
#   - VS Code/Copilot/gh     : IDE decision deferred (#43 decision 1).
#
# Models are NEVER baked (ADR-005 user-driven loading) — pulled post-flash.
# Each install is guarded; per-component failure is logged, not fatal.
#
# Env overrides:
#   KINTSUGI_OLLAMA_VERSION           (default: latest)
#   KINTSUGI_OLLAMA_INSTALLER_SHA256  (default: pinned below; update after review)
#   KINTSUGI_YQ_VERSION               (default: v4.44.3)

set -u
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# Empty = the installer's built-in latest. Do NOT default to the literal "latest":
# install.sh builds VER_PARAM="?version=$OLLAMA_VERSION", and ".../ollama-linux-amd64.tar.zst?version=latest"
# 404s (only the bare URL serves latest). A real pinned version (e.g. "0.5.7") is fine.
OLLAMA_VERSION="${KINTSUGI_OLLAMA_VERSION:-}"
OLLAMA_INSTALLER_SHA256="${KINTSUGI_OLLAMA_INSTALLER_SHA256:-25f64b810b947145095956533e1bdf56eacea2673c55a7e586be4515fc882c9f}"
YQ_VERSION="${KINTSUGI_YQ_VERSION:-v4.44.3}"

LOG=/etc/kintsugi/ai-stack-install.log
MANIFEST=/etc/kintsugi/ai-stack-installed.txt
mkdir -p /etc/kintsugi
: > "$LOG"; : > "$MANIFEST"
log()    { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG" >&2; }
record() { echo "$1" >> "$MANIFEST"; }

log "=== Kintsugi AI-stack provisioning ==="

apt-get update >>"$LOG" 2>&1 || true
# curl/ca-certificates for fetch; zstd is REQUIRED by modern Ollama's installer
# (its release artifacts are .tar.zst — install.sh hard-errors without zstd);
# findutils/gawk satisfy the installer's `require curl awk grep sed tee xargs` gate.
apt-get install -y --no-install-recommends curl ca-certificates zstd findutils gawk >>"$LOG" 2>&1 || true

# --- mikefarah/yq (runtime dep of kintsugi-models / kintsugi-frameworks) -------
log "installing mikefarah yq ${YQ_VERSION} ..."
if curl -fsSL -o /usr/local/bin/yq \
      "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" >>"$LOG" 2>&1 \
   && chmod +x /usr/local/bin/yq \
   && /usr/local/bin/yq --version 2>&1 | grep -qi mikefarah; then
    record "yq ${YQ_VERSION} (mikefarah)"
    log "  ✓ yq: $(/usr/local/bin/yq --version 2>&1 | head -1)"
else
    log "  ✗ yq FAILED (kintsugi-models/-frameworks will not parse manifests)"
fi

# --- Ollama (offline LLM runtime, ADR-005 §D2; installer sha256-pinned, #40) ---
log "installing Ollama (version=${OLLAMA_VERSION:-latest/unpinned}) ..."
INSTALL_SH=$(mktemp --suffix=.sh)
if curl -fsSL --max-time 60 https://ollama.com/install.sh -o "$INSTALL_SH" 2>>"$LOG"; then
    GOT_SHA=$(sha256sum "$INSTALL_SH" | awk '{print $1}')
    # Build-chroot guard: shim `systemctl` to a no-op for the Ollama install + disable.
    # Upstream install.sh enables AND STARTS ollama.service when it detects systemd —
    # and the build chroot sees the host's /run/systemd through bind mounts, so it
    # tries. A started `ollama serve` (whose root is the chroot) holds the chroot's
    # /dev busy and breaks the squashfs repack ("umount .../minimal/dev: target is
    # busy"). The shim also keeps the real systemctl from touching the HOST's
    # ollama.service. The image ships Ollama installed-but-stopped + not enabled;
    # start-ai.sh launches it on demand at runtime (ADR-005 §D2).
    SHIM_DIR=$(mktemp -d)
    printf '#!/bin/sh\nexit 0\n' > "$SHIM_DIR/systemctl"; chmod +x "$SHIM_DIR/systemctl"
    if [ "$GOT_SHA" != "$OLLAMA_INSTALLER_SHA256" ]; then
        log "  ✗ Ollama installer sha256 MISMATCH — refusing to run (supply-chain guard #40)"
        log "      expected: $OLLAMA_INSTALLER_SHA256"
        log "      got:      $GOT_SHA"
        log "      Review the new upstream installer, then update the pin."
    elif PATH="$SHIM_DIR:$PATH" OLLAMA_VERSION="$OLLAMA_VERSION" bash "$INSTALL_SH" >>"$LOG" 2>&1; then
        # enable/start were no-ops via the shim; assert not-enabled (also shimmed).
        PATH="$SHIM_DIR:$PATH" systemctl disable ollama.service >>"$LOG" 2>&1 || true
        if command -v ollama >/dev/null 2>&1; then
            record "ollama ${OLLAMA_VERSION}"
            log "  ✓ ollama: $(ollama --version 2>/dev/null | head -1 || echo installed)"
        else
            log "  ✗ Ollama installer ran but 'ollama' not on PATH"
        fi
    else
        log "  ✗ Ollama install script failed (continuing without it)"
    fi
    rm -rf "$SHIM_DIR"
else
    log "  ✗ could not fetch Ollama installer (no network at build time?)"
fi
rm -f "$INSTALL_SH"

# --- Summary -------------------------------------------------------------------
COUNT=$(wc -l < "$MANIFEST" 2>/dev/null || echo 0)
log "=== done — ${COUNT} AI-core component(s) installed ==="
sed 's/^/  - /' "$MANIFEST" 2>/dev/null | tee -a "$LOG" >&2

apt-get clean >>"$LOG" 2>&1 || true
rm -rf /var/lib/apt/lists/* /root/.cache 2>/dev/null || true

# Non-fatal: per-component failures are recorded, not fatal to the build.
exit 0
