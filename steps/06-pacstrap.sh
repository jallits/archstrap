#!/bin/bash
# steps/06-pacstrap.sh - Base system installation

set -euo pipefail

run_step() {
    step_start "06-pacstrap" "Installing base system"

    # Determine kernel package
    local kernel_package="linux"
    local kernel_headers="linux-headers"
    if [[ "$(config_get use_hardened_kernel)" == "1" ]]; then
        kernel_package="linux-hardened"
        kernel_headers="linux-hardened-headers"
        log_info "Using hardened kernel for enhanced security"
    fi

    # Base packages
    local base_packages=(
        # Base system
        "base"
        "${kernel_package}"
        "${kernel_headers}"
        "linux-firmware"
        "btrfs-progs"

        # Boot and security
        "systemd-ukify"
        "sbsigntools"
        "efibootmgr"
        "tpm2-tools"
        "plymouth"

        # Essential utilities
        "sudo"
        "zsh"
        "vim"
        "less"
        "man-db"
        "man-pages"
        "texinfo"

        # Filesystem tools
        "dosfstools"
        "e2fsprogs"

        # Hardware support
        "usbutils"
        "pciutils"

        # Removable media management
        "udisks2"             # D-Bus disk management (allows non-root mount/unmount)

        # Mirror and firmware management
        "reflector"           # Mirror list optimization
        "fwupd"               # Firmware updates (BIOS/UEFI)

        # Snapshot management
        "snapper"             # BTRFS snapshot manager
        "snap-pac"            # Automatic pre/post pacman snapshots

        # Security hardening (Arch Wiki recommendations)
        "libpwquality"        # Password quality checking

        # Location services (for automatic timezone)
        "geoclue"             # Location framework for automatic-timezoned
    )

    # Add firewall packages if enabled
    if [[ "$(config_get enable_firewall)" == "1" ]]; then
        base_packages+=("nftables" "iptables-nft")
        log_info "Adding firewall packages: nftables"
    fi

    # Add AppArmor if enabled
    if [[ "$(config_get enable_apparmor)" == "1" ]]; then
        base_packages+=("apparmor")
        log_info "Adding AppArmor for mandatory access control"
    fi

    # Add microcode
    local microcode
    microcode="$(get_microcode_package)"
    if [[ -n "${microcode}" ]]; then
        base_packages+=("${microcode}")
        log_info "Adding CPU microcode: ${microcode}"
    fi

    # Add GPU packages
    local gpu_packages
    gpu_packages="$(get_gpu_packages)"
    if [[ -n "${gpu_packages}" ]]; then
        # shellcheck disable=SC2206
        base_packages+=(${gpu_packages})
        log_info "Adding GPU packages: ${gpu_packages}"
    fi

    # Add audio packages if detected
    if [[ "$(config_get install_audio)" == "1" ]]; then
        local audio_packages
        audio_packages="$(get_audio_packages)"
        # shellcheck disable=SC2206
        base_packages+=(${audio_packages})
        log_info "Adding audio packages: ${audio_packages}"
    fi

    # Add bluetooth packages if detected
    if [[ "$(config_get install_bluetooth)" == "1" ]]; then
        local bt_packages
        bt_packages="$(get_bluetooth_packages)"
        # shellcheck disable=SC2206
        base_packages+=(${bt_packages})
        log_info "Adding Bluetooth packages: ${bt_packages}"
    fi

    # Add network packages
    local net_packages
    net_packages="$(get_network_packages)"
    # shellcheck disable=SC2206
    base_packages+=(${net_packages})

    # Add WWAN packages if detected
    if detect_wwan; then
        local wwan_packages
        wwan_packages="$(get_wwan_packages)"
        # shellcheck disable=SC2206
        base_packages+=(${wwan_packages})
        log_info "Adding WWAN packages: ${wwan_packages}"
    fi

    # Add VM packages if in VM
    local vm_packages
    vm_packages="$(get_vm_packages)"
    if [[ -n "${vm_packages}" ]]; then
        # shellcheck disable=SC2206
        base_packages+=(${vm_packages})
        log_info "Adding VM packages: ${vm_packages}"
    fi

    # Add fingerprint reader packages if detected
    if [[ "$(config_get install_fingerprint)" == "1" ]]; then
        local fp_packages
        fp_packages="$(get_fingerprint_packages)"
        # shellcheck disable=SC2206
        base_packages+=(${fp_packages})
        log_info "Adding fingerprint packages: ${fp_packages}"
    fi

    # Add Thunderbolt packages if detected
    if [[ "$(config_get install_thunderbolt)" == "1" ]]; then
        local tb_packages
        tb_packages="$(get_thunderbolt_packages)"
        # shellcheck disable=SC2206
        base_packages+=(${tb_packages})
        log_info "Adding Thunderbolt packages: ${tb_packages}"
    fi

    # Add sensor packages if detected (accelerometer, light sensor)
    if [[ "$(config_get install_sensors)" == "1" ]]; then
        local sensor_packages
        sensor_packages="$(get_sensor_packages)"
        # shellcheck disable=SC2206
        base_packages+=(${sensor_packages})
        log_info "Adding sensor packages: ${sensor_packages}"
    fi

    # Add power management packages for laptops
    if [[ "$(config_get install_power)" == "1" ]]; then
        local power_packages
        power_packages="$(get_power_packages)"
        # shellcheck disable=SC2206
        base_packages+=(${power_packages})
        log_info "Adding power management packages: ${power_packages}"
    fi

    # Add smart card packages if detected
    if [[ "$(config_get install_smartcard)" == "1" ]]; then
        local sc_packages
        sc_packages="$(get_smartcard_packages)"
        # shellcheck disable=SC2206
        base_packages+=(${sc_packages})
        log_info "Adding smart card packages: ${sc_packages}"
    fi

    # Add additional firmware packages based on detected hardware
    local fw_packages
    fw_packages="$(get_firmware_packages)"
    if [[ -n "${fw_packages}" ]]; then
        # shellcheck disable=SC2206
        base_packages+=(${fw_packages})
        log_info "Adding firmware packages: ${fw_packages}"
    fi

    # Install base system
    log_info "Installing packages with pacstrap..."
    log_info "This may take a while depending on your internet connection"

    if [[ "${DRY_RUN}" == "1" ]]; then
        echo -e "${MAGENTA}[DRY-RUN]${RESET} pacstrap -K ${MOUNT_POINT} ${base_packages[*]}"
    else
        # Sync pacman database first to catch connectivity issues early
        log_info "Syncing pacman database..."
        if ! pacman -Sy; then
            log_error "Failed to sync pacman database"
            log_error "Check your network connection and mirror configuration"
            log_info "Try running: reflector --protocol https --sort rate --fastest 5 --save /etc/pacman.d/mirrorlist"
            exit 1
        fi

        # Update keyring if it's outdated (common issue on older ISOs)
        log_info "Ensuring keyring is up to date..."
        pacman -Sy --noconfirm archlinux-keyring 2>/dev/null || true

        pacstrap -K "${MOUNT_POINT}" "${base_packages[@]}"
    fi

    state_save
    log_info "Base system installation complete"
}
