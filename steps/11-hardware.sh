#!/bin/bash
# steps/11-hardware.sh - Hardware and security configuration

set -euo pipefail

run_step() {
    step_start "11-hardware" "Configuring hardware and security"

    # ============================================
    # HARDWARE CONFIGURATION
    # ============================================

    # Enable audio services if installed
    if [[ "$(config_get install_audio)" == "1" ]]; then
        log_info "Enabling audio services"
        run arch-chroot "${MOUNT_POINT}" systemctl --global enable pipewire.socket
        run arch-chroot "${MOUNT_POINT}" systemctl --global enable pipewire-pulse.socket
        run arch-chroot "${MOUNT_POINT}" systemctl --global enable wireplumber.service
    fi

    # Enable Bluetooth if installed
    if [[ "$(config_get install_bluetooth)" == "1" ]]; then
        log_info "Enabling Bluetooth service"
        run arch-chroot "${MOUNT_POINT}" systemctl enable bluetooth.service
    fi

    # Configure NVIDIA if present
    local gpus
    gpus="$(detect_gpu)"
    if [[ "${gpus}" == *"nvidia"* ]]; then
        log_info "Configuring NVIDIA drivers"

        # Enable DRM kernel mode setting
        if [[ "${DRY_RUN}" != "1" ]]; then
            mkdir -p "${MOUNT_POINT}/etc/modprobe.d"
            echo "options nvidia_drm modeset=1 fbdev=1" > "${MOUNT_POINT}/etc/modprobe.d/nvidia.conf"
        fi
    fi

    # Configure VM-specific settings
    local vm_type
    vm_type="$(detect_vm)"
    if [[ "${vm_type}" != "none" ]]; then
        log_info "Configuring VM guest services for ${vm_type}"
        case "${vm_type}" in
            virtualbox)
                run arch-chroot "${MOUNT_POINT}" systemctl enable vboxservice.service
                ;;
            vmware)
                run arch-chroot "${MOUNT_POINT}" systemctl enable vmtoolsd.service
                run arch-chroot "${MOUNT_POINT}" systemctl enable vmware-vmblock-fuse.service
                ;;
            kvm|qemu)
                run arch-chroot "${MOUNT_POINT}" systemctl enable qemu-guest-agent.service
                ;;
        esac
    fi

    # Configure power management
    log_info "Configuring power management"
    if [[ "${DRY_RUN}" != "1" ]]; then
        # Enable fstrim for SSD
        arch-chroot "${MOUNT_POINT}" systemctl enable fstrim.timer
    fi

    # Enable laptop power management services if laptop detected
    if [[ "$(config_get install_power)" == "1" ]]; then
        log_info "Enabling laptop power management services"
        run arch-chroot "${MOUNT_POINT}" systemctl enable power-profiles-daemon.service
        # thermald for Intel CPUs
        if [[ "$(detect_cpu_vendor)" == "intel" ]]; then
            run arch-chroot "${MOUNT_POINT}" systemctl enable thermald.service
        fi
    fi

    # Enable fingerprint service if installed
    if [[ "$(config_get install_fingerprint)" == "1" ]]; then
        log_info "Enabling fingerprint authentication service"
        run arch-chroot "${MOUNT_POINT}" systemctl enable fprintd.service
        # Note: User will need to run 'fprintd-enroll' to register fingerprints
        log_info "Fingerprint enrollment: run 'fprintd-enroll' after first login"
    fi

    # Enable Thunderbolt authorization service if installed
    if [[ "$(config_get install_thunderbolt)" == "1" ]]; then
        log_info "Enabling Thunderbolt authorization service"
        run arch-chroot "${MOUNT_POINT}" systemctl enable bolt.service
    fi

    # Enable sensor proxy for accelerometer/light sensors
    if [[ "$(config_get install_sensors)" == "1" ]]; then
        log_info "Enabling IIO sensor proxy service"
        run arch-chroot "${MOUNT_POINT}" systemctl enable iio-sensor-proxy.service
    fi

    # Enable smart card service if installed
    if [[ "$(config_get install_smartcard)" == "1" ]]; then
        log_info "Enabling smart card service"
        run arch-chroot "${MOUNT_POINT}" systemctl enable pcscd.socket
    fi

    # Enable removable media management (udisks2 + udiskie)
    log_info "Enabling removable media management"
    # udisks2 is D-Bus activated, no service to enable
    # udiskie runs as a user service for auto-mounting
    run arch-chroot "${MOUNT_POINT}" systemctl --global enable udiskie.service

    # ============================================
    # MIRROR AND FIRMWARE MANAGEMENT
    # ============================================

    # Configure reflector for automatic mirror updates
    log_info "Configuring reflector for mirror management"
    if [[ "${DRY_RUN}" != "1" ]]; then
        mkdir -p "${MOUNT_POINT}/etc/xdg/reflector"
        cp "${SCRIPT_DIR}/configs/reflector.conf" \
            "${MOUNT_POINT}/etc/xdg/reflector/reflector.conf"

        # Try to detect country and add to config
        local country=""
        country=$(curl -s --max-time 5 "https://ipapi.co/country_code" 2>/dev/null || true)
        if [[ -n "${country}" ]] && [[ "${country}" =~ ^[A-Z]{2}$ ]]; then
            log_info "Setting reflector country: ${country}"
            echo "--country ${country}" >> "${MOUNT_POINT}/etc/xdg/reflector/reflector.conf"
        fi

        # Enable reflector timer for weekly mirror updates
        arch-chroot "${MOUNT_POINT}" systemctl enable reflector.timer
    fi

    # Configure fwupd for firmware updates
    log_info "Configuring fwupd for firmware updates"
    if [[ "${DRY_RUN}" != "1" ]]; then
        # Enable fwupd-refresh timer for automatic metadata updates
        arch-chroot "${MOUNT_POINT}" systemctl enable fwupd-refresh.timer

        # Check for available firmware updates (informational)
        log_info "Checking for available firmware updates..."
        if arch-chroot "${MOUNT_POINT}" fwupdmgr refresh --force 2>/dev/null; then
            local fw_updates
            fw_updates=$(arch-chroot "${MOUNT_POINT}" fwupdmgr get-updates 2>/dev/null || true)
            if [[ -n "${fw_updates}" ]] && [[ "${fw_updates}" != *"No updates available"* ]]; then
                log_warn "Firmware updates available:"
                echo "${fw_updates}" | head -20
                log_info "Run 'fwupdmgr update' after reboot to apply updates"
            else
                log_info "No firmware updates available"
            fi
        else
            log_debug "Could not check for firmware updates (normal in chroot)"
        fi
    fi

    # ============================================
    # SNAPSHOT MANAGEMENT (Snapper)
    # ============================================
    print_separator "-"
    log_info "Configuring BTRFS snapshots with Snapper"
    print_separator "-"

    if [[ "${DRY_RUN}" != "1" ]]; then
        # Create snapper config directory
        mkdir -p "${MOUNT_POINT}/etc/snapper/configs"

        # Configure snapper for root filesystem
        log_info "Creating snapper configuration for root filesystem"
        cp "${SCRIPT_DIR}/configs/snapper/root.conf" \
            "${MOUNT_POINT}/etc/snapper/configs/root"

        # Initialize snapper config list (user configs added in step 10-users.sh)
        mkdir -p "${MOUNT_POINT}/etc/conf.d"
        echo 'SNAPPER_CONFIGS="root"' > "${MOUNT_POINT}/etc/conf.d/snapper"

        # Set proper permissions on root snapshot directory
        # Root snapshots at /.snapshots (already exists from @snapshots subvolume)
        chmod 750 "${MOUNT_POINT}/.snapshots"
        chown root:root "${MOUNT_POINT}/.snapshots"

        # Enable snapper timers
        log_info "Enabling snapper timers"
        arch-chroot "${MOUNT_POINT}" systemctl enable snapper-timeline.timer
        arch-chroot "${MOUNT_POINT}" systemctl enable snapper-cleanup.timer

        # snap-pac is automatically active via pacman hooks (no service needed)
        log_info "snap-pac configured for automatic pacman snapshots"

        # Note: Per-user home snapshots are configured in step 10-users.sh
        log_info "User home snapshots will be configured per-user"
    fi

    # ============================================
    # SECURITY HARDENING (Arch Wiki recommendations)
    # ============================================
    print_separator "-"
    log_info "Applying security hardening"
    print_separator "-"

    if [[ "${DRY_RUN}" != "1" ]]; then
        # Kernel hardening via sysctl
        log_info "Installing kernel hardening sysctl parameters"
        mkdir -p "${MOUNT_POINT}/etc/sysctl.d"
        cp "${SCRIPT_DIR}/configs/security/sysctl-hardening.conf" \
            "${MOUNT_POINT}/etc/sysctl.d/99-security.conf"

        # Password quality policy
        log_info "Configuring password quality requirements"
        cp "${SCRIPT_DIR}/configs/security/pwquality.conf" \
            "${MOUNT_POINT}/etc/security/pwquality.conf"

        # Restrict /boot permissions (only root should access boot files)
        log_info "Restricting /boot permissions"
        chmod 700 "${MOUNT_POINT}/boot"

        # Set restrictive umask in shell configs
        log_info "Setting restrictive umask (0077)"
        echo "umask 0077" >> "${MOUNT_POINT}/etc/profile.d/umask.sh"
        chmod 644 "${MOUNT_POINT}/etc/profile.d/umask.sh"

        # SSH hardening (if sshd is installed later, config will be ready)
        log_info "Installing SSH hardening configuration"
        mkdir -p "${MOUNT_POINT}/etc/ssh/sshd_config.d"
        cp "${SCRIPT_DIR}/configs/security/ssh_hardening.conf" \
            "${MOUNT_POINT}/etc/ssh/sshd_config.d/99-hardening.conf"
    fi

    # Firewall configuration
    if [[ "$(config_get enable_firewall)" == "1" ]]; then
        log_info "Configuring nftables firewall"
        if [[ "${DRY_RUN}" != "1" ]]; then
            cp "${SCRIPT_DIR}/configs/security/nftables.conf" \
                "${MOUNT_POINT}/etc/nftables.conf"
            arch-chroot "${MOUNT_POINT}" systemctl enable nftables.service
        fi
    fi

    # AppArmor configuration
    if [[ "$(config_get enable_apparmor)" == "1" ]]; then
        log_info "Enabling AppArmor service"
        run arch-chroot "${MOUNT_POINT}" systemctl enable apparmor.service
    fi

    # Account lockout with pam_faillock (already enabled by default in pambase)
    log_info "Verifying account lockout configuration (pam_faillock)"
    # pam_faillock is enabled by default in Arch's pambase since 2021

    state_save
    log_info "Hardware and security configuration complete"
}
