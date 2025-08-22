# 🚀 ArchInstall - Arch Linux Installer

> Modular, interactive, and flexible Arch Linux installation powered by Bash

---

![License](https://img.shields.io/github/license/live4thamuzik/ArchInstall?style=flat-square)
![Issues](https://img.shields.io/github/issues/live4thamuzik/ArchInstall?style=flat-square)
![Stars](https://img.shields.io/github/stars/live4thamuzik/ArchInstall?style=flat-square)
![Last Commit](https://img.io/github/last-commit/live4thamuzik/ArchInstall?style=flat-square)

---

## ✨ Project Highlights

* **Modular Bash Architecture**
    * Clear separation of logic for disk setup, chroot config, dialogs, and utilities.

* **Interactive User Input**
    * A guided, dialog-driven flow to customize your installation without memorizing commands.

* **Advanced Features**
    * ✅ LVM and Software RAID support
    * 🔒 LUKS disk encryption
    * 🎨 GRUB theming from Git
    * 💺 Automatic GPU driver installation
    * 📆 Dynamic mkinitcpio hook handling

* **Failsafe by Design**
    * Strict Bash error handling, comprehensive pre-checks, and detailed logging to minimize risks.

---

## 📦 How to Use

1.  **Clone the repository** from a Live Arch Linux ISO session:

    ```bash
    git clone [https://github.com/live4thamuzik/ArchInstall.git](https://github.com/live4thamuzik/ArchInstall.git)
    cd ArchInstall
    ```

2.  **Make the scripts executable and run the installer**:

    ```bash
    chmod +x *.sh
    ./install_arch.sh
    ```

3.  **Follow the interactive prompts** to configure your system:
    * Choose your disk layout and filesystem.
    * Select your preferred kernel type (Default or LTS).
    * Configure your bootloader and enable theming.
    * Choose a Desktop Environment and Display Manager.
    * (Optionally) enable Flatpak, deploy dotfiles, install an AUR helper, and more.

---

## 🧱 Project Structure

```text
install_arch.sh        # Main script for the installation workflow
config.sh              # Default variables, arrays, and install flags
utils.sh               # Helper functions for logging, error handling, and command wrappers
dialogs.sh             # Interactive dialogs and user input functions
disk_strategies.sh     # Logic for partitioning, encryption, LVM, and RAID
chroot_config.sh       # Post-installation configuration tasks inside chroot
```

---

## ✅ Supported Features

| Feature | Supported |
| :--- | :--- |
| BIOS + UEFI Boot | ✅ |
| GPT + MBR Partitions | ✅ |
| LUKS Disk Encryption | ✅ |
| LVM + Software RAID | ✅ |
| GRUB + systemd-boot | ✅ |
| GRUB Theming | ✅ |
| mkinitcpio Hook Setup | ✅ |
| AUR Helper Installation | ✅ |
| Dotfiles Git Deployment | ✅ |
| Flatpak + Flathub | ✅ |
| NVIDIA, AMD, Intel GPU | ✅ |
| Microcode Installation | ✅ |
| Multilib Enablement | ✅ |

---

## 🖥️ Desktop Environment Support

Choose from pre-defined DE/DM pairs or customize your own:
* GNOME + GDM
* KDE Plasma + SDDM
* Hyprland + SDDM

---

## ⚙️ Testing in QEMU (Optional)

For safe dry-runs in a virtual environment:

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

## 🙏 Credits

* Built with ❤️ for the Arch Linux community
