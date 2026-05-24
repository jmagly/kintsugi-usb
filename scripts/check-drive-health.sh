#!/bin/bash
# check-drive-health.sh - Drive health and performance verification
# Usage: sudo ./check-drive-health.sh [device]
# Example: sudo ./check-drive-health.sh          # All drives
#          sudo ./check-drive-health.sh /dev/sda # Single drive
# Output: Markdown suitable for pasting into system docs
# Requires: smartmontools, hdparm

set -euo pipefail

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

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_stderr "${RED}ERROR: This script requires root privileges for SMART access${NC}"
        log_stderr "Run with: sudo $0"
        exit 1
    fi
}

# Check dependencies
check_deps() {
    local missing=()

    command -v smartctl &>/dev/null || missing+=("smartmontools")
    command -v hdparm &>/dev/null || missing+=("hdparm")
    command -v lsblk &>/dev/null || missing+=("util-linux")

    if [ ${#missing[@]} -gt 0 ]; then
        log_stderr "${YELLOW}Missing packages: ${missing[*]}${NC}"
        log_stderr "Install with: sudo apt install ${missing[*]}"

        # Check if critical tools are missing
        if ! command -v smartctl &>/dev/null; then
            log_stderr "${RED}ERROR: smartctl is required. Install smartmontools${NC}"
            exit 1
        fi
    fi

    # Optional: nvme-cli for enhanced NVMe support
    if ! command -v nvme &>/dev/null; then
        log_stderr "${YELLOW}NOTE: nvme-cli not installed. NVMe checks will use smartctl only${NC}"
    fi
}

# Get drive type: nvme, ssd, or hdd
get_drive_type() {
    local device="$1"
    local basename
    basename=$(basename "$device")

    # Strip partition number to get base device
    local base_device
    base_device=$(echo "$basename" | sed 's/[0-9]*$//' | sed 's/p$//')

    # NVMe detection
    if [[ "$base_device" =~ ^nvme ]]; then
        echo "nvme"
        return
    fi

    # Check rotation (ROTA): 0 = SSD, 1 = HDD
    local rota
    rota=$(lsblk -d -n -o ROTA "/dev/$base_device" 2>/dev/null || echo "1")

    if [ "$rota" = "0" ]; then
        echo "ssd"
    else
        echo "hdd"
    fi
}

# Get device model
get_device_model() {
    local device="$1"
    smartctl -i "$device" 2>/dev/null | grep -E "^(Device Model|Model Number|Product):" | head -1 | cut -d: -f2 | xargs || echo "Unknown"
}

# Get device serial
get_device_serial() {
    local device="$1"
    smartctl -i "$device" 2>/dev/null | grep -E "^Serial Number:" | cut -d: -f2 | xargs || echo "Unknown"
}

# Get device capacity
get_device_capacity() {
    local device="$1"
    local bytes
    bytes=$(lsblk -b -d -n -o SIZE "$device" 2>/dev/null || echo "0")

    if [ "$bytes" -gt 0 ]; then
        # Convert to human-readable
        local gb=$((bytes / 1000000000))
        if [ "$gb" -ge 1000 ]; then
            echo "$((gb / 1000)) TB"
        else
            echo "${gb} GB"
        fi
    else
        echo "Unknown"
    fi
}

# Parse SMART attribute value
get_smart_attr() {
    local smart_output="$1"
    local attr_id="$2"

    echo "$smart_output" | grep -E "^\s*${attr_id}\s" | awk '{print $10}' | head -1
}

# Parse SMART attribute raw value
get_smart_attr_raw() {
    local smart_output="$1"
    local attr_id="$2"

    # SMART attributes format: ID# ATTRIBUTE_NAME FLAG VALUE WORST THRESH TYPE UPDATED WHEN_FAILED RAW_VALUE
    # Raw value might have format like "22763h+30m+33.568s" - extract just the number
    local raw
    raw=$(echo "$smart_output" | grep -E "^\s*${attr_id}\s" | awk '{print $10}' | head -1)

    # Extract just the numeric part (before any 'h' or other suffix)
    echo "$raw" | sed 's/h.*//' | sed 's/[^0-9].*//'
}

# Get SMART overall health
get_smart_health() {
    local device="$1"
    local health
    health=$(smartctl -H "$device" 2>/dev/null | grep -E "SMART overall-health|SMART Health Status" | cut -d: -f2 | xargs || echo "Unknown")

    if [ -z "$health" ]; then
        echo "Unknown"
    else
        echo "$health"
    fi
}

# Get temperature from SMART
get_temperature() {
    local device="$1"
    local temp

    # Try different temperature attribute locations
    temp=$(smartctl -A "$device" 2>/dev/null | grep -E "^(190|194)\s" | awk '{print $10}' | head -1)

    if [ -z "$temp" ]; then
        # Try NVMe format
        temp=$(smartctl -A "$device" 2>/dev/null | grep "Temperature:" | awk '{print $2}' | head -1)
    fi

    if [ -n "$temp" ] && [ "$temp" -gt 0 ] 2>/dev/null; then
        echo "${temp}C"
    else
        echo "N/A"
    fi
}

# Run read speed test (non-destructive)
get_read_speed() {
    local device="$1"

    if ! command -v hdparm &>/dev/null; then
        echo "N/A (hdparm missing)"
        return
    fi

    log_stderr "  Testing read speed..."

    # Run buffered read test
    local result
    result=$(hdparm -t "$device" 2>/dev/null | grep "Timing buffered" | awk '{print $(NF-1), $NF}')

    if [ -n "$result" ]; then
        echo "$result"
    else
        echo "N/A"
    fi
}

# Check NVMe-specific health
check_nvme() {
    local device="$1"

    log_stderr "${CYAN}Checking NVMe: $device${NC}"

    local model serial capacity health temp speed
    model=$(get_device_model "$device")
    serial=$(get_device_serial "$device")
    capacity=$(get_device_capacity "$device")
    health=$(get_smart_health "$device")
    temp=$(get_temperature "$device")
    speed=$(get_read_speed "$device")

    # NVMe-specific attributes
    local percent_used power_on_hours data_read data_written
    local smart_log
    smart_log=$(smartctl -A "$device" 2>/dev/null)

    percent_used=$(echo "$smart_log" | grep "Percentage Used:" | awk '{print $3}' || echo "N/A")
    power_on_hours=$(echo "$smart_log" | grep "Power On Hours:" | awk '{print $4}' | sed 's/,//g' || echo "N/A")
    data_read=$(echo "$smart_log" | grep "Data Units Read:" | awk '{print $4}' | sed 's/,//g' || echo "N/A")
    data_written=$(echo "$smart_log" | grep "Data Units Written:" | awk '{print $4}' | sed 's/,//g' || echo "N/A")

    # Determine health status
    local status_icon="OK"
    if [ "$health" != "PASSED" ] && [ "$health" != "OK" ]; then
        status_icon="WARN"
    fi

    # Output row
    echo "| $device | NVMe | $model | $capacity | **$health** | $temp | $percent_used | $power_on_hours | $speed | $status_icon |"
}

# Check SSD-specific health
check_ssd() {
    local device="$1"

    log_stderr "${CYAN}Checking SSD: $device${NC}"

    local model serial capacity health temp speed
    model=$(get_device_model "$device")
    serial=$(get_device_serial "$device")
    capacity=$(get_device_capacity "$device")
    health=$(get_smart_health "$device")
    temp=$(get_temperature "$device")
    speed=$(get_read_speed "$device")

    # SSD-specific attributes from SMART
    local smart_output
    smart_output=$(smartctl -A "$device" 2>/dev/null)

    # Wear leveling / Percentage used (attribute 177 or 233)
    local wear_level
    wear_level=$(get_smart_attr "$smart_output" "177")
    if [ -z "$wear_level" ]; then
        wear_level=$(get_smart_attr "$smart_output" "233")
    fi
    if [ -z "$wear_level" ]; then
        wear_level="N/A"
    else
        wear_level="${wear_level}%"
    fi

    # Power on hours (attribute 9)
    local power_on_hours
    power_on_hours=$(get_smart_attr_raw "$smart_output" "9")
    [ -z "$power_on_hours" ] && power_on_hours="N/A"

    # Determine health status
    local status_icon="OK"
    if [ "$health" != "PASSED" ] && [ "$health" != "OK" ]; then
        status_icon="WARN"
    fi

    echo "| $device | SSD | $model | $capacity | **$health** | $temp | $wear_level | $power_on_hours | $speed | $status_icon |"
}

# Check HDD-specific health
check_hdd() {
    local device="$1"

    log_stderr "${CYAN}Checking HDD: $device${NC}"

    local model serial capacity health temp speed
    model=$(get_device_model "$device")
    serial=$(get_device_serial "$device")
    capacity=$(get_device_capacity "$device")
    health=$(get_smart_health "$device")
    temp=$(get_temperature "$device")
    speed=$(get_read_speed "$device")

    # HDD-specific SMART attributes
    local smart_output
    smart_output=$(smartctl -A "$device" 2>/dev/null)

    # Critical HDD attributes
    local reallocated pending uncorrectable power_on_hours

    # Reallocated Sector Count (ID 5) - bad sectors replaced
    reallocated=$(get_smart_attr_raw "$smart_output" "5")
    [ -z "$reallocated" ] && reallocated="0"

    # Current Pending Sector Count (ID 197) - sectors waiting to be remapped
    pending=$(get_smart_attr_raw "$smart_output" "197")
    [ -z "$pending" ] && pending="0"

    # Uncorrectable Sector Count (ID 198) - unrecoverable read errors
    uncorrectable=$(get_smart_attr_raw "$smart_output" "198")
    [ -z "$uncorrectable" ] && uncorrectable="0"

    # Power on hours (ID 9)
    power_on_hours=$(get_smart_attr_raw "$smart_output" "9")
    [ -z "$power_on_hours" ] && power_on_hours="N/A"

    # Determine health status
    local status_icon="OK"
    local warnings=()

    if [ "$health" != "PASSED" ] && [ "$health" != "OK" ]; then
        status_icon="FAIL"
        warnings+=("SMART FAILED")
    fi

    if [ "$reallocated" -gt 0 ] 2>/dev/null; then
        if [ "$reallocated" -gt 100 ]; then
            status_icon="WARN"
            warnings+=("$reallocated reallocated sectors")
        fi
    fi

    if [ "$pending" -gt 0 ] 2>/dev/null; then
        status_icon="WARN"
        warnings+=("$pending pending sectors")
    fi

    if [ "$uncorrectable" -gt 0 ] 2>/dev/null; then
        status_icon="WARN"
        warnings+=("$uncorrectable uncorrectable")
    fi

    # Output row
    echo "| $device | HDD | $model | $capacity | **$health** | $temp | $reallocated | $pending | $power_on_hours | $speed | $status_icon |"

    # Output warnings if any
    if [ ${#warnings[@]} -gt 0 ]; then
        log_stderr "${YELLOW}  Warning: ${warnings[*]}${NC}"
    fi
}

# Get list of physical drives (not partitions)
get_physical_drives() {
    # Get block devices that are disks (not partitions, not loop, not dm)
    lsblk -d -n -o NAME,TYPE 2>/dev/null | while read -r name type; do
        if [ "$type" = "disk" ]; then
            # Skip loop devices
            if [[ ! "$name" =~ ^loop ]]; then
                echo "/dev/$name"
            fi
        fi
    done
}

# Main check for a device
check_device() {
    local device="$1"

    if [ ! -b "$device" ]; then
        log_stderr "${RED}ERROR: $device is not a block device${NC}"
        return 1
    fi

    local drive_type
    drive_type=$(get_drive_type "$device")

    case "$drive_type" in
        nvme)
            check_nvme "$device"
            ;;
        ssd)
            check_ssd "$device"
            ;;
        hdd)
            check_hdd "$device"
            ;;
        *)
            log_stderr "${YELLOW}Unknown drive type for $device${NC}"
            ;;
    esac
}

