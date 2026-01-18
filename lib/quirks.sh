#!/bin/bash
# lib/quirks.sh - Hardware quirks detection and workarounds

set -euo pipefail

# ============================================
# QUIRK DETECTION FUNCTIONS
# ============================================

# Detect QCA6390 WiFi/Bluetooth chip (found in Dell XPS, HP, Lenovo laptops)
# Known issues: WiFi/Bluetooth race condition, suspend/resume failures
detect_qca6390() {
    # Check for QCA6390 via lspci (PCI ID 17cb:1101)
    if lspci -nn 2>/dev/null | grep -qi '17cb:1101'; then
        return 0
    fi
    # Also check for ath11k driver binding to QCA6390
    if lspci -k 2>/dev/null | grep -A2 -i 'QCA6390' | grep -qi 'ath11k'; then
        return 0
    fi
    return 1
}

# Detect Intel AX210/AX211 with known firmware issues
detect_intel_ax210_issues() {
    # Intel AX210/AX211 can have firmware crash issues on certain kernels
    if lspci -nn 2>/dev/null | grep -qiE '8086:(2725|51f0|51f1|54f0)'; then
        return 0
    fi
    return 1
}

# Detect Realtek RTL8852BE with suspend issues
detect_rtl8852be() {
    if lspci -nn 2>/dev/null | grep -qi '10ec:b852'; then
        return 0
    fi
    return 1
}

# Detect NVIDIA GPU with known suspend/resume issues
detect_nvidia_suspend_issues() {
    # Check for NVIDIA GPU with potential suspend issues
    if lspci 2>/dev/null | grep -qi 'VGA.*NVIDIA\|3D.*NVIDIA'; then
        return 0
    fi
    return 1
}

# ============================================
# QUIRK APPLICATION FUNCTIONS
# ============================================

# Apply QCA6390 workarounds
# Reference: https://wiki.archlinux.org/title/Dell_XPS_13_(9310)
apply_qca6390_quirks() {
    local mount_point="$1"

    log_info "Applying QCA6390 WiFi/Bluetooth quirks"

    # 1. Add kernel parameter for memory allocation fix
    # This prevents the race condition with firmware memory allocation
    local cmdline_file="${mount_point}/etc/kernel/cmdline"
    if [[ -f "${cmdline_file}" ]]; then
        # shellcheck disable=SC2016
        if ! grep -q 'memmap=12M$20M' "${cmdline_file}"; then
            log_info "Adding memmap kernel parameter for QCA6390"
            # Append memmap parameter (the $ is literal, not a variable)
            # shellcheck disable=SC2016
            sed -i 's/$/ memmap=12M$20M/' "${cmdline_file}"
        fi
    fi

    # 2. Create systemd services for suspend/resume module handling
    # This prevents WiFi/Bluetooth failures after suspend
    log_info "Creating ath11k suspend/resume services"

    mkdir -p "${mount_point}/etc/systemd/system"

    # Service to unload ath11k before suspend
    cat > "${mount_point}/etc/systemd/system/ath11k-suspend.service" << 'EOF'
[Unit]
Description=Unload ath11k_pci before suspend
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
ExecStart=/usr/bin/modprobe -r ath11k_pci
RemainAfterExit=yes

[Install]
WantedBy=sleep.target
EOF

    # Service to reload ath11k after resume
    cat > "${mount_point}/etc/systemd/system/ath11k-resume.service" << 'EOF'
[Unit]
Description=Reload ath11k_pci after resume
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 2
ExecStart=/usr/bin/modprobe ath11k_pci

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOF

    # Enable the services
    arch-chroot "${mount_point}" systemctl enable ath11k-suspend.service
    arch-chroot "${mount_point}" systemctl enable ath11k-resume.service

    # 3. Delay Bluetooth service startup to let WiFi initialize first
    # QCA6390 shares the chip between WiFi (ath11k) and Bluetooth (btusb/qca)
    log_info "Creating Bluetooth delay service for QCA6390"

    # Create a service that delays bluetooth.service startup
    cat > "${mount_point}/etc/systemd/system/bluetooth-delay.service" << 'EOF'
[Unit]
Description=Delay Bluetooth startup for QCA6390 WiFi/BT race condition
Before=bluetooth.service
After=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/bin/sleep 3
RemainAfterExit=yes

[Install]
WantedBy=bluetooth.service
EOF

    # Create drop-in to make bluetooth.service wait for our delay
    mkdir -p "${mount_point}/etc/systemd/system/bluetooth.service.d"
    cat > "${mount_point}/etc/systemd/system/bluetooth.service.d/qca6390-delay.conf" << 'EOF'
[Unit]
# Wait for WiFi (ath11k) to initialize before starting Bluetooth
# This prevents the QCA6390 race condition
After=bluetooth-delay.service sys-subsystem-net-devices-wlan0.device
Wants=bluetooth-delay.service
EOF

    # Enable the delay service
    arch-chroot "${mount_point}" systemctl enable bluetooth-delay.service

    log_info "QCA6390 quirks applied"
}

