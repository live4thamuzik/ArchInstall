#!/bin/bash
# chroot_config.sh - Functions for post-base-install (chroot) configurations

perform_chroot_configurations() {
    log_info "Entering chroot environment for post-installation configuration..."
    arch-chroot /mnt /bin/bash <<EOF
        set -euo pipefail

        log_info "Setting system clock and timezone..."
        ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
        hwclock --systochc

        log_info "Setting localization (locale, keymap)..."
        echo "$LOCALE" > /etc/locale.conf
        echo "LANG=$LOCALE" > /etc/locale.conf
        sed -i "s/^#${LOCALE/.UTF-8/ UTF-8}/s/^#//" /etc/locale.gen
        locale-gen
        echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

        log_info "Setting hostname..."
        echo "$SYSTEM_HOSTNAME" > /etc/hostname
        echo "127.0.0.1 localhost" >> /etc/hosts
        echo "::1       localhost" >> /etc/hosts
        echo "127.0.1.1 $SYSTEM_HOSTNAME.localdomain $SYSTEM_HOSTNAME" >> /etc/hosts

        log_info "Setting root password..."
        echo "root:$ROOT_PASSWORD" | chpasswd

        log_info "Creating main user: $MAIN_USERNAME..."
        useradd -m -G wheel -s /bin/bash "$MAIN_USERNAME"
        echo "$MAIN_USERNAME:$MAIN_USER_PASSWORD" | chpasswd
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

        log_info "Installing and configuring bootloader ($BOOTLOADER_TYPE)..."
        configure_bootloader_chroot || return 1

        log_info "Configuring GRUB default settings..."
        configure_grub_defaults_chroot || return 1

        log_info "Configuring GRUB theme..."
        configure_grub_theme_chroot || return 1

        log_info "Installing Desktop Environment: $DESKTOP_ENVIRONMENT..."
        if [[ -n "${DESKTOP_ENVIRONMENTS[$DESKTOP_ENVIRONMENT]}" ]]; then
            install_packages_chroot ${DESKTOP_ENVIRONMENTS[$DESKTOP_ENVIRONMENT]} || return 1
        fi

        log_info "Installing Display Manager: $DISPLAY_MANAGER..."
        if [[ -n "${DISPLAY_MANAGERS[$DISPLAY_MANAGER]}" ]]; then
            install_packages_chroot ${DISPLAY_MANAGERS[$DISPLAY_MANAGER]} || return 1
            enable_systemd_service_chroot "$DISPLAY_MANAGER" || return 1
        fi
        
        log_info "Installing GPU Drivers..."
        install_gpu_drivers_chroot || return 1

        log_info "Installing CPU Microcode..."
        install_microcode_chroot || return 1

        log_info "Configuring mkinitcpio hooks and rebuilding initramfs..."
        configure_mkinitpio_hooks_chroot || return 1

        log_info "Enabling Multilib repository..."
        enable_multilib_chroot || return 1

        log_info "Installing AUR Helper..."
        install_aur_helper_chroot || return 1

        log_info "Installing Flatpak..."
        install_flatpak_chroot || return 1

        log_info "Installing Custom Packages..."
        install_custom_packages_chroot || return 1

        log_info "Deploying Dotfiles..."
        deploy_dotfiles_chroot || return 1

        log_info "Configuring Numlock on boot..."
        configure_numlock_chroot || return 1

        log_info "Saving mdadm.conf for RAID arrays..."
        save_mdadm_conf_chroot || return 1

        log_info "Enabling essential services..."
        enable_systemd_service_chroot "NetworkManager"

        log_info "Chroot configuration complete."
EOF
    local chroot_status=$?
    if [ "$chroot_status" -ne 0 ]; then
        error_exit "Chroot environment exited with status $chroot_status."
    fi
}

