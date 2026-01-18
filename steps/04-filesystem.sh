#!/bin/bash
# steps/04-filesystem.sh - BTRFS filesystem creation

set -euo pipefail

run_step() {
    step_start "04-filesystem" "Creating BTRFS filesystem"

    local mapper_device="/dev/mapper/cryptroot"

    # Create BTRFS filesystem
    log_info "Creating BTRFS filesystem on ${mapper_device}"
    btrfs_create "${mapper_device}" "archroot"

    # Mount temporarily to create subvolumes
    local temp_mount="/mnt/btrfs_temp"
    run mkdir -p "${temp_mount}"
    run mount "${mapper_device}" "${temp_mount}"

    # Create subvolumes
    log_info "Creating BTRFS subvolumes"
    btrfs_create_subvolumes "${temp_mount}"

    # Display subvolume layout
    if [[ "${DRY_RUN}" != "1" ]]; then
        log_info "Subvolume layout:"
        btrfs subvolume list "${temp_mount}"
    fi

    # Unmount temporary mount
    run umount "${temp_mount}"
    run rmdir "${temp_mount}"

    state_save
    log_info "Filesystem creation complete"
}
