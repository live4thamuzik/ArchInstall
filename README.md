# 🅰️ ArchInstall - Arch Linux Installer

> Modular, interactive, and flexible Arch Linux installation powered by Bash

---

![License](https://img.shields.io/github/license/live4thamuzik/ArchInstall?style=flat-square)
![Issues](https://img.shields.io/github/issues/live4thamuzik/ArchInstall?style=flat-square)
![Stars](https://img.shields.io/github/stars/live4thamuzik/ArchInstall?style=flat-square)
![Last Commit](https://img.shields.io/github/last-commit/live4thamuzik/ArchInstall?style=flat-square)

---

## 🚀 Project Highlights

* **Modular Bash Architecture**
  Clear separation of logic: disk setup, chroot config, dialogs, and utilities.

* **Interactive User Input**
  Guided, dialog-driven flow to customize your install without memorizing commands.

* **Advanced Options**

  * ✅ LVM and RAID support
  * 🔒 LUKS encryption
  * 🎨 GRUB theming from Git
  * 💺 Auto GPU driver installation
  * 📆 Smart initcpio + mkinitcpio hook handling

* **Failsafe by Design**
  Strict Bash error handling, pre-checks, and logging to minimize risks.

---

## 📦 How to Use

1. **Clone the repo** from a Live Arch ISO session:

   ```bash
   git clone https://github.com/live4thamuzik/ArchInstall
   cd ArchInstall
   ```

2. **Run the installer**:

   ```bash
   ./install_arch.sh
   ```

3. **Follow the interactive prompts** to:

   * Choose disk layout and filesystem
   * Pick kernel type (default, LTS)
   * Configure bootloader and theming
   * Select Desktop Environment + Display Manager
   * (Optionally) enable Flatpak, dotfiles, AUR helper, and more

---

## 🧱 Project Structure

```text
install_arch.sh         # Main entry point
config.sh               # Default variables, arrays, install flags
utils.sh                # Logging, error handling, command wrappers
dialogs.sh              # Interactive dialog boxes
disk_strategies.sh      # Disk partitioning, encryption, LVM/RAID logic
chroot_config.sh        # Chroot environment setup (bootloader, DE, services, etc.)
```

---

## ✅ Supported Features

| Feature                 | Supported |
| ----------------------- | --------- |
| BIOS + UEFI Boot        | ✅         |
| GPT + MBR Partitions    | ✅         |
| LUKS Disk Encryption    | ✅         |
| LVM + Software RAID     | ✅         |
| GRUB + systemd-boot     | ✅         |
| GRUB Theming            | ✅         |
| mkinitcpio Hook Setup   | ✅         |
| AUR Helper Installation | ✅         |
| Dotfiles Git Deployment | ✅         |
| Flatpak + Flathub       | ✅         |
| NVIDIA, AMD, Intel GPU  | ✅         |
| Microcode Installation  | ✅         |
| Multilib Enablement     | ✅         |

---

## 🖥️ Desktop Environment Support

Choose from pre-defined DE/DM pairs or customize your own:

* GNOME + GDM
* KDE Plasma + SDDM
* Hyprland + SDDM

---

## 🧚‍♂️ Testing in QEMU (Optional)

For safe dry-runs:

```bash
qemu-system-x86_64 \
  -m 4G \
  -enable-kvm \
  -boot d \
  -cdrom archlinux.iso \
  -drive file=arch_disk.img,format=qcow2
```

---

## 📜 License

This project is licensed under the MIT License.
See the [LICENSE](LICENSE) file for details.

---

## 💬 Feedback & Contributions

Found a bug? Want a new feature?
Please [open an issue](https://github.com/live4thamuzik/ArchInstall/issues) or [submit a pull request](https://github.com/live4thamuzik/ArchInstall/pulls).
Contributions are welcome and appreciated!

---

## 🙏 Credits

* Built with ❤️ for the Arch Linux community
