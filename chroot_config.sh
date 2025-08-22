#!/bin/bash
# chroot_config.sh - Functions for post-base-install (chroot) configurations
# This script is designed to be copied into the /mnt environment and executed by arch-chroot.

# Strict mode for this script
set -euo pipefail

# Source its own copy of config.sh and utils.sh from its copied location
SOURCE_DIR_IN_CHROOT="/archl4tm" # Path where install_arch.sh copies these scripts
source "$SOURCE_DIR_IN_CHROOT/config.sh"
source "$SOURCE_DIR_IN_CHROOT/utils.sh"

# Note: Variables like INSTALL_DISK, ROOT_PASSWORD, etc. are populated from the environment passed by install_arch.sh
# Associative arrays like PARTITION_UUIDS are also exported (-A).
# So, they will be directly available in this script's scope.

# Re-define basic logging functions to ensure they are available within this script's context.
# These will override the log_* from utils.sh that might be sourced, but are safer for this context
# and ensure consistency if utils.sh is modified.
_log_info() { echo -e "\e[32m[INFO]\e[0m \$(date +%T) \$1"; }
_log_warn() { echo -e "\e[33m[WARN]\e[0m \$(date +%T) \$1" >&2; }
_log_error() { echo -e "\e[31m[ERROR]\e[0m \$(date +%T) \$1" >&2; exit 1; }
_log_success() { echo -e "\n\e[32;1m==================================================\e[0m\n\e[32;1m \$1 \e[0m\n\e[32;1m==================================================\e[0m\n"; }


