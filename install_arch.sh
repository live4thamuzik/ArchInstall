#!/bin/bash
# install_arch.sh - A Tasteful Arch Linux Automated Installer
# Inspired by archl4tm project and "tasteful code" principles.

# Strict mode: Exit on error, unset variables, pipefail
set -euo pipefail

# --- Source all necessary script files ---
# Source config.sh first to get default variables and arrays/maps
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/dialogs.sh"
source "$(dirname "${BASH_SOURCE[0]}")/disk_strategies.sh"

# --- Main Installation Function ---
main() {
    log_header "ARCHL4TM: Tasteful Arch Linux Installation"

    check_prerequisites || error_exit "Prerequisite check failed."

    # Install reflector prerequisites and configure mirrors (always on Live ISO)
    install_reflector_prereqs_live || error_exit "Live ISO prerequisites failed."
    configure_mirrors_live "$REFLECTOR_COUNTRY_CODE" || error_exit "Mirror configuration failed."

    # Stage 1: Gather User Input (Always interactive now, no config loading)
    log_header "Stage 1: Gathering Installation Details"
    gather_installation_details || error_exit "Installation details gathering failed."
    display_summary_and_confirm || error_exit "Installation cancelled by user."

    # Stage 2: Disk Partitioning and Formatting
    log_header "Stage 2: Disk Partitioning and Formatting"
    execute_disk_strategy || error_exit "Disk partitioning and formatting failed."

    # Stage 3: Base System Installation
    log_header "Stage 3: Installing Base System"
    install_base_system_target || error_exit "Base system installation failed."

    # Stage 4: Chroot Configuration
    log_header "Stage 4: Post-Installation (Chroot) Configuration"
    # Copy essential script files into /mnt for chroot execution
    log_info "Copying chroot configuration files to /mnt..."
    local script_root_dir="$(dirname "${BASH_SOURCE[0]}")"
    local chroot_target_dir="/archl4tm"
    local install_script_path_in_chroot="/mnt/$chroot_target_dir"

    mkdir -p "$install_script_path_in_chroot" || error_exit "Failed to create target directory '$install_script_path_in_chroot'."
    
    # Copy chroot_config.sh
    if [ ! -f "$script_root_dir/chroot_config.sh" ]; then
        error_exit "Source file not found: $script_root_dir/chroot_config.sh. Cannot proceed."
    fi
    log_info "Attempting to copy $script_root_dir/chroot_config.sh..."
    cp "$script_root_dir/chroot_config.sh" "$install_script_path_in_chroot/" || error_exit "Failed to copy chroot_config.sh."
    if [ ! -f "$install_script_path_in_chroot/chroot_config.sh" ]; then
        error_exit "Destination file NOT FOUND after copying: $install_script_path_in_chroot/chroot_config.sh."
    fi

    # Copy config.sh
    if [ ! -f "$script_root_dir/config.sh" ]; then
        error_exit "Source file not found: $script_root_dir/config.sh. Cannot proceed."
    fi
    log_info "Attempting to copy $script_root_dir/config.sh..."
    cp "$script_root_dir/config.sh" "$install_script_path_in_chroot/" || error_exit "Failed to copy config.sh to chroot."
    if [ ! -f "$install_script_path_in_chroot/config.sh" ]; then
        error_exit "Destination file NOT FOUND after copying: $install_script_path_in_chroot/config.sh."
    fi

    # Copy utils.sh
    if [ ! -f "$script_root_dir/utils.sh" ]; then
        error_exit "Source file not found: $script_root_dir/utils.sh. Cannot proceed."
    fi
    log_info "Attempting to copy $script_root_dir/utils.sh..."
    cp "$script_root_dir/utils.sh" "$install_script_path_in_chroot/" || error_exit "Failed to copy utils.sh to chroot."
    if [ ! -f "$install_script_path_in_chroot/utils.sh" ]; then
        error_exit "Destination file NOT FOUND after copying: $install_script_path_in_chroot/utils.sh."
    fi
    
    log_info "Setting permissions for chroot scripts..."
    arch-chroot /mnt chmod +x "$chroot_target_dir/chroot_config.sh" || error_exit "Failed to make chroot script executable."
    arch-chroot /mnt chmod +x "$chroot_target_dir/config.sh" || error_exit "Failed to make chroot config executable."
    arch-chroot /mnt chmod +x "$chroot_target_dir/utils.sh" || error_exit "Failed to make chroot utils executable."

    log_info "Executing chroot configuration script inside chroot..."
    
    export INSTALL_DISK BOOT_MODE WANT_ENCRYPTION LUKS_PASSPHRASE VG_NAME WANT_LVM WANT_RAID RAID_LEVEL
    export KERNEL_TYPE CPU_MICROCODE_TYPE TIMEZONE LOCALE KEYMAP REFLECTOR_COUNTRY_CODE SYSTEM_HOSTNAME
    export ROOT_PASSWORD MAIN_USERNAME MAIN_USER_PASSWORD DESKTOP_ENVIRONMENT DISPLAY_MANAGER GPU_DRIVER_TYPE
    export BOOTLOADER_TYPE ENABLE_OS_PROBER WANT_MULTILIB WANT_AUR_HELPER AUR_HELPER_CHOICE WANT_FLATPAK
    export INSTALL_CUSTOM_PACKAGES CUSTOM_PACKAGES INSTALL_CUSTOM_AUR_PACKAGES CUSTOM_AUR_PACKAGES
    export WANT_GRUB_THEME GRUB_THEME_CHOICE WANT_NUMLOCK_ON_BOOT WANT_DOTFILES_DEPLOYMENT
    export DOTFILES_REPO_URL DOTFILES_BRANCH EFI_PART_SIZE_MIB BOOT_PART_SIZE_MIB ROOT_FILESYSTEM_TYPE HOME_FILESYSTEM_TYPE
    export WANT_SWAP WANT_HOME_PARTITION

    # Export associative arrays (Bash 4.x+ feature)
    export -A PARTITION_UUIDS LUKS_DEVICES_MAP LVM_DEVICES_MAP

    arch-chroot /mnt /bin/bash "$chroot_target_dir/chroot_config.sh" || error_exit "Chroot configuration failed."

    log_info "Chroot setup complete."

    # Stage 5: Finalization
    log_header "Stage 5: Finalizing Installation"
    final_cleanup || error_exit "Final cleanup failed."

    log_success "Arch Linux installation complete! You can now reboot."
    prompt_reboot_system
}

