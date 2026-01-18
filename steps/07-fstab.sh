#!/bin/bash
# steps/07-fstab.sh - Generate and customize fstab

set -euo pipefail

# Harden fstab with secure mount options per Arch Wiki Security recommendations
harden_fstab() {
    local fstab_file="$1"

    log_info "Applying security hardening to fstab mount options"

    # /boot - nodev,nosuid,noexec (prevent execution from boot partition)
    sed -i '/\/boot/s/\(rw[^[:space:]]*\)/\1,nodev,nosuid,noexec/' "${fstab_file}"

    # /home - nodev,nosuid (no device files or setuid in home)
    sed -i '/@home.*\/home/s/\(rw[^[:space:]]*\)/\1,nodev,nosuid/' "${fstab_file}"

    # /var/log - nodev,nosuid,noexec (logs should never be executable)
    sed -i '/@var_log.*\/var\/log/s/\(rw[^[:space:]]*\)/\1,nodev,nosuid,noexec/' "${fstab_file}"

    # /var/cache - nodev,nosuid,noexec
    sed -i '/@var_cache.*\/var\/cache/s/\(rw[^[:space:]]*\)/\1,nodev,nosuid,noexec/' "${fstab_file}"

    # /.snapshots - nodev,nosuid,noexec (snapshots are read-only backups)
    sed -i '/@snapshots.*\/\.snapshots/s/\(rw[^[:space:]]*\)/\1,nodev,nosuid,noexec/' "${fstab_file}"

    # /swap - nodev,nosuid,noexec
    sed -i '/@swap.*\/swap/s/\(rw[^[:space:]]*\)/\1,nodev,nosuid,noexec/' "${fstab_file}"
}

run_step() {
    step_start "07-fstab" "Generating fstab"

    local fstab_file="${MOUNT_POINT}/etc/fstab"

    # Generate fstab
    log_info "Generating fstab..."

    if [[ "${DRY_RUN}" == "1" ]]; then
        echo -e "${MAGENTA}[DRY-RUN]${RESET} genfstab -U ${MOUNT_POINT} >> ${fstab_file}"
    else
        genfstab -U "${MOUNT_POINT}" >> "${fstab_file}"
    fi

    # Add swap file entry
    local swap_size
    swap_size="$(calculate_swap_size)"
    log_info "Swap size for hibernation: ${swap_size}"

    if [[ "${DRY_RUN}" != "1" ]]; then
        # Add swapfile entry (will be created in later step)
        echo "" >> "${fstab_file}"
        echo "# Swapfile for hibernation" >> "${fstab_file}"
        echo "/swap/swapfile    none    swap    defaults    0 0" >> "${fstab_file}"

        # Apply security hardening to mount options
        harden_fstab "${fstab_file}"
    fi

    # Store swap size for later
    state_set "swap_size" "${swap_size}"

    # Display fstab
    if [[ "${DRY_RUN}" != "1" ]]; then
        log_info "Generated fstab:"
        cat "${fstab_file}"
    fi

    state_save
    log_info "fstab generation complete"
}
