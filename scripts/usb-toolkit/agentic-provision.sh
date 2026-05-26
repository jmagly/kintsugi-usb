#!/bin/bash
# agentic-provision.sh — pre-install AIWG-supported agentic CLI platforms into
# the Kintsugi live filesystem.
#
# Runs INSIDE the chroot during remaster (make-remaster-iso.sh --with-agentic,
# via `livefs-edit --python` chroot-exec). Each install is GUARDED so one
# platform's failure cannot abort the build; results are logged to
# /etc/kintsugi/agentic-install.log and the success list to
# /etc/kintsugi/agentic-installed.txt (surfaced by start-ai.sh / first boot).
#
# Scope: the AIWG-supported platforms with a clean, verified CLI install.
# Auth (API keys, OAuth, subscription sign-in) is NEVER baked — that is a
# post-flash user responsibility (ADR-006 §D5). This installs CLIs only.
#
# Baked (verified, clean install): claude-code, codex, opencode, copilot, openclaw
# (the 5 AIWG providers) + omnius (operator-requested, omnius.nexus)
# — npm globals → /usr/bin, available to every user immediately.
#
# Not installed here (tracked separately, by design):
#   - hermes   : NousResearch hermes-agent — installs via curl|bash into a PER-USER
#                ~/.hermes Python venv (+ models); doesn't fit a chroot-time system
#                install and is heavy. Candidate for a first-boot/opt-in installer.
#   - cursor/windsurf/warp/factory : GUI/desktop IDEs (AppImage/deb), not CLI tools;
#                heavy and out of scope for a CLI-focused rescue drive.

set -u
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
export PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin

LOG=/etc/kintsugi/agentic-install.log
MANIFEST=/etc/kintsugi/agentic-installed.txt
mkdir -p /etc/kintsugi
: > "$LOG"; : > "$MANIFEST"
log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG" >&2; }
record() { echo "$1" >> "$MANIFEST"; }
try() {  # try <display> <cmd...>
    local name="$1"; shift
    log "installing ${name} ..."
    if "$@" >>"$LOG" 2>&1; then record "$name"; log "  ✓ ${name}"; else log "  ✗ ${name} FAILED (see $LOG)"; fi
}

log "=== Kintsugi agentic provisioning ==="

# --- Base runtimes -------------------------------------------------------
log "Installing base toolchain (git, python3, pipx, curl, build-essential)..."
apt-get update >>"$LOG" 2>&1 || true
# build-essential: some agentic CLIs pull native node addons compiled via node-gyp
# (e.g. omnius → hnswlib-node, a C++ vector-search lib). Without a C++ toolchain
# `node-gyp rebuild` fails. python3 + node headers are also required (present/auto).
apt-get install -y curl ca-certificates git python3 python3-venv pipx build-essential >>"$LOG" 2>&1 || true

# Node 22 LTS via NodeSource (noble's apt node is too old for some CLIs).
log "Installing Node 22 LTS (NodeSource)..."
if curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >>"$LOG" 2>&1; then
    apt-get install -y nodejs >>"$LOG" 2>&1 || true
fi
log "  node: $(node --version 2>/dev/null || echo MISSING)  npm: $(npm --version 2>/dev/null || echo MISSING)"

# --- Agentic CLI platforms (verified package names) ----------------------
if command -v npm >/dev/null 2>&1; then
    try "claude-code" npm install -g @anthropic-ai/claude-code
    try "codex"       npm install -g @openai/codex
    try "opencode"    npm install -g opencode-ai
    try "copilot"     npm install -g @github/copilot
    # openclaw: AIWG provider, clean npm package (needs Node >=22.19; we ship 22.22).
    # The `openclaw onboard --install-daemon` step is post-flash (like auth) — not baked.
    try "openclaw"    npm install -g openclaw@latest
    # omnius (omnius.nexus): operator-requested tool, clean npm package (Node >=22).
    try "omnius"      npm install -g omnius
else
    log "  ✗ npm missing — skipping npm-based platforms (claude-code, codex, opencode, copilot, openclaw, omnius)"
fi

if command -v pipx >/dev/null 2>&1; then
    # noble ships pipx 1.4.3 (no --global). PIPX_HOME/PIPX_BIN_DIR (set above)
    # already place venvs in /opt/pipx and bin symlinks in /usr/local/bin (on PATH),
    # so plain `pipx install` is system-wide here. aider is a bonus tool, not an
    # AIWG provider — its failure is non-fatal.
    try "aider" pipx install aider-chat
fi

# --- Summary -------------------------------------------------------------
COUNT=$(wc -l < "$MANIFEST" 2>/dev/null || echo 0)
log "=== done — ${COUNT} agentic platform(s) pre-installed ==="
sed 's/^/  - /' "$MANIFEST" 2>/dev/null | tee -a "$LOG" >&2

# Reclaim the C/C++ build toolchain — it was only needed at build time to compile
# native node addons (omnius → hnswlib-node). The compiled .node stays and links
# against runtime libs (libstdc++6/libc6, which remain). Shipping gcc/g++/-dev
# pushed the base squashfs past the ISO9660 4 GiB per-file ceiling.
log "reclaiming build toolchain (build-essential) to keep the squashfs under 4 GiB..."
apt-get purge -y build-essential >>"$LOG" 2>&1 || true
apt-get autoremove -y --purge >>"$LOG" 2>&1 || true

# Keep the squashfs lean.
apt-get clean >>"$LOG" 2>&1 || true
rm -rf /var/lib/apt/lists/* /root/.npm /root/.cache /root/.node-gyp 2>/dev/null || true

# Always succeed — per-platform failures are recorded, not fatal to the build.
exit 0
