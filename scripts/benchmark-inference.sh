#!/bin/bash
# benchmark-inference.sh - Standardized LLM inference benchmark suite
# Usage: ./benchmark-inference.sh > output.md
# Paste output into machine's INDEX.md or ticket
# Requires: Ollama installed and running, python3

set -euo pipefail

# Configuration
TIMEOUT=180  # seconds per test
WARMUP=true  # run warmup inference before benchmarks

# Test prompts - standardized across all runs
PROMPT_SHORT="What is the capital of France? Answer in one sentence."
PROMPT_MEDIUM="Explain how a combustion engine works in about 100 words."
PROMPT_CODE="Write a Python function to check if a number is prime. Include a docstring."
PROMPT_LONG="Write a short story about a robot learning to paint in about 200 words."

# Model tiers by VRAM requirement (approximate with Q4_K_M)
# Tier 1: 2-4GB VRAM (fits on 6GB GPUs)
MODELS_TIER1="qwen2.5:3b gemma2:2b phi3:3.8b"

# Tier 2: 4-6GB VRAM (fits on 8GB GPUs)
MODELS_TIER2="qwen2.5:7b llama3.1:8b mistral:7b gemma2:9b"

# Tier 3: 6-10GB VRAM (fits on 11-12GB GPUs)
MODELS_TIER3="qwen2.5:14b deepseek-coder:6.7b codellama:13b"

# Tier 4: 10-16GB VRAM (fits on 16GB+ GPUs)
MODELS_TIER4="qwen2.5:32b mixtral:8x7b llama3.1:70b-q2_K"

# Tier 5: 16-24GB VRAM (fits on 24GB GPUs)
MODELS_TIER5="llama3.1:70b-q4_K_M deepseek-coder:33b qwen2.5:72b-q2_K"

# Colors for terminal (disabled in pipe)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    NC=''
fi

log_stderr() {
    echo -e "$@" >&2
}