# Apply NVIDIA suspend/resume fixes
apply_nvidia_suspend_quirks() {
    local mount_point="$1"

    log_info "Applying NVIDIA suspend/resume quirks"

    # Enable preserve video memory allocations across suspend
    mkdir -p "${mount_point}/etc/modprobe.d"

    cat > "${mount_point}/etc/modprobe.d/nvidia-power-management.conf" << 'EOF'
# Enable NVIDIA power management for proper suspend/resume
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
EOF

    # Enable required systemd services for NVIDIA suspend
    arch-chroot "${mount_point}" systemctl enable nvidia-suspend.service 2>/dev/null || true
    arch-chroot "${mount_point}" systemctl enable nvidia-hibernate.service 2>/dev/null || true
    arch-chroot "${mount_point}" systemctl enable nvidia-resume.service 2>/dev/null || true

    log_info "NVIDIA suspend quirks applied"
}

# Apply Realtek RTL8852BE quirks
apply_rtl8852be_quirks() {
    local mount_point="$1"

    log_info "Applying RTL8852BE WiFi quirks"

    # The rtw89 driver may need ASPM disabled for stability
    mkdir -p "${mount_point}/etc/modprobe.d"

    cat > "${mount_point}/etc/modprobe.d/rtw89-quirks.conf" << 'EOF'
# Disable ASPM for RTL8852BE stability
options rtw89_pci disable_aspm_l1=Y disable_aspm_l1ss=Y
EOF

    log_info "RTL8852BE quirks applied"
}

# ============================================
# MAIN QUIRK DETECTION AND APPLICATION
# ============================================

# Detect all applicable quirks and return list
detect_hardware_quirks() {
    local quirks=""

    if detect_qca6390; then
        quirks="${quirks} qca6390"
    fi

    if detect_nvidia_suspend_issues; then
        quirks="${quirks} nvidia_suspend"
    fi

    if detect_rtl8852be; then
        quirks="${quirks} rtl8852be"
    fi

    echo "${quirks}" | xargs
}

# Apply all detected quirks
apply_hardware_quirks() {
    local mount_point="$1"
    local quirks="$2"

    for quirk in ${quirks}; do
        case "${quirk}" in
            qca6390)
                apply_qca6390_quirks "${mount_point}"
                ;;
            nvidia_suspend)
                apply_nvidia_suspend_quirks "${mount_point}"
                ;;
            rtl8852be)
                apply_rtl8852be_quirks "${mount_point}"
                ;;
            *)
                log_warn "Unknown quirk: ${quirk}"
                ;;
        esac
    done
}

# Get human-readable description of quirks
describe_quirks() {
    local quirks="$1"
    local descriptions=""

    for quirk in ${quirks}; do
        case "${quirk}" in
            qca6390)
                descriptions="${descriptions}\n  - QCA6390: WiFi/Bluetooth race condition and suspend fixes"
                ;;
            nvidia_suspend)
                descriptions="${descriptions}\n  - NVIDIA: Suspend/resume power management"
                ;;
            rtl8852be)
                descriptions="${descriptions}\n  - RTL8852BE: WiFi stability (ASPM disabled)"
                ;;
        esac
    done

    echo -e "${descriptions}"
}
