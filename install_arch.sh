#!/bin/bash
# install_arch.sh - Arch Linux Automated Installer

# Strict mode: Exit on error, unset variables, pipefail
set -euo pipefail

# --- Source all necessary script files ---
# Source config.sh first to get default variables and arrays/maps
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/dialogs.sh"
source "$(dirname "${BASH_SOURCE[0]}")/disk_strategies.sh"
# TUI integration - progress is handled directly by the TUI process

# --- Main Installation Function ---
main() {
    # Initialize enhanced logging system
    setup_logging
    
    # TUI integration - progress tracking handled by TUI process
    
    log_header "Arch Linux Automated Installer"
    
    # Show log access information at the start
    show_log_access

    check_prerequisites || error_exit "Prerequisite check failed."


    # Stage 1: Gather User Input (Always interactive now, no config loading)
    echo "=== PHASE 0: Gathering Installation Details ==="
    log_header "Stage 1: Gathering Installation Details"
    gather_installation_details || error_exit "Installation details gathering failed."
    display_summary_and_confirm || error_exit "Installation cancelled by user."
    
    # Verify the boot mode (UEFI bitness check) - after user input but before disk partitioning
    log_info "Verifying boot mode and UEFI bitness..."
    verify_boot_mode || error_exit "Boot mode verification failed."
    
    # Configure mirrors using reflector AFTER user input (so user choices matter!)
    log_info "Configuring mirrors based on user preferences..."
    configure_mirrors_live "$REFLECTOR_COUNTRY_CODE" || error_exit "Mirror configuration failed."
    
    # Set console keymap for live environment
    set_console_keymap_live

    # Stage 2: Disk Partitioning and Formatting
    echo "=== PHASE 1: Disk Partitioning ==="
    log_header "Stage 2: Disk Partitioning and Formatting"
    execute_disk_strategy || error_exit "Disk partitioning and formatting failed."
    echo "Disk partitioning complete"

    # Stage 3: Base System Installation
    echo "=== PHASE 2: Base Installation ==="
    log_header "Stage 3: Installing Base System"
    install_base_system_target || error_exit "Base system installation failed."
    
    # Generate fstab
    echo "Generating fstab..."
    log_info "Generating fstab file..."
    generate_fstab || error_exit "Fstab generation failed."
    echo "Packages installed"

    # Stage 4: Chroot Configuration
    echo "=== PHASE 4: System Configuration ==="
    log_header "Stage 4: Post-Installation (Chroot) Configuration"

    log_info "Copying chroot configuration files to /mnt..."
    cp -v ./chroot_config.sh ./config.sh ./utils.sh ./disk_strategies.sh ./dialogs.sh /mnt || error_exit "Failed to copy all necessary scripts to chroot."
    
    log_info "Copying Source directory to /mnt..."
    cp -r ./Source /mnt || error_exit "Failed to copy Source directory to chroot."
    
    # Ensure Plymouth script is executable in the copied location
    if [ -f "/mnt/Source/arch-glow/arch-glow.script" ]; then
        chmod +x /mnt/Source/arch-glow/arch-glow.script || log_warn "Failed to make Plymouth script executable in chroot"
        log_info "Made Plymouth script executable in chroot environment"
    fi

    # Verify the files exist at the destination
    if [ ! -f "/mnt/chroot_config.sh" ] || \
       [ ! -f "/mnt/config.sh" ] || \
       [ ! -f "/mnt/utils.sh" ] || \
       [ ! -f "/mnt/disk_strategies.sh" ] || \
       [ ! -f "/mnt/dialogs.sh" ]; then
        error_exit "One or more required script files not found in destination directory after copying."
    fi

    log_info "Setting permissions for chroot scripts..."
    chmod +x /mnt/*.sh || error_exit "Failed to make chroot scripts executable."
    
    # --- Export Variables (same method as working ArchL4TM version) ---
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

    # Ensure EFI partition is properly mounted before chroot
    if [ "$BOOT_MODE" == "uefi" ]; then
        log_info "Verifying EFI partition is properly mounted before chroot..."
        if ! mountpoint -q "/mnt/boot/efi"; then
            log_error "EFI partition not mounted at /mnt/boot/efi. Attempting to remount..."
            if [ -n "${PARTITION_UUIDS_EFI_UUID:-}" ]; then
                local efi_dev="/dev/disk/by-uuid/$PARTITION_UUIDS_EFI_UUID"
                if [ -b "$efi_dev" ]; then
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
    arch-chroot /mnt /bin/bash -c "LOG_FILE=$LOG_FILE MAIN_USERNAME='$MAIN_USERNAME' ROOT_PASSWORD='$ROOT_PASSWORD' MAIN_USER_PASSWORD='$MAIN_USER_PASSWORD' SYSTEM_HOSTNAME='$SYSTEM_HOSTNAME' USERNAME='$MAIN_USERNAME' USER_PASSWORD='$MAIN_USER_PASSWORD' HOSTNAME='$SYSTEM_HOSTNAME' ENCRYPTION_PASSWORD='$LUKS_PASSPHRASE' TIMEZONE='$TIMEZONE' LOCALE='$LOCALE' KEYMAP='$KEYMAP' DESKTOP_ENVIRONMENT='$DESKTOP_ENVIRONMENT' DISPLAY_MANAGER='$DISPLAY_MANAGER' BOOTLOADER_TYPE='$BOOTLOADER_TYPE' BOOT_MODE='$BOOT_MODE' OVERRIDE_BOOT_MODE='$OVERRIDE_BOOT_MODE' WANT_SECURE_BOOT='$WANT_SECURE_BOOT' WANT_AUR_HELPER='$WANT_AUR_HELPER' AUR_HELPER_CHOICE='$AUR_HELPER_CHOICE' WANT_GRUB_THEME='$WANT_GRUB_THEME' GRUB_THEME_CHOICE='$GRUB_THEME_CHOICE' WANT_PLYMOUTH='$WANT_PLYMOUTH' WANT_PLYMOUTH_THEME='$WANT_PLYMOUTH_THEME' PLYMOUTH_THEME_CHOICE='$PLYMOUTH_THEME_CHOICE' WANT_BTRFS='$WANT_BTRFS' WANT_BTRFS_SNAPSHOTS='$WANT_BTRFS_SNAPSHOTS' BTRFS_SNAPSHOT_FREQUENCY='$BTRFS_SNAPSHOT_FREQUENCY' BTRFS_KEEP_SNAPSHOTS='$BTRFS_KEEP_SNAPSHOTS' WANT_ENCRYPTION='$WANT_ENCRYPTION' WANT_LVM='$WANT_LVM' WANT_RAID='$WANT_RAID' RAID_LEVEL='$RAID_LEVEL' ROOT_FILESYSTEM_TYPE='$ROOT_FILESYSTEM_TYPE' HOME_FILESYSTEM_TYPE='$HOME_FILESYSTEM_TYPE' KERNEL_TYPE='$KERNEL_TYPE' CPU_MICROCODE_TYPE='$CPU_MICROCODE_TYPE' TIME_SYNC_CHOICE='$TIME_SYNC_CHOICE' GPU_DRIVER_TYPE='$GPU_DRIVER_TYPE' WANT_MULTILIB='$WANT_MULTILIB' WANT_FLATPAK='$WANT_FLATPAK' INSTALL_CUSTOM_PACKAGES='$INSTALL_CUSTOM_PACKAGES' CUSTOM_PACKAGES='$CUSTOM_PACKAGES' INSTALL_CUSTOM_AUR_PACKAGES='$INSTALL_CUSTOM_AUR_PACKAGES' CUSTOM_AUR_PACKAGES='$CUSTOM_AUR_PACKAGES' WANT_NUMLOCK_ON_BOOT='$WANT_NUMLOCK_ON_BOOT' WANT_DOTFILES_DEPLOYMENT='$WANT_DOTFILES_DEPLOYMENT' DOTFILES_REPO_URL='$DOTFILES_REPO_URL' DOTFILES_BRANCH='$DOTFILES_BRANCH' REFLECTOR_COUNTRY_CODE='$REFLECTOR_COUNTRY_CODE' ENABLE_OS_PROBER='$ENABLE_OS_PROBER' WANT_BTRFS_ASSISTANT='$WANT_BTRFS_ASSISTANT' WANT_SWAP='$WANT_SWAP' WANT_HOME_PARTITION='$WANT_HOME_PARTITION' LUKS_PASSPHRASE='$LUKS_PASSPHRASE' INSTALL_DISK='$INSTALL_DISK' ./chroot_config.sh" || error_exit "Chroot configuration failed."
    log_info "Chroot setup complete."
    echo "System configuration complete"
    
    # Stage 5: Finalization
    echo "=== PHASE 5: Finalization ==="
    log_header "Stage 5: Finalizing Installation"
    final_cleanup || error_exit "Final cleanup failed."

    echo "Installation completed successfully!"
    log_success "Arch Linux installation complete! You can now reboot."
    
    # Preserve logs for successful installation
    preserve_logs "success"
    
    # TUI cleanup handled automatically by TUI process
    
    prompt_reboot_system
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
    else
        error_exit "Unsupported KERNEL_TYPE: $KERNEL_TYPE."
    fi

    log_info "Pacstrap essentials: $essential_packages"
    pacstrap -K /mnt $essential_packages --noconfirm --needed || error_exit "Pacstrap failed to install essential base system."

    log_info "Base essentials installed on target."
}

# --- Call the main function with error handling ---
run_installation "$@"
