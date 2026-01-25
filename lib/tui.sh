#!/bin/bash
# lib/tui.sh - Text User Interface using pure bash
# No external dependencies (dialog not required)

set -euo pipefail

# Return codes (compatible with dialog)
export DIALOG_OK=0
export DIALOG_CANCEL=1
export DIALOG_ESC=255

# ANSI color codes (using $'...' for proper escape sequence interpretation)
TUI_RESET=$'\033[0m'
TUI_BOLD=$'\033[1m'
TUI_DIM=$'\033[2m'
TUI_BLUE=$'\033[34m'
TUI_CYAN=$'\033[36m'
TUI_GREEN=$'\033[32m'
TUI_RED=$'\033[31m'
TUI_YELLOW=$'\033[33m'
TUI_WHITE=$'\033[37m'
TUI_BG_BLUE=$'\033[44m'
TUI_BG_WHITE=$'\033[47m'

# Terminal dimensions
TUI_HEIGHT="${TUI_HEIGHT:-0}"
TUI_WIDTH="${TUI_WIDTH:-0}"

# Check if TUI is available (always true for bash)
tui_check() {
    return 0
}

# Initialize TUI
tui_init() {
    # Clear screen and hide cursor during prompts
    clear
    # Trap to cleanup on exit
    trap 'tui_cleanup' EXIT
}

# Cleanup TUI
tui_cleanup() {
    # Show cursor, reset colors
    printf '%s' $'\033[?25h'"${TUI_RESET}"
    clear
}

# Print a horizontal line
_tui_line() {
    local width="${1:-60}"
    printf "${TUI_DIM}"
    printf '─%.0s' $(seq 1 "${width}")
    printf "${TUI_RESET}\n"
}

# Print a title box
_tui_title() {
    local title="$1"
    local width="${2:-60}"

    echo ""
    printf "${TUI_BOLD}${TUI_CYAN}┌"
    printf '─%.0s' $(seq 1 $((width - 2)))
    printf "┐${TUI_RESET}\n"

    printf "${TUI_BOLD}${TUI_CYAN}│${TUI_RESET} ${TUI_BOLD}%-$((width - 4))s ${TUI_CYAN}│${TUI_RESET}\n" "${title}"

    printf "${TUI_BOLD}${TUI_CYAN}└"
    printf '─%.0s' $(seq 1 $((width - 2)))
    printf "┘${TUI_RESET}\n"
    echo ""
}

# Print message text (handles \n)
_tui_message() {
    local message="$1"
    echo -e "${message}"
    echo ""
}

# Display a message box (press Enter to continue)
tui_msgbox() {
    local title="$1"
    local message="$2"
    # height and width params ignored in pure bash mode

    clear
    _tui_title "${title}"
    _tui_message "${message}"

    printf "${TUI_DIM}Press Enter to continue...${TUI_RESET}"
    read -r
    return 0
}

# Display an info box (no button, brief display)
tui_infobox() {
    local title="$1"
    local message="$2"

    clear
    _tui_title "${title}"
    _tui_message "${message}"
}

