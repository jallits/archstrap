#!/bin/bash
# steps/09-locale.sh - Locale, timezone, hostname configuration

set -euo pipefail

run_step() {
    step_start "09-locale" "Configuring locale and timezone"

    local hostname
    hostname="$(config_get hostname)"

    local timezone
    timezone="$(config_get timezone)"

    local locale
    locale="$(config_get locale)"

    local keymap
    keymap="$(config_get keymap)"

    # Set timezone
    log_info "Setting timezone to ${timezone}"
    run arch-chroot "${MOUNT_POINT}" ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime
    run arch-chroot "${MOUNT_POINT}" hwclock --systohc

    # Configure locale
    log_info "Configuring locale: ${locale}"
    if [[ "${DRY_RUN}" != "1" ]]; then
        # Uncomment locale in locale.gen
        sed -i "s/^#${locale}/${locale}/" "${MOUNT_POINT}/etc/locale.gen"
        # Also enable en_US.UTF-8 as fallback if different
        if [[ "${locale}" != "en_US.UTF-8" ]]; then
            sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' "${MOUNT_POINT}/etc/locale.gen"
        fi
    fi
    run arch-chroot "${MOUNT_POINT}" locale-gen

    # Set locale.conf
    if [[ "${DRY_RUN}" != "1" ]]; then
        echo "LANG=${locale}" > "${MOUNT_POINT}/etc/locale.conf"
    fi

    # Set keyboard layout
    log_info "Setting keyboard layout: ${keymap}"
    if [[ "${DRY_RUN}" != "1" ]]; then
        echo "KEYMAP=${keymap}" > "${MOUNT_POINT}/etc/vconsole.conf"
    fi

    # Set hostname
    log_info "Setting hostname: ${hostname}"
    if [[ "${DRY_RUN}" != "1" ]]; then
        echo "${hostname}" > "${MOUNT_POINT}/etc/hostname"

        # Create hosts file
        cat > "${MOUNT_POINT}/etc/hosts" << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${hostname}.localdomain ${hostname}
EOF
    fi

    # Enable NTP time synchronization
    # Note: Automatic timezone detection (via automatic-timezoned) is configured in step 14-aur
    log_info "Enabling NTP time synchronization"
    if [[ "${DRY_RUN}" != "1" ]]; then
        run arch-chroot "${MOUNT_POINT}" systemctl enable systemd-timesyncd.service
    fi

    state_save
    log_info "Locale and timezone configuration complete"
}
