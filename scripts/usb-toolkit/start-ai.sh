#!/bin/bash
# Kintsugi USB — AI Stack Launcher
# Starts local runtimes (llama.cpp + Ollama) and reports status.
# Models are user-driven per ADR-005 (see manifest/models-recommended.yaml).
#
# Usage: start-ai.sh [--auto|--offline|--status|--stop]
#
#   --auto     (default) start local runtimes; select model from manifest by RAM
#   --offline  same as --auto but skip network probe + cloud CLI hints
#   --status   print runtime + model status; do not start/stop anything
#   --stop     stop llama-server (Ollama lifecycle handled by systemd / ollama itself)

set -euo pipefail

VERSION="0.1.0"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# Repo root (wizard / first-boot-setup may set KINTSUGI_REPO_ROOT explicitly).
# Search in priority order: env override → persistence clone → bundled payload.
REPO_ROOT="${KINTSUGI_REPO_ROOT:-}"
if [ -z "$REPO_ROOT" ]; then
    for cand in /data/repo/kintsugi-usb /opt/kintsugi-usb /cdrom/kintsugi-usb; do
        [ -d "$cand" ] && REPO_ROOT="$cand" && break
    done
fi

# Bundled tools (on VENTOY partition when booted from USB; /opt/ fallback).
TOOLS_DIR=""
for base in /cdrom /media/*/VENTOY /media/*/USB* /mnt/usb* /opt/kintsugi; do
    [ -d "${base}/tools" ] && TOOLS_DIR="${base}/tools" && break
done
[ -z "$TOOLS_DIR" ] && [ -d /opt/kintsugi/tools ] && TOOLS_DIR="/opt/kintsugi/tools"

# Model search roots (ADR-005 §D3):
# - Bundled payload (read-only when booted from USB): /payload/models/
# - Persistence (user pulls via kintsugi-models): /data/models/user/
BUNDLED_MODELS_DIR=""
for base in /cdrom /media/*/VENTOY /media/*/USB* /mnt/usb* /opt/kintsugi /payload; do
    [ -d "${base}/payload/models" ] && BUNDLED_MODELS_DIR="${base}/payload/models" && break
    [ -d "${base}/models" ] && BUNDLED_MODELS_DIR="${base}/models" && break
done
USER_MODELS_DIR="/data/models/user"

# Manifests (ADR-005 §D4).
RECOMMENDED_MANIFEST=""
[ -n "$REPO_ROOT" ] && [ -f "${REPO_ROOT}/manifest/models-recommended.yaml" ] && \
    RECOMMENDED_MANIFEST="${REPO_ROOT}/manifest/models-recommended.yaml"
USER_MANIFEST="/data/models/user/models.yaml"

# Runtime ports.
LLAMA_PORT=8080
OLLAMA_PORT=11434

# Logging.
LOG_DIR="/var/log/kintsugi"
LOG_FILE="${LOG_DIR}/start-ai.log"
LLAMA_LOG="${LOG_DIR}/llama-server.log"

mkdir -p "$LOG_DIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
    # Always print to stdout; append to log file when writable.
    # Never fail the script on log-write failure (avoids set -e aborts when
    # run unprivileged without a writable /var/log/kintsugi).
    local line
    line="[$(date '+%H:%M:%S')] $*"
    echo "$line"
    if [ -w "$LOG_DIR" ]; then
        echo "$line" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

detect_ram_gb() { free -g | awk '/Mem:/{print $2}'; }

detect_network() {
    # Probe Anthropic API (primary cloud dep); 2s timeout is intentional.
    ping -c1 -W2 api.anthropic.com &>/dev/null && echo "online" || echo "offline"
}

have_yq() { command -v yq &>/dev/null; }

port_open() {
    local port=$1
    curl -s --max-time 2 "http://localhost:${port}" &>/dev/null || \
    nc -z localhost "$port" &>/dev/null 2>&1
}

# Find the llama-server binary.
find_llama_server() {
    for p in "${TOOLS_DIR}/bin/llama-server" /usr/local/bin/llama-server /opt/kintsugi/tools/bin/llama-server /usr/bin/llama-server; do
        [ -x "$p" ] && echo "$p" && return
    done
    return 1
}

# ---------------------------------------------------------------------------
# Model discovery (manifest-driven, with find fallback)
# ---------------------------------------------------------------------------

