#!/bin/bash
# lib/hardware.sh - Hardware detection for archstrap

set -euo pipefail

# Detect CPU vendor for microcode
detect_cpu_vendor() {
    local vendor
    vendor="$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')"

    case "${vendor}" in
        GenuineIntel)
            echo "intel"
            ;;
        AuthenticAMD)
            echo "amd"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get microcode package name
get_microcode_package() {
    local vendor
    vendor="$(detect_cpu_vendor)"

    case "${vendor}" in
        intel)
            echo "intel-ucode"
            ;;
        amd)
            echo "amd-ucode"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Detect GPU vendor(s)
detect_gpu() {
    local gpus=()

    # Check for Intel GPU
    if lspci 2>/dev/null | grep -qi 'VGA.*Intel'; then
        gpus+=("intel")
    fi

    # Check for AMD GPU
    if lspci 2>/dev/null | grep -qi 'VGA.*AMD\|VGA.*ATI'; then
        gpus+=("amd")
    fi

    # Check for NVIDIA GPU
    if lspci 2>/dev/null | grep -qi 'VGA.*NVIDIA\|3D.*NVIDIA'; then
        gpus+=("nvidia")
    fi

    # Return space-separated list
    echo "${gpus[*]}"
}

# Check if system has hybrid graphics
has_hybrid_graphics() {
    local gpus
    gpus="$(detect_gpu)"
    local count
    count=$(echo "${gpus}" | wc -w)
    [[ "${count}" -gt 1 ]]
}

# Detect NVIDIA GPU generation for driver selection
# Returns: turing, ampere, ada, hopper, older, or empty if not NVIDIA
detect_nvidia_generation() {
    # Check for NVIDIA GPU first
    if ! lspci 2>/dev/null | grep -qi 'VGA.*NVIDIA\|3D.*NVIDIA'; then
        return 1
    fi

    # Get NVIDIA device IDs
    local device_ids
    device_ids=$(lspci -nn 2>/dev/null | grep -iE 'VGA.*NVIDIA|3D.*NVIDIA' | grep -oE '\[10de:[0-9a-f]+\]' | tr '[:upper:]' '[:lower:]')

    for device_id in ${device_ids}; do
        # Extract the device ID (remove vendor prefix)
        local id="${device_id#*:}"
        id="${id%]}"

        # Ada Lovelace (RTX 4000 series) - 2680-26ff, 2700-27ff
        if [[ "${id}" =~ ^(26[89a-f][0-9a-f]|27[0-9a-f][0-9a-f])$ ]]; then
            echo "ada"
            return 0
        fi

        # Ampere (RTX 3000 series) - 2200-25ff
        if [[ "${id}" =~ ^(22[0-9a-f][0-9a-f]|23[0-9a-f][0-9a-f]|24[0-9a-f][0-9a-f]|25[0-9a-f][0-9a-f])$ ]]; then
            echo "ampere"
            return 0
        fi

        # Turing (RTX 2000/GTX 1600 series) - 1e00-21ff
        if [[ "${id}" =~ ^(1e[0-9a-f][0-9a-f]|1f[0-9a-f][0-9a-f]|20[0-9a-f][0-9a-f]|21[0-9a-f][0-9a-f])$ ]]; then
            echo "turing"
            return 0
        fi
    done

    # Older GPU or unknown
    echo "older"
    return 0
}

