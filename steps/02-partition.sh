#!/bin/bash
# steps/02-partition.sh - Disk partitioning

set -euo pipefail

run_step() {
    step_start "02-partition" "Partitioning disks"

    local target_disk
    target_disk="$(config_get target_disk)"

    local efi_on_removable
    efi_on_removable="$(config_get efi_on_removable)"

    local efi_disk
    efi_disk="$(config_get efi_disk)"

    # Add cleanup handler
    add_disk_cleanup

    # Confirm destructive operation
    log_warn "About to partition disk(s). All data will be lost!"

    if [[ "${DRY_RUN}" != "1" ]]; then
        if ! confirm "Continue with partitioning?" "n"; then
            log_error "Partitioning cancelled"
            exit 1
        fi
    fi

    local secrets_on_removable
    secrets_on_removable="$(config_get secrets_on_removable)"

    # Wipe and partition based on configuration
    if [[ "${efi_on_removable}" == "1" ]]; then
        # EFI on separate removable disk
        log_info "Partitioning removable disk for EFI: ${efi_disk}"
        disk_wipe "${efi_disk}"

        if [[ "${secrets_on_removable}" == "1" ]]; then
            # EFI + secrets partitions
            partition_create_efi_with_secrets "${efi_disk}" "512M"
            local secrets_partition
            secrets_partition="$(get_partition_device "${efi_disk}" 2)"
            state_set "secrets_partition" "${secrets_partition}"
            log_info "Secrets partition created: ${secrets_partition}"
        else
            # EFI only
            partition_create_efi_only "${efi_disk}"
        fi

        log_info "Partitioning target disk for root: ${target_disk}"
        disk_wipe "${target_disk}"
        partition_create_root_only "${target_disk}"

        # Set partition variables
        local efi_partition
        efi_partition="$(get_partition_device "${efi_disk}" 1)"
        local root_partition
        root_partition="$(get_partition_device "${target_disk}" 1)"

        state_set "efi_partition" "${efi_partition}"
        state_set "root_partition" "${root_partition}"
    else
        # Standard layout: EFI and root on same disk
        log_info "Partitioning target disk: ${target_disk}"
        disk_wipe "${target_disk}"
        partition_create_gpt "${target_disk}" "512M"

        local efi_partition
        efi_partition="$(get_partition_device "${target_disk}" 1)"
        local root_partition
        root_partition="$(get_partition_device "${target_disk}" 2)"

        state_set "efi_partition" "${efi_partition}"
        state_set "root_partition" "${root_partition}"
    fi

    # Format EFI partition
    local efi_part
    efi_part="$(state_get efi_partition)"
    log_info "Formatting EFI partition: ${efi_part}"
    format_efi "${efi_part}"

    # Display partition layout
    log_info "Partition layout:"
    if [[ "${DRY_RUN}" != "1" ]]; then
        lsblk -o NAME,SIZE,TYPE,FSTYPE "${target_disk}"
        if [[ "${efi_on_removable}" == "1" ]]; then
            lsblk -o NAME,SIZE,TYPE,FSTYPE "${efi_disk}"
        fi
    fi

    state_save
    log_info "Partitioning complete"
}
