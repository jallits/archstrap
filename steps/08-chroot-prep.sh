#!/bin/bash
# steps/08-chroot-prep.sh - Prepare chroot environment

set -euo pipefail

run_step() {
    step_start "08-chroot-prep" "Preparing chroot environment"

    # Copy archstrap scripts to chroot for later use
    local chroot_scripts="${MOUNT_POINT}/root/archstrap"
    run mkdir -p "${chroot_scripts}"

    # Copy necessary scripts
    log_info "Copying scripts to chroot environment"
    run cp -r "${SCRIPT_DIR}/lib" "${chroot_scripts}/"
    run cp -r "${SCRIPT_DIR}/steps/chroot" "${chroot_scripts}/"
    run cp -r "${SCRIPT_DIR}/configs" "${chroot_scripts}/"

    # Copy configuration state
    if [[ -f "${CONFIG_FILE}" ]]; then
        run cp "${CONFIG_FILE}" "${chroot_scripts}/archstrap.conf"
    fi
    if [[ -f "${STATE_FILE}" ]]; then
        run cp "${STATE_FILE}" "${chroot_scripts}/archstrap.state"
    fi

    # Create swapfile
    local swap_size
    swap_size="$(state_get swap_size)"
    if [[ -n "${swap_size}" ]]; then
        log_info "Creating swapfile: ${swap_size}"
        create_swapfile "${MOUNT_POINT}" "${swap_size}"

        # Get swapfile offset for hibernation
        if [[ "${DRY_RUN}" != "1" ]]; then
            local swap_offset
            swap_offset="$(get_swapfile_offset "${MOUNT_POINT}/swap/swapfile")"
            if [[ -n "${swap_offset}" ]]; then
                state_set "swap_offset" "${swap_offset}"
                log_info "Swapfile offset: ${swap_offset}"
            fi
        fi
    fi

    # Copy resolv.conf for network access in chroot
    if [[ "${DRY_RUN}" != "1" ]]; then
        cp /etc/resolv.conf "${MOUNT_POINT}/etc/resolv.conf"
    fi

    state_save
    log_info "Chroot preparation complete"
}
