#!/bin/bash
# lib/common.sh - Shared utilities for archstrap
# shellcheck disable=SC2034

set -euo pipefail

# Colors (disabled if not interactive)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    BOLD=''
    RESET=''
fi

# Global variables
declare -g DRY_RUN="${DRY_RUN:-0}"
declare -g VERBOSE="${VERBOSE:-0}"
declare -g LOG_FILE="${LOG_FILE:-/tmp/archstrap.log}"

# Logging functions
log_info() {
    local msg="$1"
    echo -e "${GREEN}[INFO]${RESET} ${msg}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ${msg}" >> "${LOG_FILE}"
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}[WARN]${RESET} ${msg}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] ${msg}" >> "${LOG_FILE}"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR]${RESET} ${msg}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] ${msg}" >> "${LOG_FILE}"
}

log_debug() {
    local msg="$1"
    if [[ "${VERBOSE}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${RESET} ${msg}"
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] ${msg}" >> "${LOG_FILE}"
}

log_step() {
    local step="$1"
    local desc="$2"
    echo -e "\n${BOLD}${BLUE}==> ${step}: ${desc}${RESET}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] ${step}: ${desc}" >> "${LOG_FILE}"
}

# Run command with dry-run support
run() {
    local cmd=("$@")

    if [[ "${DRY_RUN}" == "1" ]]; then
        echo -e "${MAGENTA}[DRY-RUN]${RESET} ${cmd[*]}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DRY-RUN] ${cmd[*]}" >> "${LOG_FILE}"
        return 0
    fi

    log_debug "Executing: ${cmd[*]}"
    "${cmd[@]}"
}

# Run command with dry-run support (destructive operations highlighted)
run_destructive() {
    local cmd=("$@")

    if [[ "${DRY_RUN}" == "1" ]]; then
        echo -e "${RED}[DRY-RUN] [DESTRUCTIVE]${RESET} ${cmd[*]}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DRY-RUN] [DESTRUCTIVE] ${cmd[*]}" >> "${LOG_FILE}"
        return 0
    fi

    log_debug "Executing (destructive): ${cmd[*]}"
    "${cmd[@]}"
}

# Check if running as root
require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Prompt for yes/no confirmation
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"
    local response

    if [[ "${DRY_RUN}" == "1" ]]; then
        log_debug "Auto-confirming in dry-run mode: ${prompt}"
        return 0
    fi

    if [[ "${default}" == "y" ]]; then
        prompt="${prompt} [Y/n] "
    else
        prompt="${prompt} [y/N] "
    fi

    read -r -p "${prompt}" response
    response="${response:-${default}}"

    case "${response}" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Prompt for input with default value
prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local response

    if [[ -n "${default}" ]]; then
        read -r -p "${prompt} [${default}]: " response
        echo "${response:-${default}}"
    else
        read -r -p "${prompt}: " response
        echo "${response}"
    fi
}

# Prompt for password (hidden input)
prompt_password() {
    local prompt="${1:-Password}"
    local password
    local confirm

    while true; do
        read -r -s -p "${prompt}: " password
        echo
        read -r -s -p "Confirm ${prompt}: " confirm
        echo

        if [[ "${password}" == "${confirm}" ]]; then
            if [[ -z "${password}" ]]; then
                log_warn "Password cannot be empty"
                continue
            fi
            echo "${password}"
            return 0
        else
            log_warn "Passwords do not match, please try again"
        fi
    done
}

# Prompt for selection from list
prompt_select() {
    local prompt="$1"
    shift
    local options=("$@")
    local selection

    echo "${prompt}"
    for i in "${!options[@]}"; do
        echo "  $((i + 1))) ${options[i]}"
    done

    while true; do
        read -r -p "Selection [1-${#options[@]}]: " selection
        if [[ "${selection}" =~ ^[0-9]+$ ]] && \
           [[ "${selection}" -ge 1 ]] && \
           [[ "${selection}" -le "${#options[@]}" ]]; then
            echo "${options[$((selection - 1))]}"
            return 0
        fi
        log_warn "Invalid selection, please enter a number between 1 and ${#options[@]}"
    done
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Wait for a condition with timeout
wait_for() {
    local condition="$1"
    local timeout="${2:-30}"
    local interval="${3:-1}"
    local elapsed=0

    while ! eval "${condition}"; do
        if [[ "${elapsed}" -ge "${timeout}" ]]; then
            return 1
        fi
        sleep "${interval}"
        elapsed=$((elapsed + interval))
    done
    return 0
}

# Get script directory
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [[ -h "${source}" ]]; do
        local dir
        dir="$(cd -P "$(dirname "${source}")" && pwd)"
        source="$(readlink "${source}")"
        [[ "${source}" != /* ]] && source="${dir}/${source}"
    done
    cd -P "$(dirname "${source}")" && pwd
}

# Cleanup handler
cleanup_handlers=()

add_cleanup() {
    cleanup_handlers+=("$1")
}

run_cleanup() {
    log_debug "Running cleanup handlers..."
    for handler in "${cleanup_handlers[@]}"; do
        log_debug "Running cleanup: ${handler}"
        eval "${handler}" || true
    done
}

# Error handler
error_handler() {
    local line_no="$1"
    local error_code="$2"
    log_error "Error on line ${line_no} (exit code: ${error_code})"
    run_cleanup
    exit "${error_code}"
}

# Signal handler for graceful interruption
interrupt_handler() {
    echo
    log_warn "Installation interrupted by user"
    run_cleanup
    exit 130
}

# Setup traps
setup_traps() {
    trap 'error_handler ${LINENO} $?' ERR
    trap 'interrupt_handler' INT TERM
}

# Human readable size
human_size() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0

    while [[ "${bytes}" -ge 1024 ]] && [[ "${unit}" -lt 4 ]]; do
        bytes=$((bytes / 1024))
        unit=$((unit + 1))
    done

    echo "${bytes}${units[unit]}"
}

# Check if running in Arch ISO environment
is_arch_iso() {
    [[ -f /run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux ]] || \
    [[ -d /run/archiso ]]
}

# Print a separator line
print_separator() {
    local char="${1:--}"
    local width="${2:-60}"
    printf '%*s\n' "${width}" '' | tr ' ' "${char}"
}

# Print banner
print_banner() {
    echo -e "${BOLD}${BLUE}"
    echo "    _             _         _                   "
    echo "   / \\   _ __ ___| |__  ___| |_ _ __ __ _ _ __  "
    echo "  / _ \\ | '__/ __| '_ \\/ __| __| '__/ _\` | '_ \\ "
    echo " / ___ \\| | | (__| | | \\__ \\ |_| | | (_| | |_) |"
    echo "/_/   \\_\\_|  \\___|_| |_|___/\\__|_|  \\__,_| .__/ "
    echo "                                         |_|    "
    echo -e "${RESET}"
    echo "Modern, opinionated Arch Linux installer"
    print_separator
}
