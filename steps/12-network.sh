#!/bin/bash
# steps/12-network.sh - Network configuration

set -euo pipefail

run_step() {
    step_start "12-network" "Configuring network"

    # Install network configuration files
    install_network_configs "${MOUNT_POINT}"

    # Install resolved configuration
    install_resolved_config "${MOUNT_POINT}"

    # Enable network services
    enable_network_services "${MOUNT_POINT}"

    state_save
    log_info "Network configuration complete"
}
