#!/bin/bash
# steps/14-aur.sh - AUR helper installation

set -euo pipefail

run_step() {
    step_start "14-aur" "Installing AUR helper"

    local aur_helper
    aur_helper="$(config_get aur_helper)"

    local username
    username="$(config_get username)"

    if [[ "${aur_helper}" == "none" ]]; then
        log_info "Skipping AUR helper installation (user choice)"
        return 0
    fi

    log_info "Installing ${aur_helper}"

    # Install base-devel for building packages
    run arch-chroot "${MOUNT_POINT}" pacman -S --noconfirm --needed base-devel git

    # Build and install AUR helper as the user
    local build_dir="/home/${username}/aur_build"

    if [[ "${DRY_RUN}" != "1" ]]; then
        # Create build directory
        arch-chroot "${MOUNT_POINT}" su - "${username}" -c "mkdir -p ${build_dir}"

        case "${aur_helper}" in
            paru)
                # Clone and build paru
                arch-chroot "${MOUNT_POINT}" su - "${username}" -c \
                    "cd ${build_dir} && git clone https://aur.archlinux.org/paru-bin.git"
                arch-chroot "${MOUNT_POINT}" su - "${username}" -c \
                    "cd ${build_dir}/paru-bin && makepkg -si --noconfirm"
                ;;
            yay)
                # Clone and build yay
                arch-chroot "${MOUNT_POINT}" su - "${username}" -c \
                    "cd ${build_dir} && git clone https://aur.archlinux.org/yay-bin.git"
                arch-chroot "${MOUNT_POINT}" su - "${username}" -c \
                    "cd ${build_dir}/yay-bin && makepkg -si --noconfirm"
                ;;
        esac

        # Cleanup build directory
        arch-chroot "${MOUNT_POINT}" rm -rf "${build_dir}"

        log_info "${aur_helper} installed successfully"

        # Install automatic-timezoned for automatic timezone updates
        log_info "Installing automatic-timezoned for automatic timezone detection"
        arch-chroot "${MOUNT_POINT}" su - "${username}" -c \
            "${aur_helper} -S --noconfirm automatic-timezoned"

        # Enable the service
        arch-chroot "${MOUNT_POINT}" systemctl enable automatic-timezoned.service

        log_info "Automatic timezone detection configured"
    else
        echo -e "${MAGENTA}[DRY-RUN]${RESET} Would install ${aur_helper}"
        echo -e "${MAGENTA}[DRY-RUN]${RESET} Would install automatic-timezoned"
    fi

    state_save
}
