#!/bin/bash
# lib/tui.sh - Text User Interface using dialog

set -euo pipefail

# Dialog configuration
export DIALOGRC="${DIALOGRC:-}"
export DIALOG_OK=0
export DIALOG_CANCEL=1
export DIALOG_HELP=2
export DIALOG_EXTRA=3
export DIALOG_ITEM_HELP=4
export DIALOG_ESC=255

# Temp file for dialog output
TUI_TEMP="/tmp/archstrap_dialog.$$"

# Terminal dimensions
TUI_HEIGHT="${TUI_HEIGHT:-0}"
TUI_WIDTH="${TUI_WIDTH:-0}"

# Check if dialog is available
tui_check() {
    if ! command -v dialog &>/dev/null; then
        log_error "dialog is required for TUI mode"
        log_info "Install with: pacman -S dialog"
        return 1
    fi
    return 0
}

# Initialize TUI
tui_init() {
    tui_check || return 1

    # Create custom dialog theme for Arch look
    if [[ -z "${DIALOGRC}" ]]; then
        DIALOGRC="/tmp/archstrap_dialogrc.$$"
        cat > "${DIALOGRC}" << 'EOF'
# Archstrap dialog theme
use_shadow = OFF
use_colors = ON

screen_color = (WHITE,BLUE,ON)
shadow_color = (BLACK,BLACK,OFF)
dialog_color = (BLACK,WHITE,OFF)
title_color = (BLUE,WHITE,ON)
border_color = (WHITE,WHITE,ON)
button_active_color = (WHITE,BLUE,ON)
button_inactive_color = (BLACK,WHITE,OFF)
button_key_active_color = (WHITE,BLUE,ON)
button_key_inactive_color = (RED,WHITE,OFF)
button_label_active_color = (YELLOW,BLUE,ON)
button_label_inactive_color = (BLACK,WHITE,ON)
inputbox_color = (BLACK,WHITE,OFF)
inputbox_border_color = (BLACK,WHITE,OFF)
searchbox_color = (BLACK,WHITE,OFF)
searchbox_title_color = (BLUE,WHITE,ON)
searchbox_border_color = (WHITE,WHITE,ON)
position_indicator_color = (BLUE,WHITE,ON)
menubox_color = (BLACK,WHITE,OFF)
menubox_border_color = (WHITE,WHITE,ON)
item_color = (BLACK,WHITE,OFF)
item_selected_color = (WHITE,BLUE,ON)
tag_color = (BLUE,WHITE,ON)
tag_selected_color = (YELLOW,BLUE,ON)
tag_key_color = (RED,WHITE,OFF)
tag_key_selected_color = (RED,BLUE,ON)
check_color = (BLACK,WHITE,OFF)
check_selected_color = (WHITE,BLUE,ON)
uarrow_color = (GREEN,WHITE,ON)
darrow_color = (GREEN,WHITE,ON)
itemhelp_color = (WHITE,BLACK,OFF)
form_active_text_color = (WHITE,BLUE,ON)
form_text_color = (BLACK,WHITE,ON)
form_item_readonly_color = (CYAN,WHITE,ON)
gauge_color = (BLUE,WHITE,ON)
border2_color = (WHITE,WHITE,ON)
inputbox_border2_color = (BLACK,WHITE,OFF)
searchbox_border2_color = (WHITE,WHITE,ON)
menubox_border2_color = (WHITE,WHITE,ON)
EOF
        export DIALOGRC
    fi

    # Trap to cleanup temp files
    trap 'rm -f "${TUI_TEMP}" "${DIALOGRC}" 2>/dev/null' EXIT
}

# Cleanup TUI
tui_cleanup() {
    rm -f "${TUI_TEMP}" 2>/dev/null || true
    clear
}

# Display a message box
tui_msgbox() {
    local title="$1"
    local message="$2"
    local height="${3:-10}"
    local width="${4:-60}"

    dialog --title "${title}" \
           --msgbox "${message}" \
           "${height}" "${width}"
}

