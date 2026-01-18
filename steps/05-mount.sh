#!/bin/bash
# steps/05-mount.sh - Mount filesystems for installation

set -euo pipefail

run_step() {
    step_start "05-mount" "Mounting filesystems"

    local mapper_device="/dev/mapper/cryptroot"
    local efi_partition
    efi_partition="$(state_get efi_partition)"

    # Mount BTRFS subvolumes
    log_info "Mounting BTRFS subvolumes to ${MOUNT_POINT}"
    btrfs_mount_subvolumes "${mapper_device}" "${MOUNT_POINT}"

    # Mount EFI partition
    log_info "Mounting EFI partition"
    mount_efi "${efi_partition}" "${MOUNT_POINT}"

    # Display mount layout
    if [[ "${DRY_RUN}" != "1" ]]; then
        log_info "Mount layout:"
        findmnt -R "${MOUNT_POINT}" --output TARGET,SOURCE,FSTYPE,OPTIONS
    fi

    state_save
    log_info "Filesystems mounted"
}
