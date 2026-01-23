#!/bin/bash
# steps/01-configure.sh - Interactive configuration with TUI

set -euo pipefail

# Password confirmation helper
get_confirmed_password() {
    local title="$1"
    local prompt="$2"
    local password=""
    local confirm=""

    while true; do
        password=$(tui_passwordbox "${title}" "${prompt}") || return 1

        if [[ -z "${password}" ]]; then
            tui_msgbox "Error" "Password cannot be empty." 8 40
            continue
        fi

        confirm=$(tui_passwordbox "${title}" "Confirm password:") || return 1

        if [[ "${password}" == "${confirm}" ]]; then
            echo "${password}"
            return 0
        else
            tui_msgbox "Error" "Passwords do not match. Please try again." 8 50
        fi
    done
}

run_step() {
    step_start "01-configure" "Gathering configuration"

    # Initialize TUI
    tui_init

    # Welcome screen
    tui_welcome

    # ==========================================
    # DISK CONFIGURATION
    # ==========================================

    # Target disk selection
    local target_disk
    target_disk=$(tui_select_disk "Select the target disk for Arch Linux installation:") || {
        tui_error "No disk selected. Installation cancelled."
        exit 1
    }
    config_set "target_disk" "${target_disk}"
    state_set "target_disk" "${target_disk}"

    # Check for removable disks
    local -a removable_disks=()
    while IFS= read -r disk; do
        [[ -n "${disk}" ]] && removable_disks+=("${disk}")
    done < <(get_removable_disks)

    # EFI partition location
    if [[ ${#removable_disks[@]} -gt 0 ]]; then
        if tui_yesno "EFI Partition" \
            "Removable storage detected.\n\nWould you like to install the EFI partition on removable storage?\n\nThis allows booting only when the USB/SD card is inserted." \
            "no" 12 65; then
            config_set "efi_on_removable" "1"

            # Build menu for removable disks
            local -a efi_menu=()
            for disk in "${removable_disks[@]}"; do
                local size
                size=$(lsblk -dno SIZE "${disk}" 2>/dev/null || echo "Unknown")
                efi_menu+=("${disk}" "${size}")
            done

            local efi_disk
            efi_disk=$(tui_menu "EFI Disk" "Select removable disk for EFI partition:" \
                       15 60 5 "${efi_menu[@]}") || {
                config_set "efi_on_removable" "0"
                config_set "efi_disk" "${target_disk}"
            }
            [[ -n "${efi_disk}" ]] && config_set "efi_disk" "${efi_disk}"
        else
            config_set "efi_on_removable" "0"
            config_set "efi_disk" "${target_disk}"
        fi
    else
        config_set "efi_on_removable" "0"
        config_set "efi_disk" "${target_disk}"
    fi

    # LUKS header location
    if [[ ${#removable_disks[@]} -gt 0 ]]; then
        if tui_yesno "LUKS Header" \
            "Would you like to store the LUKS encryption header on removable storage?\n\nThis provides additional security - the disk cannot be decrypted without the removable device." \
            "no" 12 65; then
            config_set "luks_header_on_removable" "1"

            local -a header_menu=()
            for disk in "${removable_disks[@]}"; do
                local size
                size=$(lsblk -dno SIZE "${disk}" 2>/dev/null || echo "Unknown")
                header_menu+=("${disk}" "${size}")
            done

            local header_disk
            header_disk=$(tui_menu "LUKS Header Disk" \
                         "Select removable disk for LUKS header:" \
                         15 60 5 "${header_menu[@]}") || {
                config_set "luks_header_on_removable" "0"
            }
            [[ -n "${header_disk}" ]] && config_set "luks_header_disk" "${header_disk}"
        else
            config_set "luks_header_on_removable" "0"
        fi
    else
        config_set "luks_header_on_removable" "0"
    fi

    # Encrypted secrets partition on removable storage
    # Only offer if EFI is on removable (so there's remaining space to use)
    config_set "secrets_on_removable" "0"
    if [[ "$(config_get efi_on_removable)" == "1" ]]; then
        if tui_yesno "Encrypted Secrets Storage" \
            "Would you like to create an encrypted partition for sensitive data on the removable device?\n\nThis partition will use remaining space on the EFI disk for:\n• GPG keys (~/.gnupg)\n• SSH keys (~/.ssh)\n• Other sensitive files\n\nThe secrets partition requires the removable device to access these files." \
            "yes" 16 65; then
            config_set "secrets_on_removable" "1"

            # Ask about separate passphrase
            if tui_yesno "Secrets Passphrase" \
                "Use a separate passphrase for the secrets partition?\n\nRecommended: Use the same passphrase for convenience.\nOptional: Use a different passphrase for extra security." \
                "no" 12 60; then
                local secrets_passphrase
                secrets_passphrase=$(get_confirmed_password "Secrets Encryption" \
                    "Enter passphrase for secrets partition:") || {
                    tui_msgbox "Warning" "Using system encryption passphrase for secrets." 8 50
                    config_set "secrets_separate_passphrase" "0"
                }
                if [[ -n "${secrets_passphrase:-}" ]]; then
                    config_set "secrets_passphrase" "${secrets_passphrase}"
                    config_set "secrets_separate_passphrase" "1"
                fi
            else
                config_set "secrets_separate_passphrase" "0"
            fi
        fi
    fi

    # ==========================================
    # ENCRYPTION
    # ==========================================

    local passphrase
    passphrase=$(get_confirmed_password "Disk Encryption" \
        "Enter encryption passphrase:\n\nThis will be used to unlock your system at boot.") || {
        tui_error "Encryption passphrase is required."
        exit 1
    }
    config_set "luks_passphrase" "${passphrase}"

    # Encryption strength
    local encryption_strength
    encryption_strength=$(tui_radiolist "Encryption Strength" \
        "Select encryption strength for LUKS2:\n\nHigher strength increases unlock time but provides better security." \
        18 70 6 \
        "standard" "AES-256, Argon2id (default settings)" "on" \
        "high" "AES-256, Argon2id (4GB memory, 5s unlock)" "off" \
        "maximum" "AES-256 + HMAC integrity, Argon2id (4GB, 5s)" "off") || {
        encryption_strength="standard"
    }
    config_set "encryption_strength" "${encryption_strength}"

    # Warn about maximum encryption performance impact
    if [[ "${encryption_strength}" == "maximum" ]]; then
        tui_msgbox "Performance Notice" \
            "Maximum encryption enables dm-integrity for authenticated encryption.\n\nThis provides:\n• Protection against disk tampering\n• Cryptographic integrity verification\n\nTrade-offs:\n• ~2x disk space overhead for integrity metadata\n• Reduced I/O performance\n• Requires kernel dm-integrity support" \
            14 65
    fi

    # ==========================================
    # SYSTEM CONFIGURATION
    # ==========================================

    # Hostname
    local hostname
    while true; do
        hostname=$(tui_inputbox "Hostname" "Enter system hostname:" "archlinux") || {
            tui_error "Hostname is required."
            continue
        }
        if validate_hostname "${hostname}"; then
            config_set "hostname" "${hostname}"
            break
        else
            tui_msgbox "Invalid Hostname" \
                "Hostname must:\n• Start with a letter or number\n• Contain only letters, numbers, and hyphens\n• Be 1-63 characters long" \
                12 50
        fi
    done

    # Username
    local username
    while true; do
        username=$(tui_inputbox "Username" \
            "Enter username for the primary account:\n\nThis user will have sudo privileges." "") || {
            tui_error "Username is required."
            continue
        }
        if [[ -z "${username}" ]]; then
            tui_msgbox "Error" "Username cannot be empty." 8 40
            continue
        fi
        if validate_username "${username}"; then
            config_set "username" "${username}"
            break
        else
            tui_msgbox "Invalid Username" \
                "Username must:\n• Start with a lowercase letter\n• Contain only lowercase letters, numbers, hyphens, underscores\n• Be 1-32 characters long" \
                12 55
        fi
    done

    # User password
    local user_password
    user_password=$(get_confirmed_password "User Password" \
        "Enter password for '${username}':\n\nThis user will have sudo privileges.\nRoot account will be locked.") || {
        tui_error "User password is required."
        exit 1
    }
    config_set "user_password" "${user_password}"

    # Timezone
    local detected_tz
    detected_tz=$(detect_timezone)
    local timezone

    if tui_yesno "Timezone" \
        "Detected timezone: ${detected_tz}\n\nUse this timezone?" \
        "yes" 10 50; then
        timezone="${detected_tz}"
    else
        timezone=$(tui_inputbox "Timezone" \
            "Enter timezone (e.g., America/New_York):" "${detected_tz}") || {
            timezone="${detected_tz}"
        }
        if [[ ! -f "/usr/share/zoneinfo/${timezone}" ]]; then
            tui_msgbox "Warning" "Invalid timezone. Using UTC." 8 40
            timezone="UTC"
        fi
    fi
    config_set "timezone" "${timezone}"

    # Locale
    local locale
    locale=$(tui_inputbox "Locale" "Enter system locale:" "en_US.UTF-8") || {
        locale="en_US.UTF-8"
    }
    config_set "locale" "${locale}"

    # Keymap
    local keymap
    keymap=$(tui_inputbox "Keyboard" "Enter keyboard layout:" "us") || {
        keymap="us"
    }
    config_set "keymap" "${keymap}"

    # ==========================================
    # PACKAGES
    # ==========================================

    # AUR helper
    local aur_helper
    aur_helper=$(tui_radiolist "AUR Helper" \
        "Select an AUR helper to install:" \
        15 60 5 \
        "paru" "Feature-rich AUR helper written in Rust" "on" \
        "yay" "Yet Another Yogurt - AUR helper in Go" "off" \
        "none" "Don't install an AUR helper" "off") || {
        aur_helper="paru"
    }
    config_set "aur_helper" "${aur_helper}"

    # ==========================================
    # SECURITY OPTIONS
    # ==========================================

    tui_msgbox "Security Configuration" \
        "The following options configure security hardening per Arch Wiki recommendations.\n\nDefaults are set for maximum security." \
        10 60

    # Hardened kernel
    if tui_yesno "Hardened Kernel" \
        "Use linux-hardened kernel?\n\nProvides:\n• Enhanced ASLR entropy\n• Kernel exploit mitigations\n• Restricted unprivileged user namespaces\n\nRecommended for security." \
        "yes" 14 60; then
        config_set "use_hardened_kernel" "1"
    else
        config_set "use_hardened_kernel" "0"
    fi

    # Firewall
    if tui_yesno "Firewall" \
        "Enable nftables firewall?\n\nConfigures:\n• Deny all inbound connections by default\n• Allow established/related connections\n• Allow all outbound connections\n\nRecommended for security." \
        "yes" 14 60; then
        config_set "enable_firewall" "1"
    else
        config_set "enable_firewall" "0"
    fi

    # AppArmor
    if tui_yesno "AppArmor" \
        "Enable AppArmor Mandatory Access Control?\n\nProvides:\n• Application sandboxing\n• Path-based access control\n• Protection against unknown vulnerabilities\n\nRecommended for security." \
        "yes" 14 60; then
        config_set "enable_apparmor" "1"
    else
        config_set "enable_apparmor" "0"
    fi

    # ==========================================
    # HARDWARE DETECTION
    # ==========================================

    tui_infobox "Hardware Detection" "Detecting hardware..." 5 40
    sleep 1

    if detect_audio; then
        config_set "install_audio" "1"
    else
        config_set "install_audio" "0"
    fi

    if detect_bluetooth; then
        config_set "install_bluetooth" "1"
    else
        config_set "install_bluetooth" "0"
    fi

    if detect_fingerprint; then
        config_set "install_fingerprint" "1"
        log_debug "Fingerprint reader detected"
    else
        config_set "install_fingerprint" "0"
    fi

    if detect_thunderbolt; then
        config_set "install_thunderbolt" "1"
        log_debug "Thunderbolt controller detected"
    else
        config_set "install_thunderbolt" "0"
    fi

    if detect_sensors; then
        config_set "install_sensors" "1"
        log_debug "IIO sensors detected"
    else
        config_set "install_sensors" "0"
    fi

    if detect_laptop; then
        config_set "install_power" "1"
        log_debug "Laptop detected - will install power management"
    else
        config_set "install_power" "0"
    fi

    if detect_smartcard; then
        config_set "install_smartcard" "1"
        log_debug "Smart card reader detected"
    else
        config_set "install_smartcard" "0"
    fi

    if detect_touchscreen; then
        config_set "has_touchscreen" "1"
        log_debug "Touchscreen detected"
    else
        config_set "has_touchscreen" "0"
    fi

    # ==========================================
    # CONFIRMATION
    # ==========================================

    # Save configuration
    config_save

    # Build summary
    local summary=""
    summary+="DISK CONFIGURATION\n"
    summary+="══════════════════════════════════════\n"
    summary+="Target disk:     $(config_get target_disk)\n"
    if [[ "$(config_get efi_on_removable)" == "1" ]]; then
        summary+="EFI partition:   $(config_get efi_disk) (removable)\n"
    else
        summary+="EFI partition:   $(config_get target_disk)\n"
    fi
    if [[ "$(config_get luks_header_on_removable)" == "1" ]]; then
        summary+="LUKS header:     $(config_get luks_header_disk) (removable)\n"
    else
        summary+="LUKS header:     On root partition\n"
    fi
    local enc_strength
    enc_strength="$(config_get encryption_strength)"
    case "${enc_strength}" in
        high)    summary+="Encryption:      High (Argon2id 4GB/5s)\n" ;;
        maximum) summary+="Encryption:      Maximum (integrity + Argon2id)\n" ;;
        *)       summary+="Encryption:      Standard\n" ;;
    esac
    if [[ "$(config_get secrets_on_removable)" == "1" ]]; then
        summary+="Secrets storage: $(config_get efi_disk) (encrypted)\n"
    fi
    summary+="\n"
    summary+="SYSTEM CONFIGURATION\n"
    summary+="══════════════════════════════════════\n"
    summary+="Hostname:        $(config_get hostname)\n"
    summary+="Username:        $(config_get username)\n"
    summary+="Timezone:        $(config_get timezone)\n"
    summary+="Locale:          $(config_get locale)\n"
    summary+="AUR helper:      $(config_get aur_helper)\n"
    summary+="\n"
    summary+="SECURITY OPTIONS\n"
    summary+="══════════════════════════════════════\n"
    if [[ "$(config_get use_hardened_kernel)" == "1" ]]; then
        summary+="Kernel:          linux-hardened\n"
    else
        summary+="Kernel:          linux\n"
    fi
    if [[ "$(config_get enable_firewall)" == "1" ]]; then
        summary+="Firewall:        Enabled\n"
    else
        summary+="Firewall:        Disabled\n"
    fi
    if [[ "$(config_get enable_apparmor)" == "1" ]]; then
        summary+="AppArmor:        Enabled\n"
    else
        summary+="AppArmor:        Disabled\n"
    fi

    # Confirm installation
    if ! tui_confirm_install "${summary}"; then
        tui_cleanup
        log_info "Installation cancelled by user"
        exit 0
    fi

    tui_cleanup
    log_info "Configuration complete"
}