# Check dependencies
check_deps() {
    local missing=()
    command -v ollama &>/dev/null || missing+=("ollama")
    command -v python3 &>/dev/null || missing+=("python3")

    if [ ${#missing[@]} -gt 0 ]; then
        log_stderr "${RED}ERROR: Missing dependencies: ${missing[*]}${NC}"
        exit 1
    fi

    # Check Ollama is running
    if ! ollama list &>/dev/null 2>&1; then
        log_stderr "${RED}ERROR: Ollama service not running. Start with: systemctl start ollama${NC}"
        exit 1
    fi
}

# Get GPU info
get_gpu_info() {
    if command -v nvidia-smi &>/dev/null; then
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
        GPU_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
        GPU_VRAM="${GPU_VRAM_MB} MiB"
        GPU_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
        GPU_TYPE="NVIDIA"

        # Determine max tier based on VRAM
        if [ "$GPU_VRAM_MB" -ge 20000 ]; then
            MAX_TIER=5
        elif [ "$GPU_VRAM_MB" -ge 14000 ]; then
            MAX_TIER=4
        elif [ "$GPU_VRAM_MB" -ge 10000 ]; then
            MAX_TIER=3
        elif [ "$GPU_VRAM_MB" -ge 7000 ]; then
            MAX_TIER=2
        else
            MAX_TIER=1
        fi
    elif [ -f /proc/driver/nvidia/version ]; then
        GPU_NAME="NVIDIA GPU"
        GPU_VRAM="Unknown"
        GPU_VRAM_MB=0
        GPU_DRIVER=$(cat /proc/driver/nvidia/version 2>/dev/null | head -1 || echo "Unknown")
        GPU_TYPE="NVIDIA"
        MAX_TIER=2
    else
        GPU_NAME="CPU Only"
        GPU_VRAM="N/A"
        GPU_VRAM_MB=0
        GPU_DRIVER="N/A"
        GPU_TYPE="CPU"
        MAX_TIER=1
    fi
}

# Run single benchmark via Python
run_benchmark() {
    local model="$1"
    local prompt="$2"
    local test_name="$3"

    python3 << EOF
import urllib.request
import json
import sys

url = "http://localhost:11434/api/generate"
data = {
    "model": "$model",
    "prompt": """$prompt""",
    "stream": False
}

try:
    req = urllib.request.Request(url, data=json.dumps(data).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=$TIMEOUT) as response:
        result = json.loads(response.read().decode())

        eval_count = result.get('eval_count', 0)
        eval_dur = result.get('eval_duration', 0) / 1e9
        prompt_eval_count = result.get('prompt_eval_count', 0)
        prompt_eval_dur = result.get('prompt_eval_duration', 0) / 1e9
        total_dur = result.get('total_duration', 0) / 1e9
        load_dur = result.get('load_duration', 0) / 1e9

        gen_speed = eval_count / eval_dur if eval_dur > 0 else 0
        prompt_speed = prompt_eval_count / prompt_eval_dur if prompt_eval_dur > 0 else 0

        print(f"{eval_count}\t{gen_speed:.1f}\t{prompt_speed:.1f}\t{total_dur:.2f}\t{load_dur:.2f}")
except Exception as e:
    print(f"0\t0\t0\t0\t0")
    sys.exit(1)
EOF
}

# Check if model is available locally
model_available() {
    local model="$1"
    ollama list 2>/dev/null | grep -q "$model"
}

# Pull model if not available (with size check)
ensure_model() {
    local model="$1"
    if ! model_available "$model"; then
        log_stderr "${YELLOW}Pulling $model...${NC}"
        if ! ollama pull "$model" 2>&1 | tail -5 >&2; then
            log_stderr "${RED}Failed to pull $model${NC}"
            return 1
        fi
    fi
    return 0
}

# Get current VRAM usage
get_vram_usage() {
    if [ "$GPU_TYPE" = "NVIDIA" ]; then
        nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null | head -1 || echo "N/A"
    else
        echo "N/A"
    fi
}

# Get model size from ollama
get_model_size() {
    local model="$1"
    ollama list 2>/dev/null | grep "$model" | awk '{print $3}' | head -1 || echo "?"
}

# Unload current model to free VRAM
unload_models() {
    # Generate with keep_alive=0 to unload
    python3 << 'EOF' 2>/dev/null || true
import urllib.request
import json
url = "http://localhost:11434/api/generate"
data = {"model": "", "keep_alive": 0}
try:
    # This will fail but triggers cleanup
    req = urllib.request.Request(url, data=json.dumps(data).encode(), headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=5)
except:
    pass
EOF
    sleep 2
}

# Main benchmark for a single model
benchmark_model() {
    local model="$1"
    local tier="$2"

    log_stderr "${GREEN}Testing $model (Tier $tier)...${NC}"

    # Get model size
    local model_size
    model_size=$(get_model_size "$model")

    # Warmup run (load model into VRAM)
    if [ "$WARMUP" = true ]; then
        log_stderr "  Warmup..."
        run_benchmark "$model" "Count from 1 to 10" "warmup" >/dev/null 2>&1 || true
        sleep 2
    fi

    # Get VRAM after model load
    local vram_used
    vram_used=$(get_vram_usage)

    # Run tests
    log_stderr "  Short response..."
    local short_result
    short_result=$(run_benchmark "$model" "$PROMPT_SHORT" "short" 2>/dev/null) || short_result="0	0	0	0	0"
    sleep 0.5

    log_stderr "  Medium response..."
    local medium_result
    medium_result=$(run_benchmark "$model" "$PROMPT_MEDIUM" "medium" 2>/dev/null) || medium_result="0	0	0	0	0"
    sleep 0.5

    log_stderr "  Code generation..."
    local code_result
    code_result=$(run_benchmark "$model" "$PROMPT_CODE" "code" 2>/dev/null) || code_result="0	0	0	0	0"
    sleep 0.5

    log_stderr "  Long response..."
    local long_result
    long_result=$(run_benchmark "$model" "$PROMPT_LONG" "long" 2>/dev/null) || long_result="0	0	0	0	0"

    # Parse results
    IFS=$'\t' read -r short_tokens short_gen short_prompt _ _ <<< "$short_result"
    IFS=$'\t' read -r medium_tokens medium_gen medium_prompt _ _ <<< "$medium_result"
    IFS=$'\t' read -r code_tokens code_gen code_prompt _ _ <<< "$code_result"
    IFS=$'\t' read -r long_tokens long_gen long_prompt _ _ <<< "$long_result"

    # Defaults
    short_gen=${short_gen:-0}; medium_gen=${medium_gen:-0}
    code_gen=${code_gen:-0}; long_gen=${long_gen:-0}

    # Calculate average
    local avg_gen
    avg_gen=$(python3 -c "print(f'{(float(${short_gen}) + float(${medium_gen}) + float(${code_gen}) + float(${long_gen})) / 4:.1f}')" 2>/dev/null || echo "0")

    # Output row
    echo "| $model | $model_size | $tier | $short_gen | $medium_gen | $code_gen | $long_gen | **$avg_gen** | $vram_used |"

    # Unload model after test to free VRAM for next model
    unload_models
}

# Test a tier of models
test_tier() {
    local tier=$1
    local models="$2"
    local tier_name="$3"

    if [ -z "$models" ]; then
        return
    fi

    log_stderr "${CYAN}=== Testing $tier_name ===${NC}"

    for model in $models; do
        if ensure_model "$model"; then
            benchmark_model "$model" "$tier"
        else
            log_stderr "${YELLOW}Skipping $model (unavailable or too large)${NC}"
        fi
    done
}

# Main execution
main() {
    check_deps
    get_gpu_info

    local hostname
    hostname=$(hostname)

    # Determine which tiers to test
    local test_tier1="" test_tier2="" test_tier3="" test_tier4="" test_tier5=""

    # Parse mode
    local mode="${BENCHMARK_MODE:-auto}"

    case "$mode" in
        quick)
            # Just test what's installed
            test_tier2="qwen2.5:7b mistral:7b"
            ;;
        full)
            # Test all tiers up to GPU capacity
            [ "$MAX_TIER" -ge 1 ] && test_tier1="$MODELS_TIER1"
            [ "$MAX_TIER" -ge 2 ] && test_tier2="$MODELS_TIER2"
            [ "$MAX_TIER" -ge 3 ] && test_tier3="$MODELS_TIER3"
            [ "$MAX_TIER" -ge 4 ] && test_tier4="$MODELS_TIER4"
            [ "$MAX_TIER" -ge 5 ] && test_tier5="$MODELS_TIER5"
            ;;
        stress)
            # Push VRAM to the limit - largest models that might fit
            [ "$MAX_TIER" -ge 2 ] && test_tier2="qwen2.5:7b"
            [ "$MAX_TIER" -ge 3 ] && test_tier3="$MODELS_TIER3"
            [ "$MAX_TIER" -ge 4 ] && test_tier4="$MODELS_TIER4"
            [ "$MAX_TIER" -ge 5 ] && test_tier5="$MODELS_TIER5"
            ;;
        auto|*)
            # Auto-select based on VRAM: test 2-3 tiers
            if [ "$MAX_TIER" -ge 5 ]; then
                test_tier2="qwen2.5:7b"
                test_tier3="qwen2.5:14b"
                test_tier4="qwen2.5:32b"
                test_tier5="llama3.1:70b-q4_K_M"
            elif [ "$MAX_TIER" -ge 4 ]; then
                test_tier2="qwen2.5:7b"
                test_tier3="qwen2.5:14b"
                test_tier4="qwen2.5:32b"
            elif [ "$MAX_TIER" -ge 3 ]; then
                test_tier1="gemma2:2b"
                test_tier2="qwen2.5:7b mistral:7b"
                test_tier3="qwen2.5:14b"
            elif [ "$MAX_TIER" -ge 2 ]; then
                test_tier1="gemma2:2b"
                test_tier2="qwen2.5:7b llama3.1:8b mistral:7b"
            else
                test_tier1="$MODELS_TIER1"
            fi
            ;;
    esac

    # Header
    echo "## Inference Benchmark"
    echo ""
    echo "**Host:** $hostname"
    echo "**Collected:** $(date -Iseconds)"
    echo "**Ollama:** $(ollama --version 2>/dev/null | head -1 || echo 'Unknown')"
    echo "**Mode:** $mode"
    echo ""

    # System info
    echo "### System"
    echo ""
    echo "| Attribute | Value |"
    echo "|-----------|-------|"
    echo "| **GPU** | $GPU_NAME |"
    echo "| **VRAM** | $GPU_VRAM |"
    echo "| **Driver** | $GPU_DRIVER |"
    echo "| **Max Tier** | $MAX_TIER (auto-detected) |"
    echo "| **CPU** | $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || uname -m) |"
    echo "| **RAM** | $(free -h | awk '/^Mem:/ {print $2}') |"
    echo ""

    # VRAM tier guide
    echo "### VRAM Tiers"
    echo ""
    echo "| Tier | VRAM Needed | Model Sizes | Example Models |"
    echo "|------|-------------|-------------|----------------|"
    echo "| 1 | 2-4 GB | 1.5B-4B | gemma2:2b, phi3:3.8b |"
    echo "| 2 | 4-6 GB | 7B-9B | qwen2.5:7b, llama3.1:8b, mistral:7b |"
    echo "| 3 | 6-10 GB | 11B-14B | qwen2.5:14b, codellama:13b |"
    echo "| 4 | 10-16 GB | 20B-34B | qwen2.5:32b, mixtral:8x7b |"
    echo "| 5 | 16-24 GB | 70B+ (Q4) | llama3.1:70b, deepseek-coder:33b |"
    echo ""

    # Benchmark results table
    echo "### Results"
    echo ""
    echo "Generation speed in tokens/second. Higher is better."
    echo ""
    echo "| Model | Size | Tier | Short | Medium | Code | Long | **Avg** | VRAM Used |"
    echo "|-------|------|------|-------|--------|------|------|---------|-----------|"

    # Run benchmarks by tier
    local tested=0

    if [ -n "$test_tier1" ]; then
        test_tier 1 "$test_tier1" "Tier 1 (2-4GB)"
        ((tested++)) || true
    fi

    if [ -n "$test_tier2" ]; then
        test_tier 2 "$test_tier2" "Tier 2 (4-6GB)"
        ((tested++)) || true
    fi

    if [ -n "$test_tier3" ]; then
        test_tier 3 "$test_tier3" "Tier 3 (6-10GB)"
        ((tested++)) || true
    fi

    if [ -n "$test_tier4" ]; then
        test_tier 4 "$test_tier4" "Tier 4 (10-16GB)"
        ((tested++)) || true
    fi

    if [ -n "$test_tier5" ]; then
        test_tier 5 "$test_tier5" "Tier 5 (16-24GB)"
        ((tested++)) || true
    fi

    echo ""

    # Test descriptions
    echo "### Test Prompts"
    echo ""
    echo "| Test | Prompt |"
    echo "|------|--------|"
    echo "| Short | $PROMPT_SHORT |"
    echo "| Medium | $PROMPT_MEDIUM |"
    echo "| Code | $PROMPT_CODE |"
    echo "| Long | $PROMPT_LONG |"
    echo ""

    # Commands
    echo "### Commands"
    echo ""
    echo '```bash'
    echo '# Auto benchmark (detects GPU, tests appropriate models)'
    echo './scripts/benchmark-inference.sh 2>/dev/null'
    echo ''
    echo '# Quick test (7B models only, no downloads)'
    echo 'BENCHMARK_MODE=quick ./scripts/benchmark-inference.sh 2>/dev/null'
    echo ''
    echo '# Full benchmark (all tiers up to GPU capacity)'
    echo 'BENCHMARK_MODE=full ./scripts/benchmark-inference.sh 2>/dev/null'
    echo ''
    echo '# Stress test (push VRAM to limit)'
    echo 'BENCHMARK_MODE=stress ./scripts/benchmark-inference.sh 2>/dev/null'
    echo ''
    echo '# Save results'
    echo './scripts/benchmark-inference.sh 2>/dev/null > benchmark-$(hostname)-$(date +%Y%m%d).md'
    echo '```'

    log_stderr "${GREEN}Benchmark complete.${NC}"
}

main "$@"
