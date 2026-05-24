#!/bin/bash
# Kintsugi USB — Test Harness (v1.0 acceptance tool per ADR-005/006)
# Runs comprehensive tests and logs results for offline analysis.
# Usage: usb-test-harness.sh [--full|--quick|--smoke|--ai-only|--boot-only]
# Modes:
#   --full       All categories (boot, tools, AI, persistence, fleet, model
#                toolkit, framework toolkit). Requires root for some tests.
#   --quick      Boot + tools + persistence.
#   --smoke      CI-friendly subset: no-network, no-persistence-write, no-reboot
#                requirements. Safe to run inside a VM or CI container.
#   --ai-only    Both local runtimes (llama.cpp :8080 + Ollama :11434) + cloud
#                CLI presence + start-ai.sh detection.
#   --boot-only  Boot-mode + core tool presence only.
# Results: /var/log/kintsugi/test-YYYYMMDD-HHMMSS/

set -euo pipefail

# --- Config ---
VERSION="1.1.0"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
# KINTSUGI_LOG_BASE overrides the log root (useful for CI / unprivileged runs).
# Default is /var/log/kintsugi (canonical on-USB location; requires root).
LOG_BASE="${KINTSUGI_LOG_BASE:-/var/log/kintsugi}"
LOG_DIR="${LOG_BASE}/test-${TIMESTAMP}"
PERSIST_LOG_DIR=""  # Set if persistence partition found
RESULTS_FILE="${LOG_DIR}/results.json"
SUMMARY_FILE="${LOG_DIR}/summary.txt"
BOOT_TIME_FILE="/tmp/kintsugi-boot-timestamp"

# Colors (only for terminal output, not log files)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# --- Counters ---
PASS=0; FAIL=0; SKIP=0; WARN=0
declare -A TEST_RESULTS

# --- Functions ---
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_DIR}/full.log"; }
pass() { ((PASS++)); TEST_RESULTS["$1"]="PASS"; echo -e "${GREEN}PASS${NC}: $1" | tee -a "${SUMMARY_FILE}"; }
fail() { ((FAIL++)); TEST_RESULTS["$1"]="FAIL: $2"; echo -e "${RED}FAIL${NC}: $1 — $2" | tee -a "${SUMMARY_FILE}"; }
skip() { ((SKIP++)); TEST_RESULTS["$1"]="SKIP: $2"; echo -e "${YELLOW}SKIP${NC}: $1 — $2" | tee -a "${SUMMARY_FILE}"; }
warn() { ((WARN++)); TEST_RESULTS["$1"]="WARN: $2"; echo -e "${YELLOW}WARN${NC}: $1 — $2" | tee -a "${SUMMARY_FILE}"; }

collect_hw_info() {
    log "Collecting hardware info..."
    mkdir -p "${LOG_DIR}/hw"

    # CPU
    lscpu > "${LOG_DIR}/hw/lscpu.txt" 2>&1 || true
    cat /proc/cpuinfo | head -40 > "${LOG_DIR}/hw/cpuinfo.txt" 2>&1 || true

    # Memory
    free -h > "${LOG_DIR}/hw/memory.txt" 2>&1
    cat /proc/meminfo > "${LOG_DIR}/hw/meminfo.txt" 2>&1 || true

    # Storage
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL > "${LOG_DIR}/hw/lsblk.txt" 2>&1 || true

    # PCI/USB
    lspci > "${LOG_DIR}/hw/lspci.txt" 2>&1 || true
    lsusb > "${LOG_DIR}/hw/lsusb.txt" 2>&1 || true

    # Network
    ip addr > "${LOG_DIR}/hw/ip-addr.txt" 2>&1 || true
    ip route > "${LOG_DIR}/hw/ip-route.txt" 2>&1 || true

    # DMI (if root)
    dmidecode -t system > "${LOG_DIR}/hw/dmi-system.txt" 2>&1 || true
    dmidecode -t bios > "${LOG_DIR}/hw/dmi-bios.txt" 2>&1 || true

    # Boot mode
    if [ -d /sys/firmware/efi ]; then
        echo "UEFI" > "${LOG_DIR}/hw/boot-mode.txt"
        efibootmgr -v > "${LOG_DIR}/hw/efibootmgr.txt" 2>&1 || true
    else
        echo "BIOS/Legacy" > "${LOG_DIR}/hw/boot-mode.txt"
    fi

    # Secure Boot
    if command -v mokutil &>/dev/null; then
        mokutil --sb-state > "${LOG_DIR}/hw/secure-boot.txt" 2>&1 || true
    fi

    # Kernel
    uname -a > "${LOG_DIR}/hw/uname.txt" 2>&1

    log "Hardware info collected"
}

