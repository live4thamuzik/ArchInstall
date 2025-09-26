# 🚀 ArchInstall - Advanced Arch Linux Installer

> **A modern Rust-based TUI installer for Arch Linux with comprehensive partitioning, RAID support, encryption, and intelligent automation.**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org)
[![Rust](https://img.shields.io/badge/Rust-000000?logo=rust&logoColor=white)](https://rust-lang.org)

## ✨ Key Features

- **🖥️ Professional TUI** - Beautiful Rust-based interface with floating windows and smooth navigation
- **🗂️ Advanced Partitioning** - 7 partitioning strategies including LVM, RAID, and encryption
- **🔐 Full Encryption** - LUKS encryption with automatic configuration
- **💾 Software RAID** - Complete RAID 0/1/5/10 support with automatic disk detection
- **📦 Interactive Package Management** - Real-time package search and AUR integration
- **🎨 Desktop Environments** - GNOME, KDE, and Hyprland with intelligent display manager selection
- **⚡ Live ISO Ready** - Pre-compiled binary, no dependencies required

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

# Direct execution (recommended)
./target/release/archinstall-tui
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

| Strategy | Description | Encryption | LVM | RAID |
|----------|-------------|------------|-----|------|
| **auto_simple** | Standard partitioning (EFI/Boot/Root/Home) | Optional | No | No |
| **auto_simple_luks** | Simple partitioning with LUKS encryption | Auto | No | No |
| **auto_lvm** | LVM-based partitioning without encryption | No | Auto | No |
| **auto_luks_lvm** | LUKS encryption with LVM | Auto | Auto | No |
| **auto_raid_simple** | Software RAID with simple partitioning | Optional | No | Auto |
| **auto_raid_lvm** | Software RAID with LVM support | Optional | Auto | Auto |
| **manual** | Interactive manual partitioning with fdisk | User Choice | User Choice | User Choice |

## 🚨 Troubleshooting

### Common Issues
- **Installation Fails**: Check internet connection and disk space
- **Boot Problems**: Verify EFI partition mounting and bootloader configuration
- **TUI Issues**: Use `--no-tui` flag for Bash-only mode
- **Package Installation**: Ensure AUR helper is properly installed

### Getting Help
1. Check installation logs for detailed error messages
2. Use `--no-tui` flag if TUI has problems
3. Verify hardware compatibility (especially for RAID)
4. Check [Arch Wiki](https://wiki.archlinux.org) for system-specific issues

## 📜 License

MIT License - see [LICENSE](LICENSE) file for details.

---

**⚠️ Disclaimer**: This installer modifies your system disk. Always backup important data before proceeding.

**Built with ❤️ for the Arch Linux community**

*Ready to use on any Arch Linux live ISO - No additional setup required!*