#!/bin/bash
# install_arch.sh - A Tasteful Arch Linux Automated Installer
# Inspired by archl4tm project and "tasteful code" principles.

# Strict mode: Exit on error, unset variables, pipefail
set -euo pipefail

# --- Source all necessary script files ---
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/dialogs.sh"
source "$(dirname "${BASH_SOURCE[0]}")/disk_strategies.sh"
source "$(dirname "${BASH_SOURCE[0]}")/chroot_config.sh"


# --- Main Installation Function ---
main() {
    log_header "ARCHL4TM: Tasteful Arch Linux Installation"

    check_prerequisites || error_exit "Prerequisite check failed."

    install_reflector_prereqs_live || error_exit "Live ISO prerequisites failed."
    configure_mirrors_live "$REFLECTOR_COUNTRY_CODE" || error_exit "Mirror configuration failed."

    log_header "Stage 1: Gathering Installation Details"
    gather_installation_details || error_exit "Installation details gathering failed."
    display_summary_and_confirm || error_exit "Installation cancelled by user."

    log_header "Stage 2: Disk Partitioning and Formatting"
    execute_disk_strategy || error_exit "Disk partitioning and formatting failed."

    log_header "Stage 3: Installing Base System"
    install_base_system_target || error_exit "Base system installation failed."

    log_header "Stage 4: Post-Installation (Chroot) Configuration"
    log_info "Copying chroot configuration files to /mnt..."
    local script_root_dir="$(dirname "${BASH_SOURCE[0]}")"
    local chroot_target_dir="/archl4tm" # Standard place for installer files within chroot
    local install_script_path_in_chroot="/mnt/$chroot_target_dir"

    mkdir -p "$install_script_path_in_chroot" || error_exit "Failed to create target directory '$install_script_path_in_chroot'."
    
    if [ ! -f "$script_root_dir/chroot_config.sh" ]; then
        error_exit "Source file not found: $script_root_dir/chroot_config.sh. Cannot proceed."
    fi
    log_info "Attempting to copy $script_root_dir/chroot_config.sh..."
    cp "$script_root_dir/chroot_config.sh" "$install_script_path_in_chroot/" || error_exit "Failed to copy chroot_config.sh."
    if [ ! -f "$install_script_path_in_chroot/chroot_config.sh" ]; then
        error_exit "Destination file NOT FOUND after copying: $install_script_path_in_chroot/chroot_config.sh."
    fi

    if [ ! -f "$script_root_dir/config.sh" ]; then
        error_exit "Source file not found: $script_root_dir/config.sh. Cannot proceed."
    fi
    log_info "Attempting to copy $script_root_dir/config.sh..."
    cp "$script_root_dir/config.sh" "$install_script_path_in_chroot/" || error_exit "Failed to copy config.sh to chroot."
    if [ ! -f "$install_script_path_in_chroot/config.sh" ]; then
        error_exit "Destination file NOT FOUND after copying: $install_script_path_in_chroot/config.sh."
    fi

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
    arch-chroot /mnt /bin/bash "$chroot_target_dir/chroot_config.sh" || error_exit "Chroot configuration failed."

    log_info "Chroot setup complete."

    log_header "Stage 5: Finalizing Installation"
    final_cleanup || error_exit "Final cleanup failed."

    log_success "Arch Linux installation complete! You can now reboot."
    prompt_reboot_system
}

install_base_system_target() {
    log_info "Installing base system packages into /mnt..."
    
    local packages_to_install=()

    packages_to_install+=(${BASE_PACKAGES[essential]})

    if [ "$KERNEL_TYPE" == "linux" ]; then
        kernel_packages="linux linux-firmware linux-headers"
    elif [ "$KERNEL_TYPE" == "linux-lts" ]; then
        kernel_packages="linux-lts linux-lts-headers"
    fi
    
    packages_to_install+=($kernel_packages)
    packages_to_install+=(${BASE_PACKAGES[bootloader_grub]})
    packages_to_install+=(${BASE_PACKAGES[network]})
    packages_to_install+=(${BASE_PACKAGES[system_utils]})

    if [ "$WANT_LVM" == "yes" ]; then
        packages_to_install+=(${BASE_PACKAGES[lvm]})
    fi
    if [ "$WANT_RAID" == "yes" ]; then
        packages_to_install+=(${BASE_PACKAGES[raid]})
    fi
    
    if [ "$ROOT_FILESYSTEM_TYPE" == "btrfs" ]; then
        packages_to_install+=(${BASE_PACKAGES[fs_btrfs]})
    elif [ "$ROOT_FILESYSTEM_TYPE" == "xfs" ]; then
        packages_to_install+=(${BASE_PACKAGES[fs_xfs]})
    fi
    if [ "$WANT_HOME_PARTITION" == "yes" ]; then
        if [ "$HOME_FILESYSTEM_TYPE" == "btrfs" ]; then
            packages_to_install+=(${BASE_PACKAGES[fs_btrfs]})
        elif [ "$HOME_FILESYSTEM_TYPE" == "xfs" ]; then
            packages_to_install+=(${BASE_PACKAGES[fs_xfs]})
        fi
    fi
    
    run_pacstrap_base_install "${packages_to_install[@]}" || error_exit "Base system installation failed."

    generate_fstab

    log_info "Base system installation complete on target."
}

# --- Call the main function ---
main "$@"
