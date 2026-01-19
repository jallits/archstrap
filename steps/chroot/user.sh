#!/bin/bash
# steps/chroot/user.sh - User setup in chroot
# This script is executed inside the chroot environment

set -euo pipefail

main() {
    local username="${1:-}"

    if [[ -z "${username}" ]]; then
        echo "ERROR: Username required"
        exit 1
    fi

    echo "Setting up user ${username} in chroot..."

    # Ensure user home exists
    if [[ ! -d "/home/${username}" ]]; then
        echo "ERROR: Home directory not found for ${username}"
        exit 1
    fi

    # Setup XDG directories
    su - "${username}" -c "xdg-user-dirs-update"

    # Set correct ownership
    chown -R "${username}:${username}" "/home/${username}"

    echo "User setup complete"
}

main "$@"