# Return the path to a GGUF file to load into llama-server.
# Strategy:
#   1. If yq + recommended/user manifest present: select first llama-cpp entry;
#      prefer user-manifest entries (they shadow recommendations).
#   2. Else: find-based scan of USER_MODELS_DIR then BUNDLED_MODELS_DIR.
#   3. RAM hint (>=16 GB → prefer 9b; else 4b) applies to both paths.
select_gguf_for_llama_cpp() {
    local ram_gb=$1
    local prefer=""
    [ "$ram_gb" -ge 16 ] && prefer="9b" || prefer="4b"

    # Manifest-driven path (preferred when yq available + manifest readable).
    if have_yq && [ -n "$RECOMMENDED_MANIFEST" ] && [ -f "$RECOMMENDED_MANIFEST" ]; then
        # Collect llama-cpp slugs from user manifest first (shadow), then recommended.
        local slugs
        slugs=$({
            [ -f "$USER_MANIFEST" ] && yq eval '.recommended[] | select(.runtime == "llama-cpp") | .slug' "$USER_MANIFEST" 2>/dev/null
            yq eval '.recommended[] | select(.runtime == "llama-cpp") | .slug' "$RECOMMENDED_MANIFEST" 2>/dev/null
        } | awk '!seen[$0]++')

        # Match each slug against present files; prefer the RAM-appropriate size.
        local preferred_match=""
        local any_match=""
        while IFS= read -r slug; do
            [ -z "$slug" ] && continue
            local found
            found=$(find "$USER_MODELS_DIR" "$BUNDLED_MODELS_DIR" -name "$slug" 2>/dev/null | head -1)
            [ -z "$found" ] && continue
            any_match="$found"
            # Tag match against RAM preference based on the slug itself.
            if echo "$slug" | grep -qi "$prefer"; then
                preferred_match="$found"
                break
            fi
        done <<< "$slugs"

        [ -n "$preferred_match" ] && echo "$preferred_match" && return
        [ -n "$any_match" ] && echo "$any_match" && return
    fi

    # Find-based fallback (no yq or no manifest).
    local candidates
    candidates=$({
        [ -d "$USER_MODELS_DIR" ] && find "$USER_MODELS_DIR" -name "*.gguf" 2>/dev/null
        [ -n "$BUNDLED_MODELS_DIR" ] && find "$BUNDLED_MODELS_DIR" -name "*.gguf" 2>/dev/null
    })

    # Prefer files matching the RAM size hint.
    local preferred
    preferred=$(echo "$candidates" | grep -i "$prefer" | head -1 || true)
    [ -n "$preferred" ] && echo "$preferred" && return

    # Otherwise return any GGUF we found.
    echo "$candidates" | head -1
}

ollama_installed() { command -v ollama &>/dev/null; }

ollama_running() {
    curl -s --max-time 2 "http://localhost:${OLLAMA_PORT}/api/version" &>/dev/null
}

llama_server_running() {
    curl -s --max-time 2 "http://localhost:${LLAMA_PORT}/health" &>/dev/null
}

# ---------------------------------------------------------------------------
# Runtime lifecycle
# ---------------------------------------------------------------------------

start_llama_server() {
    local model=$1

    if llama_server_running; then
        log "llama-server already running on :${LLAMA_PORT}"
        return 0
    fi

    local server_bin
    if ! server_bin=$(find_llama_server); then
        log "ERROR: llama-server binary not found — skipping"
        return 1
    fi

    local ram_gb ctx_size
    ram_gb=$(detect_ram_gb)
    ctx_size=4096
    [ "$ram_gb" -ge 32 ] && ctx_size=8192

    log "Starting llama-server with $(basename "$model") (ctx=${ctx_size})..."
    nohup "$server_bin" \
        -m "$model" \
        --port "$LLAMA_PORT" \
        --ctx-size "$ctx_size" \
        --threads "$(nproc)" \
        --log-disable \
        > "$LLAMA_LOG" 2>&1 &

    local pid=$!
    echo "$pid" > /var/run/llama-server.pid 2>/dev/null || true
    log "llama-server PID: ${pid}"

    # Wait up to 120s for readiness.
    local wait=0
    while ! llama_server_running; do
        sleep 2
        wait=$((wait + 2))
        if [ "$wait" -ge 120 ]; then
            log "ERROR: llama-server failed to become ready within 120s"
            return 1
        fi
    done
    log "llama-server ready (took ${wait}s)"
}

stop_llama_server() {
    if [ -f /var/run/llama-server.pid ]; then
        kill "$(cat /var/run/llama-server.pid)" 2>/dev/null || true
        rm -f /var/run/llama-server.pid
        log "llama-server stopped (from pidfile)"
    elif pkill -f llama-server 2>/dev/null; then
        log "llama-server stopped (via pkill)"
    else
        log "llama-server not running"
    fi
}

