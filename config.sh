#!/bin/bash
# config.sh - All configurable options and package lists for Archl4tm

# --- Installation Parameters (Populated by dialogs.sh or defaults) ---
INSTALL_DISK=""               # Primary disk selected by user (e.g., /dev/sda). Blank initially.
OVERRIDE_BOOT_MODE="no"       # "yes" if user forces BIOS mode. Default to "no".
BOOT_MODE="uefi"              # "uefi" or "bios" (auto-detected, can be overridden). Default to "uefi".
WANT_WIFI_CONNECTION="no"     # "yes" or "no". Default to "no".

PARTITION_SCHEME=""           # e.g., "auto_simple", "auto_luks_lvm", "auto_raid_luks_lvm", "manual". Blank initially.
WANT_SWAP="no"                # "yes" or "no". Default to "no".
WANT_HOME_PARTITION="no"      # "yes" or "no". Default to "no".
WANT_ENCRYPTION="no"          # "yes" or "no" (implied by scheme). Default to "no".
WANT_LVM="no"                 # "yes" or "no" (implied by scheme). Default to "no".
WANT_RAID="no"                # "yes" or "no" (implied by scheme). Default to "no".
LUKS_PASSPHRASE=""            # Populated by secure_password_input. Blank initially.
RAID_LEVEL=""                 # e.g., "1", "5". Blank initially.
RAID_DEVICES=()               # Array of disks for RAID, if applicable. Empty initially.

# Default Partition Sizes (for auto-partitioning schemes) - in MiB for parted calculations
EFI_PART_SIZE_MIB=512         # 512 MiB for EFI partition
BOOT_PART_SIZE_MIB=1024       # 1024 MiB (1 GiB) for /boot partition

# Filesystem types for root and home partitions - will be selected by user
ROOT_FILESYSTEM_TYPE="ext4"   # Default FS for root, will be overridden by prompt
HOME_FILESYSTEM_TYPE="ext4"   # Default FS for /home, will be overridden by prompt

KERNEL_TYPE="linux"           # "linux" or "linux-lts". Default to "linux".
CPU_MICROCODE_TYPE="none"     # "intel", "amd", or "none" (auto-detected). Default to "none".

TIMEZONE_DEFAULT="America/New_York" # Default timezone
TIMEZONE="$TIMEZONE_DEFAULT"        # Populated by dialogs.sh. Uses default initially.
LOCALE="en_US.UTF-8"          # Default locale.
KEYMAP="us"                   # Default console keymap.

REFLECTOR_COUNTRY_CODE="US"   # Default country for reflector mirrors.

SYSTEM_HOSTNAME=""            # Populated by dialogs.sh. Blank initially.
ROOT_PASSWORD=""              # Populated by dialogs.sh (securely handled). Blank initially.
MAIN_USERNAME=""              # Populated by dialogs.sh. Blank initially.
MAIN_USER_PASSWORD=""         # Populated by dialogs.sh. Blank initially.

DESKTOP_ENVIRONMENT=""        # e.g., "gnome", "kde", "hyprland", "none". Blank initially.
DISPLAY_MANAGER=""            # e.g., "gdm", "sddm", "none". Blank initially.
GPU_DRIVER_TYPE="none"        # "amd", "nvidia", "intel", or "none" (auto-detected). Default to "none".

BOOTLOADER_TYPE="grub"        # "grub" or "systemd-boot". Default to "grub".
ENABLE_OS_PROBER="no"         # "yes" or "no" (for GRUB dual-boot). Default to "no".

WANT_MULTILIB="no"            # "yes" or "no". Default to "no".
WANT_AUR_HELPER="no"          # "yes" or "no". Default to "no".
AUR_HELPER_CHOICE=""          # e.g., "yay", "paru". Blank initially.
WANT_FLATPAK="no"             # "yes" or "no". Default to "no".

INSTALL_CUSTOM_PACKAGES="no"  # "yes" or "no". Default to "no".
CUSTOM_PACKAGES=""            # Space-separated list of custom official packages. User modifies directly in this file.
INSTALL_CUSTOM_AUR_PACKAGES="no" # "yes" or "no". Default to "no".
CUSTOM_AUR_PACKAGES=""        # Space-separated list of custom AUR packages. User modifies directly in this file.

WANT_GRUB_THEME="no"          # "yes" or "no". Default to "no".
GRUB_THEME_CHOICE=""          # e.g., "Vimix", "Poly-light". Blank initially.

WANT_NUMLOCK_ON_BOOT="no"     # "yes" or "no". Default to "no".

# --- Dotfile Deployment (for fully themed installs) ---
WANT_DOTFILES_DEPLOYMENT="no" # "yes" or "no"
DOTFILES_REPO_URL=""          # Git repository URL for dotfiles (e.g., "https://github.com/youruser/dotfiles.git")
DOTFILES_BRANCH="main"        # Branch to clone (e.g., "main", "hyprland-config")


