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
source "$(dirname "${BASH_SOURCE[0]}")/chroot_config.sh"


# --- Configuration Loading Logic ---
# Variable to store the path of the config file to load
LOAD_CONFIG_FILE=""

# 1. Check for command-line argument for config file
if [ -n "${1:-}" ] && [ -f "$1" ]; then
    LOAD_CONFIG_FILE="$1"
    log_info "Command-line argument specified config: $LOAD_CONFIG_FILE"
elif [ -n "${1:-}" ]; then
    log_warn "Command-line argument '$1' is not a valid file. Ignoring."
fi

# 2. If no CLI argument, prompt the user to load a saved config
if [ -z "$LOAD_CONFIG_FILE" ]; then
    LOAD_CONFIG_FILE=$(prompt_load_config)
    if [ -n "$LOAD_CONFIG_FILE" ]; then
        log_info "User selected config to load: $LOAD_CONFIG_FILE"
    else
        log_info "No configuration file selected for loading. Will proceed with manual configuration."
    fi
fi

# 3. Load the configuration file if determined
if [ -n "$LOAD_CONFIG_FILE" ]; then
    log_header "Loading Configuration from '$LOAD_CONFIG_FILE'"
    # Source the loaded config file. It will override defaults from config.sh
    # Passwords are NOT loaded, so they'll be prompted later.
    source "$LOAD_CONFIG_FILE" || error_exit "Failed to load configuration from '$LOAD_CONFIG_FILE'."
    log_success "Configuration loaded from '$LOAD_CONFIG_FILE'."
    CONFIG_LOADED="yes"
else
    CONFIG_LOADED="no"
fi


# --- Main Installation Function ---
main() {
    log_header "ARCHL4TM: Tasteful Arch Linux Installation"

    check_prerequisites || error_exit "Prerequisite check failed."

    # Install reflector prerequisites and configure mirrors (always on Live ISO)
    install_reflector_prereqs_live || error_exit "Live ISO prerequisites failed."
    configure_mirrors_live "$REFLECTOR_COUNTRY_CODE" || error_exit "Mirror configuration failed."

    # Stage 1: Gather User Input or Confirm Loaded Choices
    log_header "Stage 1: Gathering Installation Details"
    if [ "$CONFIG_LOADED" == "yes" ]; then
        log_info "Configuration loaded. Displaying summary for review and collecting passwords."
        # If config is loaded, we skip most prompts but still need passwords
        # This will call secure_password_input directly
        if [ "$WANT_ENCRYPTION" == "yes" ]; then
            secure_password_input "Enter LUKS encryption passphrase (for loaded config): " LUKS_PASSPHRASE
        fi
        secure_password_input "Enter root password (for loaded config): " ROOT_PASSWORD
        secure_password_input "Enter password for $MAIN_USERNAME (for loaded config): " MAIN_USER_PASSWORD
        
        # Display the full summary AFTER passwords are collected
        display_summary_and_confirm || error_exit "Installation cancelled by user."

    else
        # No config loaded, run full interactive prompts
        gather_installation_details || error_exit "Installation details gathering failed."
        display_summary_and_confirm || error_exit "Installation cancelled by user."
    fi

    # Stage 2: Disk Partitioning and Formatting
    log_header "Stage 2: Disk Partitioning and Formatting"
    execute_disk_strategy || error_exit "Disk partitioning and formatting failed."

    # Stage 3: Base System Installation
    log_header "Stage 3: Installing Base System"
    install_base_system_target || error_exit "Base system installation failed."

    # Stage 4: Chroot Configuration
    log_header "Stage 4: Post-Installation (Chroot) Configuration"
    perform_chroot_configurations || error_exit "Chroot configuration failed."

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
    
    run_pacstrap "$base_packages_list $kernel_packages"

    # Install LVM/RAID tools if chosen, as they are needed for mkinitcpio hooks later
    if [ "$WANT_LVM" == "yes" ]; then
        run_pacstrap ${BASE_PACKAGES[lvm]} || error_exit "Failed to install LVM tools."
    fi
    if [ "$WANT_RAID" == "yes" ]; then
        run_pacstrap ${BASE_PACKAGES[raid]} || error_exit "Failed to install RAID tools."
    fi
    
    # Filesystem utilities based on user choice
    if [ "$ROOT_FILESYSTEM_TYPE" == "btrfs" ]; then
        run_pacstrap ${BASE_PACKAGES[fs_btrfs]} || error_exit "Failed to install Btrfs tools."
    elif [ "$ROOT_FILESYSTEM_TYPE" == "xfs" ]; then
        run_pacstrap ${BASE_PACKAGES[fs_xfs]} || error_exit "Failed to install XFS tools."
    fi
    if [ "$HOME_FILESYSTEM_TYPE" == "btrfs" ]; then
        run_pacstrap ${BASE_PACKAGES[fs_btrfs]} || error_exit "Failed to install Btrfs tools for home."
    elif [ "$HOME_FILESYSTEM_TYPE" == "xfs" ]; then
        run_pacstrap ${BASE_PACKAGES[fs_xfs]} || error_exit "Failed to install XFS tools for home."
    fi
    
    # Common network and system utilities
    run_pacstrap ${BASE_PACKAGES[network]} ${BASE_PACKAGES[system_utils]}
    
    generate_fstab # Call the fstab generation after base install, before chroot.

    log_info "Base system installation complete on target."
}

# --- Call the main function ---
main "$@"
