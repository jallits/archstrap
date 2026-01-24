# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

archstrap is an opinionated Arch Linux installation script targeting UEFI x86_64 systems booted from the Arch Linux ISO. It features a dialog-based TUI for user-friendly configuration.

## Project Structure

```
archstrap/
├── install.sh              # Main entry point, orchestrates steps
├── lib/
│   ├── common.sh           # Logging, colors, utilities, error handling
│   ├── config.sh           # Configuration and state management
│   ├── disk.sh             # Disk operations (partitioning, LUKS, BTRFS)
│   ├── hardware.sh         # Hardware detection (CPU, GPU, audio, bluetooth)
│   ├── network.sh          # Network configuration generators
│   ├── tui.sh              # Dialog-based TUI functions
│   └── quirks.sh           # Hardware quirks detection and workarounds
├── steps/
│   ├── 00-preflight.sh     # System validation
│   ├── 01-configure.sh     # TUI configuration wizard
│   ├── 02-partition.sh     # Disk partitioning
│   ├── 03-encryption.sh    # LUKS2 setup
│   ├── 04-filesystem.sh    # BTRFS with subvolumes
│   ├── 05-mount.sh         # Mount filesystems
│   ├── 06-pacstrap.sh      # Base system installation
│   ├── 07-fstab.sh         # Generate fstab with secure mount options
│   ├── 08-chroot-prep.sh   # Prepare chroot environment
│   ├── 09-locale.sh        # Locale, timezone, hostname
│   ├── 10-users.sh         # User creation, root lockout
│   ├── 11-hardware.sh      # Hardware + security configuration
│   ├── 11a-quirks.sh       # Hardware quirks/workarounds
│   ├── 12-network.sh       # Network setup
│   ├── 13-boot.sh          # UKI, Secure Boot, TPM2, Plymouth
│   ├── 14-aur.sh           # AUR helper installation
│   ├── 15-finalize.sh      # Cleanup and completion
│   └── chroot/             # Scripts for chroot operations
└── configs/
    ├── security/           # Security hardening configs
    │   ├── sysctl-hardening.conf
    │   ├── nftables.conf
    │   ├── pwquality.conf
    │   └── ssh_hardening.conf
    ├── snapper/            # Snapper snapshot configs
    │   ├── root.conf       # Root filesystem config
    │   └── user-home.conf  # Template for per-user configs
    ├── networkd/           # systemd-networkd templates
    ├── plymouth/           # Plymouth theme
    ├── iwd/                # Wireless configuration
    └── reflector.conf      # Mirror optimization config
```

## Architecture Decisions

### User Interface
- Dialog-based TUI using `dialog` (ncurses)
- Custom Arch-themed color scheme
- Fallback to CLI prompts if dialog unavailable

### Disk Layout
- Partition table follows the Discoverable Disk Partition Specification
- EFI partition optionally installed to removable storage (SD card, USB)
- Root partition encrypted with LUKS2 (header optionally on removable storage)
- Configurable encryption strength (standard, high, maximum with integrity)
- Optional encrypted secrets partition on removable storage for GPG/SSH keys
- BTRFS filesystem with subvolumes: `@`, `@home`, `@snapshots`, `@swap`, `@var_cache`, `@var_log`
- Per-user home directories as nested BTRFS subvolumes
- Swapfile sized for hibernation support

### Encryption Strength Levels
- **Standard**: AES-256-XTS, Argon2id with default parameters (~2s unlock)
- **High**: AES-256-XTS, Argon2id with 4GB memory, 5s unlock time
- **Maximum**: High settings + HMAC-SHA256 integrity (authenticated encryption, ~2x disk overhead)

### Snapshot Management
- Snapper configured for root (`/`) with admin-only access
- Per-user snapper configs for each user's home directory
- Users can manage their own snapshots without sudo
- Automatic timeline snapshots (hourly, daily, weekly, monthly, yearly)
- snap-pac for automatic pre/post pacman transaction snapshots (root only)
- Separate snapshot subvolumes for clean rollback capability

### Secrets Storage
- Optional encrypted partition on removable storage for sensitive data
- Stores GPG keys, SSH keys, and password-store
- Symlinks from ~/.gnupg, ~/.ssh, ~/.password-store to secrets partition
- Same or separate passphrase from system encryption
- Only accessible when removable device is inserted