# Main function for chroot configuration - this is now the entry point for this script
main_chroot_config() {
    _log_info "Starting chroot configurations within target system."

    # --- Phase 1: Basic System Configuration ---
    _log_info "Configuring time, locale, hostname, and basic user setup."

    _log_info "Setting system clock and timezone..."
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime || _log_error "Failed to set timezone symlink."
    hwclock --systohc || _log_error "Failed to sync hardware clock."

    _log_info "Setting localization (locale, keymap)..."
    echo "LANG=$LOCALE" > /etc/locale.conf || _log_error "Failed to set locale.conf."
    sed -i "/^#$(echo "$LOCALE" | sed 's/\./\\./g')/s/^#//" /etc/locale.gen || _log_error "Failed to uncomment locale in locale.gen."
    locale-gen || _log_error "Failed to generate locales."
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf || _log_error "Failed to set vconsole.conf."

    _log_info "Setting hostname and /etc/hosts..."
    echo "$SYSTEM_HOSTNAME" > /etc/hostname || _log_error "Failed to set hostname."
    echo "127.0.0.1 localhost" > /etc/hosts || _log_error "Failed to write to /etc/hosts."
    echo "::1       localhost" >> /etc/hosts || _log_error "Failed to append to /etc/hosts."
    echo "127.0.1.1 $SYSTEM_HOSTNAME.localdomain $SYSTEM_HOSTNAME" >> /etc/hosts || _log_error "Failed to append to /etc/hosts."
    _log_info "/etc/hosts configured."

    _log_info "Setting root password..."
    echo "root:$ROOT_PASSWORD" | chpasswd || _log_error "Failed to set root password."

    _log_info "Creating main user: $MAIN_USERNAME..."
    if id -u "$MAIN_USERNAME" &>/dev/null; then
        _log_warn "User '$MAIN_USERNAME' already exists. Skipping user creation."
    else
        useradd -m -G wheel -s /bin/bash "$MAIN_USERNAME" || _log_error "Failed to create user '$MAIN_USERNAME'."
        echo "$MAIN_USERNAME:$MAIN_USER_PASSWORD" | chpasswd || _log_error "Failed to set password for '$MAIN_USERNAME'."
        echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel-sudo || _log_error "Failed to configure sudoers."
        chmod 0440 /etc/sudoers.d/10-wheel-sudo || _log_error "Failed to set permissions on sudoers file."
    fi

    # --- Phase 2: Bootloader & Initramfs ---
    _log_info "Configuring bootloader, GRUB defaults, theme, and mkinitpio hooks."
    configure_bootloader_chroot || _log_error "Bootloader installation failed."

    configure_grub_defaults_chroot || _log_error "GRUB default configuration failed."

    configure_grub_theme_chroot || _log_error "GRUB theme configuration failed."

    configure_grub_cmdline_chroot || _log_error "GRUB kernel command line configuration failed."

    configure_mkinitcpio_hooks_chroot || _log_error "Mkinitcpio hooks configuration or initramfs rebuild failed."


    # --- Phase 3: Desktop Environment & Drivers ---
    _log_info "Installing Desktop Environment: $DESKTOP_ENVIRONMENT..."
    local de_packages=""
    case "$DESKTOP_ENVIRONMENT" in
        "gnome") de_packages="${DESKTOP_ENVIRONMENTS_GNOME_PACKAGES[@]}" ;;
        "kde") de_packages="${DESKTOP_ENVIRONMENTS_KDE_PACKAGES[@]}" ;;
        "hyprland") de_packages="${DESKTOP_ENVIRONMENTS_HYPRLAND_PACKAGES[@]}" ;;
        "none") de_packages="" ;;
    esac
    if [[ -n "$de_packages" ]]; then
        install_packages_chroot "$de_packages" || _log_error "Desktop Environment packages installation failed."
    fi

    _log_info "Installing Display Manager: $DISPLAY_MANAGER..."
    local dm_packages=""
    case "$DISPLAY_MANAGER" in
        "gdm") dm_packages="${DISPLAY_MANAGERS_GDM_PACKAGES[@]}" ;;
        "sddm") dm_packages="${DISPLAY_MANAGERS_SDDM_PACKAGES[@]}" ;;
        "none") dm_packages="" ;;
    esac
    if [[ -n "$dm_packages" ]]; then
        install_packages_chroot "$dm_packages" || _log_error "Display Manager packages installation failed."
        enable_systemd_service_chroot "$DISPLAY_MANAGER" || _log_error "Failed to enable Display Manager service."
    fi
    
    _log_info "Installing GPU Drivers..."
    install_gpu_drivers_chroot || _log_error "GPU driver installation failed."

    _log_info "Installing CPU Microcode..."
    install_microcode_chroot || _log_error "CPU Microcode installation failed."


    # --- Phase 4: Optional Software & User Customization ---
    _log_info "Enabling Multilib repository..."
    enable_multilib_chroot || _log_error "Multilib repository configuration failed."

    _log_info "Installing AUR Helper..."
    install_aur_helper_chroot || _log_error "AUR Helper installation failed."

    _log_info "Installing Flatpak..."
    install_flatpak_chroot || _log_error "Flatpak installation failed."

    _log_info "Installing Custom Packages..."
    install_custom_packages_chroot || _log_error "Custom packages installation failed."

    _log_info "Deploying Dotfiles..."
    deploy_dotfiles_chroot || _log_error "Dotfile deployment failed."

    _log_info "Configuring Numlock on boot..."
    configure_numlock_chroot || _log_error "Numlock on boot configuration failed."

    _log_info "Saving mdadm.conf for RAID arrays..."
    save_mdadm_conf_chroot || _log_error "Mdadm.conf saving failed."


    # --- Phase 5: Final System Services ---
    _log_info "Enabling essential system services..."
    enable_systemd_service_chroot "NetworkManager" || _log_error "Failed to enable NetworkManager service."

    _log_success "Chroot configuration complete."
}

# --- Call the main function for chroot_config.sh ---
main_chroot_config "$@"

# --- Functions called by main_chroot_config (run INSIDE chroot context) ---
# Note: These functions assume they are already running inside the chroot environment.
# They should NOT have 'arch-chroot /mnt' prefixes.
# They use the _log_* variants for logging.

