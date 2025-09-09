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
- **🔍 Interactive Package Selection** - Real-time search and install packages during setup
- **📦 AUR Package Discovery** - Search AUR packages with web API fallback
- **🎯 Smart Package Management** - Add/remove packages with intuitive commands
- **AUR Integration** - Built-in support for yay and paru
- **GRUB Theming** - Beautiful bootloader themes
- **Plymouth Boot Splash** - Custom Arch Glow theme
- **Desktop Environment Setup** - Pre-configured DE/DM combinations

### 🔐 **Security & Advanced**
- **Secure Boot Support** - UEFI Secure Boot with custom keys
- **GPU Driver Detection** - Automatic NVIDIA/AMD/Intel driver installation
- **Microcode Updates** - Intel/AMD CPU microcode for stability
- **SSD Optimization** - Automatic TRIM and performance tuning
- **mkinitcpio Hooks** - Dynamic hook configuration based on hardware

### 🛡️ **Reliability**
- **Comprehensive Error Handling** - Detailed logging and error recovery
- **Pre-installation Checks** - Validates system requirements
- **Rollback Capability** - Safe installation with cleanup options
- **Extensive Testing** - QEMU virtual machine support

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
   ./install_arch.sh
   ```

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
├── Source/                # Plymouth themes and assets
│   └── arch-glow/         # Arch Glow Plymouth theme
└── README.md              # This file
```

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

---

## 📸 Btrfs Snapshots & System Recovery

> **🆕 New Feature - Automatic System Snapshots**

ArchInstall now includes comprehensive Btrfs snapshot support, providing automatic system backups and easy recovery options.

### 🎯 **Key Benefits:**
- **🔄 Automatic Snapshots** - Timeline-based snapshots (hourly/daily/weekly/monthly)
- **🚀 Boot Menu Integration** - Boot from any snapshot via GRUB menu
- **🛡️ System Recovery** - Rollback to previous working states
- **📊 Smart Cleanup** - Automatic old snapshot removal
- **🎨 GUI Management** - btrfs-assistant (AUR) for easy snapshot management

### ⚙️ **Configuration Options:**
- **Snapshot Frequency**: Choose from hourly, daily, weekly, or monthly
- **Retention Policy**: Configure how many snapshots to keep
- **Boot Integration**: Automatic GRUB menu entries for snapshot recovery
- **Subvolume Layout**: Optimized subvolume structure for better snapshots

### 🚀 **How It Works:**
1. **During Installation**: Select Btrfs as filesystem type
2. **Automatic Setup**: Snapper configuration with your chosen frequency
3. **Boot Integration**: GRUB automatically detects and lists snapshots
4. **Recovery**: Boot from any snapshot to restore your system

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

### ⚠️ **Requirements:**
- **Btrfs filesystem** (selected during installation)
- **GRUB bootloader** (for boot menu integration)
- **Sufficient disk space** (snapshots use copy-on-write)

---

## 🎨 Plymouth Boot Splash

ArchInstall includes a beautiful custom Plymouth boot splash screen with the Arch Glow theme, providing a polished boot experience.

### ✨ **Features:**
- **🎨 Arch Glow Theme** - Custom Arch Linux themed boot splash
- **⚡ Smooth Animations** - Glowing effects and progress indicators
- **🔧 Easy Configuration** - Simple yes/no prompts during installation
- **🖥️ Multi-Resolution** - Works with various screen resolutions
- **🎯 mkinitcpio Integration** - Automatic hook configuration

### 🚀 **Installation:**
During the installation process, you'll be prompted:
1. **"Install Plymouth boot splash screen?"** → Choose "yes"
2. **"Install Arch Glow Plymouth theme?"** → Choose "yes"
3. **Automatic setup** → Theme files copied and configured

### 📋 **Post-Installation:**
```bash
# Check current Plymouth theme
plymouth-set-default-theme --list

# Change theme (if multiple themes available)
sudo plymouth-set-default-theme -R arch-glow

# Test Plymouth (reboot to see changes)
sudo reboot
```

### ⚠️ **Requirements:**
- **Plymouth package** (automatically installed)
- **GRUB bootloader** (recommended for best compatibility)
- **mkinitcpio** (automatic hook configuration)

### 📦 **Optional GUI Tool:**
- **btrfs-assistant** - Install via AUR during package selection or post-installation
- Provides a user-friendly GUI for snapshot management
- Search for "btrfs-assistant" in the interactive package selection

---

## 🔐 Secure Boot Configuration

> **⚠️ Advanced Feature - Use with Caution**

Secure Boot provides additional security but requires manual UEFI configuration.

