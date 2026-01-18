#!/bin/bash
# steps/11a-quirks.sh - Hardware quirks detection and workarounds

set -euo pipefail

run_step() {
    step_start "11a-quirks" "Detecting and applying hardware quirks"

    # Detect hardware with known issues
    log_info "Scanning for hardware with known issues..."

    local detected_quirks
    detected_quirks="$(detect_hardware_quirks)"

    if [[ -z "${detected_quirks}" ]]; then
        log_info "No hardware quirks detected"
        state_save
        return 0
    fi

    # Log detected quirks
    log_info "Detected hardware requiring workarounds:"
    describe_quirks "${detected_quirks}" | while IFS= read -r line; do
        [[ -n "${line}" ]] && log_info "${line}"
    done

    # Apply quirks
    if [[ "${DRY_RUN}" != "1" ]]; then
        print_separator "-"
        log_info "Applying hardware quirks"
        print_separator "-"

        apply_hardware_quirks "${MOUNT_POINT}" "${detected_quirks}"

        # Store applied quirks in state for reference
        state_set "applied_quirks" "${detected_quirks}"
    else
        echo -e "${MAGENTA}[DRY-RUN]${RESET} Would apply quirks: ${detected_quirks}"
    fi

    state_save
    log_info "Hardware quirks applied successfully"
}
