#!/bin/bash
# steps/chroot/boot.sh - Boot configuration in chroot
# This script is executed inside the chroot environment

set -euo pipefail

main() {
    echo "Configuring boot in chroot..."

    # Regenerate initramfs
    mkinitcpio -P

    # Verify UKI was created
    if [[ -f /efi/EFI/Linux/arch-linux.efi ]]; then
        echo "UKI created successfully"
        ls -la /efi/EFI/Linux/
    else
        echo "ERROR: UKI not found!"
        exit 1
    fi

    echo "Boot configuration complete"
}

main "$@"
