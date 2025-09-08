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

# --- Main Installation Function ---
main() {
    # Initialize enhanced logging system
    setup_logging
    
    log_header "Arch Linux Automated Installer"
    
    # Show log access information at the start
    show_log_access

    check_prerequisites || error_exit "Prerequisite check failed."

    # Verify ISO signature if requested
    if [ "$VERIFY_ISO_SIGNATURE" == "yes" ]; then
        verify_iso_signature || log_warn "ISO signature verification failed (continuing anyway)"
    fi

    # Stage 1: Gather User Input (Always interactive now, no config loading)
    log_header "Stage 1: Gathering Installation Details"
    gather_installation_details || error_exit "Installation details gathering failed."
    display_summary_and_confirm || error_exit "Installation cancelled by user."
    
    # Configure mirrors using reflector AFTER user input (so user choices matter!)
    log_info "Configuring mirrors based on user preferences..."
    configure_mirrors_live "$REFLECTOR_COUNTRY_CODE" || error_exit "Mirror configuration failed."
    
    # Set console keymap for live environment
    set_console_keymap_live

    # Stage 2: Disk Partitioning and Formatting
    log_header "Stage 2: Disk Partitioning and Formatting"
    execute_disk_strategy || error_exit "Disk partitioning and formatting failed."

    # Stage 3: Base System Installation
    log_header "Stage 3: Installing Base System"
    install_base_system_target || error_exit "Base system installation failed."
    
    # Generate fstab
    log_info "Generating fstab file..."
    generate_fstab || error_exit "Fstab generation failed."

    # Stage 4: Chroot Configuration
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
    export VERIFY_ISO_SIGNATURE
    export REFLECTOR_COUNTRY_CODE
    export ENABLE_OS_PROBER
    export WANT_BTRFS_ASSISTANT
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

    log_info "Executing chroot configuration script inside chroot..."
    arch-chroot /mnt /bin/bash -c "LOG_FILE=$LOG_FILE ./chroot_config.sh" || error_exit "Chroot configuration failed."
    log_info "Chroot setup complete."
    
    # Stage 5: Finalization
    log_header "Stage 5: Finalizing Installation"
    final_cleanup || error_exit "Final cleanup failed."

    log_success "Arch Linux installation complete! You can now reboot."
    
    # Preserve logs for successful installation
    preserve_logs "success"
    
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
# Helper function for base system installation (simplified approach based on proven second revision)
install_base_system_target() {
    log_info "Installing base system packages into /mnt..."
    
    # Start with essential packages (like second revision)
    local base_packages="base expect"
    
    # Add kernel packages based on user choice
    if [ "$KERNEL_TYPE" == "linux" ]; then
        base_packages="$base_packages linux linux-firmware linux-headers"
    elif [ "$KERNEL_TYPE" == "linux-lts" ]; then
        base_packages="$base_packages linux-lts linux-firmware linux-lts-headers"
    else
        error_exit "Unsupported KERNEL_TYPE: $KERNEL_TYPE."
    fi
    
    # Add essential system packages
    base_packages="$base_packages base-devel networkmanager"
    
    # Add bootloader packages
    if [ "$BOOTLOADER_TYPE" == "grub" ]; then
        base_packages="$base_packages grub efibootmgr os-prober"
    elif [ "$BOOTLOADER_TYPE" == "systemd-boot" ]; then
        base_packages="$base_packages systemd-boot"
    fi
    
    # Add filesystem utilities
    if [ "$ROOT_FILESYSTEM_TYPE" == "btrfs" ] || [ "$HOME_FILESYSTEM_TYPE" == "btrfs" ]; then
        base_packages="$base_packages btrfs-progs"
        WANT_BTRFS="yes"
    fi
    if [ "$ROOT_FILESYSTEM_TYPE" == "ext4" ] || [ "$HOME_FILESYSTEM_TYPE" == "ext4" ]; then
        base_packages="$base_packages e2fsprogs"
    fi
    if [ "$ROOT_FILESYSTEM_TYPE" == "xfs" ] || [ "$HOME_FILESYSTEM_TYPE" == "xfs" ]; then
        base_packages="$base_packages xfsprogs"
    fi
    
    # Add LVM/RAID tools if needed
    if [ "$WANT_LVM" == "yes" ]; then
        base_packages="$base_packages lvm2"
    fi
    if [ "$WANT_RAID" == "yes" ]; then
        base_packages="$base_packages mdadm"
    fi
    
    # Add CPU microcode
    if [ "$CPU_MICROCODE_TYPE" == "intel" ]; then
        base_packages="$base_packages intel-ucode"
    elif [ "$CPU_MICROCODE_TYPE" == "amd" ]; then
        base_packages="$base_packages amd-ucode"
    fi
    
    # Add time sync packages
    case "$TIME_SYNC_CHOICE" in
        "ntpd")
            base_packages="$base_packages ntp"
            ;;
        "chrony")
            base_packages="$base_packages chrony"
            ;;
        "systemd-timesyncd")
            base_packages="$base_packages systemd-timesyncd"
            ;;
    esac
    
    # Add Btrfs snapshot packages if requested
    if [ "$WANT_BTRFS" == "yes" ] && [ "$WANT_BTRFS_SNAPSHOTS" == "yes" ]; then
        base_packages="$base_packages snapper grub-btrfs"
    fi
    
    # Add desktop environment packages
    case "$DESKTOP_ENVIRONMENT" in
        "gnome")
            base_packages="$base_packages gnome gnome-extra gnome-tweaks firefox"
            ;;
        "kde")
            base_packages="$base_packages plasma-desktop sddm kde-applications dolphin firefox"
            ;;
        "hyprland")
            base_packages="$base_packages hyprland waybar swww kitty firefox"
            ;;
        "none")
            # No desktop environment packages
            ;;
    esac
    
    # Add display manager packages
    case "$DISPLAY_MANAGER" in
        "gdm")
            base_packages="$base_packages gdm"
            ;;
        "sddm")
            base_packages="$base_packages sddm"
            ;;
        "none")
            # No display manager packages
            ;;
    esac
    
    # Add other essential packages
    base_packages="$base_packages sudo man-db man-pages vim nano bash-completion git curl"
    
    # Add Plymouth if requested
    if [ "$WANT_PLYMOUTH" == "yes" ]; then
        base_packages="$base_packages plymouth"
    fi
    
    # Add Secure Boot tools if requested
    if [ "$WANT_SECURE_BOOT" == "yes" ]; then
        base_packages="$base_packages sbctl"
    fi
    
    log_info "Installing packages: $base_packages"
    
    # Use the proven approach from second revision
    pacstrap -K /mnt $base_packages --noconfirm --needed || error_exit "Pacstrap failed to install base system."

    log_info "Base system installation complete on target."
}

# --- Call the main function with error handling ---
run_installation "$@"