# Display an info box (no button, auto-closes)
tui_infobox() {
    local title="$1"
    local message="$2"
    local height="${3:-5}"
    local width="${4:-50}"

    dialog --title "${title}" \
           --infobox "${message}" \
           "${height}" "${width}"
}

# Display a yes/no dialog
tui_yesno() {
    local title="$1"
    local question="$2"
    local default="${3:-yes}"
    local height="${4:-8}"
    local width="${5:-60}"

    local extra_args=()
    if [[ "${default}" == "no" ]]; then
        extra_args+=(--defaultno)
    fi

    dialog --title "${title}" \
           "${extra_args[@]}" \
           --yesno "${question}" \
           "${height}" "${width}"
}

# Display an input box
tui_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"
    local height="${4:-10}"
    local width="${5:-60}"

    dialog --title "${title}" \
           --inputbox "${prompt}" \
           "${height}" "${width}" "${default}" \
           2>"${TUI_TEMP}"

    local result=$?
    if [[ ${result} -eq 0 ]]; then
        cat "${TUI_TEMP}"
    fi
    return ${result}
}

# Display a password box
tui_passwordbox() {
    local title="$1"
    local prompt="$2"
    local height="${3:-10}"
    local width="${4:-60}"

    dialog --title "${title}" \
           --insecure \
           --passwordbox "${prompt}" \
           "${height}" "${width}" \
           2>"${TUI_TEMP}"

    local result=$?
    if [[ ${result} -eq 0 ]]; then
        cat "${TUI_TEMP}"
    fi
    return ${result}
}

# Display a menu
tui_menu() {
    local title="$1"
    local prompt="$2"
    local height="${3:-20}"
    local width="${4:-70}"
    local menu_height="${5:-10}"
    shift 5

    # Remaining args are tag/item pairs
    dialog --title "${title}" \
           --menu "${prompt}" \
           "${height}" "${width}" "${menu_height}" \
           "$@" \
           2>"${TUI_TEMP}"

    local result=$?
    if [[ ${result} -eq 0 ]]; then
        cat "${TUI_TEMP}"
    fi
    return ${result}
}

# Display a checklist
tui_checklist() {
    local title="$1"
    local prompt="$2"
    local height="${3:-20}"
    local width="${4:-70}"
    local list_height="${5:-10}"
    shift 5

    # Remaining args are tag/item/status triples
    dialog --title "${title}" \
           --checklist "${prompt}" \
           "${height}" "${width}" "${list_height}" \
           "$@" \
           2>"${TUI_TEMP}"

    local result=$?
    if [[ ${result} -eq 0 ]]; then
        cat "${TUI_TEMP}"
    fi
    return ${result}
}

# Display a radiolist
tui_radiolist() {
    local title="$1"
    local prompt="$2"
    local height="${3:-20}"
    local width="${4:-70}"
    local list_height="${5:-10}"
    shift 5

    # Remaining args are tag/item/status triples
    dialog --title "${title}" \
           --radiolist "${prompt}" \
           "${height}" "${width}" "${list_height}" \
           "$@" \
           2>"${TUI_TEMP}"

    local result=$?
    if [[ ${result} -eq 0 ]]; then
        cat "${TUI_TEMP}"
    fi
    return ${result}
}

# Display a gauge (progress bar)
tui_gauge() {
    local title="$1"
    local prompt="$2"
    local percent="$3"
    local height="${4:-8}"
    local width="${5:-60}"

    echo "${percent}" | dialog --title "${title}" \
                               --gauge "${prompt}" \
                               "${height}" "${width}" 0
}

# Display a progress bar that reads percentages from stdin
tui_gauge_stream() {
    local title="$1"
    local height="${2:-8}"
    local width="${3:-60}"

    dialog --title "${title}" \
           --gauge "" \
           "${height}" "${width}" 0
}

# Display a mixedgauge (multiple progress items)
tui_mixedgauge() {
    local title="$1"
    local prompt="$2"
    local percent="$3"
    local height="${4:-20}"
    local width="${5:-70}"
    shift 5

    # Remaining args are tag/status pairs
    dialog --title "${title}" \
           --mixedgauge "${prompt}" \
           "${height}" "${width}" "${percent}" \
           "$@"
}