# Print header for NVMe/SSD
print_header_flash() {
    echo "| Device | Type | Model | Capacity | Health | Temp | Wear | Hours | Read Speed | Status |"
    echo "|--------|------|-------|----------|--------|------|------|-------|------------|--------|"
}

# Print header for HDD
print_header_hdd() {
    echo "| Device | Type | Model | Capacity | Health | Temp | Realloc | Pending | Hours | Read Speed | Status |"
    echo "|--------|------|-------|----------|--------|------|---------|---------|-------|------------|--------|"
}

# Main execution
main() {
    check_root
    check_deps

    local hostname
    hostname=$(hostname)
    local specific_device="${1:-}"

    # Header
    echo "## Drive Health Report"
    echo ""
    echo "**Host:** $hostname"
    echo "**Collected:** $(date -Iseconds)"
    echo ""

    # Collect drives to check
    local drives=()
    local nvme_ssd_drives=()
    local hdd_drives=()

    if [ -n "$specific_device" ]; then
        drives=("$specific_device")
    else
        while IFS= read -r drive; do
            drives+=("$drive")
        done < <(get_physical_drives)
    fi

    if [ ${#drives[@]} -eq 0 ]; then
        log_stderr "${RED}No drives found to check${NC}"
        exit 1
    fi

    log_stderr "${GREEN}Found ${#drives[@]} drive(s) to check${NC}"

    # Separate drives by type
    for drive in "${drives[@]}"; do
        local dtype
        dtype=$(get_drive_type "$drive")
        if [ "$dtype" = "hdd" ]; then
            hdd_drives+=("$drive")
        else
            nvme_ssd_drives+=("$drive")
        fi
    done

    # Check NVMe/SSD drives
    if [ ${#nvme_ssd_drives[@]} -gt 0 ]; then
        echo "### Flash Storage (NVMe/SSD)"
        echo ""
        print_header_flash
        for drive in "${nvme_ssd_drives[@]}"; do
            check_device "$drive"
        done
        echo ""
    fi

    # Check HDD drives
    if [ ${#hdd_drives[@]} -gt 0 ]; then
        echo "### Mechanical Storage (HDD)"
        echo ""
        echo "**Critical Indicators:**"
        echo "- **Realloc (Reallocated Sectors):** Bad sectors replaced by spare sectors. >100 indicates wear."
        echo "- **Pending:** Sectors waiting to be remapped. Any value >0 indicates active degradation."
        echo ""
        print_header_hdd
        for drive in "${hdd_drives[@]}"; do
            check_device "$drive"
        done
        echo ""
    fi

    # Health key
    echo "### Status Key"
    echo ""
    echo "| Status | Meaning |"
    echo "|--------|---------|"
    echo "| OK | Drive healthy, no issues detected |"
    echo "| WARN | Potential issues detected, monitor closely |"
    echo "| FAIL | Drive failing, replace immediately |"
    echo ""

    # Commands
    echo "### Commands"
    echo ""
    echo '```bash'
    echo '# Full report'
    echo 'sudo ./scripts/check-drive-health.sh'
    echo ''
    echo '# Single drive'
    echo 'sudo ./scripts/check-drive-health.sh /dev/sda'
    echo ''
    echo '# Extended SMART test (HDD, takes hours)'
    echo 'sudo smartctl -t long /dev/sda'
    echo 'sudo smartctl -l selftest /dev/sda  # Check results'
    echo ''
    echo '# NVMe specific info'
    echo 'sudo nvme smart-log /dev/nvme0n1'
    echo ''
    echo '# Save report'
    echo 'sudo ./scripts/check-drive-health.sh > drive-health-$(hostname)-$(date +%Y%m%d).md 2>&1'
    echo '```'
    echo ""

    # Recommendations
    echo "### Maintenance Recommendations"
    echo ""
    echo "| Drive Type | Check Frequency | Long Test | Replace When |"
    echo "|------------|-----------------|-----------|--------------|"
    echo "| NVMe/SSD | Monthly | Not needed | Wear >90% or health != PASSED |"
    echo "| HDD | Weekly | Quarterly | Reallocated >200, Pending >0, or health != PASSED |"

    log_stderr "${GREEN}Health check complete.${NC}"
}

main "$@"