### Boot & Security
- Unified Kernel Image (UKI)
- Secure Boot support via sbctl with automatic setup mode detection
- Keys enrolled automatically when in setup mode, guidance provided otherwise
- UKIs signed even when Secure Boot disabled (ready for future enablement)
- TPM2 unlock for LUKS2 with passphrase fallback via Plymouth
- Early KMS: GPU modules (nvidia/i915/amdgpu) added to initramfs for seamless Plymouth
- Optional linux-hardened kernel
- Plymouth theme: black background, spinner

### Security Hardening (Arch Wiki Recommendations)
- Root account locked (sudo-only administration)
- Kernel sysctl hardening (kptr_restrict, ptrace_scope, etc.)
- Secure mount options (nodev, nosuid, noexec)
- nftables firewall with deny-inbound policy
- AppArmor mandatory access control
- Password policy via libpwquality
- Restrictive umask (0077)
- SSH hardening configuration
- DNS-over-TLS with DNSSEC

### Hardware Quirks
- Auto-detect and apply workarounds for known hardware issues
- QCA6390 (ath11k): WiFi/Bluetooth race condition fix, suspend/resume services
- NVIDIA: Suspend/resume power management configuration
- RTL8852BE (rtw89): ASPM disabled for stability

### Hardware Detection
- Auto-detect and install appropriate CPU microcode (Intel/AMD)
- Auto-detect GPU drivers (Intel, AMD, NVIDIA with nvidia-open for Turing+, hybrid graphics)
  - Uses non-DKMS packages for reliability with UKI + Secure Boot
  - Kernel headers installed to allow DKMS conversion if users add multiple kernels later
  - NVIDIA hybrid: nvidia-prime installed (provides `prime-run` wrapper for Wayland compositors)
- Auto-detect and configure audio (Pipewire + Wireplumber)
- Auto-detect and configure Bluetooth (bluez)
- Auto-detect fingerprint readers (fprintd + libfprint)
- Auto-detect Thunderbolt controllers (bolt)
- Auto-detect sensors for 2-in-1 devices (iio-sensor-proxy)
- Auto-detect laptops for power management (power-profiles-daemon, thermald)
- Auto-detect smart card readers (pcsclite, ccid)
- Auto-detect touchscreens
- Auto-detect VM environment (VirtualBox, VMware, KVM/QEMU)

### Firmware Detection
- Auto-detect Intel SOF audio firmware requirements (11th gen+)
- Auto-detect Marvell wireless/ethernet firmware
- Auto-detect Broadcom wireless firmware (b43)
- Auto-detect Qualcomm/Atheros firmware
- Auto-detect MediaTek wireless firmware
- Scan dmesg for missing firmware warnings
- Install ALSA UCM configs for audio devices

### Mirror and Firmware Management
- Reflector optimizes mirrors before installation (geo-detected country)
- Reflector configured on target with weekly timer for ongoing optimization
- fwupd installed for BIOS/UEFI firmware updates
- Automatic check for available firmware updates during installation

### Time and Timezone
- NTP time synchronization via systemd-timesyncd
- Automatic timezone detection via automatic-timezoned (AUR) + GeoClue
- Timezone updates automatically when location changes (e.g., travel)

### Networking
- iwd for wireless
- systemd-networkd + systemd-resolved
- Configurations for ethernet, WLAN, and WWAN

### User Environment
- ZSH as default shell
- Home directories as BTRFS subvolumes with snapshots
- xdg-user-dirs for directory structure
- GeoClue for timezone auto-detection (with manual fallback)

### Package Constraints
- Avoid GNOME Foundation software
- User-selectable AUR helper (yay or paru)

## Development Guidelines

### Shell Standards
- `#!/bin/bash` with `set -euo pipefail`
- Quote all variables: `"${variable}"`
- Use `[[ ]]` for conditionals
- Use `run()` function for commands (supports dry-run mode)
- Use `run_destructive()` for destructive operations

### TUI Guidelines
- Use `tui_*` functions from lib/tui.sh
- Always cleanup with `tui_cleanup` on exit
- Handle dialog cancel (return code 1) gracefully

### Step Structure
Each step file must define a `run_step()` function:
```bash
run_step() {
    step_start "XX-name" "Description"
    # ... step logic ...
    state_save
    log_info "Step complete"
}
```

### Testing
Test in a UEFI-enabled VM (QEMU/VirtualBox) booted from Arch Linux ISO:
```bash
# Dry-run mode (no changes)
./install.sh --dry-run

# Verbose mode
./install.sh --verbose

# Resume interrupted installation
./install.sh --resume
```
