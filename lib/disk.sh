#!/bin/bash
# lib/disk.sh - Disk operations for archstrap

set -euo pipefail

# Discoverable Partitions Specification GUIDs
readonly ESP_TYPE_GUID="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
readonly ROOT_X86_64_GUID="4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709"
readonly LINUX_DATA_GUID="0FC63DAF-8483-4772-8E79-3D69D8477DE4"

# Mount point for installation
readonly MOUNT_POINT="/mnt"

# List available disks with details (excludes ISO boot media)
disk_list() {
    log_debug "Listing available disks"

    # Get the ISO boot disk to exclude it
    local iso_disk
    iso_disk=$(get_iso_boot_disk 2>/dev/null || true)

    local line disk
    while IFS= read -r line; do
        disk=$(echo "${line}" | awk '{print $1}')
        # Skip the ISO boot disk
        if [[ -n "${iso_disk}" ]] && [[ "${disk}" == "${iso_disk}" ]]; then
            log_debug "Excluding ISO boot disk from list: ${disk}"
            continue
        fi
        echo "${line}"
    # Order: NAME,SIZE,TRAN,MODEL - put MODEL last since it can contain spaces
    done < <(lsblk -dpno NAME,SIZE,TRAN,MODEL 2>/dev/null | \
        grep -E '^/dev/(sd|nvme|vd|mmcblk)' | \
        grep -v 'loop' || true)
}

# Check if disk is removable
disk_is_removable() {
    local disk="$1"
    local disk_name
    disk_name="$(basename "${disk}")"
    local removable_file="/sys/block/${disk_name}/removable"

    if [[ -f "${removable_file}" ]]; then
        [[ "$(cat "${removable_file}")" == "1" ]]
    else
        return 1
    fi
}

# Get partition device name (handles nvme vs sd naming)
get_partition_device() {
    local disk="$1"
    local part_num="$2"

    if [[ "${disk}" =~ nvme|mmcblk ]]; then
        echo "${disk}p${part_num}"
    else
        echo "${disk}${part_num}"
    fi
}

