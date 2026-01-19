#!/bin/bash
# steps/chroot/base.sh - Base chroot setup
# This script is executed inside the chroot environment

set -euo pipefail

# Source common library if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../../lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/../../lib/common.sh"
fi

main() {
    echo "Running base chroot setup..."

    # Initialize pacman keyring
    pacman-key --init
    pacman-key --populate archlinux

    # Update system
    pacman -Syu --noconfirm

    echo "Base chroot setup complete"
}

main "$@"
