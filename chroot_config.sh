#!/bin/bash
# chroot_config.sh - Functions for post-base-install (chroot) configurations

perform_chroot_configurations() {
    log_info "Entering chroot environment for post-installation configuration..."
    arch-chroot /mnt /bin/bash <<EOF
        set -euo pipefail

        # --- Re-define basic logging functions for use inside chroot ---
        _log_info() { echo -e "\e[32m[INFO]\e[0m \$(date +%T) \$1"; }
        _log_warn() { echo -e "\e[33m[WARN]\e[0m \$(date +%T) \$1" >&2; }
        _log_error() { echo -e "\e[31m[ERROR]\e[0m \$(date +%T) \$1" >&2; exit 1; }
        _log_success() { echo -e "\n\e[32;1m==================================================\e[0m\n\e[32;1m \$1 \e[0m\n\e[32;1m==================================================\e[0m\n"; }

        _log_info "Setting system clock and timezone..."
        ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
        hwclock --systohc

        _log_info "Setting localization (locale, keymap)..."
        echo "LANG=$LOCALE" > /etc/locale.conf
        sed -i "/^#$(echo "$LOCALE" | sed 's/\./\\./g')/s/^#//" /etc/locale.gen
        locale-gen

        echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

        _log_info "Setting hostname and /etc/hosts..."
        echo "$SYSTEM_HOSTNAME" > /etc/hostname
        # Overwrite /etc/hosts cleanly instead of appending
        cat <<EOT > /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 $SYSTEM_HOSTNAME.localdomain $SYSTEM_HOSTNAME
EOT

        _log_info "Setting root password..."
        echo "root:$ROOT_PASSWORD" | chpasswd

        _log_info "Creating main user: $MAIN_USERNAME..."
        if id -u "$MAIN_USERNAME" &>/dev/null; then
            _log_warn "User '$MAIN_USERNAME' already exists. Skipping user creation."
        else
            useradd -m -G wheel -s /bin/bash "$MAIN_USERNAME" || _log_error "Failed to create user '$MAIN_USERNAME'."
            echo "$MAIN_USERNAME:$MAIN_USER_PASSWORD" | chpasswd || _log_error "Failed to set password for '$MAIN_USERNAME'."
            # Use /etc/sudoers.d/ for safer sudoers editing
            echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel-sudo || _log_error "Failed to configure sudoers."
            chmod 0440 /etc/sudoers.d/10-wheel-sudo || _log_error "Failed to set permissions on sudoers file."
        fi

        _log_info "Installing and configuring bootloader ($BOOTLOADER_TYPE)..."
        configure_bootloader_chroot || exit 1 # Calls sub-function within chroot

        _log_info "Configuring GRUB default settings..."
        configure_grub_defaults_chroot || exit 1

        _log_info "Configuring GRUB theme..."
        configure_grub_theme_chroot || exit 1

        _log_info "Installing Desktop Environment: $DESKTOP_ENVIRONMENT..."
        if [[ -n "${DESKTOP_ENVIRONMENTS[$DESKTOP_ENVIRONMENT]}" ]]; then
            install_packages_chroot ${DESKTOP_ENVIRONMENTS[$DESKTOP_ENVIRONMENT]} || exit 1
        fi

        _log_info "Installing Display Manager: $DISPLAY_MANAGER..."
        if [[ -n "${DISPLAY_MANAGERS[$DISPLAY_MANAGER]}" ]]; then
            install_packages_chroot ${DISPLAY_MANAGERS[$DISPLAY_MANAGER]} || exit 1
            enable_systemd_service_chroot "$DISPLAY_MANAGER" || exit 1
        fi
        
        _log_info "Installing GPU Drivers..."
        install_gpu_drivers_chroot || exit 1

        _log_info "Installing CPU Microcode..."
        install_microcode_chroot || exit 1

        _log_info "Configuring mkinitcpio hooks and rebuilding initramfs..."
        configure_mkinitpio_hooks_chroot || exit 1 # Fix mkinitpio typo

        _log_info "Enabling Multilib repository..."
        enable_multilib_chroot || exit 1

        _log_info "Installing AUR Helper..."
        install_aur_helper_chroot || exit 1

        _log_info "Installing Flatpak..."
        install_flatpak_chroot || exit 1

        _log_info "Installing Custom Packages..."
        install_custom_packages_chroot || exit 1

        _log_info "Deploying Dotfiles..."
        deploy_dotfiles_chroot || exit 1

        _log_info "Configuring Numlock on boot..."
        configure_numlock_chroot || exit 1

        _log_info "Saving mdadm.conf for RAID arrays..."
        save_mdadm_conf_chroot || exit 1

        _log_info "Enabling essential services..."
        enable_systemd_service_chroot "NetworkManager"

        _log_info "Chroot configuration complete."
EOF
    local chroot_status=$?
    if [ "$chroot_status" -ne 0 ]; then
        error_exit "Chroot environment exited with status $chroot_status."
    fi
}