configure_bootloader_chroot() {
    case "$BOOTLOADER_TYPE" in
        grub)
            log_info "Installing GRUB for $BOOT_MODE..."
            if [ "$BOOT_MODE" == "uefi" ]; then
                grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || return 1
            else
                grub-install "$INSTALL_DISK" || return 1
            fi
            grub-mkconfig -o /boot/grub/grub.cfg || return 1
            ;;
        systemd-boot)
            log_info "Installing systemd-boot..."
            bootctl install || return 1
            log_warn "systemd-boot configuration requires manual setup of loader entries for now."
            ;;
        *)
            log_warn "No bootloader selected or invalid. Skipping bootloader installation."
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
    log_info "Cloning $repo_url into $target_dir inside chroot..."
    arch-chroot /mnt git clone --depth 1 $branch_arg "$repo_url" "$target_dir" || return 1
}

# Configures GRUB default settings.
configure_grub_defaults_chroot() {
    local grub_default_file="/etc/default/grub"

    log_info "Setting GRUB default configurations in $grub_default_file..."

    edit_file_in_chroot "$grub_default_file" "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=saved|"
    edit_file_in_chroot "$grub_default_file" "s|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=3|"
    edit_file_in_chroot "$grub_default_file" "s|^#GRUB_SAVEDEFAULT=true|GRUB_SAVEDEFAULT=true|" || true

    if [ "$WANT_ENCRYPTION" == "yes" ]; then
        log_info "Enabling GRUB_ENABLE_CRYPTODISK for encrypted setup."
        edit_file_in_chroot "$grub_default_file" "s|^#GRUB_ENABLE_CRYPTODISK=y|GRUB_ENABLE_CRYPTODISK=y|" || true
    fi

    edit_file_in_chroot "$grub_default_file" "s|^GRUB_GFXMODE=auto|GRUB_GFXMODE=1920x1440x32|"

    log_info "GRUB default configurations applied."
}

