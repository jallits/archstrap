#!/bin/bash
# steps/00-preflight.sh - System validation

set -euo pipefail

run_step() {
    step_start "00-preflight" "Validating system requirements"

    local errors=0

    # Check UEFI boot mode
    log_info "Checking boot mode..."
    if [[ ! -d /sys/firmware/efi/efivars ]]; then
        log_error "System not booted in UEFI mode"
        log_error "Please boot from the Arch Linux ISO in UEFI mode"
        ((errors++))
    else
        log_info "UEFI mode: OK"

        # Check Secure Boot status (informational)
        log_info "Checking Secure Boot status..."
        local sb_status
        sb_status="$(get_secure_boot_status)"

        case "${sb_status}" in
            setup_mode)
                log_info "Secure Boot: Setup mode (keys can be enrolled)"
                ;;
            enabled)
                log_warn "Secure Boot: Enabled but NOT in setup mode"
                log_warn "Custom Secure Boot keys cannot be enrolled in this state"
                log_warn "If you want to use Secure Boot with custom keys:"
                log_warn "  1. Enter UEFI/BIOS setup (usually F2, F12, Del, or Esc at boot)"
                log_warn "  2. Find Secure Boot settings"
                log_warn "  3. Clear existing keys or enable 'Setup Mode'"
                log_warn "  4. Save and restart the installation"
                log_warn "Or continue without custom key enrollment"
                print_separator "-"
                ;;
            disabled)
                log_info "Secure Boot: Disabled (keys will be created for future use)"
                ;;
            *)
                log_info "Secure Boot: Not available"
                ;;
        esac
    fi

    # Check architecture
    log_info "Checking architecture..."
    local arch
    arch="$(uname -m)"
    if [[ "${arch}" != "x86_64" ]]; then
        log_error "Unsupported architecture: ${arch}"
        log_error "archstrap only supports x86_64 systems"
        ((errors++))
    else
        log_info "Architecture (${arch}): OK"
    fi

    # Check if running from Arch ISO
    log_info "Checking installation environment..."
    if ! is_arch_iso; then
        log_warn "Not running from Arch Linux ISO"
        log_warn "Some features may not work correctly"
    else
        log_info "Arch Linux ISO: OK"
    fi

    # Check internet connectivity
    log_info "Checking network connectivity..."
    if ! network_wait 10; then
        log_error "No network connectivity"
        log_error "Please connect to the internet before running archstrap"
        ((errors++))
    else
        log_info "Network: OK"

        # Optimize mirrors with reflector (if available)
        if command_exists reflector; then
            log_info "Optimizing pacman mirrors with reflector..."
            if [[ "${DRY_RUN}" != "1" ]]; then
                # Get country from IP geolocation, fallback to worldwide
                local country=""
                country=$(curl -s --max-time 5 "https://ipapi.co/country_code" 2>/dev/null || true)

                local reflector_args=(
                    --protocol https
                    --age 12
                    --sort rate
                    --fastest 10
                    --save /etc/pacman.d/mirrorlist
                )

                if [[ -n "${country}" ]] && [[ "${country}" =~ ^[A-Z]{2}$ ]]; then
                    log_info "Detected country: ${country}"
                    reflector_args+=(--country "${country}")
                else
                    log_info "Using worldwide mirrors"
                fi

                if reflector "${reflector_args[@]}" 2>/dev/null; then
                    log_info "Mirror list optimized"
                else
                    log_warn "Reflector failed, using existing mirrors"
                fi
            else
                echo -e "${MAGENTA}[DRY-RUN]${RESET} reflector --protocol https --age 12 --sort rate --fastest 10"
            fi
        else
            log_warn "Reflector not available, using existing mirrors"
        fi
    fi

    # Check available memory
    log_info "Checking available memory..."
    local ram_kb
    ram_kb="$(get_total_ram)"
    local ram_mb=$(( ram_kb / 1024 ))
    if [[ "${ram_mb}" -lt 512 ]]; then
        log_error "Insufficient memory: ${ram_mb}MB"
        log_error "At least 512MB of RAM is required"
        ((errors++))
    else
        log_info "Memory (${ram_mb}MB): OK"
    fi

    # Check for available disks
    log_info "Checking for available disks..."
    local disk_count
    disk_count="$(disk_list | wc -l)"
    if [[ "${disk_count}" -lt 1 ]]; then
        log_error "No suitable disks found"
        log_error "Please ensure at least one disk is available"
        ((errors++))
    else
        log_info "Disks found: ${disk_count}"
    fi

    # Display hardware summary
    hardware_summary

    # Check for required commands
    log_info "Checking required commands..."
    local required_cmds=(
        "pacstrap"
        "arch-chroot"
        "genfstab"
        "sgdisk"
        "cryptsetup"
        "mkfs.btrfs"
        "mkfs.fat"
    )

    for cmd in "${required_cmds[@]}"; do
        if ! command_exists "${cmd}"; then
            log_error "Required command not found: ${cmd}"
            ((errors++))
        fi
    done

    if [[ "${errors}" -eq 0 ]]; then
        log_info "Required commands: OK"
    fi

    # Summary
    print_separator
    if [[ "${errors}" -gt 0 ]]; then
        log_error "Preflight check failed with ${errors} error(s)"
        exit 1
    fi

    log_info "All preflight checks passed"
}
