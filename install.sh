#!/bin/bash
# install.sh - Main entry point for archstrap
# Modern, opinionated Arch Linux installer

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library modules
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/disk.sh
source "${SCRIPT_DIR}/lib/disk.sh"
# shellcheck source=lib/hardware.sh
source "${SCRIPT_DIR}/lib/hardware.sh"
# shellcheck source=lib/network.sh
source "${SCRIPT_DIR}/lib/network.sh"
# shellcheck source=lib/tui.sh
source "${SCRIPT_DIR}/lib/tui.sh"
# shellcheck source=lib/quirks.sh
source "${SCRIPT_DIR}/lib/quirks.sh"

# Installation steps in order
STEPS=(
    "00-preflight"
    "01-configure"
    "02-partition"
    "03-encryption"
    "04-filesystem"
    "05-mount"
    "06-pacstrap"
    "07-fstab"
    "08-chroot-prep"
    "09-locale"
    "10-users"
    "11-hardware"
    "11a-quirks"
    "12-network"
    "13-boot"
    "14-aur"
    "15-finalize"
)

# Print usage
usage() {
    cat << EOF
Usage: ${0##*/} [OPTIONS]

Modern, opinionated Arch Linux installer

Options:
    -h, --help      Show this help message
    -d, --dry-run   Show what would be done without making changes
    -r, --resume    Resume from a previous interrupted installation
    -v, --verbose   Enable verbose output
    --no-color      Disable colored output

Environment variables:
    DRY_RUN         Set to 1 to enable dry-run mode
    VERBOSE         Set to 1 to enable verbose output
    LOG_FILE        Log file location (default: /tmp/archstrap.log)

For more information, visit: https://github.com/jallits/archstrap
EOF
}

# Parse command line arguments
parse_args() {
    local resume=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=1
                log_info "Dry-run mode enabled"
                shift
                ;;
            -r|--resume)
                resume=1
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            --no-color)
                RED=''
                GREEN=''
                YELLOW=''
                BLUE=''
                MAGENTA=''
                CYAN=''
                BOLD=''
                RESET=''
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    echo "${resume}"
}

# Execute a step
execute_step() {
    local step="$1"
    local step_file="${SCRIPT_DIR}/steps/${step}.sh"

    if [[ ! -f "${step_file}" ]]; then
        log_error "Step file not found: ${step_file}"
        return 1
    fi

    # Check if step is already completed (resume mode)
    if step_is_complete "${step}"; then
        log_info "Skipping completed step: ${step}"
        return 0
    fi

    # Source and execute the step
    # shellcheck source=/dev/null
    source "${step_file}"

    # Each step file should define a run_step function
    if declare -f run_step > /dev/null; then
        run_step
        unset -f run_step
    else
        log_error "Step ${step} does not define run_step function"
        return 1
    fi

    step_complete "${step}"
}

# Main installation flow
main() {
    local resume
    resume=$(parse_args "$@")

    # Setup error handling
    setup_traps

    # Print banner
    print_banner

    # Ensure running as root
    require_root

    # Initialize configuration
    config_init

    # Handle resume mode
    if [[ "${resume}" == "1" ]]; then
        if state_load; then
            config_load || true
            if ! state_validate; then
                log_error "Cannot resume: invalid state"
                log_info "Starting fresh installation..."
                state_clear
            fi
        else
            log_warn "No previous state found, starting fresh installation"
        fi
    fi

    # Log start
    log_info "Starting Arch Linux installation"
    log_info "Log file: ${LOG_FILE}"

    if [[ "${DRY_RUN}" == "1" ]]; then
        log_warn "DRY-RUN MODE: No changes will be made"
    fi

    # Execute all steps
    for step in "${STEPS[@]}"; do
        execute_step "${step}"
    done

    # Clear state on successful completion
    state_clear

    print_separator "="
    echo -e "${BOLD}${GREEN}Installation complete!${RESET}"
    print_separator "="
    echo
    echo "Your new Arch Linux system is ready."
    echo "Remove the installation media and reboot."
    echo
    if [[ "${DRY_RUN}" != "1" ]]; then
        if confirm "Reboot now?" "n"; then
            run reboot
        fi
    fi
}

main "$@"
