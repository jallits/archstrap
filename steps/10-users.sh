#!/bin/bash
# steps/10-users.sh - User creation with ZSH and home subvolumes

set -euo pipefail

run_step() {
    step_start "10-users" "Creating users"

    local username
    username="$(config_get username)"

    local user_password
    user_password="$(config_get user_password)"

    # Create user with ZSH as default shell
    # User is added to wheel group for sudo access
    log_info "Creating user: ${username} (with sudo privileges)"
    run arch-chroot "${MOUNT_POINT}" useradd -m -G wheel -s /bin/zsh "${username}"

    # Set user password
    log_info "Setting password for ${username}"
    if [[ "${DRY_RUN}" != "1" ]]; then
        echo "${username}:${user_password}" | arch-chroot "${MOUNT_POINT}" chpasswd
    else
        echo -e "${MAGENTA}[DRY-RUN]${RESET} Setting user password"
    fi

    # Configure sudo for wheel group
    log_info "Configuring sudo access for wheel group"
    if [[ "${DRY_RUN}" != "1" ]]; then
        # Uncomment wheel group line in sudoers
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' \
            "${MOUNT_POINT}/etc/sudoers"
    fi

    # Lock root account (security best practice per Arch Wiki)
    # Users should use sudo instead of logging in as root
    log_info "Locking root account (use sudo for administrative tasks)"
    run arch-chroot "${MOUNT_POINT}" passwd --lock root

    # Create home directory as BTRFS subvolume for snapshots
    log_info "Setting up home directory as BTRFS subvolume"
    local home_dir="${MOUNT_POINT}/home/${username}"

    if [[ "${DRY_RUN}" != "1" ]]; then
        # Home was created by useradd, but we want it as a subvolume
        # Move existing home contents
        local temp_home="/tmp/home_${username}_temp"
        mv "${home_dir}" "${temp_home}" 2>/dev/null || true

        # Create subvolume for user's home
        btrfs subvolume create "${home_dir}"

        # Create .snapshots subvolume inside user's home for snapper
        log_info "Creating user snapshot subvolume"
        btrfs subvolume create "${home_dir}/.snapshots"

        # Restore contents if any
        if [[ -d "${temp_home}" ]]; then
            cp -a "${temp_home}/." "${home_dir}/"
            rm -rf "${temp_home}"
        fi

        # Fix ownership - user owns their home and snapshots
        arch-chroot "${MOUNT_POINT}" chown -R "${username}:${username}" "/home/${username}"
        # .snapshots needs special permissions for snapper
        chmod 750 "${home_dir}/.snapshots"
    fi

    # Configure snapper for user's home directory
    log_info "Configuring snapper for ${username}'s home directory"
    if [[ "${DRY_RUN}" != "1" ]]; then
        mkdir -p "${MOUNT_POINT}/etc/snapper/configs"

        # Create snapper config from template
        sed -e "s|__SUBVOLUME__|/home/${username}|g" \
            -e "s|__USERNAME__|${username}|g" \
            "${SCRIPT_DIR}/configs/snapper/user-home.conf" \
            > "${MOUNT_POINT}/etc/snapper/configs/${username}"

        # Add config to snapper's config list
        local snapper_configs
        if [[ -f "${MOUNT_POINT}/etc/conf.d/snapper" ]]; then
            # Append to existing configs
            snapper_configs=$(grep '^SNAPPER_CONFIGS=' "${MOUNT_POINT}/etc/conf.d/snapper" | sed 's/SNAPPER_CONFIGS="\(.*\)"/\1/')
            snapper_configs="${snapper_configs} ${username}"
        else
            snapper_configs="${username}"
        fi
        mkdir -p "${MOUNT_POINT}/etc/conf.d"
        echo "SNAPPER_CONFIGS=\"root ${snapper_configs}\"" > "${MOUNT_POINT}/etc/conf.d/snapper"

        log_info "User ${username} can manage their own snapshots with 'snapper -c ${username}'"
    fi

    # Setup XDG user directories
    log_info "Configuring XDG user directories"
    if [[ "${DRY_RUN}" != "1" ]]; then
        # Install xdg-user-dirs if not present
        arch-chroot "${MOUNT_POINT}" pacman -S --noconfirm --needed xdg-user-dirs

        # Create XDG directories for user
        arch-chroot "${MOUNT_POINT}" su - "${username}" -c "xdg-user-dirs-update"
    fi

    # Create basic ZSH configuration
    log_info "Setting up ZSH configuration"
    if [[ "${DRY_RUN}" != "1" ]]; then
        cat > "${MOUNT_POINT}/home/${username}/.zshrc" << 'EOF'
# Basic ZSH configuration
autoload -Uz compinit promptinit
compinit
promptinit

# History settings
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
setopt sharehistory
setopt hist_ignore_dups

# Enable completion
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# Key bindings
bindkey -e
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Aliases
alias ls='ls --color=auto'
alias ll='ls -la'
alias grep='grep --color=auto'

# Prompt
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '
EOF
        arch-chroot "${MOUNT_POINT}" chown "${username}:${username}" "/home/${username}/.zshrc"
    fi

    # Set ZSH as default shell for root as well
    run arch-chroot "${MOUNT_POINT}" chsh -s /bin/zsh root

    # Configure secrets storage if enabled
    if [[ "$(config_get secrets_on_removable)" == "1" ]]; then
        log_info "Configuring encrypted secrets storage for ${username}"

        if [[ "${DRY_RUN}" != "1" ]]; then
            local secrets_uuid
            secrets_uuid="$(state_get secrets_uuid)"
            local secrets_mount="/home/${username}/.secrets"

            # Create mount point
            mkdir -p "${MOUNT_POINT}${secrets_mount}"
            arch-chroot "${MOUNT_POINT}" chown "${username}:${username}" "${secrets_mount}"
            chmod 700 "${MOUNT_POINT}${secrets_mount}"

            # Add crypttab entry for secrets partition
            # If same passphrase as root, it will be unlocked in sequence
            # If different passphrase, user will be prompted
            local crypttab_opts="luks,noauto,nofail"
            if [[ "$(config_get secrets_separate_passphrase)" != "1" ]]; then
                # Same passphrase - can be unlocked automatically after root
                crypttab_opts="luks,nofail"
            fi
            echo "cryptsecrets UUID=${secrets_uuid} none ${crypttab_opts}" >> \
                "${MOUNT_POINT}/etc/crypttab"

            # Add fstab entry for secrets mount
            echo "# Encrypted secrets storage on removable device" >> "${MOUNT_POINT}/etc/fstab"
            echo "/dev/mapper/cryptsecrets ${secrets_mount} ext4 defaults,noauto,nofail,user 0 2" >> \
                "${MOUNT_POINT}/etc/fstab"

            # Create systemd mount unit for automatic mounting
            mkdir -p "${MOUNT_POINT}/etc/systemd/system"
            local mount_unit_name
            mount_unit_name="$(systemd-escape --path "${secrets_mount}").mount"

            cat > "${MOUNT_POINT}/etc/systemd/system/${mount_unit_name}" << EOF
[Unit]
Description=Encrypted Secrets Storage
After=systemd-cryptsetup@cryptsecrets.service
Requires=systemd-cryptsetup@cryptsecrets.service
ConditionPathExists=/dev/mapper/cryptsecrets

[Mount]
What=/dev/mapper/cryptsecrets
Where=${secrets_mount}
Type=ext4
Options=defaults,noatime

[Install]
WantedBy=multi-user.target
EOF

            # Create directory structure inside secrets (during installation while mounted)
            # The secrets partition is currently open at /dev/mapper/cryptsecrets
            local tmp_secrets="/tmp/secrets_mount"
            mkdir -p "${tmp_secrets}"
            mount /dev/mapper/cryptsecrets "${tmp_secrets}"

            # Create directories for sensitive data
            mkdir -p "${tmp_secrets}/gnupg"
            mkdir -p "${tmp_secrets}/ssh"
            mkdir -p "${tmp_secrets}/password-store"

            # Set ownership
            local user_uid user_gid
            user_uid=$(arch-chroot "${MOUNT_POINT}" id -u "${username}")
            user_gid=$(arch-chroot "${MOUNT_POINT}" id -g "${username}")
            chown -R "${user_uid}:${user_gid}" "${tmp_secrets}"

            # Set secure permissions
            chmod 700 "${tmp_secrets}/gnupg"
            chmod 700 "${tmp_secrets}/ssh"
            chmod 700 "${tmp_secrets}/password-store"

            umount "${tmp_secrets}"
            rmdir "${tmp_secrets}"

            # Create symlinks from user's home to secrets storage
            # These will work when the secrets partition is mounted
            log_info "Creating symlinks for GPG and SSH"

            # Remove any existing directories (from skeleton)
            rm -rf "${MOUNT_POINT}/home/${username}/.gnupg" 2>/dev/null || true
            rm -rf "${MOUNT_POINT}/home/${username}/.ssh" 2>/dev/null || true
            rm -rf "${MOUNT_POINT}/home/${username}/.password-store" 2>/dev/null || true

            # Create symlinks
            ln -s ".secrets/gnupg" "${MOUNT_POINT}/home/${username}/.gnupg"
            ln -s ".secrets/ssh" "${MOUNT_POINT}/home/${username}/.ssh"
            ln -s ".secrets/password-store" "${MOUNT_POINT}/home/${username}/.password-store"

            # Fix symlink ownership
            arch-chroot "${MOUNT_POINT}" chown -h "${username}:${username}" \
                "/home/${username}/.gnupg" \
                "/home/${username}/.ssh" \
                "/home/${username}/.password-store"

            log_info "Secrets storage configured at ${secrets_mount}"
            log_info "GPG, SSH, and password-store will use encrypted removable storage"
        else
            echo -e "${MAGENTA}[DRY-RUN]${RESET} Would configure secrets storage for ${username}"
        fi
    fi

    state_save
    log_info "User creation complete"
}