# Get GPU driver packages
get_gpu_packages() {
    local gpus
    gpus="$(detect_gpu)"
    local packages=()

    for gpu in ${gpus}; do
        case "${gpu}" in
            intel)
                packages+=("mesa" "intel-media-driver" "vulkan-intel")
                ;;
            amd)
                packages+=("mesa" "libva-mesa-driver" "vulkan-radeon" "xf86-video-amdgpu")
                ;;
            nvidia)
                # Use nvidia-open for Turing (RTX 2000/GTX 1600) and newer
                local nvidia_gen
                nvidia_gen="$(detect_nvidia_generation)"
                case "${nvidia_gen}" in
                    ada|ampere|hopper)
                        # Recommended: nvidia-open for Ampere and newer
                        packages+=("nvidia-open" "nvidia-utils" "nvidia-settings")
                        log_debug "Using nvidia-open driver (${nvidia_gen} GPU detected)"
                        ;;
                    turing)
                        # Supported: nvidia-open works but may have minor issues
                        packages+=("nvidia-open" "nvidia-utils" "nvidia-settings")
                        log_debug "Using nvidia-open driver (Turing GPU detected)"
                        ;;
                    *)
                        # Older GPUs: use proprietary driver
                        packages+=("nvidia" "nvidia-utils" "nvidia-settings")
                        log_debug "Using proprietary nvidia driver (older GPU)"
                        ;;
                esac
                ;;
        esac
    done

    # Add nvidia-prime for NVIDIA hybrid graphics (provides prime-run wrapper)
    # AMD hybrid graphics works with DRI_PRIME=1 without additional packages
    if has_hybrid_graphics && [[ " ${packages[*]} " =~ " nvidia" ]]; then
        packages+=("nvidia-prime")
    fi

    # Remove duplicates and echo
    printf '%s\n' "${packages[@]}" | sort -u | tr '\n' ' '
}

# Detect if audio hardware is present
detect_audio() {
    # Check for any audio devices
    if [[ -d /sys/class/sound ]] && [[ -n "$(ls -A /sys/class/sound 2>/dev/null)" ]]; then
        return 0
    fi

    # Check via lspci
    if lspci 2>/dev/null | grep -qi 'audio'; then
        return 0
    fi

    return 1
}

# Get audio packages (avoiding GNOME software as per requirements)
get_audio_packages() {
    # Pipewire stack without GNOME dependencies
    echo "pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber"
}