# --- Functions that run INSIDE chroot, called from perform_chroot_configurations ---
# Note: These functions will use the _log_* variants defined in the heredoc above.

configure_bootloader_chroot() {
    case "$BOOTLOADER_TYPE" in
        grub)
            _log_info "Installing GRUB for $BOOT_MODE..."
            if [ "$BOOT_MODE" == "uefi" ]; then
                grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || _log_error "GRUB UEFI installation failed."
            else
                grub-install "$INSTALL_DISK" || _log_error "GRUB BIOS installation failed."
            fi
            grub-mkconfig -o /boot/grub/grub.cfg || _log_error "GRUB configuration generation failed."
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
# Note: This function runs INSIDE the chroot. 'git' must be installed there.
# Args: $1 = repo_url, $2 = target_dir_in_chroot, $3 = branch (optional)
git_clone_chroot() {
    local repo_url="$1"
    local target_dir="$2"
    local branch_arg=""
    if [ -n "$3" ]; then
        branch_arg="--branch $3"
    fi
    _log_info "Cloning $repo_url into $target_dir inside chroot..."
    git clone --depth 1 $branch_arg "$repo_url" "$target_dir" || _log_error "Git clone failed for $repo_url."
}

# Configures GRUB default settings.
configure_grub_defaults_chroot() {
    local grub_default_file="/etc/default/grub"

    _log_info "Setting GRUB default configurations in $grub_default_file..."

    edit_file_in_chroot "$grub_default_file" "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=saved|"
    edit_file_in_chroot "$grub_default_file" "s|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=3|"
    edit_file_in_chroot "$grub_default_file" "s|^#GRUB_SAVEDEFAULT=true|GRUB_SAVEDEFAULT=true|" || true # Use || true for optional uncomment

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
    local theme_info_string="${GRUB_THEME_SOURCES[$theme_name]}"

    if [ -z "$theme_info_string" ]; then
        _log_warn "No source info defined for GRUB theme '$theme_name'. Skipping theming."
        return 0
    fi

    IFS='|' read -r theme_repo_url theme_file_in_repo_relative <<< "$theme_info_string"
    local theme_clone_dir="/tmp/grub_theme_clone" # Temporary clone location inside chroot's /tmp
    
    _log_info "Installing GRUB theme: $theme_name from $theme_repo_url..."

    git_clone_chroot "$theme_repo_url" "$theme_clone_dir" || return 1

    local actual_theme_source_dir_in_clone=""
    if [ "$(dirname "$theme_file_in_repo_relative")" == "." ]; then
        actual_theme_source_dir_in_clone="$theme_clone_dir"
    else
        actual_theme_source_dir_in_clone="${theme_clone_dir}/$(dirname "$theme_file_in_repo_relative")"
    fi

    if [ ! -d "$actual_theme_source_dir_in_clone" ]; then # Use test -d without arch-chroot prefix here
        _log_error "Calculated theme source directory '$actual_theme_source_dir_in_clone' not found in cloned repo."
    fi

    local final_grub_theme_install_dir="/boot/grub/themes/$theme_name"
    local final_theme_txt_path="${final_grub_theme_install_dir}/$(basename "$theme_file_in_repo_relative")"

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
        local luks_container_uuid="${PARTITION_UUIDS[luks_container_uuid]}"
        if [ -z "$luks_container_uuid" ]; then
            _log_error "LUKS UUID not found for GRUB command line."
        fi
        kernel_cmdline+=" ${GRUB_CMDLINE_LUKS_BASE/<LUKS_CONTAINER_UUID>/$luks_container_uuid}"
    fi

    if [ "$WANT_LVM" == "yes" ]; then
        kernel_cmdline+=" ${GRUB_CMDLINE_LVM_ON_LUKS}"
    fi

    local root_fs_uuid="${PARTITION_UUIDS[lv_root_uuid]:-}"
    if [ -z "$root_fs_uuid" ]; then
        root_fs_uuid="${PARTITION_UUIDS[root_uuid]:-}"
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
        edit_file_in_chroot "/etc/default/grub" "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$kernel_cmdline\"|"
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

    hooks_string=$(echo "$hooks_string" | xargs) # Removed redundant sed 's/ /\ /g'

    _log_info "Setting mkinitcpio HOOKS=($hooks_string)..."
    edit_file_in_chroot "/etc/mkinitcpio.conf" "s/^HOOKS=.*/HOOKS=($hooks_string)/"

    _log_info "Running mkinitcpio -P to rebuild initramfs..."
    arch-chroot /mnt mkinitpio -P || return 1 # Fixed typo mkinitpio -> mkinitcpio
    _log_info "Initramfs rebuilt."
}