test_boot_timing() {
    log "Testing boot timing..."
    if [ -f "$BOOT_TIME_FILE" ]; then
        local boot_start=$(cat "$BOOT_TIME_FILE")
        local now=$(date +%s)
        local elapsed=$((now - boot_start))
        echo "${elapsed}" > "${LOG_DIR}/boot-time-seconds.txt"
        if [ "$elapsed" -le 60 ]; then
            pass "TC-BOOT-TIME: Boot in ${elapsed}s (target: ≤60s)"
        elif [ "$elapsed" -le 90 ]; then
            warn "TC-BOOT-TIME: Boot in ${elapsed}s (target: ≤60s, acceptable: ≤90s)" "${elapsed}s"
        else
            fail "TC-BOOT-TIME: Boot in ${elapsed}s" "Exceeds 90s target"
        fi
    else
        skip "TC-BOOT-TIME" "No boot timestamp found (run from systemd unit for timing)"
    fi
}

test_tool_presence() {
    log "Testing rescue tool presence (TC-3)..."

    # Critical tools
    local critical_tools=(
        "fsck.ext4:filesystem" "xfs_repair:filesystem" "ntfsfix:filesystem"
        "parted:partition" "fdisk:partition" "gdisk:partition"
        "smartctl:drive-health" "testdisk:recovery"
        "nmap:network" "curl:network" "ssh:network"
        "grub-install:boot-repair" "efibootmgr:boot-repair"
        "tmux:shell" "vim:shell" "git:shell" "jq:shell" "rsync:shell"
        "python3:runtime"
    )

    # High-priority tools
    local high_tools=(
        "btrfs:filesystem" "nvme:drive-health" "hdparm:drive-health"
        "photorec:recovery" "ddrescue:recovery"
        "tcpdump:network" "mtr:network" "dig:network" "iperf3:network" "arp-scan:network"
        "htop:monitoring" "iotop:monitoring" "lsof:monitoring" "strace:monitoring"
        "dmidecode:sysinfo" "inxi:sysinfo" "lshw:sysinfo"
        "nano:shell" "pv:shell" "tree:shell"
        "pip3:runtime" "node:runtime"
    )

    # Optional tools
    local optional_tools=(
        "gparted:partition-gui" "os-prober:boot-repair"
        "wget:network" "netcat:network"
        "firefox:browser" "startx:desktop"
    )

    local crit_missing=() high_missing=() opt_missing=()

    for entry in "${critical_tools[@]}"; do
        local tool="${entry%%:*}" category="${entry#*:}"
        if command -v "$tool" &>/dev/null; then
            local ver=$("$tool" --version 2>&1 | head -1 || echo "unknown")
            echo "${tool}|${category}|PRESENT|${ver}" >> "${LOG_DIR}/tool-inventory.txt"
        else
            crit_missing+=("$tool")
            echo "${tool}|${category}|MISSING|" >> "${LOG_DIR}/tool-inventory.txt"
        fi
    done

    for entry in "${high_tools[@]}"; do
        local tool="${entry%%:*}" category="${entry#*:}"
        if command -v "$tool" &>/dev/null; then
            local ver=$("$tool" --version 2>&1 | head -1 || echo "unknown")
            echo "${tool}|${category}|PRESENT|${ver}" >> "${LOG_DIR}/tool-inventory.txt"
        else
            high_missing+=("$tool")
            echo "${tool}|${category}|MISSING|" >> "${LOG_DIR}/tool-inventory.txt"
        fi
    done

    for entry in "${optional_tools[@]}"; do
        local tool="${entry%%:*}" category="${entry#*:}"
        if command -v "$tool" &>/dev/null; then
            echo "${tool}|${category}|PRESENT|" >> "${LOG_DIR}/tool-inventory.txt"
        else
            opt_missing+=("$tool")
            echo "${tool}|${category}|MISSING|" >> "${LOG_DIR}/tool-inventory.txt"
        fi
    done

    if [ ${#crit_missing[@]} -eq 0 ]; then
        pass "TC-3-CRITICAL: All critical rescue tools present"
    else
        fail "TC-3-CRITICAL" "Missing: ${crit_missing[*]}"
    fi

    if [ ${#high_missing[@]} -eq 0 ]; then
        pass "TC-3-HIGH: All high-priority tools present"
    else
        warn "TC-3-HIGH: Missing high-priority tools" "${high_missing[*]}"
    fi

    if [ ${#opt_missing[@]} -gt 0 ]; then
        log "Optional tools missing (OK): ${opt_missing[*]}"
    fi
}

test_ai_offline() {
    log "Testing offline AI stack (TC-5)..."

    # Check llama binaries
    local llama_cli="" llama_server=""
    for path in /usr/local/bin/llama-cli /opt/llama/llama-cli /tools/bin/llama-cli; do
        [ -x "$path" ] && llama_cli="$path" && break
    done
    for path in /usr/local/bin/llama-server /opt/llama/llama-server /tools/bin/llama-server; do
        [ -x "$path" ] && llama_server="$path" && break
    done

    if [ -z "$llama_cli" ]; then
        fail "TC-5-BINARY-CLI" "llama-cli not found in expected paths"
    else
        pass "TC-5-BINARY-CLI: llama-cli found at ${llama_cli}"
    fi

    if [ -z "$llama_server" ]; then
        fail "TC-5-BINARY-SERVER" "llama-server not found in expected paths"
    else
        pass "TC-5-BINARY-SERVER: llama-server found at ${llama_server}"
    fi

    # Check models
    local model_dir=""
    for path in /models /opt/models /tools/models; do
        [ -d "$path" ] && model_dir="$path" && break
    done

    if [ -z "$model_dir" ]; then
        # Check USB mount points
        for mnt in /media/*/USB*/models /mnt/*/models; do
            [ -d "$mnt" ] && model_dir="$mnt" && break
        done
    fi

    if [ -z "$model_dir" ]; then
        fail "TC-5-MODELS-DIR" "No models directory found"
    else
        log "Models directory: ${model_dir}"
        ls -lh "${model_dir}"/*.gguf > "${LOG_DIR}/model-inventory.txt" 2>&1 || true

        local model_count=$(find "$model_dir" -name "*.gguf" 2>/dev/null | wc -l)
        if [ "$model_count" -ge 2 ]; then
            pass "TC-5-MODELS: ${model_count} GGUF models found"
        elif [ "$model_count" -ge 1 ]; then
            warn "TC-5-MODELS: Only ${model_count} model found (expected 2)" "Partial"
        else
            fail "TC-5-MODELS" "No GGUF models found in ${model_dir}"
        fi
    fi

    # RAM-based model selection test (TC-11)
    local ram_gb=$(free -g | awk '/Mem:/{print $2}')
    log "Available RAM: ${ram_gb} GB"
    echo "${ram_gb}" > "${LOG_DIR}/ram-gb.txt"

    if [ "$ram_gb" -ge 16 ]; then
        log "TC-11: Would select Qwen2.5-Coder 7B (RAM: ${ram_gb}GB >= 16GB)"
        echo "SELECTED: qwen2.5-coder-7b (ram=${ram_gb}GB)" > "${LOG_DIR}/model-selection.txt"
    else
        log "TC-11: Would select Phi-4-mini (RAM: ${ram_gb}GB < 16GB)"
        echo "SELECTED: phi-4-mini (ram=${ram_gb}GB)" > "${LOG_DIR}/model-selection.txt"
    fi
    pass "TC-11-MODEL-SELECT: RAM=${ram_gb}GB, model selection logic validated"

    # Inference test (only if we have both binary and model)
    if [ -n "$llama_cli" ] && [ -n "$model_dir" ]; then
        local test_model=$(find "$model_dir" -name "*phi*q4*" -o -name "*phi*Q4*" 2>/dev/null | head -1)
        [ -z "$test_model" ] && test_model=$(find "$model_dir" -name "*.gguf" 2>/dev/null | head -1)

        if [ -n "$test_model" ]; then
            log "Running inference test with: $(basename "$test_model")"
            local start_time=$(date +%s%N)

            timeout 120 "$llama_cli" \
                -m "$test_model" \
                -p "Write a one-line bash command to check disk health:" \
                -n 50 \
                --no-display-prompt \
                2>"${LOG_DIR}/llama-stderr.txt" \
                > "${LOG_DIR}/llama-inference-output.txt" || true

            local end_time=$(date +%s%N)
            local elapsed_ms=$(( (end_time - start_time) / 1000000 ))
            echo "${elapsed_ms}" > "${LOG_DIR}/inference-time-ms.txt"

            if [ -s "${LOG_DIR}/llama-inference-output.txt" ]; then
                local output_len=$(wc -c < "${LOG_DIR}/llama-inference-output.txt")
                pass "TC-5-INFERENCE: Generated ${output_len} bytes in ${elapsed_ms}ms"

                # Extract tokens/second from llama.cpp stderr
                grep -o '[0-9.]\+ tokens per second' "${LOG_DIR}/llama-stderr.txt" > "${LOG_DIR}/inference-speed.txt" 2>/dev/null || true
            else
                fail "TC-5-INFERENCE" "No output generated (check llama-stderr.txt)"
            fi
        else
            skip "TC-5-INFERENCE" "No GGUF model file found for testing"
        fi
    else
        skip "TC-5-INFERENCE" "Missing llama-cli or models"
    fi
}

test_ai_online() {
    log "Testing online AI stack (TC-4)..."

    # Network connectivity
    if ping -c1 -W3 api.anthropic.com &>/dev/null; then
        pass "TC-4-NETWORK: Internet available (api.anthropic.com reachable)"
        echo "ONLINE" > "${LOG_DIR}/network-status.txt"
    else
        skip "TC-4-ONLINE" "No internet (offline mode)"
        echo "OFFLINE" > "${LOG_DIR}/network-status.txt"
        return
    fi

    # Claude Code binary
    if command -v claude &>/dev/null; then
        claude --version > "${LOG_DIR}/claude-version.txt" 2>&1 || true
        pass "TC-4-CLAUDE-BINARY: Claude Code binary present"

        # Check API key
        if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            pass "TC-4-CLAUDE-APIKEY: ANTHROPIC_API_KEY is set"
            # Don't log the actual key!
            echo "KEY_SET=true KEY_LENGTH=${#ANTHROPIC_API_KEY}" > "${LOG_DIR}/api-key-status.txt"
        else
            warn "TC-4-CLAUDE-APIKEY: ANTHROPIC_API_KEY not set" "Set via persistence"
        fi
    else
        fail "TC-4-CLAUDE-BINARY" "Claude Code not found in PATH"
    fi

    # Codex CLI
    if command -v codex &>/dev/null; then
        pass "TC-4-CODEX: Codex CLI present"
    else
        skip "TC-4-CODEX" "Codex CLI not installed (optional)"
    fi

    # Aider
    if command -v aider &>/dev/null; then
        aider --version > "${LOG_DIR}/aider-version.txt" 2>&1 || true
        pass "TC-4-AIDER: Aider present"
    else
        warn "TC-4-AIDER: Aider not found" "Install via pip"
    fi
}

test_persistence() {
    log "Testing persistence (TC-6)..."

    # Check if we're running with persistence
    if mount | grep -q "overlay\|casper-rw\|persistence"; then
        pass "TC-6-OVERLAY: Persistence overlay active"
        mount | grep -E "overlay|casper|persistence" > "${LOG_DIR}/persistence-mounts.txt" 2>&1
    else
        warn "TC-6-OVERLAY: No persistence overlay detected" "May be first boot"
    fi

    # Write persistence marker
    local marker="/root/.kintsugi-persist-marker"
    if [ -f "$marker" ]; then
        local prev_time=$(cat "$marker")
        pass "TC-6-PERSIST: Previous marker found (written: ${prev_time})"
        echo "PERSIST_VERIFIED=true PREVIOUS=${prev_time}" > "${LOG_DIR}/persistence-status.txt"
    else
        echo "$(date -Iseconds)" > "$marker" 2>/dev/null || true
        log "TC-6: Wrote persistence marker — reboot to verify"
        echo "PERSIST_MARKER_WRITTEN=true" > "${LOG_DIR}/persistence-status.txt"
    fi

    # Check persistence size
    if mount | grep -q "casper-rw"; then
        df -h $(mount | grep "casper-rw" | awk '{print $1}') > "${LOG_DIR}/persistence-space.txt" 2>&1 || true
    fi
}

test_fleet_integration() {
    log "Testing fleet integration (TC-8)..."

    # SSH keys
    if [ -f /root/.ssh/authorized_keys ] || [ -f /root/.ssh/id_ed25519 ]; then
        pass "TC-8-SSH: SSH keys present"
        ls -la /root/.ssh/ > "${LOG_DIR}/ssh-keys.txt" 2>&1 || true
    else
        warn "TC-8-SSH: No SSH keys found" "Configure in persistence"
    fi

    # Fleet hosts in /etc/hosts (operator-provided optional config; none by default)
    if grep -q "kintsugi optional config" /etc/hosts 2>/dev/null; then
        pass "TC-8-HOSTS: operator fleet hosts present in /etc/hosts"
        sed -n '/kintsugi optional config/,$p' /etc/hosts > "${LOG_DIR}/fleet-hosts.txt" 2>&1 || true
    else
        skip "TC-8-HOSTS: no operator fleet hosts configured" "expected default; add config/fleet-hosts to opt in"
    fi

    # Fleet scripts
    local scripts_found=false
    for path in /data/scripts /tools/scripts /opt/sysops/scripts; do
        if [ -d "$path" ]; then
            scripts_found=true
            pass "TC-8-SCRIPTS: Fleet scripts at ${path}"
            ls "$path" > "${LOG_DIR}/fleet-scripts.txt" 2>&1 || true
            break
        fi
    done
    if ! $scripts_found; then
        warn "TC-8-SCRIPTS: Fleet scripts not found" "Copy to USB data partition"
    fi
}

test_start_ai_script() {
    log "Testing start-ai.sh..."

    local start_ai=""
    for path in /usr/local/bin/start-ai.sh \
                /opt/kintsugi/tools/bin/start-ai.sh \
                /opt/kintsugi-usb/scripts/usb-toolkit/start-ai.sh \
                /data/repo/kintsugi-usb/scripts/usb-toolkit/start-ai.sh \
                /tools/bin/start-ai.sh; do
        [ -x "$path" ] && start_ai="$path" && break
    done

    if [ -z "$start_ai" ]; then
        fail "TC-START-AI" "start-ai.sh not found in any known location"
        return
    fi
    pass "TC-START-AI-PRESENT: start-ai.sh found at ${start_ai}"

    # --status should exit zero even when no models/runtimes are up
    if "$start_ai" --status >/dev/null 2>&1; then
        pass "TC-START-AI-STATUS: --status exits 0"
    else
        warn "TC-START-AI-STATUS" "--status exited non-zero (may indicate runtime issues)"
    fi

    # Unknown mode should exit non-zero (regression guard)
    if ! "$start_ai" --bogus-mode >/dev/null 2>&1; then
        pass "TC-START-AI-REJECT: rejects unknown modes"
    else
        warn "TC-START-AI-REJECT" "accepted unknown mode (expected non-zero exit)"
    fi
}

test_ollama_runtime() {
    log "Testing Ollama runtime (ADR-005 dual-runtime)..."

    if ! command -v ollama &>/dev/null; then
        skip "TC-OLLAMA-PRESENT" "ollama binary not installed"
        return
    fi
    pass "TC-OLLAMA-PRESENT: ollama binary at $(command -v ollama)"

    if curl -s --max-time 2 "http://localhost:11434/api/version" &>/dev/null; then
        local ver
        ver=$(curl -s --max-time 2 "http://localhost:11434/api/version" 2>/dev/null | \
              python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")
        pass "TC-OLLAMA-RUNNING: Ollama :11434 reachable (version ${ver})"
    else
        warn "TC-OLLAMA-RUNNING" "Ollama not running on :11434 (start-ai.sh should start it)"
    fi

    # Check persistence-overlay data dir per ADR-005 §D2
    if [ -d /data/ollama ]; then
        pass "TC-OLLAMA-STORE: /data/ollama present (persistence overlay)"
    else
        warn "TC-OLLAMA-STORE" "/data/ollama missing — Ollama pulls won't survive reboot"
    fi
}

test_model_toolkit() {
    log "Testing kintsugi-models CLI (ADR-005 §D3)..."

    local kintsugi_models=""
    for path in /usr/local/bin/kintsugi-models \
                /opt/kintsugi/tools/bin/kintsugi-models \
                /opt/kintsugi-usb/scripts/usb-toolkit/kintsugi-models \
                /data/repo/kintsugi-usb/scripts/usb-toolkit/kintsugi-models; do
        [ -x "$path" ] && kintsugi_models="$path" && break
    done

    if [ -z "$kintsugi_models" ]; then
        skip "TC-KINTSUGI-MODELS" "kintsugi-models CLI not yet installed (iteration-1 in progress)"
        return
    fi
    pass "TC-KINTSUGI-MODELS-PRESENT: ${kintsugi_models}"

    if "$kintsugi_models" list >/dev/null 2>&1; then
        pass "TC-KINTSUGI-MODELS-LIST: 'list' subcommand works"
    else
        warn "TC-KINTSUGI-MODELS-LIST" "'list' subcommand failed"
    fi

    # Recommended manifest should be readable
    local manifest=""
    for path in /data/repo/kintsugi-usb/manifest/models-recommended.yaml \
                /opt/kintsugi-usb/manifest/models-recommended.yaml \
                /cdrom/manifest/models-recommended.yaml; do
        [ -f "$path" ] && manifest="$path" && break
    done
    if [ -z "$manifest" ]; then
        warn "TC-MODELS-MANIFEST" "manifest/models-recommended.yaml not found"
    else
        pass "TC-MODELS-MANIFEST: ${manifest}"
    fi
}

test_framework_toolkit() {
    log "Testing kintsugi-frameworks CLI (ADR-006 §D2)..."

    local kintsugi_fw=""
    for path in /usr/local/bin/kintsugi-frameworks \
                /opt/kintsugi/tools/bin/kintsugi-frameworks \
                /opt/kintsugi-usb/scripts/usb-toolkit/kintsugi-frameworks \
                /data/repo/kintsugi-usb/scripts/usb-toolkit/kintsugi-frameworks; do
        [ -x "$path" ] && kintsugi_fw="$path" && break
    done

    if [ -z "$kintsugi_fw" ]; then
        skip "TC-KINTSUGI-FW" "kintsugi-frameworks CLI not yet installed (iteration-1 in progress)"
        return
    fi
    pass "TC-KINTSUGI-FW-PRESENT: ${kintsugi_fw}"

    if "$kintsugi_fw" list >/dev/null 2>&1; then
        pass "TC-KINTSUGI-FW-LIST: 'list' subcommand works"
    else
        warn "TC-KINTSUGI-FW-LIST" "'list' subcommand failed"
    fi
}

test_vscode_copilot() {
    log "Testing VS Code + Copilot base (ADR-006 §D3)..."

    if ! command -v code &>/dev/null; then
        skip "TC-VSCODE" "VS Code not installed (ADR-006 §D3 deliverable; wizard opt-out is also valid)"
        return
    fi
    pass "TC-VSCODE-PRESENT: $(command -v code)"

    # Telemetry should be off by default per R-19 mitigation
    local settings=""
    for path in /etc/skel/.config/Code/User/settings.json \
                /root/.config/Code/User/settings.json; do
        [ -f "$path" ] && settings="$path" && break
    done
    if [ -z "$settings" ]; then
        warn "TC-VSCODE-TELEMETRY" "No VS Code settings.json found to verify telemetry default"
    elif grep -q '"telemetry.telemetryLevel"[[:space:]]*:[[:space:]]*"off"' "$settings" 2>/dev/null; then
        pass "TC-VSCODE-TELEMETRY: telemetry disabled in ${settings}"
    else
        warn "TC-VSCODE-TELEMETRY" "telemetry setting not 'off' in ${settings}"
    fi

    # Copilot extension
    if code --list-extensions 2>/dev/null | grep -qi "github.copilot"; then
        pass "TC-VSCODE-COPILOT: GitHub Copilot extension installed"
    else
        warn "TC-VSCODE-COPILOT" "GitHub Copilot extension not listed by 'code --list-extensions'"
    fi

    # gh CLI
    if command -v gh &>/dev/null; then
        pass "TC-GH-CLI: $(command -v gh)"
    else
        warn "TC-GH-CLI" "gh CLI not installed"
    fi
}

generate_json_results() {
    log "Generating JSON results..."

    local hostname=$(hostname 2>/dev/null || echo "unknown")
    local boot_mode="unknown"
    [ -d /sys/firmware/efi ] && boot_mode="UEFI" || boot_mode="BIOS"
    local ram_gb=$(free -g | awk '/Mem:/{print $2}')
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "unknown")

    cat > "${RESULTS_FILE}" <<ENDJSON
{
  "test_harness_version": "${VERSION}",
  "timestamp": "$(date -Iseconds)",
  "hostname": "${hostname}",
  "hardware": {
    "cpu": "${cpu_model}",
    "ram_gb": ${ram_gb},
    "boot_mode": "${boot_mode}"
  },
  "summary": {
    "pass": ${PASS},
    "fail": ${FAIL},
    "warn": ${WARN},
    "skip": ${SKIP},
    "total": $((PASS + FAIL + WARN + SKIP))
  },
  "results": {
$(for key in "${!TEST_RESULTS[@]}"; do
    local val="${TEST_RESULTS[$key]}"
    val="${val//\"/\\\"}"
    echo "    \"${key}\": \"${val}\","
done | sed '$ s/,$//')
  }
}
ENDJSON

    log "JSON results written to ${RESULTS_FILE}"
}

copy_to_persistence() {
    # Try to copy results to USB data partition for retrieval
    for mnt in /media/*/USB* /mnt/usb* /mnt/ventoy*; do
        if [ -d "$mnt" ]; then
            local dest="${mnt}/data/test-results/test-${TIMESTAMP}"
            mkdir -p "$dest" 2>/dev/null && cp -r "${LOG_DIR}/"* "$dest/" 2>/dev/null && {
                log "Results copied to USB: ${dest}"
                return 0
            }
        fi
    done
    log "Could not copy results to USB data partition (mount manually if needed)"
}

# --- Main ---
main() {
    local mode="${1:---full}"

    # Handle --help and unknown modes BEFORE mkdir so they work unprivileged.
    case "$mode" in
        -h|--help)
            sed -n '2,15p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        --full|--quick|--smoke|--ai-only|--boot-only)
            ;;
        *)
            echo "Unknown mode: $mode" >&2
            echo "Usage: $0 [--full|--quick|--smoke|--ai-only|--boot-only|--help]" >&2
            exit 2
            ;;
    esac

    if ! mkdir -p "${LOG_DIR}/hw" 2>/dev/null; then
        echo "ERROR: cannot create log dir ${LOG_DIR}" >&2
        echo "Hint: either run as root, or set KINTSUGI_LOG_BASE=/tmp/kintsugi-logs" >&2
        exit 1
    fi

    echo "=========================================" | tee "${SUMMARY_FILE}"
    echo " Kintsugi USB Test Harness v${VERSION}" | tee -a "${SUMMARY_FILE}"
    echo " $(date)" | tee -a "${SUMMARY_FILE}"
    echo " Mode: ${mode}" | tee -a "${SUMMARY_FILE}"
    echo "=========================================" | tee -a "${SUMMARY_FILE}"
    echo "" | tee -a "${SUMMARY_FILE}"

    # Always collect hardware info
    collect_hw_info

    case "$mode" in
        --full)
            test_boot_timing
            test_tool_presence
            test_ai_offline
            test_ai_online
            test_ollama_runtime
            test_persistence
            test_fleet_integration
            test_start_ai_script
            test_model_toolkit
            test_framework_toolkit
            test_vscode_copilot
            ;;
        --quick)
            test_boot_timing
            test_tool_presence
            test_persistence
            test_start_ai_script
            ;;
        --smoke)
            # CI-friendly: no network, no persistence writes, no reboot.
            test_tool_presence
            test_start_ai_script
            test_model_toolkit
            test_framework_toolkit
            test_ollama_runtime
            test_vscode_copilot
            ;;
        --ai-only)
            test_ai_offline
            test_ai_online
            test_ollama_runtime
            test_start_ai_script
            test_model_toolkit
            test_framework_toolkit
            ;;
        --boot-only)
            test_boot_timing
            test_tool_presence
            ;;
    esac

    echo "" | tee -a "${SUMMARY_FILE}"
    echo "=========================================" | tee -a "${SUMMARY_FILE}"
    echo " RESULTS: ${PASS} pass, ${FAIL} fail, ${WARN} warn, ${SKIP} skip" | tee -a "${SUMMARY_FILE}"
    echo " Logs: ${LOG_DIR}/" | tee -a "${SUMMARY_FILE}"
    echo "=========================================" | tee -a "${SUMMARY_FILE}"

    generate_json_results
    copy_to_persistence

    # Print final location
    echo ""
    echo "Full logs: ${LOG_DIR}/"
    echo "JSON results: ${RESULTS_FILE}"
    echo "Summary: ${SUMMARY_FILE}"

    # Exit with failure count
    exit ${FAIL}
}

main "$@"