# Helper function for base system installation
install_base_system_target() {
    log_info "Installing base system packages into /mnt..."
    
    local packages_to_install=() # Initialize an array to hold all packages

    # Add essential base packages - ensure it's not empty
    if [[ -n "${BASE_PACKAGES[essential]}" ]]; then
        packages_to_install+=(${BASE_PACKAGES[essential]})
    fi

    local kernel_packages=""
    if [ "$KERNEL_TYPE" == "linux" ]; then
        kernel_packages="linux linux-firmware linux-headers"
    elif [ "$KERNEL_TYPE" == "linux-lts" ]; then
        kernel_packages="linux-lts linux-lts-headers"
    else
        # This error_exit should prevent empty kernel_packages.
        error_exit "Unsupported KERNEL_TYPE: $KERNEL_TYPE."
    fi
    # Add kernel packages - ensure it's not empty after determination
    if [[ -n "$kernel_packages" ]]; then
        packages_to_install+=($kernel_packages)
    fi
    
    # Add bootloader, network, and general system utilities - ensure they are not empty
    if [[ -n "${BASE_PACKAGES[bootloader_grub]}" ]]; then
        packages_to_install+=(${BASE_PACKAGES[bootloader_grub]})
    fi
    if [ "$BOOTLOADER_TYPE" == "systemd-boot" ] && [[ -n "${BASE_PACKAGES[bootloader_systemdboot]}" ]]; then
        packages_to_install+=(${BASE_PACKAGES[bootloader_systemdboot]})
    fi
    if [[ -n "${BASE_PACKAGES[network]}" ]]; then
        packages_to_install+=(${BASE_PACKAGES[network]})
    fi
    if [[ -n "${BASE_PACKAGES[system_utils]}" ]]; then
        packages_to_install+=(${BASE_PACKAGES[system_utils]})
    fi

    # Install LVM/RAID tools if chosen (ensure they are not empty)
    if [ "$WANT_LVM" == "yes" ] && [[ -n "${BASE_PACKAGES[lvm]}" ]]; then
        packages_to_install+=(${BASE_PACKAGES[lvm]})
    fi
    if [ "$WANT_RAID" == "yes" ] && [[ -n "${BASE_PACKAGES[raid]}" ]]; then
        packages_to_install+=(${BASE_PACKAGES[raid]})
    fi
    
    # Add Filesystem utilities based on user choice (ensure they are not empty)
    if [ "$ROOT_FILESYSTEM_TYPE" == "btrfs" ] && [[ -n "${BASE_PACKAGES[fs_btrfs]}" ]]; then
        packages_to_install+=(${BASE_PACKAGES[fs_btrfs]})
    elif [ "$ROOT_FILESYSTEM_TYPE" == "xfs" ] && [[ -n "${BASE_PACKAGES[fs_xfs]}" ]]; then
        packages_to_install+=(${BASE_PACKAGES[fs_xfs]})
    fi
    # Only add home FS tools if home partition is desired AND FS is not ext4 (ext4 tools are typically in base)
    if [ "$WANT_HOME_PARTITION" == "yes" ]; then
        if [ "$HOME_FILESYSTEM_TYPE" == "btrfs" ] && [[ -n "${BASE_PACKAGES[fs_btrfs]}" ]]; then
            packages_to_install+=(${BASE_PACKAGES[fs_btrfs]})
        elif [ "$HOME_FILESYSTEM_TYPE" == "xfs" ] && [[ -n "${BASE_PACKAGES[fs_xfs]}" ]]; then
            packages_to_install+=(${BASE_PACKAGES[fs_xfs]})
        fi
    fi
    
    # Crucial: Ensure the array is not empty before passing to pacstrap
    if [ ${#packages_to_install[@]} -eq 0 ]; then
        error_exit "No packages compiled for base system installation. This should not happen."
    fi

    run_pacstrap_base_install "${packages_to_install[@]}" || error_exit "Base system installation failed."

    generate_fstab # Call the fstab generation after base install, before chroot.

    log_info "Base system installation complete on target."
}

# --- Call the main function ---
main "$@"
