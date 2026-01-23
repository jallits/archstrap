#!/bin/bash
# steps/03-encryption.sh - LUKS2 encryption setup

set -euo pipefail

run_step() {
    step_start "03-encryption" "Setting up disk encryption"

    local root_partition
    root_partition="$(state_get root_partition)"

    local passphrase
    passphrase="$(config_get luks_passphrase)"

    local luks_header_on_removable
    luks_header_on_removable="$(config_get luks_header_on_removable)"

    local header_file=""

    # Handle detached header if configured
    if [[ "${luks_header_on_removable}" == "1" ]]; then
        local header_disk
        header_disk="$(config_get luks_header_disk)"

        # Create header file on removable storage
        # First, mount the EFI partition if it's the header disk
        local efi_partition
        efi_partition="$(state_get efi_partition)"

        local header_mount="/tmp/luks_header_mount"
        run mkdir -p "${header_mount}"

        # Determine where to put the header
        if [[ "$(config_get efi_disk)" == "${header_disk}" ]]; then
            run mount "${efi_partition}" "${header_mount}"
            header_file="${header_mount}/cryptroot.header"
        else
            # Separate header disk - mount first partition
            local header_partition
            header_partition="$(get_partition_device "${header_disk}" 1)"
            run mount "${header_partition}" "${header_mount}"
            header_file="${header_mount}/cryptroot.header"
        fi

        log_info "LUKS header will be stored at: ${header_file}"
        state_set "luks_header_file" "${header_file}"
    fi

    # Get encryption strength setting
    local encryption_strength
    encryption_strength="$(config_get encryption_strength "standard")"

    # Format LUKS2 container
    log_info "Creating LUKS2 encrypted container on ${root_partition}"
    luks_format "${root_partition}" "${passphrase}" "${header_file}" "${encryption_strength}"

    # Get LUKS UUID
    local luks_uuid
    if [[ "${DRY_RUN}" != "1" ]]; then
        if [[ -n "${header_file}" ]]; then
            luks_uuid="$(cryptsetup luksUUID --header "${header_file}" "${root_partition}")"
        else
            luks_uuid="$(luks_get_uuid "${root_partition}")"
        fi
        state_set "luks_uuid" "${luks_uuid}"
        log_info "LUKS UUID: ${luks_uuid}"
    else
        log_info "LUKS UUID: [dry-run - would be generated]"
    fi

    # Open LUKS container
    log_info "Opening LUKS container"
    luks_open "${root_partition}" "cryptroot" "${passphrase}" "${header_file}"

    # Unmount header mount if used
    if [[ -n "${header_file}" ]]; then
        run umount "${header_mount}" || true
        run rmdir "${header_mount}" || true
    fi

    # Handle secrets partition encryption if configured
    if [[ "$(config_get secrets_on_removable)" == "1" ]]; then
        local secrets_partition
        secrets_partition="$(state_get secrets_partition)"

        # Determine passphrase for secrets
        local secrets_passphrase
        if [[ "$(config_get secrets_separate_passphrase)" == "1" ]]; then
            secrets_passphrase="$(config_get secrets_passphrase)"
        else
            secrets_passphrase="${passphrase}"
        fi

        # Format LUKS2 container for secrets (use same encryption strength)
        log_info "Creating LUKS2 encrypted container for secrets on ${secrets_partition}"
        luks_format "${secrets_partition}" "${secrets_passphrase}" "" "${encryption_strength}"

        # Get secrets LUKS UUID
        if [[ "${DRY_RUN}" != "1" ]]; then
            local secrets_uuid
            secrets_uuid="$(luks_get_uuid "${secrets_partition}")"
            state_set "secrets_uuid" "${secrets_uuid}"
            log_info "Secrets LUKS UUID: ${secrets_uuid}"
        fi

        # Open secrets LUKS container
        log_info "Opening secrets LUKS container"
        luks_open "${secrets_partition}" "cryptsecrets" "${secrets_passphrase}"

        # Format ext4 inside the container
        format_ext4 "/dev/mapper/cryptsecrets" "secrets"

        log_info "Secrets partition encrypted and formatted"
    fi

    state_save
    log_info "Encryption setup complete"
}
