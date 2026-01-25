#!/bin/bash
# lib/network.sh - Network configuration for archstrap

set -euo pipefail

# Wait for network connectivity
network_wait() {
    local timeout="${1:-30}"
    local test_host="${2:-archlinux.org}"

    log_info "Waiting for network connectivity..."

    if wait_for "ping -c1 -W1 ${test_host} &>/dev/null" "${timeout}"; then
        log_info "Network is available"
        return 0
    else
        log_error "Network not available after ${timeout} seconds"
        return 1
    fi
}

# Get network interface type
network_interface_type() {
    local iface="$1"

    if [[ -d "/sys/class/net/${iface}/wireless" ]]; then
        echo "wlan"
    elif [[ -d "/sys/class/net/${iface}/device/wwan" ]]; then
        echo "wwan"
    elif [[ "${iface}" == eth* ]] || [[ "${iface}" == en* ]]; then
        echo "ethernet"
    else
        echo "unknown"
    fi
}

# List network interfaces
list_interfaces() {
    local type="${1:-all}"

    for iface in /sys/class/net/*; do
        local name
        name="$(basename "${iface}")"
        [[ "${name}" == "lo" ]] && continue

        local iface_type
        iface_type="$(network_interface_type "${name}")"

        if [[ "${type}" == "all" ]] || [[ "${type}" == "${iface_type}" ]]; then
            echo "${name}"
        fi
    done
}

# Get wireless interface name
get_wireless_interface() {
    list_interfaces "wlan" | head -n1
}

# Get ethernet interface name
get_ethernet_interface() {
    list_interfaces "ethernet" | head -n1
}

# Generate systemd-networkd config for ethernet
generate_ethernet_config() {
    local iface="$1"

    cat << EOF
[Match]
Name=${iface}

[Network]
DHCP=yes
IPv6PrivacyExtensions=yes

[DHCPv4]
RouteMetric=100

[IPv6AcceptRA]
RouteMetric=100
EOF
}

# Generate systemd-networkd config for wireless
generate_wireless_config() {
    local iface="$1"

    cat << EOF
[Match]
Name=${iface}

[Network]
DHCP=yes
IPv6PrivacyExtensions=yes
IgnoreCarrierLoss=3s

[DHCPv4]
RouteMetric=600

[IPv6AcceptRA]
RouteMetric=600
EOF
}

# Generate systemd-networkd config for WWAN
generate_wwan_config() {
    local iface="$1"

    cat << EOF
[Match]
Name=${iface}

[Network]
DHCP=yes
IPv6PrivacyExtensions=yes

[DHCPv4]
RouteMetric=700

[IPv6AcceptRA]
RouteMetric=700
EOF
}

# Generate iwd main configuration
generate_iwd_config() {
    cat << EOF
[General]
EnableNetworkConfiguration=false

[Network]
EnableIPv6=true

[Scan]
DisablePeriodicScan=false

[Settings]
AutoConnect=true
EOF
}

# Generate NetworkManager configuration for systemd-resolved integration
generate_networkmanager_dns_config() {
    cat << EOF
[main]
dns=systemd-resolved
EOF
}

# Install network configuration files
install_network_configs() {
    local root="${1:-/mnt}"
    local stack
    stack="$(config_get network_stack "systemd")"

    log_info "Installing network configuration (${stack})"

    if [[ "${stack}" == "networkmanager" ]]; then
        # NetworkManager handles network configuration automatically,
        # but needs explicit config to use systemd-resolved for DNS
        local nm_conf_dir="${root}/etc/NetworkManager/conf.d"
        run mkdir -p "${nm_conf_dir}"

        log_info "Configuring NetworkManager to use systemd-resolved"
        if [[ "${DRY_RUN}" != "1" ]]; then
            generate_networkmanager_dns_config > "${nm_conf_dir}/dns.conf"
        else
            echo -e "${MAGENTA}[DRY-RUN]${RESET} Would create ${nm_conf_dir}/dns.conf"
        fi
        return 0
    fi

    # systemd-networkd configuration
    local networkd_dir="${root}/etc/systemd/network"
    local iwd_dir="${root}/etc/iwd"

    run mkdir -p "${networkd_dir}"
    run mkdir -p "${iwd_dir}"

    # Ethernet configuration
    local eth_iface
    eth_iface="$(get_ethernet_interface)"
    if [[ -n "${eth_iface}" ]]; then
        log_debug "Configuring ethernet: ${eth_iface}"
        if [[ "${DRY_RUN}" != "1" ]]; then
            generate_ethernet_config "${eth_iface}" > "${networkd_dir}/20-ethernet.network"
        else
            echo -e "${MAGENTA}[DRY-RUN]${RESET} Would create ${networkd_dir}/20-ethernet.network"
        fi
    fi

    # Wireless configuration
    if detect_wireless; then
        local wlan_iface
        wlan_iface="$(get_wireless_interface)"
        if [[ -n "${wlan_iface}" ]]; then
            log_debug "Configuring wireless: ${wlan_iface}"
            if [[ "${DRY_RUN}" != "1" ]]; then
                generate_wireless_config "${wlan_iface}" > "${networkd_dir}/25-wireless.network"
                generate_iwd_config > "${iwd_dir}/main.conf"
            else
                echo -e "${MAGENTA}[DRY-RUN]${RESET} Would create ${networkd_dir}/25-wireless.network"
                echo -e "${MAGENTA}[DRY-RUN]${RESET} Would create ${iwd_dir}/main.conf"
            fi
        fi
    fi

    # WWAN configuration
    if detect_wwan; then
        log_debug "Configuring WWAN"
        if [[ "${DRY_RUN}" != "1" ]]; then
            generate_wwan_config "wwan0" > "${networkd_dir}/30-wwan.network"
        else
            echo -e "${MAGENTA}[DRY-RUN]${RESET} Would create ${networkd_dir}/30-wwan.network"
        fi
    fi
}

# Get network packages based on detected hardware and selected stack
get_network_packages() {
    local stack
    stack="$(config_get network_stack "systemd")"
    local packages=()

    if [[ "${stack}" == "networkmanager" ]]; then
        # NetworkManager stack
        packages+=("networkmanager")
        if detect_wireless; then
            packages+=("wpa_supplicant")
        fi
    else
        # systemd-networkd stack (default)
        packages+=("iwd" "systemd-resolvconf")
    fi

    if detect_wwan; then
        packages+=("modemmanager" "usb_modeswitch")
    fi

    echo "${packages[*]}"
}

# Configure resolved
generate_resolved_config() {
    cat << EOF
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
FallbackDNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net
DNSSEC=yes
DNSOverTLS=yes
Domains=~.
EOF
}

# Install resolved configuration
install_resolved_config() {
    local root="${1:-/mnt}"
    local resolved_dir="${root}/etc/systemd/resolved.conf.d"

    log_info "Installing DNS configuration"

    run mkdir -p "${resolved_dir}"

    if [[ "${DRY_RUN}" != "1" ]]; then
        generate_resolved_config > "${resolved_dir}/dns.conf"
    else
        echo -e "${MAGENTA}[DRY-RUN]${RESET} Would create ${resolved_dir}/dns.conf"
    fi
}

# Enable network services in chroot
enable_network_services() {
    local root="${1:-/mnt}"
    local stack
    stack="$(config_get network_stack "systemd")"

    log_info "Enabling network services (${stack})"

    if [[ "${stack}" == "networkmanager" ]]; then
        # NetworkManager stack
        run arch-chroot "${root}" systemctl enable NetworkManager.service

        if detect_wwan; then
            run arch-chroot "${root}" systemctl enable ModemManager.service
        fi

        # NetworkManager handles DNS, but we can still use systemd-resolved
        run arch-chroot "${root}" systemctl enable systemd-resolved.service
        run ln -sf /run/systemd/resolve/stub-resolv.conf "${root}/etc/resolv.conf"
    else
        # systemd-networkd stack (default)
        run arch-chroot "${root}" systemctl enable systemd-networkd.service
        run arch-chroot "${root}" systemctl enable systemd-resolved.service
        run arch-chroot "${root}" systemctl enable iwd.service

        if detect_wwan; then
            run arch-chroot "${root}" systemctl enable ModemManager.service
        fi

        # Create resolv.conf symlink
        run ln -sf /run/systemd/resolve/stub-resolv.conf "${root}/etc/resolv.conf"
    fi
}