# Configures and installs the chosen GRUB theme within the chroot.
configure_grub_theme_chroot() {
    if [ "$WANT_GRUB_THEME" == "no" ] || [ "$GRUB_THEME_CHOICE" == "Default" ]; then
        log_info "GRUB theming not requested or default theme chosen. Skipping."
        return 0
    fi

    local theme_name="$GRUB_THEME_CHOICE"
    local theme_info_string="${GRUB_THEME_SOURCES[$theme_name]}"

    if [ -z "$theme_info_string" ]; then
        log_warn "No source info defined for GRUB theme '$theme_name'. Skipping theming."
        return 0
    fi

    IFS='|' read -r theme_repo_url theme_file_in_repo_relative <<< "$theme_info_string"
    local theme_clone_dir="/tmp/grub_theme_clone"
    
    log_info "Installing GRUB theme: $theme_name from $theme_repo_url..."

    git_clone_chroot "$theme_repo_url" "$theme_clone_dir" || return 1

    local actual_theme_source_dir_in_clone=""
    if [ "$(dirname "$theme_file_in_repo_relative")" == "." ]; then
        actual_theme_source_dir_in_clone="$theme_clone_dir"
    else
        actual_theme_source_dir_in_clone="${theme_clone_dir}/$(dirname "$theme_file_in_repo_relative")"
    fi

    if ! arch-chroot /mnt test -d "$actual_theme_source_dir_in_clone"; then
        log_error "Calculated theme source directory '$actual_theme_source_dir_in_clone' not found in cloned repo."
        return 1
    fi

    local final_grub_theme_install_dir="/boot/grub/themes/$theme_name"
    local final_theme_txt_path="${final_grub_theme_install_dir}/$(basename "$theme_file_in_repo_relative")"

    log_info "Copying theme files from '$actual_theme_source_dir_in_clone' to '$final_grub_theme_install_dir'..."
    arch-chroot /mnt mkdir -p "$final_grub_theme_install_dir" || return 1
    arch-chroot /mnt rsync -av "${actual_theme_source_dir_in_clone}/" "$final_grub_theme_install_dir/" || return 1

    local grub_default_file="/etc/default/grub"
    local theme_config_line="GRUB_THEME=\"$final_theme_txt_path\""

    log_info "Updating $grub_default_file with GRUB_THEME: $theme_config_line"
    edit_file_in_chroot "$grub_default_file" "s|^GRUB_THEME=.*|$theme_config_line|" || \
    edit_file_in_chroot "$grub_default_file" "/^GRUB_CMDLINE_LINUX_DEFAULT=/a $theme_config_line" || \
    edit_file_in_chroot "$grub_default_file" "$ a $theme_config_line"

    arch-chroot /mnt rm -rf "$theme_clone_dir" || log_warn "Failed to remove temporary GRUB theme clone directory."

    log_info "GRUB theme $theme_name installed and configured."
    
    arch-chroot /mnt chown -R root:root "$final_grub_theme_install_dir" || log_warn "Failed to set ownership for GRUB theme directory."
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
            error_exit "LUKS UUID not found for GRUB command line."
        fi
        kernel_cmdline+=" ${GRUB_CMDLINE_LUKS_BASE/<LUKS_CONTAINER_UUID>/$luks_container_uuid}"
    fi

    if [ "$WANT_LVM" == "yes" ]; then
        kernel_cmdline+=" ${GRUB_CMDLINE_LVM_ON_LUKS}"
    fi

    local root_fs_uuid="${PARTITION_UUIDS[lv_root_uuid]:-}" # Corrected: now lv_root_uuid
    if [ -z "$root_fs_uuid" ]; then
        root_fs_uuid="${PARTITION_UUIDS[root_uuid]:-}"
    fi

    if [ -z "$root_fs_uuid" ]; then
        error_exit "Could not determine root filesystem UUID for GRUB_CMDLINE_LINUX_DEFAULT."
    fi
    kernel_cmdline+=" root=UUID=$root_fs_uuid"

    kernel_cmdline+=" loglevel=3 quiet"

    if [ "$ENABLE_OS_PROBER" == "yes" ]; then
        log_info "Enabling OS Prober in GRUB."
        edit_file_in_chroot "/etc/default/grub" "s|^#GRUB_DISABLE_OS_PROBER=true|GRUB_DISABLE_OS_PROBER=false|" || true
    fi

    kernel_cmdline=$(echo "$kernel_cmdline" | xargs)

    if [ -n "$kernel_cmdline" ]; then
        log_info "Setting GRUB_CMDLINE_LINUX_DEFAULT=\"$kernel_cmdline\""
        edit_file_in_chroot "/etc/default/grub" "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$kernel_cmdline\"|"
    fi

    log_info "GRUB command line configured."
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

    hooks_string=$(echo "$hooks_string" | xargs | sed 's/ /\ /g')

    log_info "Setting mkinitcpio HOOKS=($hooks_string)..."
    edit_file_in_chroot "/etc/mkinitcpio.conf" "s/^HOOKS=.*/HOOKS=($hooks_string)/"

    log_info "Running mkinitcpio -P to rebuild initramfs..."
    arch-chroot /mnt mkinitcpio -P || return 1
    log_info "Initramfs rebuilt."
}

# Installs GPU drivers based on detected type.
install_gpu_drivers_chroot() {
    if [ "$GPU_DRIVER_TYPE" == "none" ]; then
        log_info "No specific GPU driver type detected or needed. Skipping GPU driver installation."
        return 0
    fi

    local gpu_packages="${GPU_DRIVERS[$GPU_DRIVER_TYPE]}"
    if [ -z "$gpu_packages" ]; then
        log_warn "No packages defined for GPU driver type '$GPU_DRIVER_TYPE'. Skipping installation."
        return 0
    fi

    log_info "Installing $GPU_DRIVER_TYPE GPU drivers: '$gpu_packages'..."
    install_packages_chroot "$gpu_packages" || return 1
    log_info "GPU driver installation complete."
}

# Enables the Multilib repository in pacman.conf.
enable_multilib_chroot() {
    if [ "$WANT_MULTILIB" == "no" ]; then
        log_info "Multilib repository not requested. Skipping."
        return 0
    fi

    log_info "Enabling Multilib repository in /etc/pacman.conf..."
    edit_file_in_chroot "/etc/pacman.conf" "s|^#\[multilib\]|\\[multilib\]|"
    edit_file_in_chroot "/etc/pacman.conf" "s|^#Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/mirrorlist|"

    log_info "Syncing pacman databases for Multilib."
    arch-chroot /mnt pacman -Sy --noconfirm || return 1
    log_info "Multilib repository enabled."
}