configure_bootloader_chroot() {
    case "$BOOTLOADER_TYPE" in
        grub)
            _log_info "Installing GRUB for $BOOT_MODE..."
            # grub-install and grub-mkconfig will be run inside this single-command chroot.
            if [ "$BOOTLOADER_TYPE" == "grub" ]; then
                if [ "$BOOT_MODE" == "uefi" ]; then
                    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || _log_error "GRUB UEFI installation failed."
                else
                    grub-install "$INSTALL_DISK" || _log_error "GRUB BIOS installation failed."
                fi
                # grub-mkconfig is called by main_chroot_config after all GRUB settings are done.
            else
                _log_warn "GRUB installation skipped because BOOTLOADER_TYPE is not grub."
            fi
            ;;
        systemd-boot)
            _log_info "Installing systemd-boot..."
            bootctl install || _log_error "systemd-boot installation failed."
            _log_warn "systemd-boot configuration requires manual setup of loader entries for now."
            ;;
        *)
            _log_warn "No bootloader selected or invalid. Skipping bootloader installation."
            ;;
    esac
}

# Helper to clone a Git repository inside the chroot.
# Args: $1 = repo_url, $2 = target_dir_in_chroot, $3 = branch (optional)
git_clone_chroot() {
    local repo_url="$1"
    local target_dir="$2"
    local branch_arg=""
    if [ -n "$3" ]; then
        branch_arg="--branch $3"
    fi
    _log_info "Cloning $repo_url into $target_dir..."
    git clone --depth 1 $branch_arg "$repo_url" "$target_dir" || _log_error "Git clone failed for $repo_url."
}

# Configures GRUB default settings.
configure_grub_defaults_chroot() {
    local grub_default_file="/etc/default/grub"

    _log_info "Setting GRUB default configurations in $grub_default_file..."

    edit_file_in_chroot "$grub_default_file" "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=saved|"
    edit_file_in_chroot "$grub_default_file" "s|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=3|"
    edit_file_in_chroot "$grub_default_file" "s|^#GRUB_SAVEDEFAULT=true|GRUB_SAVEDEFAULT=true|" || true

    if [ "$WANT_ENCRYPTION" == "yes" ]; then
        _log_info "Enabling GRUB_ENABLE_CRYPTODISK for encrypted setup."
        edit_file_in_chroot "$grub_default_file" "s|^#GRUB_ENABLE_CRYPTODISK=y|GRUB_ENABLE_CRYPTODISK=y|" || true
    fi

    edit_file_in_chroot "$grub_default_file" "s|^GRUB_GFXMODE=auto|GRUB_GFXMODE=1920x1440x32|"

    _log_info "GRUB default configurations applied."
}