# Display a yes/no dialog
# Returns 0 for yes, 1 for no
tui_yesno() {
    local title="$1"
    local question="$2"
    local default="${3:-yes}"

    clear
    _tui_title "${title}"
    _tui_message "${question}"

    local prompt
    if [[ "${default}" == "yes" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    while true; do
        printf "${TUI_BOLD}${prompt}${TUI_RESET} "
        read -r answer

        # Handle empty input (use default)
        if [[ -z "${answer}" ]]; then
            if [[ "${default}" == "yes" ]]; then
                return 0
            else
                return 1
            fi
        fi

        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     printf "${TUI_RED}Please enter y or n${TUI_RESET}\n" ;;
        esac
    done
}

# Display an input box
# Outputs the entered text to stdout
tui_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"

    clear
    _tui_title "${title}"
    _tui_message "${prompt}"

    local input
    if [[ -n "${default}" ]]; then
        printf "${TUI_DIM}Default: ${default}${TUI_RESET}\n"
        printf "${TUI_BOLD}>${TUI_RESET} "
        read -r input
        if [[ -z "${input}" ]]; then
            input="${default}"
        fi
    else
        printf "${TUI_BOLD}>${TUI_RESET} "
        read -r input
    fi

    echo "${input}"
    return 0
}

# Display a password box (masked input)
# Outputs the entered password to stdout
tui_passwordbox() {
    local title="$1"
    local prompt="$2"

    clear
    _tui_title "${title}"
    _tui_message "${prompt}"

    local password
    printf "${TUI_BOLD}>${TUI_RESET} "
    read -rs password
    echo "" >&2  # newline after hidden input (to stderr so it doesn't mix with output)

    echo "${password}"
    return 0
}

# Display a menu (single selection from tag/description pairs)
# Args: title prompt height width menu_height tag1 desc1 tag2 desc2 ...
# Outputs the selected tag to stdout
tui_menu() {
    local title="$1"
    local prompt="$2"
    # Skip height, width, menu_height (positions 3, 4, 5)
    shift 5

    # Collect items into arrays
    local -a tags=()
    local -a descs=()

    while [[ $# -ge 2 ]]; do
        tags+=("$1")
        descs+=("$2")
        shift 2
    done

    if [[ ${#tags[@]} -eq 0 ]]; then
        return 1
    fi

    clear
    _tui_title "${title}"
    _tui_message "${prompt}"

    # Display numbered options
    local i
    for i in "${!tags[@]}"; do
        printf "  ${TUI_BOLD}${TUI_CYAN}%2d)${TUI_RESET} %-15s ${TUI_DIM}%s${TUI_RESET}\n" \
            "$((i + 1))" "${tags[$i]}" "${descs[$i]}"
    done
    echo ""

    # Get selection
    while true; do
        printf "${TUI_BOLD}Enter selection [1-%d]:${TUI_RESET} " "${#tags[@]}"
        read -r selection

        # Check for cancel (empty or 'q')
        if [[ -z "${selection}" ]] || [[ "${selection}" == "q" ]]; then
            return 1
        fi

        # Validate number
        if [[ "${selection}" =~ ^[0-9]+$ ]] && \
           [[ "${selection}" -ge 1 ]] && \
           [[ "${selection}" -le "${#tags[@]}" ]]; then
            echo "${tags[$((selection - 1))]}"
            return 0
        fi

        printf "${TUI_RED}Invalid selection. Enter 1-%d or q to cancel.${TUI_RESET}\n" "${#tags[@]}"
    done
}

# Display a checklist (multiple selection)
# Args: title prompt height width list_height tag1 desc1 status1 tag2 desc2 status2 ...
# Outputs space-separated selected tags to stdout
tui_checklist() {
    local title="$1"
    local prompt="$2"
    # Skip height, width, list_height
    shift 5

    # Collect items
    local -a tags=()
    local -a descs=()
    local -a selected=()

    while [[ $# -ge 3 ]]; do
        tags+=("$1")
        descs+=("$2")
        if [[ "$3" == "on" ]]; then
            selected+=("1")
        else
            selected+=("0")
        fi
        shift 3
    done

    if [[ ${#tags[@]} -eq 0 ]]; then
        return 1
    fi

    while true; do
        clear
        _tui_title "${title}"
        _tui_message "${prompt}"

        # Display options with checkboxes
        local i
        for i in "${!tags[@]}"; do
            local checkbox
            if [[ "${selected[$i]}" == "1" ]]; then
                checkbox="${TUI_GREEN}[x]${TUI_RESET}"
            else
                checkbox="${TUI_DIM}[ ]${TUI_RESET}"
            fi
            printf "  ${TUI_BOLD}${TUI_CYAN}%2d)${TUI_RESET} %s %-15s ${TUI_DIM}%s${TUI_RESET}\n" \
                "$((i + 1))" "${checkbox}" "${tags[$i]}" "${descs[$i]}"
        done
        echo ""
        printf "${TUI_DIM}Enter number to toggle, 'd' when done, 'q' to cancel${TUI_RESET}\n"
        printf "${TUI_BOLD}>${TUI_RESET} "
        read -r input

        case "${input}" in
            d|D|done)
                # Output selected tags
                local result=""
                for i in "${!tags[@]}"; do
                    if [[ "${selected[$i]}" == "1" ]]; then
                        result+="${tags[$i]} "
                    fi
                done
                echo "${result% }"
                return 0
                ;;
            q|Q|quit)
                return 1
                ;;
            *)
                if [[ "${input}" =~ ^[0-9]+$ ]] && \
                   [[ "${input}" -ge 1 ]] && \
                   [[ "${input}" -le "${#tags[@]}" ]]; then
                    local idx=$((input - 1))
                    if [[ "${selected[$idx]}" == "1" ]]; then
                        selected[$idx]="0"
                    else
                        selected[$idx]="1"
                    fi
                fi
                ;;
        esac
    done
}

# Display a radiolist (single selection with default)
# Args: title prompt height width list_height tag1 desc1 status1 tag2 desc2 status2 ...
# Outputs the selected tag to stdout
tui_radiolist() {
    local title="$1"
    local prompt="$2"
    # Skip height, width, list_height
    shift 5

    # Collect items
    local -a tags=()
    local -a descs=()
    local default_idx=0
    local idx=0

    while [[ $# -ge 3 ]]; do
        tags+=("$1")
        descs+=("$2")
        if [[ "$3" == "on" ]]; then
            default_idx="${idx}"
        fi
        shift 3
        ((++idx))
    done

    if [[ ${#tags[@]} -eq 0 ]]; then
        return 1
    fi

    clear
    _tui_title "${title}"
    _tui_message "${prompt}"

    # Display numbered options with default marker
    local i
    for i in "${!tags[@]}"; do
        local marker=""
        if [[ $i -eq ${default_idx} ]]; then
            marker=" ${TUI_GREEN}(default)${TUI_RESET}"
        fi
        printf "  ${TUI_BOLD}${TUI_CYAN}%2d)${TUI_RESET} %-15s ${TUI_DIM}%s${TUI_RESET}%s\n" \
            "$((i + 1))" "${tags[$i]}" "${descs[$i]}" "${marker}"
    done
    echo ""

    # Get selection
    while true; do
        printf "${TUI_BOLD}Enter selection [1-%d, Enter for default]:${TUI_RESET} " "${#tags[@]}"
        read -r selection

        # Handle empty input (use default)
        if [[ -z "${selection}" ]]; then
            echo "${tags[$default_idx]}"
            return 0
        fi

        # Check for cancel
        if [[ "${selection}" == "q" ]]; then
            return 1
        fi

        # Validate number
        if [[ "${selection}" =~ ^[0-9]+$ ]] && \
           [[ "${selection}" -ge 1 ]] && \
           [[ "${selection}" -le "${#tags[@]}" ]]; then
            echo "${tags[$((selection - 1))]}"
            return 0
        fi

        printf "${TUI_RED}Invalid selection. Enter 1-%d, Enter for default, or q to cancel.${TUI_RESET}\n" "${#tags[@]}"
    done
}

# Display a gauge (progress bar)
tui_gauge() {
    local title="$1"
    local prompt="$2"
    local percent="$3"

    clear
    _tui_title "${title}"

    # Draw progress bar
    local width=50
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    printf "%s\n\n" "${prompt}"
    printf "${TUI_CYAN}["
    printf "${TUI_GREEN}"
    printf '█%.0s' $(seq 1 "${filled}" 2>/dev/null) || true
    printf "${TUI_DIM}"
    printf '░%.0s' $(seq 1 "${empty}" 2>/dev/null) || true
    printf "${TUI_CYAN}]${TUI_RESET} %3d%%\n" "${percent}"
}

# Display a progress bar that reads percentages from stdin
tui_gauge_stream() {
    local title="$1"

    while read -r percent; do
        tui_gauge "${title}" "" "${percent}"
    done
}

# Display a mixedgauge (status list) - simplified version
tui_mixedgauge() {
    local title="$1"
    local prompt="$2"
    local percent="$3"
    shift 3

    clear
    _tui_title "${title}"
    echo -e "${prompt}\n"

    # Display status items
    while [[ $# -ge 2 ]]; do
        local item="$1"
        local status="$2"
        local status_color

        case "${status,,}" in
            completed|done|success) status_color="${TUI_GREEN}" ;;
            "in progress"|running)  status_color="${TUI_YELLOW}" ;;
            pending|waiting)        status_color="${TUI_DIM}" ;;
            failed|error)           status_color="${TUI_RED}" ;;
            *)                      status_color="${TUI_RESET}" ;;
        esac

        printf "  %-30s ${status_color}%s${TUI_RESET}\n" "${item}" "${status}"
        shift 2
    done

    echo ""
    tui_gauge "" "" "${percent}"
}

# Display a form for multiple inputs (simplified)
tui_form() {
    local title="$1"
    local prompt="$2"
    # Form args are complex, this is a simplified version
    shift 5

    clear
    _tui_title "${title}"
    _tui_message "${prompt}"

    printf "${TUI_DIM}Form input not fully implemented in pure bash mode${TUI_RESET}\n"
    return 1
}

# Display program output (pass through)
tui_programbox() {
    local title="$1"

    clear
    _tui_title "${title}"

    # Just pass through stdin to screen
    cat

    printf "\n${TUI_DIM}Press Enter to continue...${TUI_RESET}"
    read -r
}

# Display a text file
tui_textbox() {
    local title="$1"
    local file="$2"

    clear
    _tui_title "${title}"

    if [[ -f "${file}" ]]; then
        cat "${file}"
    else
        printf "${TUI_RED}File not found: ${file}${TUI_RESET}\n"
    fi

    printf "\n${TUI_DIM}Press Enter to continue...${TUI_RESET}"
    read -r
}

# Pause with a message
tui_pause() {
    local title="$1"
    local message="$2"
    local seconds="${3:-5}"

    clear
    _tui_title "${title}"
    _tui_message "${message}"

    for ((i=seconds; i>0; i--)); do
        printf "\r${TUI_DIM}Continuing in %d seconds... (press Enter to skip)${TUI_RESET}" "$i"
        read -t 1 -r && break
    done
    echo ""
}

# Display welcome screen
tui_welcome() {
    clear
    printf "${TUI_BOLD}${TUI_CYAN}"
    cat << 'EOF'

       _             _         _
      / \   _ __ ___| |__  ___| |_ _ __ __ _ _ __
     / _ \ | '__/ __| '_ \/ __| __| '__/ _` | '_ \
    / ___ \| | | (__| | | \__ \ |_| | | (_| | |_) |
   /_/   \_\_|  \___|_| |_|___/\__|_|  \__,_| .__/
                                            |_|
EOF
    printf "${TUI_RESET}\n"

    printf "${TUI_BOLD}Modern, opinionated Arch Linux installer${TUI_RESET}\n\n"

    printf "This installer will guide you through setting up:\n"
    printf "  ${TUI_CYAN}•${TUI_RESET} LUKS2 encrypted root partition\n"
    printf "  ${TUI_CYAN}•${TUI_RESET} BTRFS filesystem with subvolumes\n"
    printf "  ${TUI_CYAN}•${TUI_RESET} Unified Kernel Image (UKI) with Secure Boot\n"
    printf "  ${TUI_CYAN}•${TUI_RESET} TPM2 automatic unlock\n"
    printf "  ${TUI_CYAN}•${TUI_RESET} Security hardening per Arch Wiki\n"
    echo ""

    printf "${TUI_DIM}Press Enter to continue...${TUI_RESET}"
    read -r
}

# Display disk selection
tui_select_disk() {
    local prompt="$1"
    local -a menu_items=()

    while IFS= read -r line; do
        local disk size model
        disk=$(echo "${line}" | awk '{print $1}')
        size=$(echo "${line}" | awk '{print $2}')
        model=$(echo "${line}" | awk '{$1=$2=""; print $0}' | xargs)
        [[ -z "${model}" ]] && model="Unknown"
        menu_items+=("${disk}" "${size} - ${model}")
    done < <(disk_list)

    if [[ ${#menu_items[@]} -eq 0 ]]; then
        tui_msgbox "Error" "No disks found!" 8 40
        return 1
    fi

    tui_menu "Disk Selection" "${prompt}" 18 70 10 "${menu_items[@]}"
}

# Display installation progress
tui_show_progress() {
    local current_step="$1"
    local total_steps="$2"
    local step_name="$3"
    local percent=$(( (current_step * 100) / total_steps ))

    tui_infobox "Installing" "Step ${current_step}/${total_steps}: ${step_name}"
}

# Confirmation dialog before installation
tui_confirm_install() {
    local summary="$1"

    clear
    _tui_title "Confirm Installation"
    echo -e "${summary}"
    echo ""
    printf "${TUI_RED}${TUI_BOLD}WARNING: This will DESTROY all data on the selected disk(s)!${TUI_RESET}\n\n"

    printf "Proceed with installation? ${TUI_BOLD}[y/N]${TUI_RESET} "
    read -r answer

    case "${answer,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

# Display error
tui_error() {
    local message="$1"

    clear
    _tui_title "Error"
    printf "${TUI_RED}%s${TUI_RESET}\n\n" "${message}"

    printf "${TUI_DIM}Press Enter to continue...${TUI_RESET}"
    read -r
}

# Display completion message
tui_complete() {
    clear
    _tui_title "Installation Complete"

    printf "${TUI_GREEN}Installation completed successfully!${TUI_RESET}\n\n"

    printf "Your new Arch Linux system has been installed with:\n"
    printf "  ${TUI_CYAN}•${TUI_RESET} LUKS2 encrypted root partition\n"
    printf "  ${TUI_CYAN}•${TUI_RESET} BTRFS filesystem with subvolumes\n"
    printf "  ${TUI_CYAN}•${TUI_RESET} Security hardening enabled\n\n"

    printf "${TUI_YELLOW}Security notes:${TUI_RESET}\n"
    printf "  ${TUI_CYAN}•${TUI_RESET} Root account is LOCKED\n"
    printf "  ${TUI_CYAN}•${TUI_RESET} Use sudo for administrative tasks\n\n"

    printf "${TUI_BOLD}Next steps:${TUI_RESET}\n"
    printf "  1. Remove the installation media\n"
    printf "  2. Reboot into your new system\n"
    printf "  3. Log in with your user account\n\n"

    printf "${TUI_DIM}Press Enter to exit...${TUI_RESET}"
    read -r
}
