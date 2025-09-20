#!/bin/bash
# install_arch.sh - Arch Linux Automated Installer
#
# ARCHITECTURE OVERVIEW:
# This script is part of a hybrid Rust/Bash architecture:
# - Rust TUI (archinstall-tui): Handles user interface and configuration
# - Bash Scripts (this file): Execute actual system installation commands
# - Communication: Direct process communication via JSON progress updates
#
# The TUI launches this script with --bash-only flag and monitors its output
# for structured progress updates. This separation allows us to leverage:
# - Rust: Safe, fast, polished user interface with modern TUI libraries
# - Bash: Natural system command execution and shell scripting capabilities

# Strict mode: Exit on error, unset variables, pipefail
set -euo pipefail

# --- Source all necessary script files ---
# Source YAML parser first
source "$(dirname "${BASH_SOURCE[0]}")/yaml_parser.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/disk_strategies.sh"

# Only source dialogs.sh if NOT running in TUI mode
if [ "${TUI_MODE:-}" != "true" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/dialogs.sh"
fi
# TUI integration - progress is handled directly by the TUI process

# --- Phase Functions ---
# Phase 0: Initialize and validate configuration
phase_initialization() {
    # Load YAML configuration first
    load_yaml_config "config.yaml" || error_exit "Failed to load YAML configuration"
    
    # Initialize enhanced logging system
    setup_logging
    
    # TUI integration - progress tracking handled by TUI process
    
    log_header "Arch Linux Automated Installer"
    
    # Show log access information at the start
    show_log_access

    check_prerequisites || error_exit "Prerequisite check failed."

    # Apply boot mode override if specified
    apply_boot_mode_override
}

# Phase 1: Gather user input and validate configuration
phase_user_input() {

    # Stage 1: Gather User Input (Skip if running from TUI)
    if [ "${TUI_MODE:-}" != "true" ]; then
        echo "=== PHASE 0: Gathering Installation Details ==="
        tui_progress_update "UserInput" "10" "Gathering installation details..."
        log_header "Stage 1: Gathering Installation Details"
        gather_installation_details || error_exit "Installation details gathering failed."
        display_summary_and_confirm || error_exit "Installation cancelled by user."
        tui_progress_update "UserInput" "20" "User input completed"
    else
        echo "=== PHASE 0: Using TUI Configuration ==="
        tui_progress_update "UserInput" "10" "Using configuration from TUI..."
        log_header "Stage 1: Using TUI Configuration"
        log_info "Running in TUI mode - using pre-configured values"
        
        # Validate that required TUI configuration is present
        if [ -z "${MAIN_USERNAME:-}" ] || [ -z "${INSTALL_DISK:-}" ] || [ -z "${SYSTEM_HOSTNAME:-}" ]; then
            error_exit "Required configuration missing from TUI. Please check username, disk, and hostname."
        fi
        
        # Validate input parameters to prevent command injection
        if ! validate_username "$MAIN_USERNAME" "TUI configuration"; then
            error_exit "Invalid username provided in TUI configuration"
        fi
        
        if ! validate_hostname "$SYSTEM_HOSTNAME" "TUI configuration"; then
            error_exit "Invalid hostname provided in TUI configuration"
        fi
        
        if ! validate_disk_device "$INSTALL_DISK" "TUI configuration"; then
            error_exit "Invalid disk device provided in TUI configuration"
        fi
        
        log_info "Configuration validated successfully"
        tui_progress_update "UserInput" "20" "TUI configuration loaded and validated"
    fi
    
    # Verify the boot mode (UEFI bitness check) - after user input but before disk partitioning
    log_info "Verifying boot mode and UEFI bitness..."
    verify_boot_mode || error_exit "Boot mode verification failed."
    
    # Configure mirrors using reflector AFTER user input (so user choices matter!)
    log_info "Configuring mirrors based on user preferences..."
    configure_mirrors_live "$REFLECTOR_COUNTRY_CODE" || error_exit "Mirror configuration failed."
    
    # Set console keymap for live environment
    set_console_keymap_live
}

# Phase 2: Disk partitioning and formatting
phase_disk_partitioning() {

    # Stage 2: Disk Partitioning and Formatting
    echo "=== PHASE 1: Disk Partitioning ==="
    tui_progress_update "DiskPartitioning" "30" "Starting disk partitioning..."
    log_header "Stage 2: Disk Partitioning and Formatting"
    execute_disk_strategy || error_exit "Disk partitioning and formatting failed."
    tui_progress_update "DiskPartitioning" "40" "Disk partitioning completed"
    echo "Disk partitioning complete"
}

# Phase 3: Base system installation
phase_base_installation() {
    # Stage 3: Base System Installation
    echo "=== PHASE 2: Base Installation ==="
    tui_progress_update "PackageInstallation" "50" "Installing base system packages..."
    log_header "Stage 3: Installing Base System"
    install_base_system_target || error_exit "Base system installation failed."
    tui_progress_update "PackageInstallation" "60" "Base system installation completed"
    
    # Generate fstab
    echo "Generating fstab..."
    log_info "Generating fstab file..."
    generate_fstab || error_exit "Fstab generation failed."
    echo "Packages installed"
}

# Phase 4: Prepare chroot environment and copy files
phase_prepare_chroot() {

    # Stage 4: Chroot Configuration
    echo "=== PHASE 4: System Configuration ==="
    tui_progress_update "SystemConfiguration" "70" "Starting system configuration..."
    log_header "Stage 4: Post-Installation (Chroot) Configuration"

    log_info "Copying chroot configuration files to /mnt..."
    if [ "${TUI_MODE:-}" != "true" ]; then
        cp -v ./chroot_config.sh ./config.yaml ./yaml_parser.sh ./utils.sh ./disk_strategies.sh ./dialogs.sh /mnt || error_exit "Failed to copy all necessary scripts to chroot."
    else
        cp -v ./chroot_config.sh ./config.yaml ./yaml_parser.sh ./utils.sh ./disk_strategies.sh /mnt || error_exit "Failed to copy all necessary scripts to chroot."
    fi
    
    log_info "Copying Source directory to /mnt..."
    cp -r ./Source /mnt || error_exit "Failed to copy Source directory to chroot."
    
    # Ensure Plymouth script is executable in the copied location
    if [ -f "/mnt/Source/arch-glow/arch-glow.script" ]; then
        chmod +x /mnt/Source/arch-glow/arch-glow.script || log_warn "Failed to make Plymouth script executable in chroot"
        log_info "Made Plymouth script executable in chroot environment"
    fi

    # Verify the files exist at the destination
    if [ "${TUI_MODE:-}" != "true" ]; then
        if [ ! -f "/mnt/chroot_config.sh" ] || \
           [ ! -f "/mnt/config.yaml" ] || \
           [ ! -f "/mnt/yaml_parser.sh" ] || \
           [ ! -f "/mnt/utils.sh" ] || \
           [ ! -f "/mnt/disk_strategies.sh" ] || \
           [ ! -f "/mnt/dialogs.sh" ]; then
            error_exit "One or more required script files not found in destination directory after copying."
        fi
    else
        if [ ! -f "/mnt/chroot_config.sh" ] || \
           [ ! -f "/mnt/config.yaml" ] || \
           [ ! -f "/mnt/yaml_parser.sh" ] || \
           [ ! -f "/mnt/utils.sh" ] || \
           [ ! -f "/mnt/disk_strategies.sh" ]; then
            error_exit "One or more required script files not found in destination directory after copying."
        fi
    fi

    log_info "Setting permissions for chroot scripts..."
    chmod +x /mnt/*.sh || error_exit "Failed to make chroot scripts executable."
}

# Export all variables for chroot environment
export_chroot_variables() {
    log_info "Exporting variables for chroot environment..."
    export MAIN_USERNAME
    export ROOT_PASSWORD
    export MAIN_USER_PASSWORD
    export SYSTEM_HOSTNAME
    export TIMEZONE
    export LOCALE
    export KEYMAP
    export DESKTOP_ENVIRONMENT
    export DISPLAY_MANAGER
    export BOOTLOADER_TYPE
    export BOOT_MODE
    export OVERRIDE_BOOT_MODE
    export WANT_SECURE_BOOT
    export WANT_AUR_HELPER
    export AUR_HELPER_CHOICE
    export WANT_GRUB_THEME
    export GRUB_THEME_CHOICE
    export WANT_PLYMOUTH
    export WANT_PLYMOUTH_THEME
    export PLYMOUTH_THEME_CHOICE
    export WANT_BTRFS
    export WANT_BTRFS_SNAPSHOTS
    export BTRFS_SNAPSHOT_FREQUENCY
    export BTRFS_KEEP_SNAPSHOTS
    export WANT_ENCRYPTION
    export WANT_LVM
    export WANT_RAID
    export RAID_LEVEL
    export ROOT_FILESYSTEM_TYPE
    export HOME_FILESYSTEM_TYPE
    export KERNEL_TYPE
    export CPU_MICROCODE_TYPE
    export TIME_SYNC_CHOICE
    export GPU_DRIVER_TYPE
    export WANT_MULTILIB
    export WANT_FLATPAK
    export INSTALL_CUSTOM_PACKAGES
    export CUSTOM_PACKAGES
    export INSTALL_CUSTOM_AUR_PACKAGES
    export CUSTOM_AUR_PACKAGES
    export WANT_NUMLOCK_ON_BOOT
    export WANT_DOTFILES_DEPLOYMENT
    export DOTFILES_REPO_URL
    export DOTFILES_BRANCH
    export REFLECTOR_COUNTRY_CODE
    export ENABLE_OS_PROBER
    export WANT_BTRFS_ASSISTANT
    export WANT_SWAP
    export WANT_HOME_PARTITION
    export LUKS_PASSPHRASE
    export INSTALL_DISK
    export PARTITION_UUIDS_EFI_UUID
    export PARTITION_UUIDS_EFI_PARTUUID
    export PARTITION_UUIDS_ROOT_UUID
    export PARTITION_UUIDS_BOOT_UUID
    export PARTITION_UUIDS_SWAP_UUID
    export PARTITION_UUIDS_HOME_UUID
    export PARTITION_UUIDS_LUKS_CONTAINER_UUID
    export PARTITION_UUIDS_LV_ROOT_UUID
    export PARTITION_UUIDS_LV_SWAP_UUID
    export PARTITION_UUIDS_LV_HOME_UUID
    export LUKS_CRYPTROOT_DEV
    export LV_ROOT_PATH
    export LV_SWAP_PATH
    export LV_HOME_PATH
    export VG_NAME
    export -a RAID_DEVICES
    
    # Export constants and arrays used in chroot functions
    export INITCPIO_BASE_HOOKS
    export INITCPIO_LUKS_HOOK
    export INITCPIO_LVM_HOOK
    export INITCPIO_RAID_HOOK
    export INITCPIO_NVME_HOOK
    export GRUB_TIMEOUT_DEFAULT
    export FLATPAK_PACKAGE
    export LV_LAYOUT_LV_ROOT
    export LV_LAYOUT_LV_SWAP
    export LV_LAYOUT_LV_HOME
    export DEFAULT_LV_MOUNTPOINTS_LV_ROOT
    export DEFAULT_LV_MOUNTPOINTS_LV_SWAP
    export DEFAULT_LV_MOUNTPOINTS_LV_HOME
    export DEFAULT_LV_FSTYPES_LV_ROOT
    export DEFAULT_LV_FSTYPES_LV_SWAP
    export DEFAULT_LV_FSTYPES_LV_HOME
    
    # Export arrays for package lists
    export -a DESKTOP_ENVIRONMENTS_GNOME_PACKAGES
    export -a DESKTOP_ENVIRONMENTS_KDE_PACKAGES
    export -a DESKTOP_ENVIRONMENTS_HYPRLAND_PACKAGES
    export -a DISPLAY_MANAGERS_GDM_PACKAGES
    export -a DISPLAY_MANAGERS_SDDM_PACKAGES
    export -a GPU_DRIVERS_AMD_PACKAGES
    export -a GPU_DRIVERS_NVIDIA_PACKAGES
    export -a GPU_DRIVERS_INTEL_PACKAGES
    export -a GRUB_THEME_SOURCES_POLY_DARK
    export -a GRUB_THEME_SOURCES_CYBEREXS
    export -a GRUB_THEME_SOURCES_CYBERPUNK
    export -a GRUB_THEME_SOURCES_HYPERFLUENT

    # Debug: Show variables before passing to chroot
    log_info "Debug - Variables before arch-chroot:"
    log_info "  MAIN_USERNAME: '${MAIN_USERNAME:-NOT_SET}'"
    log_info "  ROOT_PASSWORD: '${ROOT_PASSWORD:+SET}' (length: ${#ROOT_PASSWORD})"
    log_info "  MAIN_USER_PASSWORD: '${MAIN_USER_PASSWORD:+SET}' (length: ${#MAIN_USER_PASSWORD})"
    log_info "  SYSTEM_HOSTNAME: '${SYSTEM_HOSTNAME:-NOT_SET}'"
}

# Phase 5: Execute chroot configuration
phase_chroot_execution() {
    # Ensure EFI partition is properly mounted before chroot
    if [ "$BOOT_MODE" == "uefi" ]; then
        log_info "Verifying EFI partition is properly mounted before chroot..."
        if ! mountpoint -q "/mnt/boot/efi"; then
            log_error "EFI partition not mounted at /mnt/boot/efi. Attempting to remount..."
            if [ -n "${PARTITION_UUIDS_EFI_UUID:-}" ]; then
                local efi_dev="/dev/disk/by-uuid/$PARTITION_UUIDS_EFI_UUID"
                if [ -b "$efi_dev" ]; then
                    log_info "Creating /mnt/boot/efi directory..."
                    mkdir -p "/mnt/boot/efi" || error_exit "Failed to create /mnt/boot/efi directory"
                    log_info "Remounting EFI partition from UUID: $efi_dev"
                    mount -t vfat -o rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro "$efi_dev" "/mnt/boot/efi" || error_exit "Failed to remount EFI partition"
                else
                    error_exit "EFI partition device not found: $efi_dev"
                fi
            else
                error_exit "EFI partition UUID not available for remounting"
            fi
        fi
        log_info "EFI partition verified and mounted at /mnt/boot/efi"
    fi

    echo "Running chroot config..."
    log_info "Executing chroot configuration script inside chroot..."
    
    # Verify critical mount points before chroot operations
    verify_critical_mounts "chroot configuration" || error_exit "Critical mount points verification failed"
    
    # Create environment file to avoid command line length limits
    log_info "Creating environment file for chroot..."
    cat > /mnt/tmp/chroot_env.sh << EOF
#!/bin/bash
# Environment variables for chroot configuration
export LOG_FILE='$LOG_FILE'
export MAIN_USERNAME='$MAIN_USERNAME'
export ROOT_PASSWORD='$ROOT_PASSWORD'
export MAIN_USER_PASSWORD='$MAIN_USER_PASSWORD'
export SYSTEM_HOSTNAME='$SYSTEM_HOSTNAME'
export USERNAME='$MAIN_USERNAME'
export USER_PASSWORD='$MAIN_USER_PASSWORD'
export HOSTNAME='$SYSTEM_HOSTNAME'
export ENCRYPTION_PASSWORD='$LUKS_PASSPHRASE'
export TIMEZONE='$TIMEZONE'
export LOCALE='$LOCALE'
export KEYMAP='$KEYMAP'
export DESKTOP_ENVIRONMENT='$DESKTOP_ENVIRONMENT'
export DISPLAY_MANAGER='$DISPLAY_MANAGER'
export BOOTLOADER_TYPE='$BOOTLOADER_TYPE'
export BOOT_MODE='$BOOT_MODE'
export OVERRIDE_BOOT_MODE='$OVERRIDE_BOOT_MODE'
export WANT_SECURE_BOOT='$WANT_SECURE_BOOT'
export WANT_AUR_HELPER='$WANT_AUR_HELPER'
export AUR_HELPER_CHOICE='$AUR_HELPER_CHOICE'
export WANT_GRUB_THEME='$WANT_GRUB_THEME'
export GRUB_THEME_CHOICE='$GRUB_THEME_CHOICE'
export WANT_PLYMOUTH='$WANT_PLYMOUTH'
export WANT_PLYMOUTH_THEME='$WANT_PLYMOUTH_THEME'
export PLYMOUTH_THEME_CHOICE='$PLYMOUTH_THEME_CHOICE'
export WANT_BTRFS='$WANT_BTRFS'
export WANT_BTRFS_SNAPSHOTS='$WANT_BTRFS_SNAPSHOTS'
export BTRFS_SNAPSHOT_FREQUENCY='$BTRFS_SNAPSHOT_FREQUENCY'
export BTRFS_KEEP_SNAPSHOTS='$BTRFS_KEEP_SNAPSHOTS'
export WANT_ENCRYPTION='$WANT_ENCRYPTION'
export WANT_LVM='$WANT_LVM'
export WANT_RAID='$WANT_RAID'
export RAID_LEVEL='$RAID_LEVEL'
export ROOT_FILESYSTEM_TYPE='$ROOT_FILESYSTEM_TYPE'
export HOME_FILESYSTEM_TYPE='$HOME_FILESYSTEM_TYPE'
export KERNEL_TYPE='$KERNEL_TYPE'
export CPU_MICROCODE_TYPE='$CPU_MICROCODE_TYPE'
export TIME_SYNC_CHOICE='$TIME_SYNC_CHOICE'
export GPU_DRIVER_TYPE='$GPU_DRIVER_TYPE'
export WANT_MULTILIB='$WANT_MULTILIB'
export WANT_FLATPAK='$WANT_FLATPAK'
export INSTALL_CUSTOM_PACKAGES='$INSTALL_CUSTOM_PACKAGES'
export CUSTOM_PACKAGES='$CUSTOM_PACKAGES'
export INSTALL_CUSTOM_AUR_PACKAGES='$INSTALL_CUSTOM_AUR_PACKAGES'
export CUSTOM_AUR_PACKAGES='$CUSTOM_AUR_PACKAGES'
export WANT_NUMLOCK_ON_BOOT='$WANT_NUMLOCK_ON_BOOT'
export WANT_DOTFILES_DEPLOYMENT='$WANT_DOTFILES_DEPLOYMENT'
export DOTFILES_REPO_URL='$DOTFILES_REPO_URL'
export DOTFILES_BRANCH='$DOTFILES_BRANCH'
export REFLECTOR_COUNTRY_CODE='$REFLECTOR_COUNTRY_CODE'
export ENABLE_OS_PROBER='$ENABLE_OS_PROBER'
export WANT_BTRFS_ASSISTANT='$WANT_BTRFS_ASSISTANT'
export WANT_SWAP='$WANT_SWAP'
export WANT_HOME_PARTITION='$WANT_HOME_PARTITION'
export LUKS_PASSPHRASE='$LUKS_PASSPHRASE'
export INSTALL_DISK='$INSTALL_DISK'
export PARTITION_UUIDS_EFI_UUID='$PARTITION_UUIDS_EFI_UUID'
export PARTITION_UUIDS_EFI_PARTUUID='$PARTITION_UUIDS_EFI_PARTUUID'
export PARTITION_UUIDS_ROOT_UUID='$PARTITION_UUIDS_ROOT_UUID'
export PARTITION_UUIDS_BOOT_UUID='$PARTITION_UUIDS_BOOT_UUID'
export PARTITION_UUIDS_SWAP_UUID='$PARTITION_UUIDS_SWAP_UUID'
export PARTITION_UUIDS_HOME_UUID='$PARTITION_UUIDS_HOME_UUID'
export PARTITION_UUIDS_LUKS_CONTAINER_UUID='$PARTITION_UUIDS_LUKS_CONTAINER_UUID'
export PARTITION_UUIDS_LV_ROOT_UUID='$PARTITION_UUIDS_LV_ROOT_UUID'
export PARTITION_UUIDS_LV_SWAP_UUID='$PARTITION_UUIDS_LV_SWAP_UUID'
export PARTITION_UUIDS_LV_HOME_UUID='$PARTITION_UUIDS_LV_HOME_UUID'
export VG_NAME='$VG_NAME'
EOF
    
    # Execute chroot configuration with environment file
    log_info "Starting chroot configuration..."
    if ! arch-chroot /mnt /bin/bash -c "source /tmp/chroot_env.sh && ./chroot_config.sh"; then
        local exit_code=$?
        log_error "Chroot configuration failed with exit code: $exit_code"
        log_error "This could be due to:"
        log_error "  - Missing or corrupted script files in /mnt"
        log_error "  - Invalid environment variables"
        log_error "  - Failed system configuration steps"
        log_error "  - Insufficient permissions in chroot environment"
        log_error "Check the chroot logs at /mnt/var/log/archinstall-chroot.log for details"
        error_exit "Chroot configuration failed."
    fi
    log_info "Chroot setup complete."
    echo "System configuration complete"
}

# Phase 6: Finalization and cleanup
phase_finalization() {
    # Stage 5: Finalization
    echo "=== PHASE 5: Finalization ==="
    tui_progress_update "Finalization" "90" "Finalizing installation..."
    log_header "Stage 5: Finalizing Installation"
    final_cleanup || error_exit "Final cleanup failed."
    tui_progress_update "Complete" "100" "Installation completed successfully!"

    echo "Installation completed successfully!"
    log_success "Arch Linux installation complete! You can now reboot."
    
    # Preserve logs for successful installation
    preserve_logs "success"
    
    # TUI cleanup handled automatically by TUI process
    
    # Only prompt for reboot in non-TUI mode
    if [ "${TUI_MODE:-}" != "true" ]; then
        prompt_reboot_system
    else
        log_info "Installation complete! The TUI will handle the completion notification."
    fi
}

# --- Main Installation Function ---
main() {
    # Execute installation phases in order
    phase_initialization
    phase_user_input
    phase_disk_partitioning
    phase_base_installation
    phase_prepare_chroot
    export_chroot_variables
    phase_chroot_execution
    phase_finalization
}

# Error handling wrapper for the main function
run_installation() {
    # Set up error handling
    set -e
    trap 'handle_installation_error' ERR
    trap 'handle_installation_interrupt' INT TERM
    
    # Run the main installation
    main "$@"
}

# Error handler for installation failures
handle_installation_error() {
    local exit_code=$?
    log_error "Installation failed with exit code: $exit_code"
    
    # Update progress to show failure
    echo "Installation failed!"
    # TUI will handle progress updates automatically
    
    # Preserve logs for failed installation
    preserve_logs "failure"
    
    # Show log access information
    show_log_access
    
    echo ""
    echo "❌ INSTALLATION FAILED"
    echo "Check the logs above for details on what went wrong."
    echo "Log files are preserved for troubleshooting."
    echo ""
    
    exit $exit_code
}

# Interrupt handler for user cancellation
handle_installation_interrupt() {
    log_warn "Installation interrupted by user"
    
    # Update progress to show interruption
    echo "Installation interrupted!"
    # TUI will handle progress updates automatically
    
    # Preserve logs for interrupted installation
    preserve_logs "interrupted"
    
    # Show log access information
    show_log_access
    
    echo ""
    echo "⚠️  INSTALLATION INTERRUPTED"
    echo "Log files are preserved for troubleshooting."
    echo ""
    
    exit 130
}
# Helper function for base system installation
install_base_system_target() {
    log_info "Installing base system packages into /mnt..."

    # Strictly essential pacstrap: base + kernel + firmware (+ headers)
    local essential_packages="base"
    if [ "$KERNEL_TYPE" == "linux" ]; then
        essential_packages="$essential_packages linux linux-firmware linux-headers"
    elif [ "$KERNEL_TYPE" == "linux-lts" ]; then
        essential_packages="$essential_packages linux-lts linux-firmware linux-lts-headers"
    elif [ "$KERNEL_TYPE" == "linux-zen" ]; then
        essential_packages="$essential_packages linux-zen linux-firmware linux-zen-headers"
    elif [ "$KERNEL_TYPE" == "linux-hardened" ]; then
        essential_packages="$essential_packages linux-hardened linux-firmware linux-hardened-headers"
    else
        error_exit "Unsupported KERNEL_TYPE: $KERNEL_TYPE."
    fi

    log_info "Pacstrap essentials: $essential_packages"
    
    # Enhanced error handling for pacstrap
    if ! pacstrap -K /mnt $essential_packages --noconfirm --needed; then
        local exit_code=$?
        log_error "Pacstrap failed with exit code: $exit_code"
        log_error "Failed to install essential packages: $essential_packages"
        log_error "This could be due to:"
        log_error "  - Network connectivity issues"
        log_error "  - Invalid mirror configuration"
        log_error "  - Insufficient disk space in /mnt"
        log_error "  - Corrupted package database"
        log_error "Please check your network connection and try again"
        error_exit "Pacstrap failed to install essential base system."
    fi

    log_info "Base essentials installed on target."
}

# --- Call the main function with error handling ---
run_installation "$@"
