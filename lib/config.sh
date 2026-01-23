#!/bin/bash
# lib/config.sh - Configuration and state management for archstrap

set -euo pipefail

# State file location
declare -g STATE_FILE="${STATE_FILE:-/tmp/archstrap.state}"
declare -g CONFIG_FILE="${CONFIG_FILE:-/tmp/archstrap.conf}"

# Associative array for configuration
declare -gA CONFIG

# Initialize configuration with defaults
config_init() {
    CONFIG[hostname]=""
    CONFIG[username]=""
    CONFIG[timezone]=""
    CONFIG[locale]="en_US.UTF-8"
    CONFIG[keymap]="us"
    CONFIG[target_disk]=""
    CONFIG[efi_disk]=""
    CONFIG[efi_on_removable]="0"
    CONFIG[luks_header_disk]=""
    CONFIG[luks_header_on_removable]="0"
    CONFIG[aur_helper]="paru"
    CONFIG[install_bluetooth]="1"
    CONFIG[install_audio]="1"
    # Security options (Arch Wiki recommendations)
    CONFIG[use_hardened_kernel]="1"
    CONFIG[enable_firewall]="1"
    CONFIG[enable_apparmor]="1"
    # Encryption strength: standard, high, maximum
    CONFIG[encryption_strength]="standard"
}

# Set a configuration value
config_set() {
    local key="$1"
    local value="$2"
    CONFIG["${key}"]="${value}"
    log_debug "Config set: ${key}=${value}"
}

# Get a configuration value
config_get() {
    local key="$1"
    local default="${2:-}"
    echo "${CONFIG[${key}]:-${default}}"
}

# Check if a configuration key exists and is non-empty
config_isset() {
    local key="$1"
    [[ -n "${CONFIG[${key}]:-}" ]]
}

# Save configuration to file
config_save() {
    log_debug "Saving configuration to ${CONFIG_FILE}"

    {
        echo "# Archstrap configuration - generated $(date)"
        for key in "${!CONFIG[@]}"; do
            echo "${key}=${CONFIG[${key}]}"
        done
    } > "${CONFIG_FILE}"
}

# Load configuration from file
config_load() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_debug "No configuration file found at ${CONFIG_FILE}"
        return 1
    fi

    log_debug "Loading configuration from ${CONFIG_FILE}"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "${key}" =~ ^#.*$ || -z "${key}" ]] && continue
        CONFIG["${key}"]="${value}"
    done < "${CONFIG_FILE}"

    return 0
}

# Step tracking
declare -ga COMPLETED_STEPS=()

# Mark a step as started
step_start() {
    local step="$1"
    local description="$2"

    log_step "${step}" "${description}"
    state_set "current_step" "${step}"
    state_save
}

# Mark a step as completed
step_complete() {
    local step="$1"

    COMPLETED_STEPS+=("${step}")
    state_set "completed_steps" "$(IFS=,; echo "${COMPLETED_STEPS[*]}")"
    state_save
    log_info "Step ${step} completed"
}

# Check if a step is completed
step_is_complete() {
    local step="$1"

    for completed in "${COMPLETED_STEPS[@]}"; do
        if [[ "${completed}" == "${step}" ]]; then
            return 0
        fi
    done
    return 1
}

# State management (separate from config - tracks progress)
declare -gA STATE

# Set state value
state_set() {
    local key="$1"
    local value="$2"
    STATE["${key}"]="${value}"
}

# Get state value
state_get() {
    local key="$1"
    local default="${2:-}"
    echo "${STATE[${key}]:-${default}}"
}

# Save state to file
state_save() {
    log_debug "Saving state to ${STATE_FILE}"

    {
        echo "# Archstrap state - $(date)"
        echo "# Do not edit manually"
        for key in "${!STATE[@]}"; do
            echo "${key}=${STATE[${key}]}"
        done
    } > "${STATE_FILE}"
}