# Configures and installs the chosen GRUB theme within the chroot.
configure_grub_theme_chroot() {
    if [ "$WANT_GRUB_THEME" == "no" ] || [ "$GRUB_THEME_CHOICE" == "Default" ]; then
        _log_info "GRUB theming not requested or default theme chosen. Skipping."
        return 0
    fi

    local theme_name="$GRUB_THEME_CHOICE"
    local theme_info_string=""

    # Correctly get the theme URL and file path using case statement and eval
    case "$theme_name" in
        "PolyDark")         eval "theme_info_string=\"\${GRUB_THEME_SOURCES_POLY_DARK[*]}\"";;
        "CyberEXS")         eval "theme_info_string=\"\${GRUB_THEME_SOURCES_CYBEREXS[*]}\"";;
        "CyberPunk")        eval "theme_info_string=\"\${GRUB_THEME_SOURCES_CYBERPUNK[*]}\"";;
        "HyperFluent")      eval "theme_info_string=\"\${GRUB_THEME_SOURCES_HYPERFLUENT[*]}\"";;
        *)                  _log_warn "No source info defined for GRUB theme '$theme_name'. Skipping theming."; return 0;;
    esac

    IFS='|' read -r theme_repo_url theme_file_in_repo_relative <<< "$theme_info_string"
    local theme_clone_dir="/tmp/grub_theme_clone" # Temporary clone location
    
    _log_info "Installing GRUB theme: $theme_name from $theme_repo_url..."

    git_clone_chroot "$theme_repo_url" "$theme_clone_dir" || return 1

    local actual_theme_source_dir_in_clone=""
    if [ "$(dirname "$theme_file_in_repo_relative")" == "." ]; then
        actual_theme_source_dir_in_clone="$theme_clone_dir"
    else
        actual_theme_source_dir_in_clone="${theme_clone_dir}/$(dirname "$theme_file_in_repo_relative")"
    fi

    # Check if the calculated source directory actually exists in the chroot
    if [ ! -d "$actual_theme_source_dir_in_clone" ]; then
        _log_error "Calculated theme source directory '$actual_theme_source_dir_in_clone' not found in cloned repo."
    fi

    local final_grub_theme_install_dir="/boot/grub/themes/$theme_name"
    local final_theme_txt_path="${final_grub_theme_install_dir}/$(basename "$theme_file_in_repo_relative")" # Path for GRUB_THEME=

    _log_info "Copying theme files from '$actual_theme_source_dir_in_clone' to '$final_grub_theme_install_dir'..."
    mkdir -p "$final_grub_theme_install_dir" || _log_error "Failed to create theme directory $final_grub_theme_install_dir."
    rsync -av "${actual_theme_source_dir_in_clone}/" "$final_grub_theme_install_dir/" || _log_error "Failed to copy GRUB theme files."

    local grub_default_file="/etc/default/grub"
    local theme_config_line="GRUB_THEME=\"$final_theme_txt_path\""

    _log_info "Updating $grub_default_file with GRUB_THEME: $theme_config_line"
    edit_file_in_chroot "$grub_default_file" "s|^GRUB_THEME=.*|$theme_config_line|" || \
    edit_file_in_chroot "$grub_default_file" "/^GRUB_CMDLINE_LINUX_DEFAULT=/a $theme_config_line" || \
    edit_file_in_chroot "$grub_default_file" "$ a $theme_config_line"

    rm -rf "$theme_clone_dir" || _log_warn "Failed to remove temporary GRUB theme clone directory."

    _log_info "GRUB theme $theme_name installed and configured."
    
    chown -R root:root "$final_grub_theme_install_dir" || _log_warn "Failed to set ownership for GRUB theme directory."
}

# Configures GRUB kernel command line.
configure_grub_cmdline_chroot() {
    local kernel_cmdline=""

    if [[ "$(get_device_type "$INSTALL_DISK")" == "nvme" ]]; then
        kernel_cmdline+=" nvme_load=YES"
    fi

    if [ "$WANT_ENCRYPTION" == "yes" ]; then
        local luks_container_uuid="${PARTITION_UUIDS_LUKS_CONTAINER_UUID}"
        if [ -z "$luks_container_uuid" ]; then
            _log_error "LUKS UUID not found for GRUB command line."
        fi
        kernel_cmdline+=" ${GRUB_CMDLINE_LUKS_BASE/<LUKS_CONTAINER_UUID>/$luks_container_uuid}"
    fi

    if [ "$WANT_LVM" == "yes" ]; then
        kernel_cmdline+=" ${GRUB_CMDLINE_LVM_ON_LUKS}"
    fi

    local root_fs_uuid="${PARTITION_UUIDS_LV_ROOT_UUID}"
    if [ -z "$root_fs_uuid" ]; then
        root_fs_uuid="${PARTITION_UUIDS_ROOT_UUID}"
    fi

    if [ -z "$root_fs_uuid" ]; then
        _log_error "Could not determine root filesystem UUID for GRUB_CMDLINE_LINUX_DEFAULT."
    fi
    kernel_cmdline+=" root=UUID=$root_fs_uuid"

    kernel_cmdline+=" loglevel=3 quiet"

    if [ "$ENABLE_OS_PROBER" == "yes" ]; then
        _log_info "Enabling OS Prober in GRUB."
        edit_file_in_chroot "/etc/default/grub" "s|^#GRUB_DISABLE_OS_PROBER=true|GRUB_DISABLE_OS_PROBER=false|" || true
    fi

    kernel_cmdline=$(echo "$kernel_cmdline" | xargs)

    if [ -n "$kernel_cmdline" ]; then
        _log_info "Setting GRUB_CMDLINE_LINUX_DEFAULT=\"$kernel_cmdline\""
        edit_file_in_chroot "$grub_default_file" "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$kernel_cmdline\"|"
    fi

    _log_info "GRUB command line configured."
}

