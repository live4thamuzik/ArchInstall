# 🚀 ArchInstall - Advanced Arch Linux Installer

> **A modern Rust-based TUI installer for Arch Linux with comprehensive partitioning, RAID support, encryption, and intelligent automation.**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org)
[![Rust](https://img.shields.io/badge/Rust-000000?logo=rust&logoColor=white)](https://rust-lang.org)


## ✨ Key Features



- **🖥️ Professional TUI** - Beautiful Rust-based interface with floating windows and smooth navigation




- **🗂️ Advanced Partitioning** - 7 partitioning strategies including LVM, RAID, and encryption




- **🔐 Full Encryption** - LUKS encryption with automatic configuration based on partitioning choice




- **💾 Software RAID** - Complete RAID 0/1/5/10 support with automatic disk detection




- **📦 Interactive Package Management** - Real-time package search and AUR integration




- **🔄 Btrfs Snapshots** - Automatic system snapshots with GRUB integration




- **🎨 Desktop Environments** - GNOME, KDE, and Hyprland with intelligent display manager selection




- **🦄 AUR Integration** - Built-in support for yay and paru with package search




- **🎭 Plymouth Themes** - Custom Arch Glow and Arch Mac Style boot splash




- **⚡ Live ISO Ready** - Pre-compiled binary, no dependencies required




- **🛡️ Secure Boot** - Complete Secure Boot support with custom key management




## 🚀 Quick Start


### Prerequisites


- Arch Linux Live ISO (any recent version)




- Internet connection




- 8GB+ free disk space




- No additional software installation required




### Installation


```bash


# Clone and run
git clone https://github.com/live4thamuzik/ArchInstall.git
cd ArchInstall
chmod +x *.sh

# Run TUI installer (recommended)
./archinstall-tui

# Or use launcher
./launch_tui_installer.sh

# Bash-only mode (fallback)
./launch_tui_installer.sh --no-tui


```




## 🔨 Building from Source

The TUI binary is pre-compiled and included for live ISO compatibility. To build from source:


### Prerequisites


- Rust toolchain (install from [rustup.rs](https://rustup.rs/))




- Linux terminal with Unicode support




### Build Commands


```bash


# Build the TUI binary
cargo build --release

# Copy to root directory
cp target/release/archinstall-tui .


```




## 📖 Usage Guide


### TUI Navigation


- **Arrow Keys**: Navigate through configuration options




- **Enter**: Select/confirm options, open popups




- **Esc**: Close popups, return to main menu




- **q**: Quit installer from main screen




- **Text Input**: Type directly for username, passwords, hostname




### Configuration Workflow
1. **Boot Configuration**: Choose boot mode (auto/UEFI/BIOS) and Secure Boot
2. **System Setup**: Configure locale, keymap, and timezone
3. **Storage**: Select disk and partitioning strategy
4. **Encryption**: Automatically configured based on partitioning choice
5. **System Packages**: Choose kernel, mirrors, and additional packages
6. **User Setup**: Create user account and set passwords
7. **Desktop Environment**: Select DE with automatic display manager
8. **Final Configuration**: Boot splash, Plymouth themes, and Git setup
9. **Installation**: Start the automated installation process


## 🗂️ Partitioning Strategies

The installer supports 7 comprehensive partitioning strategies:

| Strategy | Description | Encryption | LVM | RAID |
|----------|-------------|------------|-----|------|
| **auto_simple** | Standard partitioning (EFI/Boot/Root/Home) | Optional | No | No |
| **auto_simple_luks** | Simple partitioning with LUKS encryption | Auto | No | No |
| **auto_lvm** | LVM-based partitioning without encryption | No | Auto | No |
| **auto_luks_lvm** | LUKS encryption with LVM | Auto | Auto | No |
| **auto_raid_simple** | Software RAID with simple partitioning | Optional | No | Auto |
| **auto_raid_lvm** | Software RAID with LVM support | Optional | Auto | Auto |
| **manual** | Interactive manual partitioning with fdisk | User Choice | User Choice | User Choice |


### RAID Support


- **RAID Levels**: 0, 1, 5, 10




- **Auto-Detection**: Automatically detects available disks for RAID




- **Flexible Configuration**: Choose RAID level after selecting RAID strategy




- **Boot Support**: EFI partitions on RAID arrays




### Encryption Features


- **Smart Auto-Configuration**: Encryption automatically enabled/disabled based on partitioning strategy




- **LUKS Integration**: Full LUKS support with keyfile generation




- **Manual Override**: Full manual control available with manual partitioning




## 🔧 Supported Configurations

| Feature | Status | Details |
|---------|--------|---------|
| **Boot Modes** | ✅ Complete | BIOS, UEFI, and automatic detection with override |
| **Partition Tables** | ✅ Complete | GPT and MBR support |
| **Filesystems** | ✅ Complete | ext4, btrfs, xfs, fat32 |
| **Encryption** | ✅ Complete | LUKS with automatic keyfile generation |
| **Storage** | ✅ Complete | LVM, Software RAID (0/1/5/10), multiple disks |
| **Bootloaders** | ✅ Complete | GRUB, systemd-boot with Secure Boot |
| **Kernels** | ✅ Complete | linux, linux-lts, linux-zen, linux-hardened |
| **Desktop Environments** | ✅ Complete | GNOME, KDE, Hyprland with auto DM selection |
| **Display Managers** | ✅ Complete | GDM, SDDM with intelligent auto-selection |
| **AUR Helpers** | ✅ Complete | yay, paru with package search |


## 📦 Package Management


### Interactive Package Selection


- **Real-time Search**: Search Arch repositories and AUR




- **Package Information**: View descriptions, versions, and installation status




- **Add/Remove Packages**: Select packages during configuration




- **AUR Integration**: Automatic AUR helper installation and package search




### Base Packages Included
Essential packages automatically installed:


- **System**: sudo, man-db, nano, neovim, bash-completion




- **Network**: networkmanager, iwd, curl, wget




- **Development**: git, base-devel, archlinux-keyring




- **Audio**: pipewire, pipewire-pulse




- **Monitoring**: btop (modern htop replacement)




- **Archives**: unzip, p7zip, rsync




- **Quality of Life**: tree, which, less, dfc




## 🎮 Desktop Environment Support


### GNOME


- Complete GNOME Extra suite




- GNOME Tweaks for customization




- Firefox browser pre-installed




- Automatic GDM display manager selection




### KDE Plasma


- Full KDE Applications suite




- Dolphin file manager




- Firefox browser pre-installed




- Automatic SDDM display manager selection




### Hyprland


- Core Hyprland with Wayland support




- Essential tools: waybar, wofi, kitty, dunst




- Audio: PipeWire with pavucontrol




- Screenshot tools: grim, slurp, swappy




- Pre-configured with sensible defaults




## 🔄 Btrfs Snapshots

When using Btrfs filesystem:


- **Automatic Snapshots**: Timeline-based (hourly/daily/weekly/monthly)




- **GRUB Integration**: Boot from any snapshot via boot menu




- **System Recovery**: Rollback to previous working states




- **Smart Cleanup**: Automatic old snapshot removal




- **Assistant Integration**: Optional Btrfs assistant for advanced management




## 🎭 Plymouth Boot Splash

Custom themes included:


- **Arch Glow**: Professional Arch Linux themed boot splash




- **Arch Mac Style**: macOS-inspired boot splash with smooth animations




- **Multi-Resolution**: Works with various screen resolutions




- **Smooth Animations**: Glowing effects and progress indicators




## 🛠️ Advanced Features


### System Optimization


- **GPU Driver Detection**: Automatic NVIDIA/AMD/Intel driver installation




- **Microcode Updates**: Intel/AMD CPU microcode for stability and security




- **SSD Optimization**: Automatic TRIM and performance tuning




- **Memory Management**: No strict memory requirements, optimized for various systems




### Security Features


- **Secure Boot Support**: Complete UEFI Secure Boot with custom key management




- **Kernel Signing**: Automatic kernel and initramfs signing for Secure Boot




- **Encryption**: Full LUKS support with secure keyfile generation




- **User Security**: Proper sudo configuration and user account setup




### Localization


- **Timezone Selection**: Interactive region/city selection with search




- **Locale Support**: Multiple languages with English fallback




- **Keymap Configuration**: Full keyboard layout support




- **Mirror Optimization**: Automatic mirror selection for optimal speeds




## 🖥️ TUI Features


### Intelligent Interface


- **Smart Auto-Selection**: Display manager automatically selected based on desktop environment




- **Re-configuration**: Change any setting after initial selection




- **Progress Tracking**: Real-time installation progress with detailed status




- **Error Handling**: Comprehensive error reporting and recovery




### Package Management Interface


- **Floating Windows**: Popup interface for package selection




- **Search Functionality**: Real-time package search across repositories




- **AUR Integration**: Seamless AUR package installation




- **Package Information**: Detailed package descriptions and status




## 🚨 Troubleshooting


### Common Issues


- **Installation Fails**: Check internet connection and disk space




- **Boot Problems**: Verify EFI partition mounting and bootloader configuration




- **TUI Issues**: Use `--no-tui` flag for Bash-only mode




- **Package Installation**: Ensure AUR helper is properly installed




- **RAID Issues**: Verify multiple disks are available for RAID configuration




### Getting Help
1. Check installation logs for detailed error messages
2. Use `--no-tui` flag if TUI has problems
3. Verify hardware compatibility (especially for RAID)
4. Check [Arch Wiki](https://wiki.archlinux.org) for system-specific issues
5. Report bugs on [GitHub Issues](https://github.com/live4thamuzik/ArchInstall/issues)


## 🧪 Testing


### Safe Testing in QEMU


```bash


# Create virtual disk
qemu-img create -f qcow2 arch_disk.img 20G

# Boot Arch ISO in QEMU
qemu-system-x86_64 -m 4G -enable-kvm -boot d -cdrom archlinux.iso -drive file=arch_disk.img,format=qcow2


```




### Testing RAID Configurations


```bash


# Create multiple virtual disks for RAID testing
qemu-img create -f qcow2 arch_disk1.img 10G
qemu-img create -f qcow2 arch_disk2.img 10G
qemu-img create -f qcow2 arch_disk3.img 10G


```




## 🤝 Contributing

We welcome contributions! Please:


- Use GitHub Issues for bug reports and feature requests




- Include detailed information and installation logs




- Test thoroughly before submitting pull requests




- Follow existing code style and conventions




- Test with various hardware configurations




## 📜 License

MIT License - see [LICENSE](LICENSE) file for details.


## 🙏 Acknowledgments



- **Arch Linux Community** - For the amazing distribution and comprehensive documentation




- **Chris Titus** - Inspiration from [Linutil](https://github.com/ChrisTitusTech/linutil) TUI architecture




- **Official Arch Install** - Learning from the Python implementation




- **Rust Community** - For the excellent ratatui library and ecosystem




- **mdadm Developers** - For robust software RAID support




## 📊 System Requirements



- **Minimum RAM**: 4GB (8GB recommended)




- **Storage**: 20GB+ free space (50GB+ recommended)




- **CPU**: x86_64 architecture




- **Boot**: BIOS or UEFI compatible




- **Network**: Internet connection for package installation





---



**Built with ❤️ for the Arch Linux community**

*Ready to use on any Arch Linux live ISO - No additional setup required!*

**Features 140+ Bash functions, 7 partitioning strategies, complete RAID support, and intelligent automation for a professional Arch Linux installation experience.**