# --- Internal State Variables (Populated by functions, not user choices) ---
# These are filled by functions (e.g., capture_id_for_config, encrypt_device)
declare -A PARTITION_UUIDS    # Stores UUIDs/PARTUUIDs of created partitions/LVs (e.g., [root_uuid], [efi_partuuid])
declare -A LUKS_DEVICES_MAP   # Maps LUKS name to its opened device path (e.g., [cryptroot]=/dev/mapper/cryptroot)
declare -A LVM_DEVICES_MAP    # Maps VG_LV name to its path (e.g., [vg0_lvroot]=/dev/mapper/vg0-lvroot)
VG_NAME="volgroup0"                 # Default LVM Volume Group name (from your old script)


# --- Options for Dialogs (Arrays for select_option) ---

# Maps partition scheme choices to their corresponding implementation functions.
declare -A PARTITION_STRATEGY_FUNCTIONS=(
    ["auto_simple"]="do_auto_simple_partitioning"
    ["auto_luks_lvm"]="do_auto_luks_lvm_partitioning"
    ["auto_raid_luks_lvm"]="do_auto_raid_luks_lvm_partitioning"
    ["manual"]="do_manual_partitioning_guided"
)

# Partitioning strategies that the script supports
declare -a PARTITION_STRATEGIES_OPTIONS=(
    "auto_simple"
    "auto_luks_lvm"
    # "auto_raid_luks_lvm" is conditionally added in dialogs.sh based on disk count
    "manual"
)

# RAID levels (for mdadm software RAID)
declare -a RAID_LEVEL_OPTIONS=("1" "5" "6" "10")

# Filesystem types available for selection (primarily for root/home)
declare -a FILESYSTEM_OPTIONS=(
    "ext4"
    "btrfs"
    "xfs"
)

# Kernel types for installation
declare -a KERNEL_TYPES_OPTIONS=("linux" "linux-lts")

# Timezone top-level regions (for initial selection)
declare -a TIMEZONE_REGIONS=(
    "Africa"
    "America"
    "Antarctica"
    "Arctic"
    "Asia"
    "Atlantic"
    "Australia"
    "Europe"
    "Indian"
    "Pacific"
)

# Common locales. Add/remove as needed. 'en_US.UTF-8' is standard.
declare -a LOCALE_OPTIONS=(
    "en_US.UTF-8"
    "en_GB.UTF-8"
    "de_DE.UTF-8"
    "fr_FR.UTF-8"
    "es_ES.UTF-8"
    "ja_JP.UTF-8"
    "zh_CN.UTF-8"
)

# Common console keymaps. Can be expanded based on 'localectl list-keymaps'.
declare -a KEYMAP_OPTIONS=(
    "us" "de" "fr" "es" "gb" "jp"
)

# Common countries for Reflector.
declare -a REFLECTOR_COMMON_COUNTRIES=(
    "US" "CA" "MX" "BR"
    "DE" "FR" "GB" "IT" "NL"
    "AU" "NZ"
    "IN" "JP" "KR" "SG"
    "ZA"
)

# Bootloader options
declare -a BOOTLOADER_TYPES_OPTIONS=("grub" "systemd-boot")

# AUR Helper options
declare -a AUR_HELPERS_OPTIONS=("yay" "paru")

# GRUB Theme options (themes would need to be physically present in a 'themes' directory)
declare -a GRUB_THEME_OPTIONS=(
    "poly-dark"
    "CyberEXS"
    "Cyberpunk"
    "HyperFluent"
    "Default" # Option to use GRUB's default theme (no custom theme)
)


# --- Package Lists (Associative Arrays mapping choice to packages) ---

# Base packages for pacstrap
declare -A BASE_PACKAGES=(
    [essential]="base" # Kernel, firmware, headers are handled by KERNEL_TYPE
    [bootloader_grub]="grub efibootmgr os-prober"
    [bootloader_systemdboot]="systemd-boot"
    [network]="networkmanager dhcpcd"
    [system_utils]="sudo man-db man-pages vim nano bash-completion git"
    # CPU Microcode packages (installed conditionally based on detection)
    [firmware_intel]="intel-ucode"
    [firmware_amd]="amd-ucode"
    # LVM and RAID tools (needed if chosen in partitioning scheme)
    [lvm]="lvm2"
    [raid]="mdadm"
    # Basic filesystem utilities (e2fsprogs for ext4 is common, others for optional FS types)
    [fs_ext4]="e2fsprogs"
    [fs_btrfs]="btrfs-progs"
    [fs_xfs]="xfsprogs"
)