# Detect Bluetooth adapter
detect_bluetooth() {
    # Check for bluetooth devices
    if [[ -d /sys/class/bluetooth ]] && [[ -n "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]]; then
        return 0
    fi

    # Check via lspci/lsusb
    if lspci 2>/dev/null | grep -qi 'bluetooth'; then
        return 0
    fi

    if lsusb 2>/dev/null | grep -qi 'bluetooth'; then
        return 0
    fi

    return 1
}

# Get Bluetooth packages
get_bluetooth_packages() {
    echo "bluez bluez-utils"
}

# Detect wireless adapter
detect_wireless() {
    # Check for wireless interfaces
    if [[ -d /sys/class/net ]]; then
        for iface in /sys/class/net/*; do
            if [[ -d "${iface}/wireless" ]]; then
                return 0
            fi
        done
    fi

    # Check via lspci
    if lspci 2>/dev/null | grep -qi 'wireless\|wifi\|wlan'; then
        return 0
    fi

    return 1
}

# Detect WWAN (mobile broadband) modem
detect_wwan() {
    # Check for WWAN devices
    if lspci 2>/dev/null | grep -qi 'wwan\|cellular\|lte\|5g'; then
        return 0
    fi

    if lsusb 2>/dev/null | grep -qi 'wwan\|cellular\|sierra\|quectel\|fibocom'; then
        return 0
    fi

    return 1
}

# Get WWAN packages
get_wwan_packages() {
    echo "modemmanager usb_modeswitch"
}

# Detect if running in a virtual machine
detect_vm() {
    # Check systemd-detect-virt
    if command_exists systemd-detect-virt; then
        local virt
        virt="$(systemd-detect-virt 2>/dev/null || echo "none")"
        if [[ "${virt}" != "none" ]]; then
            echo "${virt}"
            return 0
        fi
    fi

    # Check DMI
    if [[ -f /sys/class/dmi/id/product_name ]]; then
        local product
        product="$(cat /sys/class/dmi/id/product_name)"
        case "${product}" in
            *VirtualBox*)
                echo "virtualbox"
                return 0
                ;;
            *VMware*)
                echo "vmware"
                return 0
                ;;
            *QEMU*|*KVM*)
                echo "kvm"
                return 0
                ;;
        esac
    fi

    echo "none"
    return 1
}

# Get VM-specific packages
get_vm_packages() {
    local vm_type
    vm_type="$(detect_vm)"

    case "${vm_type}" in
        virtualbox)
            echo "virtualbox-guest-utils"
            ;;
        vmware)
            echo "open-vm-tools"
            ;;
        kvm|qemu)
            echo "qemu-guest-agent spice-vdagent"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Check if system supports TPM2
detect_tpm2() {
    [[ -c /dev/tpm0 ]] || [[ -c /dev/tpmrm0 ]]
}

# Check if system is UEFI
is_uefi() {
    [[ -d /sys/firmware/efi ]]
}

# Check if Secure Boot is enabled
# Returns 0 if enabled, 1 if disabled or not available
detect_secure_boot_enabled() {
    if ! is_uefi; then
        return 1
    fi

    # Read SecureBoot EFI variable
    local sb_var
    sb_var=$(find /sys/firmware/efi/efivars -name 'SecureBoot-*' 2>/dev/null | head -1)

    if [[ -n "${sb_var}" ]] && [[ -f "${sb_var}" ]]; then
        # SecureBoot variable: last byte is 1 if enabled, 0 if disabled
        local sb_value
        sb_value=$(od -An -t u1 "${sb_var}" 2>/dev/null | awk '{print $NF}')
        [[ "${sb_value}" == "1" ]]
        return $?
    fi

    return 1
}

# Check if Secure Boot is in setup mode (allows key enrollment)
# Returns 0 if in setup mode, 1 otherwise
detect_secure_boot_setup_mode() {
    if ! is_uefi; then
        return 1
    fi

    # Read SetupMode EFI variable
    local setup_var
    setup_var=$(find /sys/firmware/efi/efivars -name 'SetupMode-*' 2>/dev/null | head -1)

    if [[ -n "${setup_var}" ]] && [[ -f "${setup_var}" ]]; then
        # SetupMode variable: last byte is 1 if in setup mode
        local setup_value
        setup_value=$(od -An -t u1 "${setup_var}" 2>/dev/null | awk '{print $NF}')
        [[ "${setup_value}" == "1" ]]
        return $?
    fi

    return 1
}

# Get Secure Boot status as string
get_secure_boot_status() {
    if ! is_uefi; then
        echo "not_uefi"
        return
    fi

    local enabled="no"
    local setup_mode="no"

    if detect_secure_boot_enabled; then
        enabled="yes"
    fi

    if detect_secure_boot_setup_mode; then
        setup_mode="yes"
    fi

    if [[ "${enabled}" == "yes" ]]; then
        echo "enabled"
    elif [[ "${setup_mode}" == "yes" ]]; then
        echo "setup_mode"
    else
        echo "disabled"
    fi
}

# Legacy function for backward compatibility
detect_secure_boot() {
    detect_secure_boot_enabled || detect_secure_boot_setup_mode
}

# Detect fingerprint reader
detect_fingerprint() {
    # Check via lsusb for common fingerprint reader vendors
    if lsusb 2>/dev/null | grep -qiE 'fingerprint|validity|synaptics.*fp|elan.*fp|goodix|fpc.*sensor|authentitech'; then
        return 0
    fi

    # Check for fprintd-compatible devices
    if [[ -d /sys/class/fingerprint ]]; then
        return 0
    fi

    return 1
}

# Get fingerprint packages
get_fingerprint_packages() {
    echo "fprintd libfprint"
}

# Detect Thunderbolt controller
detect_thunderbolt() {
    # Check for Thunderbolt controllers
    if [[ -d /sys/bus/thunderbolt ]]; then
        if [[ -n "$(ls -A /sys/bus/thunderbolt/devices 2>/dev/null)" ]]; then
            return 0
        fi
    fi

    # Check via lspci
    if lspci 2>/dev/null | grep -qi 'thunderbolt'; then
        return 0
    fi

    return 1
}

# Get Thunderbolt packages
get_thunderbolt_packages() {
    echo "bolt"
}

# Detect sensors (accelerometer, ambient light sensor, etc.)
detect_sensors() {
    # Check for IIO (Industrial I/O) sensors
    if [[ -d /sys/bus/iio/devices ]]; then
        for device in /sys/bus/iio/devices/iio:device*; do
            if [[ -d "${device}" ]]; then
                # Check for accelerometer or light sensor
                if [[ -f "${device}/in_accel_x_raw" ]] || \
                   [[ -f "${device}/in_illuminance_raw" ]] || \
                   [[ -f "${device}/in_proximity_raw" ]]; then
                    return 0
                fi
            fi
        done
    fi

    return 1
}

# Get sensor packages
get_sensor_packages() {
    echo "iio-sensor-proxy"
}

# Detect if system is a laptop (for power management)
detect_laptop() {
    # Check for battery
    if [[ -d /sys/class/power_supply ]]; then
        for supply in /sys/class/power_supply/*; do
            if [[ -f "${supply}/type" ]]; then
                local type
                type="$(cat "${supply}/type" 2>/dev/null || true)"
                if [[ "${type}" == "Battery" ]]; then
                    return 0
                fi
            fi
        done
    fi

    # Check DMI chassis type
    if [[ -f /sys/class/dmi/id/chassis_type ]]; then
        local chassis
        chassis="$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "0")"
        # Laptop chassis types: 8=Portable, 9=Laptop, 10=Notebook, 14=Sub Notebook, 31=Convertible, 32=Detachable
        case "${chassis}" in
            8|9|10|14|31|32)
                return 0
                ;;
        esac
    fi

    return 1
}

# Get power management packages
get_power_packages() {
    # Use power-profiles-daemon for modern hardware (integrates with GNOME/KDE)
    # Avoiding TLP as it can conflict and needs more configuration
    echo "power-profiles-daemon thermald"
}

# Detect touchscreen
detect_touchscreen() {
    # Check for touchscreen input devices
    if [[ -d /sys/class/input ]]; then
        for input in /sys/class/input/event*; do
            if [[ -f "${input}/device/capabilities/abs" ]]; then
                local caps
                caps="$(cat "${input}/device/capabilities/abs" 2>/dev/null || true)"
                # Touchscreens have ABS_MT_POSITION capabilities
                if [[ -n "${caps}" ]] && [[ "${caps}" != "0" ]]; then
                    # Check device name for touchscreen indicators
                    local name=""
                    [[ -f "${input}/device/name" ]] && name="$(cat "${input}/device/name" 2>/dev/null || true)"
                    if echo "${name}" | grep -qiE 'touch|wacom|elan.*touch|goodix'; then
                        return 0
                    fi
                fi
            fi
        done
    fi

    return 1
}

# Detect smart card reader
detect_smartcard() {
    # Check via lsusb for common smart card readers
    if lsusb 2>/dev/null | grep -qiE 'smart ?card|yubikey|nitrokey|solokey|feitian|gemalto|omnikey'; then
        return 0
    fi

    # Check for PC/SC devices
    if [[ -d /sys/class/pcsc ]]; then
        return 0
    fi

    return 1
}

# Get smart card packages
get_smartcard_packages() {
    echo "ccid opensc pcsclite"
}

# Detect if system has backlight control
detect_backlight() {
    [[ -d /sys/class/backlight ]] && [[ -n "$(ls -A /sys/class/backlight 2>/dev/null)" ]]
}

# ============================================
# FIRMWARE DETECTION
# ============================================

# Detect if SOF (Sound Open Firmware) is needed for Intel audio
# Required for Intel 11th gen+ and some 10th gen laptops
detect_sof_firmware() {
    # Check for Intel audio devices that need SOF
    if lspci 2>/dev/null | grep -qiE 'audio.*intel.*(tiger|alder|raptor|meteor|lunar|ice|jasper|elkhart)'; then
        return 0
    fi

    # Check for specific Intel audio device IDs that need SOF
    # These are common SOF-required device IDs
    if lspci -nn 2>/dev/null | grep -qiE '\[8086:(a0c8|43c8|51c8|51cc|51cd|51ce|51cf|54c8|7ad0|7a50)\]'; then
        return 0
    fi

    # Check kernel messages for SOF requests
    if dmesg 2>/dev/null | grep -qi 'sof.*firmware'; then
        return 0
    fi

    return 1
}

# Detect Marvell wireless/ethernet devices needing extra firmware
detect_marvell_firmware() {
    if lspci 2>/dev/null | grep -qiE 'marvell.*(wireless|wifi|ethernet|network)'; then
        return 0
    fi
    if lsusb 2>/dev/null | grep -qiE 'marvell'; then
        return 0
    fi
    return 1
}

# Detect Broadcom wireless devices needing firmware
detect_broadcom_firmware() {
    # Check for Broadcom wireless
    if lspci 2>/dev/null | grep -qiE 'broadcom.*(wireless|wifi|bcm)'; then
        return 0
    fi
    if lspci -nn 2>/dev/null | grep -qiE '\[14e4:(43|44|4727)\]'; then
        return 0
    fi
    return 1
}

# Detect Qualcomm/Atheros devices needing firmware
detect_qualcomm_firmware() {
    # Qualcomm wireless/bluetooth (common in newer laptops)
    if lspci 2>/dev/null | grep -qiE 'qualcomm|qca|atheros.*wifi'; then
        return 0
    fi
    if lsusb 2>/dev/null | grep -qiE 'qualcomm|qca'; then
        return 0
    fi
    return 1
}

# Detect Realtek devices that may need additional firmware
detect_realtek_firmware() {
    # Some Realtek wireless need extra firmware beyond linux-firmware
    if lspci 2>/dev/null | grep -qiE 'realtek.*(wireless|wifi|rtl8)'; then
        return 0
    fi
    if lsusb 2>/dev/null | grep -qiE 'realtek.*(wireless|wifi|rtl8)'; then
        return 0
    fi
    return 1
}

# Detect MediaTek wireless devices needing firmware
detect_mediatek_firmware() {
    if lspci 2>/dev/null | grep -qiE 'mediatek|mt7'; then
        return 0
    fi
    if lsusb 2>/dev/null | grep -qiE 'mediatek|mt7'; then
        return 0
    fi
    return 1
}

# Detect Intel wireless needing specific firmware
detect_intel_wireless_firmware() {
    # Intel wireless adapters (most are covered by linux-firmware, but check anyway)
    if lspci 2>/dev/null | grep -qiE 'intel.*(wireless|wifi|centrino|wi-fi)'; then
        return 0
    fi
    return 1
}

# Get list of additional firmware packages needed
get_firmware_packages() {
    local packages=()

    # SOF firmware for Intel audio (11th gen+)
    if detect_sof_firmware; then
        packages+=("sof-firmware")
    fi

    # Marvell firmware
    if detect_marvell_firmware; then
        packages+=("linux-firmware-marvell")
    fi

    # Broadcom firmware - use b43-fwcutter for open source driver
    if detect_broadcom_firmware; then
        packages+=("b43-fwcutter")
    fi

    # Qualcomm/Atheros - usually in linux-firmware but ensure qcom is there
    if detect_qualcomm_firmware; then
        packages+=("linux-firmware-qcom")
    fi

    # MediaTek firmware
    if detect_mediatek_firmware; then
        packages+=("linux-firmware-mediatek")
    fi

    # ALSA firmware for some audio devices (UCM configs)
    if detect_audio; then
        packages+=("alsa-ucm-conf")
    fi

    # Return unique packages
    if [[ ${#packages[@]} -gt 0 ]]; then
        printf '%s\n' "${packages[@]}" | sort -u | tr '\n' ' '
    fi
}

# Check for missing firmware by scanning dmesg
detect_missing_firmware() {
    local missing=()

    # Parse dmesg for firmware loading failures
    while IFS= read -r line; do
        if [[ "${line}" =~ failed\ to\ load\ firmware|firmware.*not\ found|Direct\ firmware\ load.*failed ]]; then
            # Extract firmware name if possible
            local fw_name
            fw_name=$(echo "${line}" | grep -oE '[a-zA-Z0-9_/-]+\.(bin|fw|ucode)' | head -1)
            if [[ -n "${fw_name}" ]]; then
                missing+=("${fw_name}")
            fi
        fi
    done < <(dmesg 2>/dev/null | grep -iE 'firmware')

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf '%s\n' "${missing[@]}" | sort -u
        return 0
    fi
    return 1
}

# Get total RAM in KB
get_total_ram() {
    grep MemTotal /proc/meminfo | awk '{print $2}'
}

# Get total RAM in human readable format
get_total_ram_human() {
    local ram_kb
    ram_kb="$(get_total_ram)"
    local ram_gb=$(( ram_kb / 1024 / 1024 ))
    echo "${ram_gb}GB"
}

# Print hardware detection summary
hardware_summary() {
    print_separator "-"
    echo "Hardware Detection Summary"
    print_separator "-"

    echo "CPU: $(detect_cpu_vendor)"
    local gpus
    gpus="$(detect_gpu)"
    echo "GPU: ${gpus}"
    # Show NVIDIA generation if applicable
    if [[ "${gpus}" == *"nvidia"* ]]; then
        local nvidia_gen
        nvidia_gen="$(detect_nvidia_generation)"
        if [[ -n "${nvidia_gen}" ]]; then
            echo "NVIDIA generation: ${nvidia_gen} (using nvidia-open: $([[ "${nvidia_gen}" != "older" ]] && echo "yes" || echo "no"))"
        fi
    fi
    echo "RAM: $(get_total_ram_human)"

    if detect_laptop; then
        echo "Form factor: Laptop"
    else
        echo "Form factor: Desktop"
    fi

    if detect_audio; then
        echo "Audio: detected"
    else
        echo "Audio: not detected"
    fi

    if detect_bluetooth; then
        echo "Bluetooth: detected"
    else
        echo "Bluetooth: not detected"
    fi

    if detect_wireless; then
        echo "Wireless: detected"
    else
        echo "Wireless: not detected"
    fi

    if detect_wwan; then
        echo "WWAN: detected"
    else
        echo "WWAN: not detected"
    fi

    if detect_fingerprint; then
        echo "Fingerprint: detected"
    else
        echo "Fingerprint: not detected"
    fi

    if detect_thunderbolt; then
        echo "Thunderbolt: detected"
    else
        echo "Thunderbolt: not detected"
    fi

    if detect_sensors; then
        echo "Sensors: detected (accelerometer/light)"
    else
        echo "Sensors: not detected"
    fi

    if detect_touchscreen; then
        echo "Touchscreen: detected"
    else
        echo "Touchscreen: not detected"
    fi

    if detect_smartcard; then
        echo "Smart card: detected"
    else
        echo "Smart card: not detected"
    fi

    if detect_backlight; then
        echo "Backlight: controllable"
    fi

    # Firmware detection
    local fw_packages
    fw_packages="$(get_firmware_packages)"
    if [[ -n "${fw_packages}" ]]; then
        echo "Extra firmware: ${fw_packages}"
    fi

    # Check for missing firmware warnings
    local missing_fw
    if missing_fw="$(detect_missing_firmware 2>/dev/null)"; then
        echo "Missing firmware: ${missing_fw}"
    fi

    local vm
    vm="$(detect_vm)"
    if [[ "${vm}" != "none" ]]; then
        echo "Virtualization: ${vm}"
    fi

    if detect_tpm2; then
        echo "TPM2: available"
    else
        echo "TPM2: not available"
    fi

    # Secure Boot status
    local sb_status
    sb_status="$(get_secure_boot_status)"
    case "${sb_status}" in
        enabled)
            echo "Secure Boot: enabled (keys enrolled)"
            ;;
        setup_mode)
            echo "Secure Boot: setup mode (ready for key enrollment)"
            ;;
        disabled)
            echo "Secure Boot: disabled"
            ;;
        *)
            echo "Secure Boot: not available"
            ;;
    esac

    print_separator "-"
}