# Installs GPU drivers based on detected type.
install_gpu_drivers_chroot() {
    if [ "$GPU_DRIVER_TYPE" == "none" ]; then
        _log_info "No specific GPU driver type detected or needed. Skipping GPU driver installation."
        return 0
    fi

    local gpu_packages="${GPU_DRIVERS[$GPU_DRIVER_TYPE]}"
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
        _log_info "Multilib repository not requested. Skipping."
        return 0
    fi

    _log_info "Enabling Multilib repository in /etc/pacman.conf..."
    edit_file_in_chroot "/etc/pacman.conf" "s|^#\[multilib\]|\\[multilib\]|"
    edit_file_in_chroot "/etc/pacman.conf" "s|^#Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/mirrorlist|"

    _log_info "Syncing pacman databases for Multilib."
    arch-chroot /mnt pacman -Sy --noconfirm || return 1
    _log_info "Multilib repository enabled."
}

# Installs the chosen AUR helper.
install_aur_helper_chroot() {
    if [ "$WANT_AUR_HELPER" == "no" ] || [ -z "$AUR_HELPER_CHOICE" ]; then
        _log_info "AUR helper not requested. Skipping."
        return 0
    fi

    local helper_package_name="${AUR_HELPERS[$AUR_HELPER_CHOICE]}"
    if [ -z "$helper_package_name" ]; then
        _log_error "AUR helper package name not defined for '$AUR_HELPER_CHOICE'."
    fi

    _log_info "Installing AUR helper: $AUR_HELPER_CHOICE ($helper_package_name)..."
    
    local user_home="/home/$MAIN_USERNAME"
    local temp_aur_dir="$user_home/aur_build_temp"

    # Define logging functions within this subshell for su -c context
    # This ensures logging works within the non-root execution
    arch-chroot /mnt su - "$MAIN_USERNAME" -c "
        _log_info() { echo -e \"\e[32m[INFO]\e[0m \$(date +%T) \$1\"; }
        _log_warn() { echo -e \"\e[33m[WARN]\e[0m \$(date +%T) \$1\" >&2; }
        _log_error() { echo -e \"\e[31m[ERROR]\e[0m \$(date +%T) \$1\" >&2; exit 1; } # Use exit 1 to propagate failure

        _log_info \"Building and installing $AUR_HELPER_CHOICE as user $MAIN_USERNAME...\"
        mkdir -p \"$temp_aur_dir\" || _log_error \"Failed to create temporary AUR directory.\"
        cd \"$temp_aur_dir\" || _log_error \"Failed to navigate to temporary AUR directory.\"
        git clone https://aur.archlinux.org/${helper_package_name}.git || _log_error \"Failed to clone AUR helper repository.\"
        cd \"$helper_package_name\" || _log_error \"Failed to navigate into cloned AUR helper directory.\"
        makepkg -si --noconfirm || _log_error \"makepkg failed for $AUR_HELPER_CHOICE.\"
        _log_info \"Cleaning up temporary AUR directory.\"
        rm -rf \"$temp_aur_dir\" || _log_warn \"Failed to remove temporary AUR build directory.\"
    " || return 1 # Propagate failure back to main script
    _log_info "AUR helper $AUR_HELPER_CHOICE installed."
}

# Installs Flatpak and adds Flathub remote.
install_flatpak_chroot() {
    if [ "$WANT_FLATPAK" == "no" ]; then
        _log_info "Flatpak support not requested. Skipping."
        return 0
    fi

    _log_info "Installing Flatpak..."
    install_packages_chroot "$FLATPAK_PACKAGE" || return 1

    _log_info "Adding Flathub remote..."
    arch-chroot /mnt flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || return 1
    _log_info "Flatpak installed and Flathub remote added."
}

# Installs custom packages from official repos and AUR.
install_custom_packages_chroot() {
    if [ "$INSTALL_CUSTOM_PACKAGES" == "yes" ] && [ -n "$CUSTOM_PACKAGES" ]; then
        _log_info "Installing custom official packages: '$CUSTOM_PACKAGES'..."
        install_packages_chroot "$CUSTOM_PACKAGES" || return 1
    else
        _log_info "No custom official packages requested. Skipping."
    fi

    if [ "$INSTALL_CUSTOM_AUR_PACKAGES" == "yes" ] && [ -n "$CUSTOM_AUR_PACKAGES" ]; then
        if [ "$WANT_AUR_HELPER" == "no" ]; then
            _log_warn "Custom AUR packages requested, but no AUR helper selected. Skipping AUR package installation."
            return 0
        fi
        
        local aur_install_cmd="${AUR_HELPER_CHOICE} -S --noconfirm --needed"
        _log_info "Installing custom AUR packages: '$CUSTOM_AUR_PACKAGES' using $AUR_HELPER_CHOICE..."
        
        # Define logging functions within this subshell for su -c context
        arch-chroot /mnt su - "$MAIN_USERNAME" -c "
            _log_info() { echo -e \"\e[32m[INFO]\e[0m \$(date +%T) \$1\"; }
            _log_warn() { echo -e \"\e[33m[WARN]\e[0m \$(date +%T) \$1\" >&2; }
            _log_error() { echo -e \"\e[31m[ERROR]\e[0m \$(date +%T) \$1\" >&2; exit 1; }

            _log_info \"Running $AUR_HELPER_CHOICE to install custom AUR packages as user $MAIN_USERNAME...\"
            $aur_install_cmd $CUSTOM_AUR_PACKAGES || _log_error \"Failed to install custom AUR packages.\"
        " || return 1
        _log_info "Custom AUR packages installed."
    else
        _log_info "No custom AUR packages requested. Skipping."
    fi
}

# Deploys dotfiles from a Git repository to the main user's home directory.
# Global: MAIN_USERNAME, DOTFILES_REPO_URL, DOTFILES_BRANCH, WANT_DOTFILES_DEPLOYMENT (from config.sh)
deploy_dotfiles_chroot() {
    if [ "$WANT_DOTFILES_DEPLOYMENT" == "no" ] || [ -z "$DOTFILES_REPO_URL" ]; then
        _log_info "Dotfile deployment not requested or repository URL not provided. Skipping."
        return 0
    fi

    _log_info "Deploying dotfiles for user '$MAIN_USERNAME' from $DOTFILES_REPO_URL (branch: $DOTFILES_BRANCH)..."

    local user_home="/home/$MAIN_USERNAME"
    local dotfiles_clone_dir="$user_home/dotfiles_repo_temp"

    # Run commands as the new user, using a new login shell to ensure correct environment
    # Define logging functions within this subshell for su -c context
    arch-chroot /mnt su - "$MAIN_USERNAME" -c "
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
        _log_info "Numlock on boot not requested. Skipping."
        return 0
    fi

    _log_info "Enabling numlock on boot via systemd-numlock-on.service..."
    enable_systemd_service_chroot "systemd-numlock-on.service" || return 1
    _log_info "Numlock on boot enabled."
}

# Saves mdadm.conf for RAID arrays.
save_mdadm_conf_chroot() {
    if [ "$WANT_RAID" == "no" ]; then
        _log_info "RAID not configured. Skipping mdadm.conf saving."
        return 0
    fi

    _log_info "Saving mdadm.conf for RAID arrays..."
    mdadm --detail --scan > /etc/mdadm.conf || _log_error "Failed to save mdadm.conf."
    _log_info "mdadm.conf saved."
}

# --- Final Cleanup ---
final_cleanup() {
    log_info "Performing final cleanup..."
    safe_umount /mnt/boot/efi || true
    safe_umount /mnt/boot || true
    safe_umount /mnt || true
    log_info "Cleanup complete."
}