### When to Enable:
- ✅ **Dual-booting with Windows 11**
- ✅ **Gaming** (some games require TPM/Secure Boot)
- ✅ **Enterprise security requirements**
- ❌ **Single-boot Linux systems** (usually unnecessary)
- ❌ **If you don't understand the risks**

### Prerequisites (BEFORE Installation):
1. **Disable Secure Boot** in UEFI firmware
2. **Clear all existing Secure Boot keys**
3. **Enable "Custom Key" mode** in UEFI
4. **Verify motherboard supports custom key enrollment**

## 🔐 Security Notice

**IMPORTANT:** Always verify your ISO signature before creating bootable media for security:

### Download from Official Sources
- **Official Download Page:** [archlinux.org/download](https://archlinux.org/download/)
- **Recommended US Mirrors:** MIT, Kernel.org, Berkeley, Purdue
- **Always download both:** `archlinux-YYYY.MM.DD-x86_64.iso` and `archlinux-YYYY.MM.DD-x86_64.iso.sig`

### Verify ISO Signature
```bash
# Import Arch Linux signing key
gpg --auto-key-locate clear,wkd -v --locate-external-key pierre@archlinux.org

# Verify ISO signature
gpg --verify archlinux-YYYY.MM.DD-x86_64.iso.sig archlinux-YYYY.MM.DD-x86_64.iso
```

**Expected output:** `Good signature from "Pierre Schmitz <pierre@archlinux.org>"`

### Alternative: Verify Checksums
```bash
# Download checksums file
wget https://mirrors.mit.edu/archlinux/iso/YYYY.MM.DD/sha256sums.txt

# Verify ISO checksum
sha256sum -c sha256sums.txt
```

**⚠️ Security Warning:** Never skip ISO verification. Always verify before booting!

### Post-Installation Steps:
1. **Boot into your system** (works normally without Secure Boot)
2. **Enroll keys:** `sbctl enroll-keys`
3. **Enable Secure Boot** in UEFI firmware
4. **Test system** (disable if boot fails)

### ⚠️ Important Warnings:
- **System won't boot** with Secure Boot enabled until manual setup is complete
- **Motherboard variations** - Each UEFI firmware is different
- **Potential boot failures** - Disable Secure Boot if issues occur
- **Most users should answer "no"** to the Secure Boot question

---

## 🎭 Plymouth Boot Splash

Experience a beautiful boot sequence with the custom "Arch Glow" theme:

### Features:
- **Automatic installation** - Included with base system
- **Custom Arch theme** - Professional Arch Linux branding
- **GRUB integration** - Seamless bootloader theming
- **Hardware detection** - Works with most graphics cards

### Requirements:
- **GRUB bootloader** - Plymouth works best with GRUB
- **Graphics support** - Requires proper GPU drivers
- **UEFI or BIOS** - Supported on both boot modes

### Note:
- **systemd-boot users** - Plymouth support is limited
- **Automatic configuration** - No manual setup required

---

## 🛠️ Advanced Features

### mkinitcpio Hooks
Automatic configuration based on your system:

- **Base hooks** - Essential system functionality
- **Encryption** - LUKS support when encryption is enabled
- **LVM** - Logical Volume Manager support
- **RAID** - Software RAID support
- **NVMe** - SSD optimization hooks
- **Plymouth** - Boot splash screen support

### GPU Driver Detection
Automatic hardware detection and driver installation:

- **NVIDIA** - Proprietary drivers with CUDA support
- **AMD** - Open-source and proprietary options
- **Intel** - Integrated graphics support
- **Microcode** - CPU stability updates

### System Services
Essential services enabled by default:

- **NetworkManager** - Network connectivity
- **Time Synchronization** - User-selectable: ntpd (default), chrony, or systemd-timesyncd
- **fstrim.timer** - SSD optimization (automatic TRIM)

### Localization Support
Comprehensive internationalization and localization:

- **Timezone Selection** - Interactive region and city selection
- **Locale Configuration** - Support for multiple languages and regions
- **Console Keymap** - Keyboard layout for both live environment and installed system
- **UTF-8 Support** - Full Unicode support for international characters

### System Configuration
Essential system setup and configuration:

- **Hostname Configuration** - Custom system hostname with proper `/etc/hosts` setup
- **Mirror Optimization** - Automatic mirror selection using reflector for optimal download speeds
- **CPU Microcode** - Automatic detection and installation of Intel/AMD microcode updates
- **Fstab Generation** - Automatic filesystem table generation for proper boot mounting

### Security Features
Built-in security measures and verification:

- **PGP Signature Verification** - Optional ISO signature verification for integrity and authenticity
- **Secure Boot Support** - UEFI Secure Boot configuration with custom keys
- **LUKS Encryption** - Full disk encryption with keyfile support
- **Secure Package Installation** - Verified package downloads and installation

### Time Synchronization Options:
- **ntpd** (default) - Traditional NTP daemon with high precision
- **chrony** - Modern NTP client with better accuracy and network handling
- **systemd-timesyncd** - Lightweight built-in option for basic time sync

---

## 🖥️ Desktop Environment Support

### **Desktop Environments:**
- **none** - Server/minimal installation (no GUI)
- **GNOME** - Modern, touch-friendly desktop environment
- **KDE Plasma** - Feature-rich, customizable desktop environment  
- **Hyprland** - Modern tiling window manager with Wayland support

### **Display Managers:**
- **none** - No display manager (manual start)
- **GDM** - GNOME Display Manager (recommended for GNOME)
- **SDDM** - Simple Desktop Display Manager (recommended for KDE/Hyprland)

### **Hyprland Features:**
- **Core Hyprland** - Main window manager with Wayland support
- **Essential Tools** - waybar, wofi, kitty, dunst, hyprpaper
- **Audio Support** - PipeWire with pavucontrol
- **Screenshot Tools** - grim, slurp, swappy
- **Basic Configuration** - Pre-configured with sensible defaults
- **Auto-start Services** - Automatic startup of essential components

---

## 🧪 Testing and Development

### QEMU Virtual Machine Testing
Test the installer safely in a virtual environment:

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

### Development Setup
For contributors and advanced users:

```bash
# Clone the repository
git clone https://github.com/live4thamuzik/ArchInstall.git
cd ArchInstall

# Make scripts executable
chmod +x *.sh

# Run in test mode (if available)
./install_arch.sh --test
```

---

## 🚨 Troubleshooting

### Common Installation Issues

#### **Installation Fails:**
- **Check internet connection** - Ensure stable connectivity
- **Verify disk space** - Minimum 8GB free space required
- **Check UEFI/BIOS settings** - Ensure proper boot mode
- **Review installation logs** - Check for specific error messages

#### **Boot Problems:**
- **GRUB not found** - Verify EFI partition mounting
- **Kernel panic** - Check mkinitcpio hooks configuration
- **Encryption issues** - Verify LUKS keyfile and hooks
- **Secure Boot problems** - Disable Secure Boot in UEFI

#### **Package Installation:**
- **AUR packages fail** - Ensure AUR helper is properly installed
- **Permission errors** - Check user permissions in chroot
- **Package conflicts** - Review package dependencies

#### **Performance Issues:**
- **Slow boot** - Check Plymouth and GRUB theme configuration
- **SSD not optimized** - Verify fstrim.timer is enabled
- **GPU issues** - Check driver installation and configuration

### Getting Help

1. **Check installation logs** - Detailed logs are saved for debugging
2. **Arch Wiki** - Comprehensive documentation at [wiki.archlinux.org](https://wiki.archlinux.org)
3. **Community Support** - Arch Linux forums and Reddit communities
4. **GitHub Issues** - Report bugs and request features

---

## 🤝 Contributing

We welcome contributions! Here's how you can help:

### **Bug Reports:**
- Use GitHub Issues with detailed information
- Include installation logs and system specifications
- Describe steps to reproduce the problem

### **Feature Requests:**
- Open GitHub Issues with clear descriptions
- Explain the use case and expected behavior
- Consider contributing the implementation

### **Code Contributions:**
- Fork the repository
- Create feature branches
- Follow existing code style and conventions
- Test thoroughly before submitting pull requests

### **Documentation:**
- Improve README.md and inline comments
- Add examples and use cases
- Translate documentation to other languages

---

## 📜 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

The MIT License allows you to:
- ✅ Use the software for any purpose
- ✅ Modify and distribute the software
- ✅ Use in commercial projects
- ✅ Distribute under different licenses

---

## 🙏 Acknowledgments

- **Arch Linux Community** - For the amazing distribution and documentation
- **Chris Titus** - Inspiration from ArchTitus project
- **Official Arch Install** - Learning from the Python implementation
- **Arch Wiki Contributors** - Comprehensive documentation and guides
- **Open Source Community** - For the tools and libraries that make this possible

---

## 📞 Support and Community

- **GitHub Repository:** [github.com/live4thamuzik/ArchInstall](https://github.com/live4thamuzik/ArchInstall)
- **Issues and Bug Reports:** [GitHub Issues](https://github.com/live4thamuzik/ArchInstall/issues)
- **Arch Linux Forums:** [bbs.archlinux.org](https://bbs.archlinux.org)
- **Reddit Community:** [r/archlinux](https://reddit.com/r/archlinux)

---

**Built with ❤️ for the Arch Linux community**

*ArchInstall - Making Arch Linux accessible while preserving its power and flexibility*