# Desktop Environments and their core packages
declare -A DESKTOP_ENVIRONMENTS=(
    [gnome]="gnome gnome-extra gnome-tweaks gnome-shell-extensions gnome-browser-connector firefox"
    [kde]="plasma-desktop kde-applications dolphin firefox lxappearance"
    [hyprland]="hyprland hyprland-protocols xdg-desktop-portal-hyprland" # Core Hyprland & Wayland integration
    [hyprland]+=" hypridle hyprlock hyprpicker hyprshade hyprsunset cliphist grim grimblast-git slurp swappy swww swaylockeffects-git swayosd-git wlogout" # Hyprland specific utilities
    [hyprland]+=" kitty waybar wofi mako dunst" # Essential UI/Interaction (Terminal, Bar, Launcher, Notifications)
    [hyprland]+=" pipewire wireplumber pipewire-alsa pipewire-audio pipewire-jack pipewire-pulse pipewire-v4l2 gst-plugin-pipewire pamixer pavucontrol" # Audio Stack
    [hyprland]+=" network-manager-applet" # Network Tray Icon
    [hyprland]+=" brightnessctl udiskie" # Hardware control, automount
    [hyprland]+=" polkit-gnome" # PolicyKit authentication agent
    [hyprland]+=" qt5-wayland qt6-wayland kvantum kvantum-qt5 qt5ct qt6ct" # Qt Wayland integration & theming
    [hyprland]+=" nwg-look nwg-displays bluez bluez-utils blueman" # Theming tools & Bluetooth stack
    [hyprland]+=" ttf-firacode-nerd ttf-font-awesome ttf-meslo-nerd noto-fonts-emoji ttf-anonymouspro-nerd ttf-daddytime-mono-nerd" # All fonts added/corrected
    [hyprland]+=" dolphin rofi-wayland satty imagemagick" # Common GUI file manager & other utilities
    [hyprland]+=" wlr-protocols wlr-randr" # Explicit Wayland protocol/randr utilities
    [hyprland]+=" xdg-desktop-portal-gtk libnotify" # XDG Desktop Portal for GTK, General notification library
    [none]="" # For server or minimal install
)

# Display Managers for various DEs (installed conditionally)
declare -A DISPLAY_MANAGERS=(
    [gdm]="gdm"
    [sddm]="sddm"
    [none]="" # No display manager for server/WM-only
)

# GPU Drivers (packages installed conditionally based on auto-detection)
declare -A GPU_DRIVERS=(
    [amd]="xf86-video-amdgpu mesa vulkan-radeon"
    [nvidia]="nvidia nvidia-utils nvidia-settings"
    [intel]="xf86-video-intel mesa vulkan-intel"
    [none]="" # For headless systems or if detection fails
)

# AUR Helper packages
declare -A AUR_HELPERS=(
    [yay]="yay"
    [paru]="paru"
)

# Flatpak package
FLATPAK_PACKAGE="flatpak"

# Custom packages specified by the user to be installed from Arch repos
CUSTOM_PACKAGES="neovim"

# Custom AUR packages specified by the user to be installed via AUR helper
CUSTOM_AUR_PACKAGES=""

# GRUB Theme specific directories/files (used by chroot_config.sh for installation)
# Format: "git_url|path/to/theme.txt_relative_to_repo_root"
declare -A GRUB_THEME_SOURCES=(
    [poly-dark]="https://github.com/shvchk/poly-dark.git|theme.txt"
    [CyberEXS]="https://github.com/HenriqueLopes42/themeGrub.CyberEXS.git|theme.txt"
    [Cyberpunk]="https://gitlab.com/anoopmsivadas/Cyberpunk-GRUB-Theme.git|Cyberpunk/theme.txt"
    [HyperFluent]="https://github.com/Coopydood/HyperFluent-GRUB-Theme.git|arch/theme.txt"
    [Default]="" # No source for default theme
)


# --- mkinitcpio Hooks (Dynamic components based on features) ---
INITCPIO_BASE_HOOKS="base udev autodetect modconf block keyboard keymap filesystems fsck"
INITCPIO_LUKS_HOOK="encrypt"
INITCPIO_LVM_HOOK="lvm2"
INITCPIO_RAID_HOOK="mdadm_udev"
INITCPIO_NVME_HOOK="nvme"


# --- GRUB Kernel Command Line Parameters ---
GRUB_CMDLINE_LUKS_BASE="cryptdevice=UUID=<LUKS_CONTAINER_UUID>:cryptroot"
GRUB_CMDLINE_LVM_ON_LUKS="rd.lvm.vg=$VG_NAME"


# --- Default Logical Volume Layout (for LVM schemes) ---
declare -A LV_LAYOUT=(
    [lv_root]="100G"
    [lv_swap]="4G"
    [lv_home]="100%FREE"
)
declare -A DEFAULT_LV_MOUNTPOINTS=(
    [lv_root]="/mnt"
    [lv_swap]="[SWAP]"
    [lv_home]="/mnt/home"
)
declare -A DEFAULT_LV_FSTYPES=(
    [lv_root]="$ROOT_FILESYSTEM_TYPE"
    [lv_swap]="swap"
    [lv_home]="$HOME_FILESYSTEM_TYPE"
)