# Wipe disk to factory default state
disk_wipe() {
    local disk="$1"

    log_info "Preparing disk ${disk} (restoring to factory default)"

    # Close any LUKS containers on this disk
    log_debug "Closing any LUKS containers on ${disk}"
    for mapper in /dev/mapper/*; do
        if [[ -e "${mapper}" ]] && [[ "${mapper}" != "/dev/mapper/control" ]]; then
            local backing
            backing=$(cryptsetup status "$(basename "${mapper}")" 2>/dev/null | grep "device:" | awk '{print $2}' || true)
            if [[ "${backing}" == "${disk}"* ]]; then
                log_debug "Closing LUKS container: ${mapper}"
                run cryptsetup close "$(basename "${mapper}")" 2>/dev/null || true
            fi
        fi
    done

    # Unmount any partitions from this disk
    log_debug "Unmounting any partitions on ${disk}"
    for part in "${disk}"*; do
        if [[ "${part}" != "${disk}" ]] && mountpoint -q "${part}" 2>/dev/null; then
            run umount -l "${part}" 2>/dev/null || true
        fi
    done
    # Also check by mount point
    while read -r mounted_part _; do
        if [[ "${mounted_part}" == "${disk}"* ]]; then
            run umount -l "${mounted_part}" 2>/dev/null || true
        fi
    done < /proc/mounts

    # Disable any swap on this disk
    log_debug "Disabling swap on ${disk}"
    for part in "${disk}"*; do
        run swapoff "${part}" 2>/dev/null || true
    done

    # Wipe filesystem signatures
    log_info "Wiping filesystem signatures"
    run_destructive wipefs -af "${disk}"

    # Zap GPT and MBR structures
    log_info "Removing partition tables"
    run_destructive sgdisk -Z "${disk}"

    # Zero out first and last 1MB to ensure clean state
    # This removes any residual boot sectors or backup partition tables
    log_info "Zeroing partition table areas"
    if [[ "${DRY_RUN}" != "1" ]]; then
        dd if=/dev/zero of="${disk}" bs=1M count=1 status=none 2>/dev/null || true

        # Zero last 1MB (backup GPT location)
        local disk_size_bytes
        disk_size_bytes=$(blockdev --getsize64 "${disk}" 2>/dev/null || echo "0")
        if [[ "${disk_size_bytes}" -gt 1048576 ]]; then
            dd if=/dev/zero of="${disk}" bs=1M count=1 seek=$(( (disk_size_bytes / 1048576) - 1 )) status=none 2>/dev/null || true
        fi
    else
        echo -e "${RED}[DRY-RUN] [DESTRUCTIVE]${RESET} dd if=/dev/zero of=${disk} bs=1M count=1"
    fi

    # For SSDs: use blkdiscard for fast secure erase (TRIM entire disk)
    if [[ -f "/sys/block/$(basename "${disk}")/queue/discard_max_bytes" ]]; then
        local discard_max
        discard_max=$(cat "/sys/block/$(basename "${disk}")/queue/discard_max_bytes" 2>/dev/null || echo "0")
        if [[ "${discard_max}" -gt 0 ]]; then
            log_info "SSD detected - sending TRIM to entire disk"
            run_destructive blkdiscard -f "${disk}" 2>/dev/null || true
        fi
    fi

    # Inform kernel of changes
    run partprobe "${disk}" 2>/dev/null || true
    sleep 1

    log_info "Disk ${disk} wiped successfully"
}

# Create GPT partition table with EFI and root partitions
partition_create_gpt() {
    local disk="$1"
    local efi_size="${2:-512M}"

    log_info "Creating GPT partition table on ${disk}"

    # Create GPT table
    run_destructive sgdisk -Z "${disk}"
    run_destructive sgdisk -o "${disk}"

    # Partition 1: EFI System Partition
    run sgdisk -n 1:0:+"${efi_size}" \
               -t 1:"${ESP_TYPE_GUID}" \
               -c 1:"EFI System Partition" \
               "${disk}"

    # Partition 2: Root (Linux x86-64 root)
    run sgdisk -n 2:0:0 \
               -t 2:"${ROOT_X86_64_GUID}" \
               -c 2:"Arch Linux Root" \
               "${disk}"

    # Inform kernel of partition changes
    run partprobe "${disk}"
    sleep 1
}

# Create single EFI partition on removable disk
partition_create_efi_only() {
    local disk="$1"

    log_info "Creating EFI partition on ${disk}"

    run_destructive sgdisk -Z "${disk}"
    run_destructive sgdisk -o "${disk}"

    # Single EFI partition using entire disk
    run sgdisk -n 1:0:0 \
               -t 1:"${ESP_TYPE_GUID}" \
               -c 1:"EFI System Partition" \
               "${disk}"

    run partprobe "${disk}"
    sleep 1
}

# Create EFI + secrets partitions on removable disk
partition_create_efi_with_secrets() {
    local disk="$1"
    local efi_size="${2:-512M}"

    log_info "Creating EFI and secrets partitions on ${disk}"

    run_destructive sgdisk -Z "${disk}"
    run_destructive sgdisk -o "${disk}"

    # Partition 1: EFI System Partition (512MB)
    run sgdisk -n 1:0:+"${efi_size}" \
               -t 1:"${ESP_TYPE_GUID}" \
               -c 1:"EFI System Partition" \
               "${disk}"

    # Partition 2: Secrets partition (remaining space, will be LUKS encrypted)
    run sgdisk -n 2:0:0 \
               -t 2:"${LINUX_DATA_GUID}" \
               -c 2:"Encrypted Secrets" \
               "${disk}"

    run partprobe "${disk}"
    sleep 1
}

# Create root-only partition on disk (when EFI is elsewhere)
partition_create_root_only() {
    local disk="$1"

    log_info "Creating root partition on ${disk}"

    run_destructive sgdisk -Z "${disk}"
    run_destructive sgdisk -o "${disk}"

    # Single root partition using entire disk
    run sgdisk -n 1:0:0 \
               -t 1:"${ROOT_X86_64_GUID}" \
               -c 1:"Arch Linux Root" \
               "${disk}"

    run partprobe "${disk}"
    sleep 1
}

# Format EFI partition
format_efi() {
    local partition="$1"

    log_info "Formatting EFI partition: ${partition}"
    run_destructive mkfs.fat -F 32 -n ESP "${partition}"
}

# Format ext4 partition (for secrets storage)
format_ext4() {
    local device="$1"
    local label="${2:-secrets}"

    log_info "Formatting ext4 filesystem on ${device}"
    run_destructive mkfs.ext4 -L "${label}" "${device}"
}

# LUKS2 format with optional detached header
# Encryption strength levels:
#   standard: AES-256-XTS, Argon2id with default parameters
#   high: AES-256-XTS, Argon2id with 4GB memory, 5s iteration time
#   maximum: AES-256-XTS + HMAC-SHA256 integrity, Argon2id with 4GB memory, 5s iteration time
luks_format() {
    local partition="$1"
    local passphrase="$2"
    local header_file="${3:-}"
    local strength="${4:-standard}"

    log_info "Formatting LUKS2 container on ${partition} (strength: ${strength})"

    local luks_opts=(
        --type luks2
        --cipher aes-xts-plain64
        --key-size 512
        --hash sha512
        --pbkdf argon2id
        --use-random
        --batch-mode
    )

    # Apply encryption strength settings
    case "${strength}" in
        high)
            # Stronger Argon2id parameters: 4GB memory, 5 second unlock time
            luks_opts+=(--pbkdf-memory 4194304)
            luks_opts+=(--iter-time 5000)
            log_info "Using high encryption: Argon2id with 4GB memory, 5s unlock"
            ;;
        maximum)
            # Strongest settings: integrity + stronger Argon2id
            luks_opts+=(--pbkdf-memory 4194304)
            luks_opts+=(--iter-time 5000)
            luks_opts+=(--integrity hmac-sha256)
            log_info "Using maximum encryption: Argon2id with 4GB memory, 5s unlock, HMAC-SHA256 integrity"
            log_warn "Integrity mode has ~2x disk space overhead and performance impact"
            ;;
        *)
            # Standard: use cryptsetup defaults for Argon2id
            log_info "Using standard encryption: Argon2id with default parameters"
            ;;
    esac

    if [[ -n "${header_file}" ]]; then
        luks_opts+=(--header "${header_file}")
        log_info "Using detached header: ${header_file}"
    fi

    if [[ "${DRY_RUN}" == "1" ]]; then
        echo -e "${RED}[DRY-RUN] [DESTRUCTIVE]${RESET} cryptsetup luksFormat ${luks_opts[*]} ${partition}"
        return 0
    fi

    echo -n "${passphrase}" | cryptsetup luksFormat "${luks_opts[@]}" "${partition}" -
}

# Open LUKS container
luks_open() {
    local partition="$1"
    local name="$2"
    local passphrase="$3"
    local header_file="${4:-}"

    log_info "Opening LUKS container: ${partition} -> /dev/mapper/${name}"

    local luks_opts=()
    if [[ -n "${header_file}" ]]; then
        luks_opts+=(--header "${header_file}")
    fi

    if [[ "${DRY_RUN}" == "1" ]]; then
        echo -e "${MAGENTA}[DRY-RUN]${RESET} cryptsetup open ${luks_opts[*]} ${partition} ${name}"
        return 0
    fi

    echo -n "${passphrase}" | cryptsetup open "${luks_opts[@]}" "${partition}" "${name}" -
}

# Close LUKS container
luks_close() {
    local name="$1"

    if [[ -e "/dev/mapper/${name}" ]]; then
        log_info "Closing LUKS container: ${name}"
        run cryptsetup close "${name}"
    fi
}

# Get LUKS UUID
luks_get_uuid() {
    local partition="$1"
    cryptsetup luksUUID "${partition}" 2>/dev/null || true
}

# Create BTRFS filesystem
btrfs_create() {
    local device="$1"
    local label="${2:-archroot}"

    log_info "Creating BTRFS filesystem on ${device}"
    run_destructive mkfs.btrfs -f -L "${label}" "${device}"
}

# Create BTRFS subvolumes
btrfs_create_subvolumes() {
    local mount_point="$1"

    log_info "Creating BTRFS subvolumes"

    local subvolumes=(
        "@"
        "@home"
        "@snapshots"
        "@swap"
        "@var_cache"
        "@var_log"
    )

    for subvol in "${subvolumes[@]}"; do
        log_debug "Creating subvolume: ${subvol}"
        run btrfs subvolume create "${mount_point}/${subvol}"
    done
}

# Mount BTRFS subvolumes for installation
btrfs_mount_subvolumes() {
    local device="$1"
    local mount_point="$2"

    local mount_opts="compress=zstd:1,noatime,discard=async"

    log_info "Mounting BTRFS subvolumes"

    # Mount root subvolume
    run mount -o "subvol=@,${mount_opts}" "${device}" "${mount_point}"

    # Create mount points
    # Note: /boot stays on encrypted root, /efi is the ESP mount point
    run mkdir -p "${mount_point}"/{home,.snapshots,swap,var/cache,var/log,boot,efi}

    # Mount other subvolumes
    run mount -o "subvol=@home,${mount_opts}" "${device}" "${mount_point}/home"
    run mount -o "subvol=@snapshots,${mount_opts}" "${device}" "${mount_point}/.snapshots"
    run mount -o "subvol=@swap,nodatacow,${mount_opts}" "${device}" "${mount_point}/swap"
    run mount -o "subvol=@var_cache,${mount_opts}" "${device}" "${mount_point}/var/cache"
    run mount -o "subvol=@var_log,${mount_opts}" "${device}" "${mount_point}/var/log"
}

# Mount EFI partition
mount_efi() {
    local partition="$1"
    local mount_point="$2"

    # Mount ESP at /efi to minimize unencrypted data
    # /boot stays on encrypted root, only UKI goes to /efi
    log_info "Mounting EFI partition: ${partition} -> ${mount_point}/efi"
    run mkdir -p "${mount_point}/efi"
    run mount "${partition}" "${mount_point}/efi"
}

# Unmount all installation mounts
unmount_all() {
    local mount_point="${1:-${MOUNT_POINT}}"

    log_info "Unmounting all filesystems"

    # Unmount in reverse order
    local mounts
    mounts="$(findmnt -R -l -n -o TARGET "${mount_point}" 2>/dev/null | tac || true)"

    while IFS= read -r mnt; do
        if [[ -n "${mnt}" ]]; then
            log_debug "Unmounting: ${mnt}"
            run umount -l "${mnt}" 2>/dev/null || true
        fi
    done <<< "${mounts}"
}

# Create swapfile for hibernation
create_swapfile() {
    local mount_point="$1"
    local size="$2"

    log_info "Creating swapfile: ${size}"

    local swapfile="${mount_point}/swap/swapfile"

    # Create swapfile with proper attributes
    run truncate -s 0 "${swapfile}"
    run chattr +C "${swapfile}"
    run fallocate -l "${size}" "${swapfile}"
    run chmod 600 "${swapfile}"
    run mkswap "${swapfile}"
}

# Get swapfile offset for resume (hibernation)
get_swapfile_offset() {
    local swapfile="$1"

    if command_exists filefrag; then
        filefrag -v "${swapfile}" 2>/dev/null | \
            awk 'NR==4 {print $4}' | \
            sed 's/\.\.//' || echo ""
    fi
}

# Check if device is mounted
is_mounted() {
    local device="$1"
    findmnt -n "${device}" &>/dev/null
}

# Get device by label
get_device_by_label() {
    local label="$1"
    blkid -L "${label}" 2>/dev/null || true
}

# Get device by UUID
get_device_by_uuid() {
    local uuid="$1"
    blkid -U "${uuid}" 2>/dev/null || true
}

# Add cleanup handler for disk unmounting
add_disk_cleanup() {
    add_cleanup "unmount_all ${MOUNT_POINT}"
    add_cleanup "luks_close cryptsecrets"
    add_cleanup "luks_close cryptroot"
}
