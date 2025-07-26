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
# chroot_config.sh will be copied and executed within chroot, not sourced here directly


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
    local chroot_target_dir="/opt/archl4tm" # Standard place for installer files within chroot
    
    # Create target directory and copy scripts
    arch-chroot /mnt mkdir -p "$chroot_target_dir" || error_exit "Failed to create chroot target directory '$chroot_target_dir'."
    cp "$script_root_dir/chroot_config.sh" "/mnt/$chroot_target_dir/" || error_exit "Failed to copy chroot_config.sh."
    cp "$script_root_dir/config.sh" "/mnt/$chroot_target_dir/" || error_exit "Failed to copy config.sh to chroot."
    cp "$script_root_dir/utils.sh" "/mnt/$chroot_target_dir/" || error_exit "Failed to copy utils.sh to chroot."
    
    # Make chroot script executable within the chroot
    arch-chroot /mnt chmod +x "$chroot_target_dir/chroot_config.sh" || error_exit "Failed to make chroot script executable."
    
    # Execute the chroot configuration script directly inside the chroot
    log_info "Executing chroot configuration script inside chroot..."
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
    
    local base_packages_list="${BASE_PACKAGES[essential]}" # "base"
    local kernel_packages=""
    if [ "$KERNEL_TYPE" == "linux" ]; then
        kernel_packages="linux linux-firmware linux-headers"
    elif [ "$KERNEL_TYPE" == "linux-lts" ]; then
        kernel_packages="linux-lts linux-lts-headers"
    fi
    
    run_pacstrap_base_install "$base_packages_list $kernel_packages"

    # Install LVM/RAID tools if chosen, as they are needed for mkinitcpio hooks later
    if [ "$WANT_LVM" == "yes" ]; then
        run_pacstrap_base_install ${BASE_PACKAGES[lvm]} || error_exit "Failed to install LVM tools."
    fi
    if [ "$WANT_RAID" == "yes" ]; then
        run_pacstrap_base_install ${BASE_PACKAGES[raid]} || error_exit "Failed to install RAID tools."
    fi
    
    # Filesystem utilities based on user choice
    if [ "$ROOT_FILESYSTEM_TYPE" == "btrfs" ]; then
        run_pacstrap_base_install ${BASE_PACKAGES[fs_btrfs]} || error_exit "Failed to install Btrfs tools."
    elif [ "$ROOT_FILESYSTEM_TYPE" == "xfs" ]; then
        run_pacstrap_base_install ${BASE_PACKAGES[fs_xfs]} || error_exit "Failed to install XFS tools."
    fi
    if [ "$HOME_FILESYSTEM_TYPE" == "btrfs" ]; then
        run_pacstrap_base_install ${BASE_PACKAGES[fs_btrfs]} || error_exit "Failed to install Btrfs tools for home."
    elif [ "$HOME_FILESYSTEM_TYPE" == "xfs" ]; then
        run_pacstrap_base_install ${BASE_PACKAGES[fs_xfs]} || error_exit "Failed to install XFS tools for home."
    fi
    
    # Common network and system utilities
    run_pacstrap_base_install ${BASE_PACKAGES[network]} ${BASE_PACKAGES[system_utils]}
    
    generate_fstab # Call the fstab generation after base install, before chroot.

    log_info "Base system installation complete on target."
}

# --- Call the main function ---
main "$@"