start_ollama() {
    if ! ollama_installed; then
        log "Ollama not installed — skipping"
        return 0
    fi
    if ollama_running; then
        log "Ollama already running on :${OLLAMA_PORT}"
        return 0
    fi
    # Use the persistence-backed model store (/data survives reboots) so pulled and
    # pre-loaded models persist. Defaults to ~/.ollama (ephemeral on a live boot) otherwise.
    export OLLAMA_MODELS="${OLLAMA_MODELS:-/data/ollama/models}"
    mkdir -p "$OLLAMA_MODELS" 2>/dev/null || true
    log "Ollama model store: ${OLLAMA_MODELS}"
    # Ollama is intended to run as a systemd user service; if it isn't, start a backgrounded daemon.
    if systemctl --user is-enabled ollama.service &>/dev/null; then
        systemctl --user start ollama.service 2>/dev/null || true
        log "Ollama start requested via systemd user service"
    else
        nohup ollama serve > "${LOG_DIR}/ollama.log" 2>&1 &
        log "Ollama daemonized (PID $!); consider enabling ollama.service"
    fi
}

configure_aider() {
    local network=$1
    if [ "$network" = "online" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        export AIDER_MODEL="claude-sonnet-4-20250514"
        log "Aider configured for remote Anthropic API"
    elif ollama_running; then
        export OPENAI_API_BASE="http://localhost:${OLLAMA_PORT}/v1"
        export OPENAI_API_KEY="ollama"
        log "Aider configured for local Ollama (:${OLLAMA_PORT})"
    else
        export OPENAI_API_BASE="http://localhost:${LLAMA_PORT}/v1"
        export OPENAI_API_KEY="local"
        export AIDER_MODEL="openai/local"
        log "Aider configured for local llama-server (:${LLAMA_PORT})"
    fi
}

# ---------------------------------------------------------------------------
# Status reporting
# ---------------------------------------------------------------------------

count_gguf_files() {
    local user_count bundled_count
    user_count=$([ -d "$USER_MODELS_DIR" ] && find "$USER_MODELS_DIR" -name "*.gguf" 2>/dev/null | wc -l || echo 0)
    bundled_count=$([ -n "$BUNDLED_MODELS_DIR" ] && find "$BUNDLED_MODELS_DIR" -name "*.gguf" 2>/dev/null | wc -l || echo 0)
    echo "$user_count $bundled_count"
}

report_llama_cpp_section() {
    echo "--- llama.cpp (Tier 1 local, :${LLAMA_PORT}) ---"
    if llama_server_running; then
        local loaded="unknown"
        loaded=$(curl -s --max-time 2 "http://localhost:${LLAMA_PORT}/v1/models" 2>/dev/null | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || echo "running")
        echo "  status: RUNNING    loaded: ${loaded}"
    else
        echo "  status: STOPPED"
    fi
    if local bin; bin=$(find_llama_server 2>/dev/null); then
        echo "  binary: ${bin}"
    else
        echo "  binary: NOT FOUND"
    fi
    command -v llama-cli &>/dev/null && echo "  llama-cli: $(command -v llama-cli)" || echo "  llama-cli: NOT FOUND"
}

report_ollama_section() {
    echo "--- Ollama (Tier 1 local, :${OLLAMA_PORT}) ---"
    if ! ollama_installed; then
        echo "  status: NOT INSTALLED"
        return
    fi
    if ollama_running; then
        local version
        version=$(curl -s --max-time 2 "http://localhost:${OLLAMA_PORT}/api/version" 2>/dev/null | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version','?'))" 2>/dev/null || echo "?")
        echo "  status: RUNNING    version: ${version}"
        local models
        models=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' | paste -sd ',' -)
        if [ -n "$models" ]; then
            echo "  loaded: ${models}"
        else
            echo "  loaded: (none — run: kintsugi-models pull <slug>)"
        fi
    else
        echo "  status: STOPPED    binary: $(command -v ollama)"
    fi
}

report_cloud_section() {
    echo "--- Cloud CLIs (Tier 2, require internet + auth) ---"
    command -v claude  &>/dev/null && echo "  claude:  $(command -v claude)"  || echo "  claude:  NOT INSTALLED (install via kintsugi-frameworks)"
    command -v codex   &>/dev/null && echo "  codex:   $(command -v codex)"   || echo "  codex:   NOT INSTALLED (install via kintsugi-frameworks)"
    command -v aider   &>/dev/null && echo "  aider:   $(command -v aider)"   || echo "  aider:   NOT INSTALLED (install via kintsugi-frameworks)"
    [ -n "${ANTHROPIC_API_KEY:-}" ] && echo "  ANTHROPIC_API_KEY: set (${#ANTHROPIC_API_KEY} chars)" || echo "  ANTHROPIC_API_KEY: NOT SET"
    [ -n "${OPENAI_API_KEY:-}"    ] && echo "  OPENAI_API_KEY:    set (${#OPENAI_API_KEY} chars)"    || echo "  OPENAI_API_KEY:    NOT SET"
}

report_models_section() {
    echo "--- Models ---"
    local counts user_count bundled_count
    counts=$(count_gguf_files)
    user_count=$(echo "$counts" | awk '{print $1}')
    bundled_count=$(echo "$counts" | awk '{print $2}')

    if [ "$user_count" = "0" ] && [ "$bundled_count" = "0" ] && ! ollama_running; then
        echo "  No models present. Run: kintsugi-models pull <slug>"
        echo "  See manifest/models-recommended.yaml for recommendations."
        return
    fi

    [ -n "$BUNDLED_MODELS_DIR" ] && [ "$bundled_count" != "0" ] && {
        echo "  Bundled (${BUNDLED_MODELS_DIR}):"
        find "$BUNDLED_MODELS_DIR" -name "*.gguf" -exec ls -lh {} \; 2>/dev/null | awk '{print "    " $NF " (" $5 ")"}'
    }
    [ -d "$USER_MODELS_DIR" ] && [ "$user_count" != "0" ] && {
        echo "  User (${USER_MODELS_DIR}):"
        find "$USER_MODELS_DIR" -name "*.gguf" -exec ls -lh {} \; 2>/dev/null | awk '{print "    " $NF " (" $5 ")"}'
    }
    if ollama_running; then
        echo "  Ollama-managed (see 'ollama list')"
    fi
}

show_status() {
    echo "=== Kintsugi USB AI Stack Status (v${VERSION}) ==="
    echo ""
    echo "RAM:     $(detect_ram_gb) GB"
    echo "Network: $(detect_network)"
    echo "Repo:    ${REPO_ROOT:-<not found>}"
    echo ""
    report_llama_cpp_section
    echo ""
    report_ollama_section
    echo ""
    report_cloud_section
    echo ""
    report_models_section
    echo ""
    echo "--- Quick commands ---"
    echo "  ai          interactive chat with local model"
    echo "  aide        start Aider (best available backend)"
    echo "  cc          launch Claude Code (cloud)"
    echo "  ai-status   this status"
    echo "  ai-stop     stop llama-server"
    echo "  kintsugi-models list    list available models"
    echo "  kintsugi-models pull <slug>  download a model"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local mode="${1:---auto}"
    log "=== Kintsugi USB AI Stack v${VERSION} ==="
    log "Mode: ${mode}"

    case "$mode" in
        --status) show_status; return 0 ;;
        --stop)   stop_llama_server; return 0 ;;
        --auto|--offline) ;;  # fall through
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \?//'
            return 0 ;;
        *)
            echo "Unknown mode: $mode" >&2
            echo "Usage: $0 [--auto|--offline|--status|--stop]" >&2
            return 2 ;;
    esac

    # Source API keys (path is runtime-determined; dynamic source is intentional).
    # shellcheck disable=SC1090
    for keyfile in /root/.config/ai-keys.env /home/*/.config/ai-keys.env /etc/kintsugi/ai-keys.env; do
        for kf in $keyfile; do
            [ -f "$kf" ] && { source "$kf"; log "Loaded API keys from ${kf}"; break 2; }
        done
    done

    local ram_gb network
    ram_gb=$(detect_ram_gb)
    [ "$mode" = "--offline" ] && network="offline" || network=$(detect_network)
    log "RAM: ${ram_gb} GB, Network: ${network}"

    # Start Ollama first (non-blocking; fast when it's a systemd service).
    start_ollama

    # Start llama-server if a GGUF is available.
    local model=""
    model=$(select_gguf_for_llama_cpp "$ram_gb")
    if [ -n "$model" ]; then
        log "llama-server model: $(basename "$model")"
        start_llama_server "$model" || log "WARNING: llama-server failed to start"
    else
        log "No GGUF model found for llama-server — skipping."
        log "      (Ollama may still be available. Run: kintsugi-models pull <slug>)"
    fi

    configure_aider "$network"

    echo ""
    show_status

    # Emit helper aliases.
    cat > /tmp/kintsugi-ai-aliases.sh <<ALIASES
# Source this file to enable ai / aide / cc / ai-status / ai-stop aliases.
alias ai='llama-cli -m "\$(find ${USER_MODELS_DIR} ${BUNDLED_MODELS_DIR} -name "*.gguf" 2>/dev/null | head -1)" -cnv'
alias aide='aider --no-auto-commits'
alias cc='claude'
alias ai-status='$(readlink -f "$0") --status'
alias ai-stop='$(readlink -f "$0") --stop'
ALIASES
    echo ""
    echo "Run: source /tmp/kintsugi-ai-aliases.sh  (enable ai/aide/cc/ai-status aliases)"
}

main "$@"
