# 🚀 ArchInstall - Advanced Arch Linux Installer

> **A comprehensive, modular, and user-friendly Arch Linux installation script that bridges the gap between manual installation and automated tools. Features Btrfs snapshots, interactive package selection, and superior customization compared to the official archinstall.**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org)
[![Bash](https://img.shields.io/badge/Bash-4.4+-green.svg)](https://www.gnu.org/software/bash/)

---

## 🎯 Project Philosophy

ArchInstall is designed for users who want the power and flexibility of Arch Linux with the convenience of guided installation. Unlike the official `archinstall` Python script, this Bash-based solution provides:

- **Full transparency** - Every step is visible and logged
- **Modular architecture** - Easy to understand, modify, and extend
- **Interactive guidance** - No need to memorize complex commands
- **Comprehensive features** - Everything from basic installation to advanced configurations
- **The "Arch Way"** - Maintains Arch Linux's DIY philosophy while reducing complexity
- **Professional TUI** - Beautiful, real-time progress display inspired by Linutil
- **Live ISO Ready** - Pre-compiled binaries for immediate use on any Arch live media

### 🆚 **ArchInstall (Bash) vs. Official archinstall (Python)**

| Feature | ArchInstall (This) | Official archinstall |
|---------|-------------------|---------------------|
| **Btrfs Snapshots** | ✅ Full support with snapper | ✅ Basic support |
| **Interactive Package Search** | ✅ Real-time search & install | ❌ Pre-configured only |
| **AUR Package Discovery** | ✅ Web API fallback search | ❌ Limited |
| **Transparency** | ✅ Full logging & visibility | ❌ Black box |
| **Customization** | ✅ Modular & extensible | ❌ Fixed workflows |
| **Error Handling** | ✅ Detailed diagnostics | ❌ Basic error messages |
| **Boot Integration** | ✅ GRUB snapshot menus | ❌ Limited |
| **Package Management** | ✅ Smart conditional installs | ❌ Static package lists |
| **TUI Experience** | ✅ Professional Rust-based TUI | ❌ Basic text interface |
| **Live ISO Support** | ✅ Pre-compiled binaries | ❌ Requires Python installation |

---

## ✨ Key Features

### 🔧 **Core Installation**
- **BIOS & UEFI Support** - Automatic detection and configuration
- **GPT & MBR Partitions** - Flexible partitioning strategies
- **LUKS Encryption** - Full disk encryption with keyfile support
- **LVM & Software RAID** - Advanced storage management
- **Multiple Bootloaders** - GRUB (EFI/BIOS) and systemd-boot
- **Btrfs Snapshots** - Automatic system snapshots with snapper and grub-btrfs

### 🎨 **User Experience**
- **🖥️ Text-based User Interface (TUI)** - Beautiful real-time progress display with Arch Linux branding
- **📊 Live Progress Tracking** - Visual progress bars and status updates during installation
- **🔍 Interactive Package Selection** - Real-time search and install packages during setup
- **📦 AUR Package Discovery** - Search AUR packages with web API fallback
- **🎯 Smart Package Management** - Add/remove packages with intuitive commands
- **AUR Integration** - Built-in support for yay and paru
- **GRUB Theming** - Beautiful bootloader themes
- **Plymouth Boot Splash** - Custom Arch Glow theme
- **Desktop Environment Setup** - Pre-configured DE/DM combinations
- **Timezone Selection** - Interactive region/city selection with search and pagination
- **Quality of Life Packages** - Essential tools included by default (btop, neovim, etc.)

### 🔐 **Security & Advanced**
- **Secure Boot Support** - UEFI Secure Boot with custom keys
- **GPU Driver Detection** - Automatic NVIDIA/AMD/Intel driver installation
- **Microcode Updates** - Intel/AMD CPU microcode for stability
- **SSD Optimization** - Automatic TRIM and performance tuning
- **mkinitcpio Hooks** - Dynamic hook configuration based on hardware
- **UUID-based Configuration** - Reliable device identification for all partition schemes
- **EFI Partition Handling** - Proper mounting and configuration for UEFI systems

### 🛡️ **Reliability**
- **Comprehensive Error Handling** - Detailed logging and error recovery
- **Pre-installation Checks** - Validates system requirements
- **Rollback Capability** - Safe installation with cleanup options
- **Extensive Testing** - QEMU virtual machine support
- **Direct Process Communication** - Eliminates file-based communication issues
- **Real-time Progress Tracking** - Live installation monitoring and status updates
- **Clean Logging** - Inline progress indicators replace verbose logging noise
- **Fallback Support** - Graceful degradation to Bash mode if TUI fails

---

## 🚀 Quick Start

### Prerequisites
- **Arch Linux Live ISO** (latest version recommended)
- **Internet connection** (for package downloads)
- **8GB+ free disk space**
- **Basic understanding** of Linux partitioning

### Installation Steps

1. **Boot from Arch Linux Live ISO**

2. **Clone and run the installer:**
   ```bash
   git clone https://github.com/live4thamuzik/ArchInstall.git
   cd ArchInstall
   chmod +x *.sh
   
   # Option 1: Run with TUI (recommended)
   ./launch_tui_installer.sh
   
   # Option 2: Run in Bash-only mode
   ./launch_tui_installer.sh --no-tui
   
   # Option 3: Run original installer directly
   ./install_arch.sh
   ```
   
   **Note:** The launcher automatically makes the TUI binary executable if needed. The TUI binary (`archinstall-tui`) is pre-compiled and included in the repository for live ISO compatibility.

3. **Follow the interactive prompts:**
   - Configure disk layout and encryption
   - Select bootloader and theming options
   - Choose desktop environment
   - Install additional packages (optional)
   - Configure Secure Boot (optional)

4. **Complete post-installation setup:**
   - Reboot into your new system
   - Follow any additional setup instructions
   - Enjoy your Arch Linux installation!

---

## 🖥️ Text-based User Interface (TUI)

> **🆕 New Feature - Beautiful Real-time Progress Display**

ArchInstall now includes a modern TUI built in Rust that provides a beautiful, real-time progress display during installation. Inspired by the excellent [Linutil](https://github.com/ChrisTitusTech/linutil) project, this TUI offers a professional installation experience that rivals commercial installers.

### ✨ **TUI Features:**
- **🎨 Arch Linux Branding** - Custom ASCII logo and blue color scheme
- **📊 Live Progress Bars** - Real-time installation progress tracking
- **📝 Status Updates** - Current phase and detailed status messages
- **🔄 Auto-refresh** - Updates every second during installation
- **⌨️ Keyboard Controls** - ESC to exit, H for help, L for logs
- **🖥️ Terminal Compatibility** - Works with most terminal emulators
- **🚀 Direct Process Execution** - No file-based communication, more reliable

### 🚀 **How It Works:**
1. **Launcher Script** - `launch_tui_installer.sh` handles everything automatically
2. **Rust TUI** - Beautiful progress display in the main terminal
3. **Bash Installer** - Executes directly within the TUI process
4. **Real-time Output Parsing** - Direct stdout/stderr capture and parsing
5. **Automatic Cleanup** - All temporary files cleaned up on exit

### 📋 **Installation Options:**
```bash
# TUI Mode (recommended) - Beautiful progress display
./launch_tui_installer.sh

# Bash-only Mode - Traditional text output
./launch_tui_installer.sh --no-tui

# Direct Installer - Skip launcher entirely
./install_arch.sh
```

### 🔧 **Technical Details:**
- **Built with Rust** - Fast, reliable, and memory-efficient
- **ratatui Library** - Modern terminal UI framework
- **Direct Process Execution** - Uses `std::process::Command` for real-time communication
- **Pre-compiled Binary** - TUI binary included in repository for live ISO use
- **Fallback Support** - Gracefully falls back to Bash mode if needed
- **Live ISO Compatible** - No Rust installation required on live media

### ⚠️ **Requirements:**
- **Terminal emulator** - Any modern terminal (xterm, gnome-terminal, konsole, alacritty, etc.)
- **Live ISO compatible** - Works on any Arch Linux live ISO without additional setup

---

## 📦 Base Packages Included

ArchInstall automatically installs a comprehensive set of essential packages beyond the minimal `base` and `base-devel` groups. This ensures your system is ready for daily use without requiring additional package installation.

### **Core System Packages:**
- **`sudo`** - Privilege escalation
- **`man-db`**, **`man-pages`**, **`texinfo`** - Documentation system
- **`nano`**, **`neovim`** - Text editors
- **`bash-completion`** - Shell command completion
- **`git`**, **`curl`** - Development and networking tools
- **`networkmanager`**, **`iwd`** - Network management
- **`archlinux-keyring`** - Package verification
- **`base-devel`** - Development tools (gcc, make, etc.)
- **`pipewire`** - Audio system
- **`btop`** - System monitor
- **`openssh`** - Remote access
- **`parallel`** - Parallel processing

### **File System & Archive Tools:**
- **`exfat-utils`** - exFAT filesystem support
- **`unzip`** - ZIP archive extraction
- **`p7zip`** - 7-Zip archive support (RAR, 7z, etc.)
- **`rsync`** - File synchronization
- **`wget`** - Alternative download tool
- **`tree`** - Directory structure visualization
- **`which`** - Command location finder
- **`less`** - Enhanced pager
- **`dfc`** - Colored disk usage display

### **Quality of Life Improvements:**
- **`btop`** - Modern system monitor (replaces htop)
- **`neovim`** - Advanced text editor with modern features
- **`exfat-utils`** - Essential for USB drives and external storage
- **`p7zip`** - Support for common archive formats
- **`tree`** - Visual directory structure display
- **`dfc`** - Colored disk usage with better formatting

### **Conditional Packages (Installed Only When Needed):**
- **`lvm2`** - Logical Volume Manager (LVM setups only)
- **`mdadm`** - Software RAID management (RAID setups only)
- **`btrfs-progs`** - Btrfs filesystem tools (Btrfs setups only)
- **`e2fsprogs`** - ext4 filesystem tools (ext4 setups only)
- **`xfsprogs`** - XFS filesystem tools (XFS setups only)

### **Why This Matters:**
- **No Bloat** - Only installs what you actually need based on your configuration
- **Transparency** - You know exactly what's being installed
- **Efficiency** - Avoids duplicate package installation during additional package selection
- **Ready to Use** - System is functional immediately after installation
- **Clean Logging** - Inline progress indicators replace verbose logging noise
- **Better UX** - Quality-of-life packages included by default for immediate productivity

### **Package Selection Tips:**
- **Check the list above** before adding packages during installation
- **Avoid duplicates** - Don't add packages that are already included
- **Consider your setup** - LVM/RAID users get additional tools automatically
- **Customize as needed** - Add desktop environments, applications, and AUR packages

---

## 📁 Project Structure

```
ArchInstall/
├── install_arch.sh        # Main installation orchestrator
├── config.sh              # Configuration variables and package lists
├── utils.sh               # Utility functions and chroot operations
├── dialogs.sh             # Interactive user interface
├── disk_strategies.sh     # Partitioning and storage management
├── chroot_config.sh       # Post-installation configuration
├── launch_tui_installer.sh # TUI launcher script
├── archinstall-tui        # Pre-compiled Rust TUI binary
├── Cargo.toml             # Rust project configuration
├── src/                   # Rust TUI source code
│   └── main.rs            # TUI implementation
├── Source/                # Plymouth themes and assets
│   └── arch-glow/         # Arch Glow Plymouth theme
└── README.md              # This file
```

**Note:** The TUI binary (`archinstall-tui`) is pre-compiled and included for live ISO compatibility.

---

## 🔧 Supported Configurations

| Feature | Status | Notes |
|---------|--------|-------|
| **Boot Modes** | ✅ | BIOS and UEFI |
| **Partition Tables** | ✅ | GPT and MBR |
| **Filesystems** | ✅ | ext4, btrfs, xfs |
| **Btrfs Snapshots** | ✅ | Automatic snapshots with snapper |
| **Encryption** | ✅ | LUKS with keyfile |
| **Storage** | ✅ | LVM, Software RAID |
| **Bootloaders** | ✅ | GRUB, systemd-boot |
| **Package Selection** | ✅ | Interactive search & install |
| **Desktop Environments** | ✅ | GNOME, KDE, Hyprland |
| **Package Managers** | ✅ | pacman, AUR helpers |
| **Security** | ✅ | Secure Boot, TPM |
| **Hardware** | ✅ | GPU drivers, microcode |
| **TUI Interface** | ✅ | Rust-based with pre-compiled binary |
| **Live ISO Support** | ✅ | No additional setup required |

**Note:** All configurations are automatically detected and configured during installation.

---

## 🎮 Interactive Package Selection

### Official Packages
Search and install packages from official repositories during installation:

```bash
Package selection> search firefox
Package selection> add firefox
Package selection> add thunderbird
Package selection> list
Package selection> done
```

**Available commands:**
- `search <term>` - Search packages using `pacman -Ss`
- `add <package>` - Add package to installation list
- `remove <package>` - Remove package from list
- `list` - Show current selection
- `done` - Finish selection

**Note:** Check the "Base Packages Included" section above to avoid installing duplicate packages. The installer automatically includes essential packages by default.

### AUR Packages
Install packages from the Arch User Repository (requires AUR helper):

```bash
AUR Package selection> search visual-studio-code-bin
AUR Package selection> add visual-studio-code-bin
AUR Package selection> add google-chrome
AUR Package selection> done
```

**Supported AUR helpers:**
- `yay` - Fast and feature-rich
- `paru` - Rust-based alternative

**Note:** AUR helpers are automatically installed when you select AUR package installation. You can choose between yay and paru during the installation process.

---

## 📸 Btrfs Snapshots & System Recovery

> **🆕 New Feature - Automatic System Snapshots**

ArchInstall now includes comprehensive Btrfs snapshot support, providing automatic system backups and easy recovery options. This feature is automatically configured when you select Btrfs as your filesystem type during installation.

### 🎯 **Key Benefits:**
- **🔄 Automatic Snapshots** - Timeline-based snapshots (hourly/daily/weekly/monthly)
- **🚀 Boot Menu Integration** - Boot from any snapshot via GRUB menu
- **🛡️ System Recovery** - Rollback to previous working states
- **📊 Smart Cleanup** - Automatic old snapshot removal
- **🎨 GUI Management** - btrfs-assistant (AUR) for easy snapshot management

**Note:** Snapshot frequency and retention policies are configurable during installation.

### ⚙️ **Configuration Options:**
- **Snapshot Frequency**: Choose from hourly, daily, weekly, or monthly
- **Retention Policy**: Configure how many snapshots to keep
- **Boot Integration**: Automatic GRUB menu entries for snapshot recovery
- **Subvolume Layout**: Optimized subvolume structure for better snapshots

**Note:** All configuration options are presented during the interactive installation process.

### 🚀 **How It Works:**
1. **During Installation**: Select Btrfs as filesystem type
2. **Automatic Setup**: Snapper configuration with your chosen frequency
3. **Boot Integration**: GRUB automatically detects and lists snapshots
4. **Recovery**: Boot from any snapshot to restore your system

**Note:** The entire process is automated and requires no manual configuration.

### 📋 **Post-Installation:**
```bash
# List all snapshots
sudo snapper list

# Create manual snapshot
sudo snapper create --description "Before system update"

# Boot from snapshot via GRUB menu
# (Available automatically in boot menu)

# Install and manage snapshots with GUI (AUR package)
# yay -S btrfs-assistant  # or paru -S btrfs-assistant
btrfs-assistant
```

**Note:** All snapshot management commands are available immediately after installation.

### ⚠️ **Requirements:**
- **Btrfs filesystem** (selected during installation)
- **GRUB bootloader** (for boot menu integration)
- **Sufficient disk space** (snapshots use copy-on-write)

**Note:** These requirements are automatically configured when you select Btrfs during installation.

---

## 🎨 Plymouth Boot Splash

ArchInstall includes a beautiful custom Plymouth boot splash screen with the Arch Glow theme, providing a polished boot experience. This feature is automatically configured when you select Plymouth during installation.

### ✨ **Features:**
- **🎨 Arch Glow Theme** - Custom Arch Linux themed boot splash
- **⚡ Smooth Animations** - Glowing effects and progress indicators
- **🔧 Easy Configuration** - Simple yes/no prompts during installation
- **🖥️ Multi-Resolution** - Works with various screen resolutions
- **🎯 mkinitcpio Integration** - Automatic hook configuration

**Note:** Plymouth is automatically configured and enabled when selected during installation.

### 🚀 **Installation:**
During the installation process, you'll be prompted:
1. **"Install Plymouth boot splash screen?"** → Choose "yes"
2. **"Install Arch Glow Plymouth theme?"** → Choose "yes"
3. **Automatic setup** → Theme files copied and configured

**Note:** Plymouth installation is completely automated once you answer the prompts.

### 📋 **Post-Installation:**
```bash
# Check current Plymouth theme
plymouth-set-default-theme --list

# Change theme (if multiple themes available)
sudo plymouth-set-default-theme -R arch-glow

# Test Plymouth (reboot to see changes)
sudo reboot
```

**Note:** Plymouth is ready to use immediately after installation and reboot.

### ⚠️ **Requirements:**
- **Plymouth package** (automatically installed)
- **GRUB bootloader** (recommended for best compatibility)
- **mkinitcpio** (automatic hook configuration)

**Note:** All requirements are automatically configured when you select Plymouth during installation.

### 📦 **Optional GUI Tool:**
- **btrfs-assistant** - Install via AUR during package selection or post-installation
- Provides a user-friendly GUI for snapshot management
- Search for "btrfs-assistant" in the interactive package selection

**Note:** This tool is optional and can be installed later if needed.

---

## 🔐 Secure Boot Configuration

> **⚠️ Advanced Feature - Use with Caution**

Secure Boot provides additional security but requires manual UEFI configuration. Most users should answer "no" to the Secure Boot question during installation.

### When to Enable:
- ✅ **Dual-booting with Windows 11**
- ✅ **Gaming** (some games require TPM/Secure Boot)
- ✅ **Enterprise security requirements**
- ❌ **Single-boot Linux systems** (usually unnecessary)
- ❌ **If you don't understand the risks**

**Note:** Secure Boot is optional and most users should skip this feature.

### Prerequisites (BEFORE Installation):
1. **Disable Secure Boot** in UEFI firmware
2. **Clear all existing Secure Boot keys**
3. **Enable "Custom Key" mode** in UEFI
4. **Verify motherboard supports custom key enrollment**

**Note:** These steps must be completed before running the installer.

## 🔐 Security Notice

**IMPORTANT:** Always verify your ISO signature before creating bootable media for security. This step is optional but recommended for maximum security:

### Download from Official Sources
- **Official Download Page:** [archlinux.org/download](https://archlinux.org/download/)
- **Recommended US Mirrors:** MIT, Kernel.org, Berkeley, Purdue
- **Always download both:** `archlinux-YYYY.MM.DD-x86_64.iso` and `archlinux-YYYY.MM.DD-x86_64.iso.sig`

**Note:** Always download from official sources to ensure security and integrity.

### Verify ISO Signature
```bash
# Import Arch Linux signing key
gpg --auto-key-locate clear,wkd -v --locate-external-key pierre@archlinux.org

# Verify ISO signature
gpg --verify archlinux-YYYY.MM.DD-x86_64.iso.sig archlinux-YYYY.MM.DD-x86_64.iso
```

**Expected output:** `Good signature from "Pierre Schmitz <pierre@archlinux.org>"`

**Note:** ISO verification is optional but recommended for security.

### Alternative: Verify Checksums
```bash
# Download checksums file
wget https://mirrors.mit.edu/archlinux/iso/YYYY.MM.DD/sha256sums.txt

# Verify ISO checksum
sha256sum -c sha256sums.txt
```

**⚠️ Security Warning:** Never skip ISO verification. Always verify before booting!

**Note:** Checksum verification is an alternative to PGP signature verification.

### Post-Installation Steps:
1. **Boot into your system** (works normally without Secure Boot)
2. **Enroll keys:** `sbctl enroll-keys`
3. **Enable Secure Boot** in UEFI firmware
4. **Test system** (disable if boot fails)

**Note:** These steps are only required if you enabled Secure Boot during installation. Most users should skip Secure Boot entirely.

### ⚠️ Important Warnings:
- **System won't boot** with Secure Boot enabled until manual setup is complete
- **Motherboard variations** - Each UEFI firmware is different
- **Potential boot failures** - Disable Secure Boot if issues occur
- **Most users should answer "no"** to the Secure Boot question
- **Advanced users only** - Requires understanding of UEFI firmware and key management

**Note:** Secure Boot is an advanced feature that most users should avoid.

---

## 🎭 Plymouth Boot Splash

Experience a beautiful boot sequence with the custom "Arch Glow" theme. This feature is automatically configured when you select Plymouth during installation:

### Features:
- **Automatic installation** - Included with base system
- **Custom Arch theme** - Professional Arch Linux branding
- **GRUB integration** - Seamless bootloader theming
- **Hardware detection** - Works with most graphics cards

**Note:** Plymouth is automatically configured when selected during installation.

### Requirements:
- **GRUB bootloader** - Plymouth works best with GRUB
- **Graphics support** - Requires proper GPU drivers
- **UEFI or BIOS** - Supported on both boot modes

**Note:** All requirements are automatically configured when you select Plymouth during installation.

### Note:
- **systemd-boot users** - Plymouth support is limited
- **Automatic configuration** - No manual setup required

**Note:** Plymouth works best with GRUB bootloader for full compatibility.

---

## 🛠️ Advanced Features

### mkinitcpio Hooks
Automatic configuration based on your system. These hooks are automatically configured during installation:

- **Base hooks** - Essential system functionality
- **Encryption** - LUKS support when encryption is enabled
- **LVM** - Logical Volume Manager support
- **RAID** - Software RAID support
- **NVMe** - SSD optimization hooks
- **Plymouth** - Boot splash screen support

**Note:** Hooks are automatically configured based on your installation choices. No manual configuration required.

### GPU Driver Detection
Automatic hardware detection and driver installation:

- **NVIDIA** - Proprietary drivers with CUDA support
- **AMD** - Open-source and proprietary options
- **Intel** - Integrated graphics support
- **Microcode** - CPU stability updates

**Note:** Drivers are automatically detected and installed based on your hardware. No manual driver installation required.

### System Services
Essential services enabled by default:

- **NetworkManager** - Network connectivity
- **Time Synchronization** - User-selectable: ntpd (default), chrony, or systemd-timesyncd
- **fstrim.timer** - SSD optimization (automatic TRIM)

**Note:** Services are automatically configured and enabled during installation. No manual service configuration required.

### Localization Support
Comprehensive internationalization and localization:

- **Timezone Selection** - Interactive region and city selection with search functionality
- **US Regional Timezones** - Support for US/Eastern, US/Pacific, etc.
- **Pagination & Search** - Navigate large timezone lists with arrow keys and search
- **Locale Configuration** - Support for multiple languages and regions
- **Console Keymap** - Keyboard layout for both live environment and installed system
- **UTF-8 Support** - Full Unicode support for international characters

**Note:** All localization settings are configured during the interactive installation process. No manual configuration required.

### System Configuration
Essential system setup and configuration:

- **Hostname Configuration** - Custom system hostname with proper `/etc/hosts` setup
- **Mirror Optimization** - Automatic mirror selection using reflector for optimal download speeds
- **CPU Microcode** - Automatic detection and installation of Intel/AMD microcode updates
- **Fstab Generation** - Automatic filesystem table generation with UUIDs for reliable boot mounting
- **GRUB Configuration** - Proper UUID-based root device detection for all partition schemes
- **EFI Partition Handling** - Correct mounting and configuration for UEFI systems

**Note:** All system configuration is handled automatically during installation. No manual configuration required.

### Security Features
Built-in security measures and verification:

- **PGP Signature Verification** - Optional ISO signature verification for integrity and authenticity
- **Secure Boot Support** - UEFI Secure Boot configuration with custom keys
- **LUKS Encryption** - Full disk encryption with keyfile support
- **Secure Package Installation** - Verified package downloads and installation

**Note:** Security features are optional and can be enabled during installation. Most users should skip Secure Boot.

### Time Synchronization Options:
- **ntpd** (default) - Traditional NTP daemon with high precision for better accuracy
- **chrony** - Modern NTP client with better accuracy and network handling
- **systemd-timesyncd** - Lightweight built-in option for basic time sync

**Note:** Time synchronization service is selected during installation and automatically configured. ntpd is recommended for better precision.

---

## 🖥️ Desktop Environment Support

### **Desktop Environments:**
- **none** - Server/minimal installation (no GUI)
- **GNOME** - Modern, touch-friendly desktop environment
- **KDE Plasma** - Feature-rich, customizable desktop environment  
- **Hyprland** - Modern tiling window manager with Wayland support

**Note:** Desktop environments are selected during installation and automatically configured. All necessary packages and configurations are handled automatically.

### **Display Managers:**
- **none** - No display manager (manual start)
- **GDM** - GNOME Display Manager (recommended for GNOME)
- **SDDM** - Simple Desktop Display Manager (recommended for KDE/Hyprland)

**Note:** Display managers are automatically selected based on your desktop environment choice. No manual configuration required.

### **Hyprland Features:**
- **Core Hyprland** - Main window manager with Wayland support
- **Essential Tools** - waybar, wofi, kitty, dunst, hyprpaper
- **Audio Support** - PipeWire with pavucontrol
- **Screenshot Tools** - grim, slurp, swappy
- **Basic Configuration** - Pre-configured with sensible defaults
- **Auto-start Services** - Automatic startup of essential components

**Note:** Hyprland setup is automatically configured when selected during installation. All necessary packages and configurations are handled automatically.

---

## 🧪 Testing and Development

### QEMU Virtual Machine Testing
Test the installer safely in a virtual environment. This is recommended for testing before installing on real hardware:

```bash
# Create a virtual disk
qemu-img create -f qcow2 arch_disk.img 20G

# Boot Arch Linux ISO in QEMU
qemu-system-x86_64 \
  -m 4G \
  -enable-kvm \
  -boot d \
  -cdrom archlinux.iso \
  -drive file=arch_disk.img,format=qcow2
```

**Note:** QEMU testing is recommended for safe testing before installing on real hardware.

### Development Setup
For contributors and advanced users. This section covers building the TUI from source and testing:

```bash
# Clone the repository
git clone https://github.com/live4thamuzik/ArchInstall.git
cd ArchInstall

# Make scripts executable
chmod +x *.sh

# Build TUI from source (if Rust is available)
cargo build --release

# Run in test mode (if available)
./install_arch.sh --test

# Run TUI in development mode
./target/release/archinstall-tui
```

**Note:** Development setup is only needed for contributors. Regular users can use the pre-compiled TUI binary.

---

## 🚨 Troubleshooting

### Common Installation Issues
If you encounter problems during installation, check these common issues and solutions. Most issues can be resolved by following these troubleshooting steps:

#### **Installation Fails:**
- **Check internet connection** - Ensure stable connectivity
- **Verify disk space** - Minimum 8GB free space required
- **Check UEFI/BIOS settings** - Ensure proper boot mode
- **Review installation logs** - Check for specific error messages
- **TUI Issues** - Use `--no-tui` flag to run in Bash-only mode
- **Permission Issues** - Ensure scripts are executable with `chmod +x *.sh`

**Note:** Most installation failures are due to network or disk space issues.

#### **Boot Problems:**
- **GRUB not found** - Verify EFI partition mounting and UUID configuration
- **Kernel panic** - Check mkinitcpio hooks configuration
- **Encryption issues** - Verify LUKS keyfile and hooks
- **Secure Boot problems** - Disable Secure Boot in UEFI
- **UUID Issues** - Ensure fstab and GRUB use UUIDs instead of device names

**Note:** Boot problems are usually related to EFI partition mounting or UUID configuration.

#### **Package Installation:**
- **AUR packages fail** - Ensure AUR helper is properly installed
- **Permission errors** - Check user permissions in chroot
- **Package conflicts** - Review package dependencies

**Note:** Package installation issues are usually related to AUR helper configuration or package conflicts.

#### **Performance Issues:**
- **Slow boot** - Check Plymouth and GRUB theme configuration
- **SSD not optimized** - Verify fstrim.timer is enabled
- **GPU issues** - Check driver installation and configuration
- **TUI Performance** - TUI runs efficiently with minimal resource usage

**Note:** Performance issues are usually related to driver configuration or SSD optimization.

### Getting Help

1. **Check installation logs** - Detailed logs are saved for debugging
2. **Arch Wiki** - Comprehensive documentation at [wiki.archlinux.org](https://wiki.archlinux.org)
3. **Community Support** - Arch Linux forums and Reddit communities
4. **GitHub Issues** - Report bugs and request features
5. **TUI Issues** - Use `--no-tui` flag to run in Bash-only mode if TUI has problems

**Note:** Most issues can be resolved by checking the installation logs and following the troubleshooting steps above.

---

## 🤝 Contributing

We welcome contributions! Here's how you can help improve ArchInstall. All contributions are appreciated and help make the project better:

### **Bug Reports:**
- Use GitHub Issues with detailed information
- Include installation logs and system specifications
- Describe steps to reproduce the problem
- **TUI Issues** - Include TUI version and terminal emulator information

**Note:** Detailed bug reports help us fix issues faster and improve the installer.

### **Feature Requests:**
- Open GitHub Issues with clear descriptions
- Explain the use case and expected behavior
- Consider contributing the implementation
- **TUI Features** - Suggest improvements to the user interface

**Note:** Feature requests help us understand what users need and prioritize development.

### **Code Contributions:**
- Fork the repository
- Create feature branches
- Follow existing code style and conventions
- Test thoroughly before submitting pull requests
- **Rust TUI Development** - Use `cargo build --release` to test TUI changes
- **Bash Script Testing** - Test in QEMU virtual machine for safety
- **Documentation** - Keep README.md and inline comments up to date

**Note:** Code contributions are welcome and help improve the installer for everyone.

### **Documentation:**
- Improve README.md and inline comments
- Add examples and use cases
- Translate documentation to other languages
- **TUI Documentation** - Help improve TUI_README.md and user guides
- **Code Comments** - Focus on readability and explain what code does
- **User Guides** - Create step-by-step installation guides for different scenarios

**Note:** Documentation improvements help users understand and use the installer more effectively.

---

## 📜 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

The MIT License allows you to:
- ✅ Use the software for any purpose
- ✅ Modify and distribute the software
- ✅ Use in commercial projects
- ✅ Distribute under different licenses

**Note:** This includes both the Bash installer scripts and the Rust TUI components. The MIT License provides maximum flexibility for users and contributors.

---

## 🙏 Acknowledgments

- **Arch Linux Community** - For the amazing distribution and documentation
- **Chris Titus** - Inspiration from ArchTitus project and [Linutil](https://github.com/ChrisTitusTech/linutil) TUI architecture
- **Official Arch Install** - Learning from the Python implementation
- **Arch Wiki Contributors** - Comprehensive documentation and guides
- **Open Source Community** - For the tools and libraries that make this possible
- **Rust Community** - For the excellent ratatui library and ecosystem

**Note:** This project builds upon the work of many talented developers and communities.

---

## 📞 Support and Community

- **GitHub Repository:** [github.com/live4thamuzik/ArchInstall](https://github.com/live4thamuzik/ArchInstall)
- **Issues and Bug Reports:** [GitHub Issues](https://github.com/live4thamuzik/ArchInstall/issues)
- **Arch Linux Forums:** [bbs.archlinux.org](https://bbs.archlinux.org)
- **Reddit Community:** [r/archlinux](https://reddit.com/r/archlinux)
- **TUI Issues:** Use `--no-tui` flag for Bash-only mode if TUI has problems
- **Live ISO Support:** Pre-compiled TUI binary included for immediate use
- **Community Discord:** Join our Discord server for real-time support

**Note:** Multiple support channels are available to help you with any issues or questions.

---

**Built with ❤️ for the Arch Linux community**

*ArchInstall - Making Arch Linux accessible while preserving its power and flexibility*

**Inspired by [Linutil](https://github.com/ChrisTitusTech/linutil) - Professional TUI experience for Linux system management**

**Ready to use on any Arch Linux live ISO - No additional setup required!**

**Experience the future of Arch Linux installation with our professional TUI interface!**