# Configures mkinitcpio hooks and rebuilds initramfs.
configure_mkinitcpio_hooks_chroot() {
    local hooks_string="$INITCPIO_BASE_HOOKS"

    if [[ "$(get_device_type "$INSTALL_DISK")" == "nvme" ]]; then
        hooks_string+=" $INITCPIO_NVME_HOOK"
    fi
    if [ "$WANT_ENCRYPTION" == "yes" ]; then
        hooks_string+=" $INITCPIO_LUKS_HOOK"
    fi
    if [ "$WANT_LVM" == "yes" ]; then
        hooks_string+=" $INITCPIO_LVM_HOOK"
    fi
    if [ "$WANT_RAID" == "yes" ]; then
        hooks_string+=" $INITCPIO_RAID_HOOK"
    fi

    hooks_string=$(echo "$hooks_string" | xargs)

    _log_info "Setting mkinitcpio HOOKS=($hooks_string)..."
    edit_file_in_chroot "/etc/mkinitcpio.conf" "s/^HOOKS=.*/HOOKS=($hooks_string)/"

    _log_info "Running mkinitcpio -P to rebuild initramfs..."
    mkinitcpio -P || return 1
    _log_info "Initramfs rebuilt."
}

# Installs GPU drivers based on detected type.
install_gpu_drivers_chroot() {
    if [ "$GPU_DRIVER_TYPE" == "none" ]; then
        _log_info "No specific GPU driver type detected or needed. Skipping GPU driver installation."
        return 0
    fi

    local gpu_packages=""
    case "$GPU_DRIVER_TYPE" in
        "amd")      gpu_packages="${GPU_DRIVERS_AMD_PACKAGES[@]}";;
        "nvidia")   gpu_packages="${GPU_DRIVERS_NVIDIA_PACKAGES[@]}";;
        "intel")    gpu_packages="${GPU_DRIVERS_INTEL_PACKAGES[@]}";;
        "none")     gpu_packages="";;
    esac

    if [ -z "$gpu_packages" ]; then
        _log_warn "No packages defined for GPU driver type '$GPU_DRIVER_TYPE'. Skipping installation."
        return 0
    fi

    _log_info "Installing $GPU_DRIVER_TYPE GPU drivers: '$gpu_packages'..."
    install_packages_chroot "$gpu_packages" || return 1
    _log_info "GPU driver installation complete."
}

# Enables the Multilib repository in pacman.conf.
enable_multilib_chroot() {
    if [ "$WANT_MULTILIB" == "no" ]; then
        log_info "Multilib repository not requested. Skipping."
        return 0
    fi

    _log_info "Enabling Multilib repository in /etc/pacman.conf..."
    edit_file_in_chroot "/etc/pacman.conf" "s|^#\[multilib\]|\\[multilib\]|"
    edit_file_in_chroot "/etc/pacman.conf" "s|^#Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/mirrorlist|"

    _log_info "Syncing pacman databases for Multilib."
    pacman -Sy --noconfirm || return 1
    _log_info "Multilib repository enabled."
}

