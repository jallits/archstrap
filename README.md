# archstrap

A modern, opinionated Arch Linux installation script with a user-friendly TUI. Provides a minimal, secure base system ready for your preferred desktop environment.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=arch-linux&logoColor=white)

## Features

- **User-Friendly TUI**: Dialog-based interface for easy configuration
- **Full Disk Encryption**: LUKS2 with optional detached header on removable storage
- **Modern Filesystem**: BTRFS with subvolumes and automatic snapshots via snapper
- **Secure Boot**: Unified Kernel Image (UKI) with Secure Boot support
- **TPM2 Integration**: Automatic unlock with passphrase fallback via Plymouth
- **Security Hardening**: Comprehensive hardening per [Arch Wiki Security](https://wiki.archlinux.org/title/Security)
- **Hardware Detection**: Auto-configures CPU microcode, GPU drivers, audio, Bluetooth, fingerprint readers, Thunderbolt, sensors, and more
- **Mirror Optimization**: Reflector auto-selects fastest mirrors based on your location
- **Firmware Updates**: fwupd integration for BIOS/UEFI updates
- **Modern Networking**: systemd-networkd + systemd-resolved + iwd for wireless
- **Resume Support**: Installation can be resumed if interrupted
- **Dry-Run Mode**: Test the installation flow without making changes
- **Automatic Timezone**: Location-based timezone updates via GeoClue
- **Minimal Base**: No GUI by default - install your preferred desktop or see [Hyprstrap](https://github.com/jallits/hyprstrap) for a complete setup

## Screenshots

```
┌────────────────── Welcome to Archstrap ──────────────────┐
│                                                          │
│     _             _         _                            │
│    / \   _ __ ___| |__  ___| |_ _ __ __ _ _ __           │
│   / _ \ | '__/ __| '_ \/ __| __| '__/ _` | '_ \          │
│  / ___ \| | | (__| | | \__ \ |_| | | (_| | |_) |         │
│ /_/   \_\_|  \___|_| |_|___/\__|_|  \__,_| .__/          │
│                                          |_|             │
│                                                          │
│ Modern, opinionated Arch Linux installer                 │
│                                                          │
│ This installer will guide you through setting up:        │
│ • LUKS2 encrypted root partition                         │
│ • BTRFS filesystem with subvolumes                       │
│ • Unified Kernel Image (UKI) with Secure Boot            │
│ • TPM2 automatic unlock                                  │
│ • Security hardening per Arch Wiki                       │
│                                                          │
│                        < OK >                            │
└──────────────────────────────────────────────────────────┘
```

## Requirements

- UEFI firmware (no legacy BIOS support)
- x86_64 processor
- Boot from Arch Linux ISO
- Internet connection
- At least 512MB RAM
- At least one disk for installation

## Quick Start

Boot from the Arch Linux ISO and run:

```bash
curl -sL https://raw.githubusercontent.com/jallits/archstrap/master/install.sh -o install.sh
chmod +x install.sh
./install.sh
```

Or clone the repository:

```bash
git clone https://github.com/jallits/archstrap.git
cd archstrap
./install.sh
```

## Usage

```
Usage: install.sh [OPTIONS]

Options:
    -h, --help      Show help message
    -d, --dry-run   Show what would be done without making changes
    -r, --resume    Resume from a previous interrupted installation
    -v, --verbose   Enable verbose output
    --no-color      Disable colored output
```

### Examples

```bash
# Normal installation with TUI
./install.sh

# Test installation flow without making changes
./install.sh --dry-run

# Resume a previously interrupted installation
./install.sh --resume

# Verbose output for debugging
./install.sh --verbose
```

## What Gets Installed

### Disk Layout

| Mount Point | Subvolume | Purpose |
|-------------|-----------|---------|
| `/` | `@` | Root filesystem |
| `/home` | `@home` | User home directories |
| `/.snapshots` | `@snapshots` | Root snapshots (snapper) |
| `/swap` | `@swap` | Swapfile for hibernation |
| `/var/cache` | `@var_cache` | Package cache |
| `/var/log` | `@var_log` | System logs |
| `/home/{user}` | (nested) | Per-user home subvolume |
| `/home/{user}/.snapshots` | (nested) | Per-user snapshots |

### Partition Scheme

Following the Discoverable Partitions Specification:
- **EFI System Partition**: 512MB FAT32 (optionally on removable storage)
  - Mounted at `/efi` - contains only the UKI (Unified Kernel Image)
  - `/boot` remains on encrypted root to minimize unencrypted data exposure
- **Root Partition**: LUKS2-encrypted BTRFS (header optionally on removable storage)
- **Secrets Partition**: Optional LUKS2-encrypted ext4 on removable storage for sensitive data

### Packages

- **Base**: base, linux/linux-hardened, linux-firmware, btrfs-progs
- **Boot**: systemd-ukify, sbsigntools, efibootmgr, tpm2-tools, plymouth (with early KMS)
- **Shell**: zsh (default), sudo, vim
- **Network**: iwd, systemd-resolvconf
- **Audio**: pipewire, pipewire-alsa, pipewire-pulse, wireplumber
- **Bluetooth**: bluez, bluez-utils
- **Security**: libpwquality, nftables, apparmor
- **System Management**: reflector, fwupd, snapper, snap-pac
- **CPU Microcode**: intel-ucode or amd-ucode (auto-detected)
- **GPU Drivers**: Auto-detected (Intel, AMD, NVIDIA with nvidia-open for RTX, or hybrid)

### Hardware Detection

The installer automatically detects and configures the following hardware:

| Hardware | Detection | Packages Installed |
|----------|-----------|-------------------|
| CPU Microcode | `/proc/cpuinfo` vendor | intel-ucode / amd-ucode |
| GPU | lspci VGA/3D devices | mesa, vulkan, nvidia-open (RTX) or nvidia |
| Audio | `/sys/class/sound`, lspci | pipewire, wireplumber, alsa-ucm-conf |
| Bluetooth | `/sys/class/bluetooth`, lspci/lsusb | bluez, bluez-utils |
| Fingerprint | lsusb (Validity, Synaptics, etc.) | fprintd, libfprint |
| Thunderbolt | `/sys/bus/thunderbolt`, lspci | bolt |
| Sensors | IIO devices (accel, light) | iio-sensor-proxy |
| Laptop | Battery, DMI chassis type | power-profiles-daemon, thermald |
| Smart Card | lsusb (YubiKey, etc.) | ccid, opensc, pcsclite |
| Touchscreen | Input device capabilities | (libinput built-in) |
| WWAN | lspci/lsusb cellular modems | modemmanager, usb_modeswitch |
| VM Guest | systemd-detect-virt, DMI | Guest tools (VBox/VMware/QEMU) |

### Hardware Quirks

The installer automatically detects and applies workarounds for known hardware issues:

| Hardware | Issue | Fix Applied |
|----------|-------|-------------|
| QCA6390 (ath11k) | WiFi/Bluetooth race condition, suspend failures | `memmap=12M$20M` kernel param, systemd suspend/resume services |
| NVIDIA GPUs | Suspend/resume memory issues | Power management module options, systemd services |
| RTL8852BE (rtw89) | WiFi stability issues | ASPM disabled via module options |

### Firmware Detection

Additional firmware packages are automatically detected and installed:

| Firmware | Detection | Package |
|----------|-----------|---------|
| Intel SOF Audio | Intel 11th gen+ audio devices | sof-firmware |
| Marvell | Marvell wireless/ethernet | linux-firmware-marvell |
| Broadcom | Broadcom wireless adapters | b43-fwcutter |
| Qualcomm | Qualcomm/Atheros wireless | linux-firmware-qcom |
| MediaTek | MediaTek wireless adapters | linux-firmware-mediatek |
| ALSA UCM | Audio device configs | alsa-ucm-conf |

The installer also scans `dmesg` for missing firmware warnings to help identify any additional firmware needs.

**NVIDIA driver selection:**

| GPU Generation | Examples | Driver |
|----------------|----------|--------|
| Ada Lovelace | RTX 4000 series | nvidia-open |
| Ampere | RTX 3000 series | nvidia-open |
| Turing | RTX 2000, GTX 1600 series | nvidia-open |
| Older (Pascal, Maxwell, etc.) | GTX 1000 series and older | nvidia (proprietary) |

*Note: Non-DKMS packages are used for reliability with UKI + Secure Boot. Kernel headers are installed to allow switching to DKMS versions if you later install multiple kernels.*

### Mirror and System Management

| Feature | Tool | Configuration |
|---------|------|---------------|
| Mirror optimization | reflector | Runs before install, weekly timer on target |
| Country detection | IP geolocation | Auto-configures reflector country |
| Firmware updates | fwupd | Checks for BIOS/UEFI updates, weekly refresh |
| Time sync | systemd-timesyncd | NTP-based clock synchronization |
| Timezone detection | automatic-timezoned (AUR) | Auto-updates timezone based on location via GeoClue |

**Reflector** optimizes the pacman mirror list:
- Uses HTTPS mirrors only
- Filters mirrors synced within 12 hours
- Sorts by download speed
- Auto-detects your country for faster mirrors

**fwupd** manages firmware updates:
- Supports UEFI firmware updates from LVFS
- Run `fwupdmgr get-updates` to check for updates
- Run `fwupdmgr update` to apply updates

### Snapshot Management

Automatic BTRFS snapshots are configured using **snapper**:

| Configuration | Subvolume | Location | Managed By |
|---------------|-----------|----------|------------|
| root | `@` | `/.snapshots` | root (sudo) |
| {username} | `/home/{user}` | `/home/{user}/.snapshots` | user |

**Per-user snapshots:**
- Each user has their own snapper configuration
- Users can manage their own snapshots without sudo
- Snapshots stored in `~/.snapshots` (BTRFS subvolume)

**Snapshot retention policy:**

| Type | Root | User Home |
|------|------|-----------|
| Hourly | 5 | 5 |
| Daily | 7 | 7 |
| Weekly | 4 | 4 |
| Monthly | 6 | 12 |
| Yearly | 2 | 5 |

**snap-pac** automatically creates root snapshots before and after pacman transactions.

**Common snapper commands:**
```bash
# Root snapshots (requires sudo)
sudo snapper -c root list
sudo snapper -c root create -d "Before major change"

# User home snapshots (no sudo needed)
snapper -c $USER list
snapper -c $USER create -d "Before cleanup"
snapper -c $USER diff 1..2
snapper -c $USER undochange 1..0
```

## Security Features

All security hardening follows [Arch Wiki Security recommendations](https://wiki.archlinux.org/title/Security).

### LUKS2 Encryption
- AES-XTS-PLAIN64 cipher with 512-bit key
- Argon2id key derivation
- Optional detached header on removable storage for enhanced security

### Secure Boot
- Unified Kernel Image (UKI) signed with sbctl
- Automatic setup mode detection via EFI variables
- Keys automatically enrolled if Secure Boot is in setup mode
- Provides guidance for enabling setup mode if Secure Boot is already enabled
- UKIs are signed even when Secure Boot is disabled (ready for future enablement)
- Early KMS enabled (GPU modules in initramfs for seamless Plymouth boot)

### TPM2 Unlock
- Automatic LUKS unlock using TPM2 with PCR 7 binding
- Falls back to Plymouth passphrase prompt if TPM unlock fails

### Encrypted Secrets Storage
When EFI is installed on removable storage, optionally create an encrypted secrets partition:
- Uses remaining space on removable device after EFI partition
- LUKS2 encryption (same or separate passphrase)
- Stores GPG keys (`~/.gnupg`), SSH keys (`~/.ssh`), and password-store (`~/.password-store`)
- Symlinks created automatically in user's home directory
- Secrets only accessible when removable device is inserted

### Kernel Hardening
- Optional **linux-hardened** kernel with enhanced exploit mitigations
- Comprehensive sysctl hardening (kernel.kptr_restrict, ptrace_scope, etc.)
- Network stack hardening (SYN cookies, rp_filter, no redirects)

### Filesystem Security
- Secure mount options: `nodev`, `nosuid`, `noexec` on /efi, /home, /var
- Restrictive umask (0077) for new files
- Protected hardlinks/symlinks via sysctl

### Access Control
- **Root account locked** - use sudo for administration
- **AppArmor** mandatory access control (optional)
- **nftables** firewall with restrictive defaults (deny inbound)
- Password policy enforcement via libpwquality
- Account lockout via pam_faillock

### Network Security
- DNS-over-TLS with privacy-respecting resolvers (Cloudflare, Quad9)
- DNSSEC validation enabled
- SSH hardening configuration (key-only auth, no root login)

## Post-Installation

### GUI Environment

archstrap provides a **minimal base system** without a display manager, window manager, or desktop environment. This gives you full control over your graphical environment.

**Options:**

1. **[Hyprstrap](https://github.com/jallits/hyprstrap)** - A companion project that builds on archstrap to provide a complete Hyprland-based desktop environment with:
   - Hyprland (tiling Wayland compositor)
   - Pre-configured applications and tools
   - Beautiful theming and aesthetics
   - Optimized for productivity

2. **Install your preferred environment** - After reboot, install any desktop environment or window manager you prefer:
   ```bash
   # Example: GNOME
   sudo pacman -S gnome gnome-extra gdm
   sudo systemctl enable gdm

   # Example: KDE Plasma
   sudo pacman -S plasma kde-applications sddm
   sudo systemctl enable sddm

   # Example: i3 + LightDM
   sudo pacman -S i3-wm i3status dmenu lightdm lightdm-gtk-greeter
   sudo systemctl enable lightdm
   ```

### Next Steps

After rebooting into your new system:
1. Log in as the user you created during installation
2. Configure networking if needed (WiFi connections, etc.)
3. Install and configure your preferred GUI environment
4. Set up additional applications and services

## Project Structure

```
archstrap/
├── install.sh              # Main entry point
├── lib/
│   ├── common.sh           # Logging, colors, utilities
│   ├── config.sh           # Configuration and state management
│   ├── disk.sh             # Disk operations
│   ├── hardware.sh         # Hardware detection
│   ├── network.sh          # Network configuration
│   ├── tui.sh              # Dialog-based TUI
│   └── quirks.sh           # Hardware quirks/workarounds
├── steps/
│   ├── 00-preflight.sh     # System validation
│   ├── 01-configure.sh     # TUI configuration wizard
│   ├── 02-partition.sh     # Disk partitioning
│   ├── 03-encryption.sh    # LUKS2 setup
│   ├── 04-filesystem.sh    # BTRFS creation
│   ├── 05-mount.sh         # Mount filesystems
│   ├── 06-pacstrap.sh      # Install base system
│   ├── 07-fstab.sh         # Generate fstab
│   ├── 08-chroot-prep.sh   # Prepare chroot
│   ├── 09-locale.sh        # Locale and timezone
│   ├── 10-users.sh         # User creation
│   ├── 11-hardware.sh      # Hardware + security config
│   ├── 11a-quirks.sh       # Hardware quirks/workarounds
│   ├── 12-network.sh       # Network setup
│   ├── 13-boot.sh          # Boot configuration
│   ├── 14-aur.sh           # AUR helper
│   └── 15-finalize.sh      # Cleanup and finish
└── configs/
    ├── security/           # Security hardening configs
    ├── snapper/            # Snapper snapshot configs
    ├── networkd/           # Network templates
    ├── plymouth/           # Plymouth theme
    ├── iwd/                # Wireless configuration
    └── reflector.conf      # Mirror optimization config
```

## Configuration Options

The TUI will guide you through configuring:

**Disk & Encryption:**
- Target disk for installation
- EFI partition location (internal or removable)
- LUKS header location (with root or removable)
- Encrypted secrets partition on removable storage (for GPG/SSH keys)
- Encryption passphrase(s)

**System:**
- Hostname
- Username and password
- Timezone (auto-detected)
- Locale and keyboard layout
- AUR helper (paru, yay, or none)

**Security (defaults to maximum security):**
- Hardened kernel (linux-hardened vs standard)
- Firewall (nftables with restrictive defaults)
- AppArmor (mandatory access control)

**Hardware (auto-detected):**
- All hardware is automatically detected and configured
- No manual intervention required for supported devices
- Run with `--verbose` to see detected hardware

## Testing

Test in a UEFI-enabled virtual machine:

### QEMU
```bash
# Create disk image
qemu-img create -f qcow2 disk.qcow2 20G

# Run VM
qemu-system-x86_64 -enable-kvm -m 4G \
  -bios /usr/share/edk2-ovmf/x64/OVMF.fd \
  -drive file=disk.qcow2,format=qcow2 \
  -cdrom archlinux.iso
```

### VirtualBox
Enable EFI in System settings before booting from ISO.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test in a VM with `--dry-run`
4. Submit a pull request

## License

MIT