# Load state from file
state_load() {
    if [[ ! -f "${STATE_FILE}" ]]; then
        log_debug "No state file found at ${STATE_FILE}"
        return 1
    fi

    log_info "Resuming from previous state..."

    while IFS='=' read -r key value; do
        [[ "${key}" =~ ^#.*$ || -z "${key}" ]] && continue
        STATE["${key}"]="${value}"
    done < "${STATE_FILE}"

    # Restore completed steps
    if [[ -n "${STATE[completed_steps]:-}" ]]; then
        IFS=',' read -ra COMPLETED_STEPS <<< "${STATE[completed_steps]}"
    fi

    return 0
}

# Clear state (called on successful completion)
state_clear() {
    log_debug "Clearing state file"
    rm -f "${STATE_FILE}"
    STATE=()
    COMPLETED_STEPS=()
}

# Validate state for resume
state_validate() {
    # Check if target disk still exists
    local target_disk
    target_disk="$(state_get target_disk)"

    if [[ -n "${target_disk}" ]] && [[ ! -b "${target_disk}" ]]; then
        log_error "Target disk ${target_disk} no longer exists"
        return 1
    fi

    # Check if LUKS container is still present (if we got past encryption step)
    if step_is_complete "03-encryption"; then
        local luks_uuid
        luks_uuid="$(state_get luks_uuid)"
        if [[ -n "${luks_uuid}" ]] && ! blkid -t UUID="${luks_uuid}" &>/dev/null; then
            log_warn "LUKS container UUID ${luks_uuid} not found"
            return 1
        fi
    fi

    return 0
}

# Validate hostname
validate_hostname() {
    local hostname="$1"

    # Must be 1-63 characters, alphanumeric and hyphens, no leading/trailing hyphen
    if [[ ! "${hostname}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return 1
    fi
    return 0
}

# Validate username
validate_username() {
    local username="$1"

    # Must start with letter, contain only lowercase letters, digits, hyphens, underscores
    # Must be 1-32 characters
    if [[ ! "${username}" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
        return 1
    fi
    return 0
}

# Get the disk hosting the Arch ISO (to exclude from selection)
get_iso_boot_disk() {
    local iso_mount="/run/archiso/bootmnt"

    # Check if running from Arch ISO
    if [[ -d "${iso_mount}" ]]; then
        # Find the device mounted at the ISO mount point
        local iso_device
        iso_device=$(findmnt -n -o SOURCE "${iso_mount}" 2>/dev/null || true)

        if [[ -n "${iso_device}" ]]; then
            # Get the parent disk (strip partition number)
            local iso_disk
            iso_disk=$(lsblk -no PKNAME "${iso_device}" 2>/dev/null | head -1)
            if [[ -n "${iso_disk}" ]]; then
                echo "/dev/${iso_disk}"
                return 0
            fi
        fi
    fi

    # Fallback: check /proc/mounts for archiso
    local archiso_device
    archiso_device=$(grep -E '/run/archiso|/mnt/archiso' /proc/mounts 2>/dev/null | awk '{print $1}' | head -1 || true)
    if [[ -n "${archiso_device}" ]] && [[ -b "${archiso_device}" ]]; then
        local iso_disk
        iso_disk=$(lsblk -no PKNAME "${archiso_device}" 2>/dev/null | head -1)
        if [[ -n "${iso_disk}" ]]; then
            echo "/dev/${iso_disk}"
            return 0
        fi
    fi

    return 1
}

# Get available disks for selection (excludes ISO boot media)
get_available_disks() {
    local iso_disk
    iso_disk=$(get_iso_boot_disk 2>/dev/null || true)

    local line disk
    while IFS= read -r line; do
        disk=$(echo "${line}" | awk '{print $1}')
        # Skip the ISO boot disk
        if [[ -n "${iso_disk}" ]] && [[ "${disk}" == "${iso_disk}" ]]; then
            log_debug "Excluding ISO boot disk: ${disk}"
            continue
        fi
        echo "${line}"
    done < <(lsblk -dpno NAME,SIZE,MODEL,TRAN 2>/dev/null | \
        grep -E '^/dev/(sd|nvme|vd|mmcblk)' | \
        grep -v 'loop' || true)
}

# Get removable disks
get_removable_disks() {
    local disk
    while read -r disk _; do
        local removable
        removable="$(cat "/sys/block/$(basename "${disk}")/removable" 2>/dev/null || echo "0")"
        if [[ "${removable}" == "1" ]]; then
            echo "${disk}"
        fi
    done < <(get_available_disks)
}

# Get disk size in bytes
get_disk_size() {
    local disk="$1"
    local disk_name
    disk_name="$(basename "${disk}")"
    local size_file="/sys/block/${disk_name}/size"

    if [[ -f "${size_file}" ]]; then
        echo $(( $(cat "${size_file}") * 512 ))
    else
        echo 0
    fi
}

# Calculate swap size based on RAM (for hibernation)
calculate_swap_size() {
    local ram_kb
    ram_kb="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
    local ram_gb=$(( ram_kb / 1024 / 1024 ))

    # Hibernation recommendation: RAM + sqrt(RAM)
    # Simplified: RAM <= 8GB: RAM * 1.5, RAM > 8GB: RAM + 2GB
    if [[ "${ram_gb}" -le 8 ]]; then
        echo "$(( ram_gb * 3 / 2 ))G"
    else
        echo "$(( ram_gb + 2 ))G"
    fi
}

# Detect timezone using geoclue or IP-based service
detect_timezone() {
    # Try geoclue first (not available in ISO, but good for completeness)
    if command_exists timedatectl; then
        local tz
        tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
        if [[ -n "${tz}" ]] && [[ "${tz}" != "UTC" ]]; then
            echo "${tz}"
            return 0
        fi
    fi

    # Try IP-based geolocation
    local tz
    tz="$(curl -sf "http://ip-api.com/line/?fields=timezone" 2>/dev/null || true)"
    if [[ -n "${tz}" ]] && [[ -f "/usr/share/zoneinfo/${tz}" ]]; then
        echo "${tz}"
        return 0
    fi

    # Fallback to UTC
    echo "UTC"
}

# Display configuration summary
config_summary() {
    print_separator "="
    echo -e "${BOLD}Configuration Summary${RESET}"
    print_separator "="
    echo "Hostname:        $(config_get hostname)"
    echo "Username:        $(config_get username)"
    echo "Timezone:        $(config_get timezone)"
    echo "Locale:          $(config_get locale)"
    echo "Target disk:     $(config_get target_disk)"

    if [[ "$(config_get efi_on_removable)" == "1" ]]; then
        echo "EFI partition:   $(config_get efi_disk) (removable)"
    else
        echo "EFI partition:   $(config_get target_disk) (internal)"
    fi

    if [[ "$(config_get luks_header_on_removable)" == "1" ]]; then
        echo "LUKS header:     $(config_get luks_header_disk) (removable)"
    else
        echo "LUKS header:     On root partition"
    fi

    local enc_strength
    enc_strength="$(config_get encryption_strength "standard")"
    case "${enc_strength}" in
        high)    echo "Encryption:      High (Argon2id 4GB/5s)" ;;
        maximum) echo "Encryption:      Maximum (integrity + Argon2id 4GB/5s)" ;;
        *)       echo "Encryption:      Standard" ;;
    esac

    echo "AUR helper:      $(config_get aur_helper)"
    echo "Bluetooth:       $(config_get install_bluetooth)"
    echo "Audio:           $(config_get install_audio)"

    print_separator "-"
    echo -e "${BOLD}Security Options${RESET}"
    print_separator "-"

    if [[ "$(config_get use_hardened_kernel)" == "1" ]]; then
        echo "Kernel:          linux-hardened"
    else
        echo "Kernel:          linux (standard)"
    fi

    if [[ "$(config_get enable_firewall)" == "1" ]]; then
        echo "Firewall:        nftables (enabled)"
    else
        echo "Firewall:        disabled"
    fi

    if [[ "$(config_get enable_apparmor)" == "1" ]]; then
        echo "AppArmor:        enabled"
    else
        echo "AppArmor:        disabled"
    fi

    echo "Sysctl hardening: enabled"
    echo "Password policy:  enforced (libpwquality)"
    echo "Secure mounts:    nodev,nosuid,noexec"

    print_separator "="
}
