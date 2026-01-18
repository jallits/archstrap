#!/bin/bash
# steps/15-finalize.sh - Final cleanup and unmount

set -euo pipefail

run_step() {
    step_start "15-finalize" "Finalizing installation"

    # Enable additional useful services
    log_info "Enabling additional services"
    run arch-chroot "${MOUNT_POINT}" systemctl enable systemd-oomd.service
    run arch-chroot "${MOUNT_POINT}" systemctl enable systemd-boot-update.service 2>/dev/null || true

    # Setup BTRFS snapshots directory
    log_info "Setting up snapshot infrastructure"
    if [[ "${DRY_RUN}" != "1" ]]; then
        # Create snapper-like directory structure
        mkdir -p "${MOUNT_POINT}/.snapshots"
    fi

    # Clear sensitive data from configuration
    log_info "Clearing sensitive configuration data"
    if [[ "${DRY_RUN}" != "1" ]]; then
        # Remove passwords from stored config
        sed -i '/luks_passphrase/d' "${MOUNT_POINT}/root/archstrap/archstrap.conf" 2>/dev/null || true
        sed -i '/user_password/d' "${MOUNT_POINT}/root/archstrap/archstrap.conf" 2>/dev/null || true
        sed -i '/root_password/d' "${MOUNT_POINT}/root/archstrap/archstrap.conf" 2>/dev/null || true
    fi

    # Clean up pacman cache
    log_info "Cleaning package cache"
    run arch-chroot "${MOUNT_POINT}" pacman -Scc --noconfirm

    # Sync filesystems
    log_info "Syncing filesystems"
    run sync

    # Unmount all filesystems
    log_info "Unmounting filesystems"
    unmount_all "${MOUNT_POINT}"

    # Close LUKS container
    luks_close "cryptroot"

    # Final message
    print_separator "="
    echo -e "${BOLD}${GREEN}"
    echo "  Installation Complete!"
    echo -e "${RESET}"
    print_separator "="
    echo
    echo "Your new Arch Linux system has been installed with:"
    echo "  - LUKS2 encrypted root partition"
    echo "  - BTRFS filesystem with subvolumes"
    echo "  - Unified Kernel Image (UKI)"
    if detect_tpm2; then
        echo "  - TPM2 automatic unlock (with passphrase fallback)"
    fi
    if detect_secure_boot; then
        echo "  - Secure Boot support"
    fi
    echo "  - Plymouth boot splash"
    echo "  - systemd-networkd networking"
    if [[ "$(config_get use_hardened_kernel)" == "1" ]]; then
        echo "  - Hardened kernel (linux-hardened)"
    fi
    if [[ "$(config_get enable_firewall)" == "1" ]]; then
        echo "  - nftables firewall"
    fi
    if [[ "$(config_get enable_apparmor)" == "1" ]]; then
        echo "  - AppArmor MAC"
    fi
    echo
    echo "Security notes:"
    echo "  - Root account is LOCKED (use sudo for admin tasks)"
    echo "  - User '$(config_get username)' has sudo privileges"
    echo "  - Kernel hardening sysctl parameters applied"
    echo
    echo "Next steps:"
    echo "  1. Remove the installation media"
    echo "  2. Reboot into your new system"
    echo "  3. Log in as '$(config_get username)'"
    echo "  4. Use 'sudo' for administrative tasks"
    echo
    echo "Documentation: https://wiki.archlinux.org"
    echo

    state_save
    log_info "Installation complete!"
}
