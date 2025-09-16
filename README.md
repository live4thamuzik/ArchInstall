# 🚀 ArchInstall - Arch Linux Installer

> **A modern TUI-based Arch Linux installer with interactive package selection, Btrfs snapshots, and comprehensive system configuration.**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org)

## ✨ Key Features

- **🖥️ Professional TUI** - Beautiful Rust-based interface with floating windows
- **📦 Interactive Package Selection** - Real-time search and install packages during setup
- **🔄 Btrfs Snapshots** - Automatic system snapshots with GRUB integration
- **🔐 Full Encryption** - LUKS encryption with LVM and RAID support
- **🎨 Desktop Environments** - GNOME, KDE, and Hyprland with full OOBE
- **🦄 AUR Integration** - Built-in support for yay and paru
- **🎭 Plymouth Themes** - Custom Arch Glow and Arch Mac Style boot splash
- **⚡ Live ISO Ready** - Pre-compiled binary, no setup required

## 🚀 Quick Start

### Prerequisites
- Arch Linux Live ISO
- Internet connection
- 8GB+ free disk space

### Installation
```bash
# Clone and run
git clone https://github.com/live4thamuzik/ArchInstall.git
cd ArchInstall
chmod +x *.sh

# Run TUI (recommended)
./archinstall-tui

# Or use launcher
./launch_tui_installer.sh

# Bash-only mode
./launch_tui_installer.sh --no-tui
```

## 🖥️ TUI Features

### Interactive Configuration
- **Navigation**: Arrow keys to navigate, Enter to select
- **Text Input**: Username, passwords, hostname
- **Popup Selections**: Disk, desktop environment, timezone, locale
- **Auto-selection**: Display manager automatically selected based on DE

### Package Management
- **Real-time Search**: `search <term>` to find packages
- **Add/Remove**: `add <package>` and `remove <package>`
- **AUR Support**: Search and install AUR packages with yay/paru
- **Floating Windows**: Popup interface for package selection

### Progress Tracking
- **Live Updates**: Real-time progress bars during installation
- **Status Display**: Current phase and detailed status messages
- **Auto-refresh**: Updates every second during installation

## 🔧 Supported Configurations

| Feature | Status | Notes |
|---------|--------|-------|
| **Boot Modes** | ✅ | BIOS and UEFI |
| **Partition Tables** | ✅ | GPT and MBR |
| **Filesystems** | ✅ | ext4, btrfs, xfs |
| **Encryption** | ✅ | LUKS with keyfile |
| **Storage** | ✅ | LVM, Software RAID |
| **Bootloaders** | ✅ | GRUB, systemd-boot |
| **Desktop Environments** | ✅ | GNOME, KDE, Hyprland |
| **AUR Helpers** | ✅ | yay, paru |

## 📦 Base Packages Included

Essential packages automatically installed:
- **System**: sudo, man-db, nano, neovim, bash-completion
- **Network**: networkmanager, iwd, curl, wget
- **Development**: git, base-devel, archlinux-keyring
- **Audio**: pipewire
- **Monitoring**: btop (replaces htop)
- **Archives**: unzip, p7zip, rsync
- **Quality of Life**: tree, which, less, dfc

## 🎮 Desktop Environment Support

### GNOME
- Complete GNOME Extra suite
- GNOME Tweaks for customization
- Firefox browser ready to use

### KDE Plasma
- Full KDE Applications suite
- Dolphin file manager
- Firefox browser ready to use

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

## 🎭 Plymouth Boot Splash

Custom themes included:
- **Arch Glow**: Professional Arch Linux themed boot splash
- **Arch Mac Style**: macOS-inspired boot splash
- **Smooth Animations**: Glowing effects and progress indicators
- **Multi-Resolution**: Works with various screen resolutions

## 🛠️ Advanced Features

- **GPU Driver Detection**: Automatic NVIDIA/AMD/Intel driver installation
- **Microcode Updates**: Intel/AMD CPU microcode for stability
- **SSD Optimization**: Automatic TRIM and performance tuning
- **Secure Boot Support**: UEFI Secure Boot with custom keys
- **Timezone Selection**: Interactive region/city selection with search
- **Localization**: Multiple languages with English fallback
- **Mirror Optimization**: Automatic mirror selection for optimal speeds

## 🚨 Troubleshooting

### Common Issues
- **Installation Fails**: Check internet connection and disk space
- **Boot Problems**: Verify EFI partition mounting and UUID configuration
- **TUI Issues**: Use `--no-tui` flag for Bash-only mode
- **Package Installation**: Ensure AUR helper is properly installed

### Getting Help
1. Check installation logs for detailed error messages
2. Use `--no-tui` flag if TUI has problems
3. Check [Arch Wiki](https://wiki.archlinux.org) for system-specific issues
4. Report bugs on [GitHub Issues](https://github.com/live4thamuzik/ArchInstall/issues)

## 🧪 Testing

Test safely in QEMU:
```bash
# Create virtual disk
qemu-img create -f qcow2 arch_disk.img 20G

# Boot Arch ISO in QEMU
qemu-system-x86_64 -m 4G -enable-kvm -boot d -cdrom archlinux.iso -drive file=arch_disk.img,format=qcow2
```

## 🤝 Contributing

We welcome contributions! Please:
- Use GitHub Issues for bug reports and feature requests
- Include detailed information and installation logs
- Test thoroughly before submitting pull requests
- Follow existing code style and conventions

## 📜 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Arch Linux Community** - For the amazing distribution and documentation
- **Chris Titus** - Inspiration from [Linutil](https://github.com/ChrisTitusTech/linutil) TUI architecture
- **Official Arch Install** - Learning from the Python implementation
- **Rust Community** - For the excellent ratatui library and ecosystem

---

**Built with ❤️ for the Arch Linux community**

*Ready to use on any Arch Linux live ISO - No additional setup required!*
