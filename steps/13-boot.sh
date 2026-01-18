#!/bin/bash
# steps/13-boot.sh - UKI, Secure Boot, TPM2, Plymouth configuration

set -euo pipefail

run_step() {
    step_start "13-boot" "Configuring boot"

    local root_partition
    root_partition="$(state_get root_partition)"

    local luks_uuid
    luks_uuid="$(state_get luks_uuid)"

    local swap_offset
    swap_offset="$(state_get swap_offset)"

    local luks_header_on_removable
    luks_header_on_removable="$(config_get luks_header_on_removable)"

    # Determine kernel name based on choice
    local kernel_name="linux"
    local kernel_vmlinuz="vmlinuz-linux"
    if [[ "$(config_get use_hardened_kernel)" == "1" ]]; then
        kernel_name="linux-hardened"
        kernel_vmlinuz="vmlinuz-linux-hardened"
    fi

    # Configure mkinitcpio for systemd-based initramfs
    log_info "Configuring mkinitcpio"
    if [[ "${DRY_RUN}" != "1" ]]; then
        # Build MODULES array based on detected hardware
        local mkinitcpio_modules="btrfs"

        # Add GPU modules for early KMS (required for Plymouth)
        local gpus
        gpus="$(detect_gpu)"
        log_info "Detected GPU(s): ${gpus}"

        if [[ "${gpus}" == *"nvidia"* ]]; then
            # NVIDIA modules for early KMS
            mkinitcpio_modules="${mkinitcpio_modules} nvidia nvidia_modeset nvidia_uvm nvidia_drm"
            log_info "Adding NVIDIA modules for early KMS"
        fi

        if [[ "${gpus}" == *"intel"* ]]; then
            # Intel GPU module
            mkinitcpio_modules="${mkinitcpio_modules} i915"
            log_info "Adding Intel i915 module for early KMS"
        fi

        if [[ "${gpus}" == *"amd"* ]]; then
            # AMD GPU module
            mkinitcpio_modules="${mkinitcpio_modules} amdgpu"
            log_info "Adding AMD amdgpu module for early KMS"
        fi

        # Create mkinitcpio configuration
        local mkinitcpio_hooks="systemd autodetect microcode modconf kms keyboard sd-vconsole plymouth sd-encrypt block filesystems fsck"

        # Add AppArmor hook if enabled
        if [[ "$(config_get enable_apparmor)" == "1" ]]; then
            mkinitcpio_hooks="systemd autodetect microcode modconf kms keyboard sd-vconsole plymouth apparmor sd-encrypt block filesystems fsck"
        fi

        cat > "${MOUNT_POINT}/etc/mkinitcpio.conf" << EOF
MODULES=(${mkinitcpio_modules})
BINARIES=()
FILES=()
HOOKS=(${mkinitcpio_hooks})
EOF

        # Configure mkinitcpio for UKI generation
        mkdir -p "${MOUNT_POINT}/etc/mkinitcpio.d"
        cat > "${MOUNT_POINT}/etc/mkinitcpio.d/${kernel_name}.preset" << EOF
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/${kernel_vmlinuz}"
ALL_microcode=(/boot/*-ucode.img)

PRESETS=('default' 'fallback')

default_uki="/efi/EFI/Linux/arch-linux.efi"
default_options=""

fallback_uki="/efi/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
EOF
    fi

    # Build kernel command line
    log_info "Building kernel command line"
    local cmdline="rd.luks.name=${luks_uuid}=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw"

    # Add hibernation parameters
    if [[ -n "${swap_offset}" ]]; then
        cmdline="${cmdline} resume=/dev/mapper/cryptroot resume_offset=${swap_offset}"
    fi

    # Add Plymouth quiet boot
    cmdline="${cmdline} quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3"

    # Add AppArmor LSM if enabled
    if [[ "$(config_get enable_apparmor)" == "1" ]]; then
        cmdline="${cmdline} lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
    fi

    # Add detached header if configured
    if [[ "${luks_header_on_removable}" == "1" ]]; then
        local header_file
        header_file="$(state_get luks_header_file)"
        cmdline="${cmdline} rd.luks.options=${luks_uuid}=header=${header_file}"
    fi

    if [[ "${DRY_RUN}" != "1" ]]; then
        mkdir -p "${MOUNT_POINT}/etc/kernel"
        echo "${cmdline}" > "${MOUNT_POINT}/etc/kernel/cmdline"
        log_info "Kernel cmdline: ${cmdline}"
    fi

    # Configure Plymouth
    log_info "Configuring Plymouth"
    if [[ "${DRY_RUN}" != "1" ]]; then
        # Set Plymouth theme (using built-in spinner with customization)
        arch-chroot "${MOUNT_POINT}" plymouth-set-default-theme -R spinner

        # Custom Plymouth configuration for Arch look
        mkdir -p "${MOUNT_POINT}/etc/plymouth"
        cat > "${MOUNT_POINT}/etc/plymouth/plymouthd.conf" << 'EOF'
[Daemon]
Theme=spinner
ShowDelay=0
DeviceTimeout=8

[BootUp]
UseFirmwareBackground=false
EOF
    fi

    # Create UKI directory on ESP
    run mkdir -p "${MOUNT_POINT}/efi/EFI/Linux"

    # Generate UKI
    log_info "Generating Unified Kernel Image"
    run arch-chroot "${MOUNT_POINT}" mkinitcpio -P

    # Setup Secure Boot
    log_info "Checking Secure Boot status"
    local sb_status
    sb_status="$(get_secure_boot_status)"
    log_info "Secure Boot status: ${sb_status}"

    if [[ "${DRY_RUN}" != "1" ]]; then
        # Install sbctl for Secure Boot key management (always install for future use)
        arch-chroot "${MOUNT_POINT}" pacman -S --noconfirm --needed sbctl

        case "${sb_status}" in
            setup_mode)
                log_info "Secure Boot is in setup mode - enrolling keys"

                # Create Secure Boot keys
                arch-chroot "${MOUNT_POINT}" sbctl create-keys

                # Sign the UKI
                arch-chroot "${MOUNT_POINT}" sbctl sign -s /efi/EFI/Linux/arch-linux.efi
                arch-chroot "${MOUNT_POINT}" sbctl sign -s /efi/EFI/Linux/arch-linux-fallback.efi

                # Enroll keys (with Microsoft keys for compatibility)
                if arch-chroot "${MOUNT_POINT}" sbctl enroll-keys -m; then
                    log_info "Secure Boot keys enrolled successfully"
                else
                    log_warn "Key enrollment failed - you may need to enroll manually"
                fi
                ;;
            enabled)
                log_warn "Secure Boot is enabled but not in setup mode"
                log_warn "Cannot enroll custom keys - Secure Boot must be in setup mode"
                log_warn "To enable custom keys:"
                log_warn "  1. Enter UEFI/BIOS setup"
                log_warn "  2. Clear Secure Boot keys or enable Setup Mode"
                log_warn "  3. Run: sbctl enroll-keys -m"
                ;;
            disabled)
                log_info "Secure Boot is disabled"
                log_info "Keys created but not enrolled - enable Secure Boot in UEFI to use"

                # Still create keys for future use
                if [[ ! -d "${MOUNT_POINT}/usr/share/secureboot/keys" ]]; then
                    arch-chroot "${MOUNT_POINT}" sbctl create-keys
                fi

                # Sign UKIs for when Secure Boot is enabled
                arch-chroot "${MOUNT_POINT}" sbctl sign -s /efi/EFI/Linux/arch-linux.efi
                arch-chroot "${MOUNT_POINT}" sbctl sign -s /efi/EFI/Linux/arch-linux-fallback.efi

                log_info "UKIs signed - to enable Secure Boot later:"
                log_info "  1. Enter UEFI/BIOS setup"
                log_info "  2. Enable Secure Boot in Setup Mode"
                log_info "  3. Run: sbctl enroll-keys -m"
                ;;
            *)
                log_warn "Secure Boot not available on this system"
                ;;
        esac
    else
        echo -e "${MAGENTA}[DRY-RUN]${RESET} Would configure Secure Boot (status: ${sb_status})"
    fi

    # Setup TPM2 unlock if available
    if detect_tpm2 || [[ "${DRY_RUN}" == "1" ]]; then
        log_info "Configuring TPM2 unlock for LUKS"

        if [[ "${DRY_RUN}" != "1" ]]; then
            # Enroll TPM2 for automatic unlock
            local passphrase
            passphrase="$(config_get luks_passphrase)"

            log_info "Enrolling TPM2 key for automatic unlock"
            log_warn "You will need the passphrase to complete enrollment"

            # Enroll TPM2 with PCR 7 (Secure Boot state)
            if echo -n "${passphrase}" | arch-chroot "${MOUNT_POINT}" \
                systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "${root_partition}"; then
                log_info "TPM2 enrollment successful"
            else
                log_warn "TPM2 enrollment failed, passphrase will be required at boot"
            fi
        fi
    else
        log_info "TPM2 not available, skipping automatic unlock setup"
    fi

    # Create boot entry using efibootmgr
    log_info "Creating UEFI boot entry"
    local efi_partition
    efi_partition="$(state_get efi_partition)"
    local efi_disk
    efi_disk="$(config_get efi_disk)"

    # Determine partition number
    local part_num
    if [[ "${efi_partition}" =~ p([0-9]+)$ ]]; then
        part_num="${BASH_REMATCH[1]}"
    else
        part_num="${efi_partition: -1}"
    fi

    if [[ "${DRY_RUN}" != "1" ]]; then
        # Remove existing Arch entries
        local existing
        existing=$(efibootmgr 2>/dev/null | grep -i "Arch Linux" | cut -d'*' -f1 | tr -d 'Boot' || true)
        for entry in ${existing}; do
            efibootmgr -b "${entry}" -B 2>/dev/null || true
        done

        # Create new entry
        efibootmgr --create \
            --disk "${efi_disk}" \
            --part "${part_num}" \
            --label "Arch Linux" \
            --loader '\EFI\Linux\arch-linux.efi' \
            --unicode
    fi

    state_save
    log_info "Boot configuration complete"
}