# Installs the chosen AUR helper.
install_aur_helper_chroot() {
    if [ "$WANT_AUR_HELPER" == "no" ] || [ -z "$AUR_HELPER_CHOICE" ]; then
        _log_info "AUR helper not requested. Skipping."
        return 0
    fi

    local helper_package_name=""
    case "$AUR_HELPER_CHOICE" in
        "yay") helper_package_name="${AUR_HELPERS_YAY_PACKAGES[@]}" ;;
        "paru") helper_package_name="${AUR_HELPERS_PARU_PACKAGES[@]}" ;;
    esac

    if [ -z "$helper_package_name" ]; then
        _log_error "AUR helper package name not defined for '$AUR_HELPER_CHOICE'."
    fi

    _log_info "Installing AUR helper: $AUR_HELPER_CHOICE ($helper_package_name)..."
    
    local user_home="/home/$MAIN_USERNAME"
    local temp_aur_dir="$user_home/aur_build_temp"

    # Define logging functions within this subshell for su -c context
    # This ensures logging works within the non-root execution
    bash -c "
        _log_info() { echo -e \"\e[32m[INFO]\e[0m \$(date +%T) \$1\"; }
        _log_warn() { echo -e \"\e[33m[WARN]\e[0m \$(date +%T) \$1\" >&2; }
        _log_error() { echo -e \"\e[31m[ERROR]\e[0m \$(date +%T) \$1\" >&2; exit 1; }

        _log_info \"Building and installing $AUR_HELPER_CHOICE as user $MAIN_USERNAME...\"
        mkdir -p \"$temp_aur_dir\" || _log_error \"Failed to create temporary AUR directory.\"
        cd \"$temp_aur_dir\" || _log_error \"Failed to navigate to temporary AUR directory.\"
        git clone https://aur.archlinux.org/${helper_package_name}.git || _log_error \"Failed to clone AUR helper repository.\"
        cd \"$helper_package_name\" || _log_error \"Failed to navigate into cloned AUR helper directory.\"
        makepkg -si --noconfirm || _log_error \"makepkg failed for $AUR_HELPER_CHOICE.\"
        _log_info \"Cleaning up temporary AUR directory.\"
        rm -rf \"$temp_aur_dir\" || _log_warn \"Failed to remove temporary AUR build directory.\"
    " || return 1
    log_info "AUR helper $AUR_HELPER_CHOICE installed."
}

# Installs Flatpak and adds Flathub remote.
install_flatpak_chroot() {
    if [ "$WANT_FLATPAK" == "no" ]; then
        log_info "Flatpak support not requested. Skipping."
        return 0
    fi

    _log_info "Installing Flatpak..."
    install_packages_chroot "$FLATPAK_PACKAGE" || return 1

    _log_info "Adding Flathub remote..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || return 1
    _log_info "Flatpak installed and Flathub remote added."
}

# Installs custom packages from official repos and AUR.
install_custom_packages_chroot() {
    if [ "$INSTALL_CUSTOM_PACKAGES" == "yes" ] && [ -n "$CUSTOM_PACKAGES" ]; then
        log_info "Installing custom official packages: '$CUSTOM_PACKAGES'..."
        install_packages_chroot "$CUSTOM_PACKAGES" || return 1
    else
        log_info "No custom official packages requested. Skipping."
    fi

    if [ "$INSTALL_CUSTOM_AUR_PACKAGES" == "yes" ] && [ -n "$CUSTOM_AUR_PACKAGES" ]; then
        if [ "$WANT_AUR_HELPER" == "no" ]; then
            log_warn "Custom AUR packages requested, but no AUR helper selected. Skipping AUR package installation."
            return 0
        fi
        
        local aur_install_cmd="${AUR_HELPER_CHOICE} -S --noconfirm --needed"
        log_info "Installing custom AUR packages: '$CUSTOM_AUR_PACKAGES' using $AUR_HELPER_CHOICE..."
        
        # Define logging functions within this subshell for su -c context
        bash -c "
            _log_info() { echo -e \"\e[32m[INFO]\e[0m \$(date +%T) \$1\"; }
            _log_warn() { echo -e \"\e[33m[WARN]\e[0m \$(date +%T) \$1\" >&2; }
            _log_error() { echo -e \"\e[31m[ERROR]\e[0m \$(date +%T) \$1\" >&2; exit 1; }

            _log_info \"Running $AUR_HELPER_CHOICE to install custom AUR packages as user $MAIN_USERNAME...\"
            $aur_install_cmd $CUSTOM_AUR_PACKAGES || _log_error \"Failed to install custom AUR packages.\"
        " || return 1
        log_info "Custom AUR packages installed."
    else
        log_info "No custom AUR packages requested. Skipping."
    fi
}

# Deploys dotfiles from a Git repository to the main user's home directory.
# Global: MAIN_USERNAME, DOTFILES_REPO_URL, DOTFILES_BRANCH, WANT_DOTFILES_DEPLOYMENT (from config.sh)
deploy_dotfiles_chroot() {
    if [ "$WANT_DOTFILES_DEPLOYMENT" == "no" ] || [ -z "$DOTFILES_REPO_URL" ]; then
        log_info "Dotfile deployment not requested or repository URL not provided. Skipping."
        return 0
    fi

    log_info "Deploying dotfiles for user '$MAIN_USERNAME' from $DOTFILES_REPO_URL (branch: $DOTFILES_BRANCH)..."

    local user_home="/home/$MAIN_USERNAME"
    local dotfiles_clone_dir="$user_home/dotfiles_repo_temp"

    # Run commands as the new user, using a new login shell to ensure correct environment
    # Define logging functions within this subshell for su -c context
    bash -c "
        _log_info() { echo -e \"\e[32m[INFO]\e[0m \$(date +%T) \$1\"; }
        _log_warn() { echo -e \"\e[33m[WARN]\e[0m \$(date +%T) \$1\" >&2; }
        _log_error() { echo -e \"\e[31m[ERROR]\e[0m \$(date +%T) \$1\" >&2; exit 1; }

        _log_info \"Cloning dotfiles repository...\"
        git clone --depth 1 --branch \"$DOTFILES_BRANCH\" \"$DOTFILES_REPO_URL\" \"$dotfiles_clone_dir\" || _log_error \"Failed to clone dotfiles repository.\"
        
        if [ ! -d \"$dotfiles_clone_dir\" ]; then
            _log_error \"Dotfiles repository did not clone correctly to $dotfiles_clone_dir.\"
            exit 1
        fi

        _log_info \"Running dotfiles deployment script...\"
        if [ -f \"$dotfiles_clone_dir/install.sh\" ]; then
            bash \"$dotfiles_clone_dir/install.sh\" || _log_error \"Dotfiles install.sh script failed.\"
        elif [ -f \"$dotfiles_clone_dir/setup.sh\" ]; then
            bash \"$dotfiles_clone_dir/setup.sh\" || _log_error \"Dotfiles setup.sh script failed.\"
        elif [ -f \"$dotfiles_clone_dir/bootstrap.sh\" ]; then
            bash \"$dotfiles_clone_dir/bootstrap.sh\" || _log_error \"Dotfiles bootstrap.sh script failed.\"
        else
            _log_warn \"No common dotfile deployment script (install.sh, setup.sh, bootstrap.sh) found in repo. User might need to manually deploy dotfiles.\"
        fi

        _log_info \"Cleaning up temporary dotfiles clone directory.\"
        rm -rf \"$dotfiles_clone_dir\" || _log_warn \"Failed to remove temporary dotfiles clone directory.\"
        
        _log_info \"Dotfile deployment for '$MAIN_USERNAME' complete.\"
    " || return 1
}

# Configures Numlock to be enabled on boot.
configure_numlock_chroot() {
    if [ "$WANT_NUMLOCK_ON_BOOT" == "no" ]; then
        log_info "Numlock on boot not requested. Skipping."
        return 0
    fi

    log_info "Enabling numlock on boot via systemd-numlock-on.service..."
    enable_systemd_service_chroot "systemd-numlock-on.service" || return 1
    log_info "Numlock on boot enabled."
}

# Saves mdadm.conf for RAID arrays.
save_mdadm_conf_chroot() {
    if [ "$WANT_RAID" == "no" ]; then
        log_info "RAID not configured. Skipping mdadm.conf saving."
        return 0
    fi

    log_info "Saving mdadm.conf for RAID arrays..."
    mdadm --detail --scan > /etc/mdadm.conf || log_error "Failed to save mdadm.conf."
    log_info "mdadm.conf saved."
}

# --- Final Cleanup ---
final_cleanup() {
    log_info "Performing final cleanup..."
    safe_umount /mnt/boot/efi || true
    safe_umount /mnt/boot || true
    safe_umount /mnt || true
    log_info "Cleanup complete."
}