# Display a form for multiple inputs
tui_form() {
    local title="$1"
    local prompt="$2"
    local height="${3:-20}"
    local width="${4:-70}"
    local form_height="${5:-10}"
    shift 5

    # Remaining args are label/y/x/item/y/x/flen/ilen groups
    dialog --title "${title}" \
           --form "${prompt}" \
           "${height}" "${width}" "${form_height}" \
           "$@" \
           2>"${TUI_TEMP}"

    local result=$?
    if [[ ${result} -eq 0 ]]; then
        cat "${TUI_TEMP}"
    fi
    return ${result}
}

# Display program output in a scrollable box
tui_programbox() {
    local title="$1"
    local height="${2:-20}"
    local width="${3:-70}"

    dialog --title "${title}" \
           --programbox \
           "${height}" "${width}"
}

# Display a text file
tui_textbox() {
    local title="$1"
    local file="$2"
    local height="${3:-20}"
    local width="${4:-70}"

    dialog --title "${title}" \
           --textbox "${file}" \
           "${height}" "${width}"
}

# Pause with a message
tui_pause() {
    local title="$1"
    local message="$2"
    local seconds="${3:-5}"
    local height="${4:-10}"
    local width="${5:-50}"

    dialog --title "${title}" \
           --pause "${message}" \
           "${height}" "${width}" "${seconds}"
}

# Display welcome screen
tui_welcome() {
    dialog --title "Welcome to Archstrap" \
           --msgbox "\
    _             _         _
   / \\   _ __ ___| |__  ___| |_ _ __ __ _ _ __
  / _ \\ | '__/ __| '_ \\/ __| __| '__/ _\` | '_ \\
 / ___ \\| | | (__| | | \\__ \\ |_| | | (_| | |_) |
/_/   \\_\\_|  \\___|_| |_|___/\\__|_|  \\__,_| .__/
                                         |_|

Modern, opinionated Arch Linux installer

This installer will guide you through setting up:
• LUKS2 encrypted root partition
• BTRFS filesystem with subvolumes
• Unified Kernel Image (UKI) with Secure Boot
• TPM2 automatic unlock
• Security hardening per Arch Wiki

Press OK to continue..." 20 65
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

    # Build step status list for mixedgauge
    local -a step_items=()
    local step_names=(
        "Preflight checks"
        "Configuration"
        "Partitioning"
        "Encryption"
        "Filesystem"
        "Mounting"
        "Base system"
        "Fstab"
        "Chroot prep"
        "Locale"
        "Users"
        "Hardware"
        "Network"
        "Boot"
        "AUR helper"
        "Finalize"
    )

    for i in "${!step_names[@]}"; do
        local status
        if [[ $i -lt $((current_step - 1)) ]]; then
            status="Completed"
        elif [[ $i -eq $((current_step - 1)) ]]; then
            status="In Progress"
        else
            status="Pending"
        fi
        step_items+=("${step_names[$i]}" "${status}")
    done

    # Note: mixedgauge uses different status codes
    # We'll use a simpler gauge for now
    tui_infobox "Installing" "Step ${current_step}/${total_steps}: ${step_name}" 5 50
}

# Confirmation dialog before installation
tui_confirm_install() {
    local summary="$1"

    dialog --title "Confirm Installation" \
           --yes-label "Install" \
           --no-label "Cancel" \
           --yesno "${summary}\n\nThis will DESTROY all data on the selected disk(s)!\n\nProceed with installation?" \
           20 70
}

# Display error
tui_error() {
    local message="$1"
    dialog --title "Error" \
           --msgbox "${message}" \
           10 60
}

# Display completion message
tui_complete() {
    dialog --title "Installation Complete" \
           --msgbox "\
Installation completed successfully!

Your new Arch Linux system has been installed with:
• LUKS2 encrypted root partition
• BTRFS filesystem with subvolumes
• Security hardening enabled

Security notes:
• Root account is LOCKED
• Use sudo for administrative tasks

Next steps:
1. Remove the installation media
2. Reboot into your new system
3. Log in with your user account

Press OK to exit." 22 60
}