# Installs the chosen AUR helper.
install_aur_helper_chroot() {
    if [ "$WANT_AUR_HELPER" == "no" ] || [ -z "$AUR_HELPER_CHOICE" ]; then
        log_info "AUR helper not requested. Skipping."
        return 0
    fi

    local helper_package_name="${AUR_HELPERS[$AUR_HELPER_CHOICE]}"
    if [ -z "$helper_package_name" ]; then
        error_exit "AUR helper package name not defined for '$AUR_HELPER_CHOICE'."
    fi

    log_info "Installing AUR helper: $AUR_HELPER_CHOICE ($helper_package_name)..."
    
    local user_home="/home/$MAIN_USERNAME"
    local temp_aur_dir="$user_home/aur_build_temp"

    arch-chroot /mnt su - "$MAIN_USERNAME" -c "
        log_info \"Building and installing $AUR_HELPER_CHOICE as user $MAIN_USERNAME...\"
        mkdir -p \"$temp_aur_dir\" || exit 1
        cd \"$temp_aur_dir\" || exit 1
        git clone https://aur.archlinux.org/${helper_package_name}.git || exit 1
        cd \"$helper_package_name\" || exit 1
        makepkg -si --noconfirm || exit 1
        log_info \"Cleaning up temporary AUR directory.\"
        rm -rf \"$temp_aur_dir\" || log_warn \"Failed to remove temporary AUR build directory.\"
    " || return 1

    log_info "AUR helper $AUR_HELPER_CHOICE installed."
}

# Installs Flatpak and adds Flathub remote.
install_flatpak_chroot() {
    if [ "$WANT_FLATPAK" == "no" ]; then
        log_info "Flatpak support not requested. Skipping."
        return 0
    fi

    log_info "Installing Flatpak..."
    install_packages_chroot "$FLATPAK_PACKAGE" || return 1

    log_info "Adding Flathub remote..."
    arch-chroot /mnt flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || return 1
    log_info "Flatpak installed and Flathub remote added."
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
        
        arch-chroot /mnt su - "$MAIN_USERNAME" -c "
            log_info \"Running $AUR_HELPER_CHOICE to install custom AUR packages as user $MAIN_USERNAME...\"
            $aur_install_cmd $CUSTOM_AUR_PACKAGES || exit 1
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
    arch-chroot /mnt su - "$MAIN_USERNAME" -c "
        log_info \"Cloning dotfiles repository...\"
        git clone --depth 1 --branch \"$DOTFILES_BRANCH\" \"$DOTFILES_REPO_URL\" \"$dotfiles_clone_dir\" || exit 1
        
        if [ ! -d \"$dotfiles_clone_dir\" ]; then
            log_error \"Dotfiles repository did not clone correctly to $dotfiles_clone_dir.\"
            exit 1
        fi

        log_info \"Running dotfiles deployment script...\"
        if [ -f \"$dotfiles_clone_dir/install.sh\" ]; then
            bash \"$dotfiles_clone_dir/install.sh\" || exit 1
        elif [ -f \"$dotfiles_clone_dir/setup.sh\" ]; then
            bash \"$dotfiles_clone_dir/setup.sh\" || exit 1
        elif [ -f \"$dotfiles_clone_dir/bootstrap.sh\" ]; then
            bash \"$dotfiles_clone_dir/bootstrap.sh\" || exit 1
        else
            log_warn \"No common dotfile deployment script (install.sh, setup.sh, bootstrap.sh) found in repo. User might need to manually deploy dotfiles.\"
        fi

        log_info \"Cleaning up temporary dotfiles clone directory.\"
        rm -rf \"$dotfiles_clone_dir\" || log_warn \"Failed to remove temporary dotfiles clone directory.\"
        
        log_info \"Dotfile deployment for '$MAIN_USERNAME' complete.\"
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
    arch-chroot /mnt mdadm --detail --scan > /etc/mdadm.conf || return 1
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
