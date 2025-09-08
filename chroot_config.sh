#!/bin/bash
# chroot_config.sh - Functions for post-base-install (chroot) configurations
# This script is designed to be copied into the /mnt environment and executed by arch-chroot.

# Strict mode for this script
set -euo pipefail

# Source its own copy of config.sh and utils.sh from its copied location
source ./config.sh
source ./utils.sh
source ./disk_strategies.sh
source ./dialogs.sh

# Note: Variables like INSTALL_DISK, ROOT_PASSWORD, etc. are now populated from the environment passed by install_arch.sh
# Associative arrays like PARTITION_UUIDs are also exported (-A).
# So, they will be directly available in this script's scope.

# Enhanced logging functions for chroot context (based on revision 2 approach)
_log_message() {
    local level="$1"
    local message="$2"
    local exit_code="${3:-0}"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local caller_info="${FUNCNAME[2]:-main}:${BASH_LINENO[1]:-0}"
    
    # Determine log level color
    local color=""
    case "$level" in
        INFO) color="\e[32m" ;;
        WARN) color="\e[33m" ;;
        ERROR) color="\e[31m" ;;
        DEBUG) color="\e[36m" ;;
        *) color="\e[0m" ;;
    esac
    
    # Format log message
    local log_entry="[$timestamp] [$level] [$caller_info] Exit Code: $exit_code - $message"
    
    # Print to terminal (with color)
    echo -e "${color}${log_entry}\e[0m"
    
    # Append to log file if LOG_FILE is set
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "$log_entry" >> "$LOG_FILE"
    fi
}

_log_info() { _log_message "INFO" "$1"; }
_log_warn() { _log_message "WARN" "$1"; }
_log_error() { _log_message "ERROR" "$1" "$?"; exit 1; }
_log_debug() { _log_message "DEBUG" "$1"; }
_log_success() { echo -e "\n\e[32;1m==================================================\e[0m\n\e[32;1m $* \e[0m\n\e[32;1m==================================================\e[0m\n"; }


# Main function for chroot configuration - this is now the entry point for this script
# Performs all post-installation configuration inside the chroot environment
# Global: All configuration variables exported from install_arch.sh
main_chroot_config() {
    _log_info "Starting chroot configurations within target system."
    
    # Debug: Show all environment variables related to passwords and users
    _log_info "Debug - Environment variables in chroot:"
    _log_info "  MAIN_USERNAME: '${MAIN_USERNAME:-NOT_SET}'"
    _log_info "  ROOT_PASSWORD: '${ROOT_PASSWORD:+SET}' (length: ${#ROOT_PASSWORD})"
    _log_info "  MAIN_USER_PASSWORD: '${MAIN_USER_PASSWORD:+SET}' (length: ${#MAIN_USER_PASSWORD})"
    _log_info "  SYSTEM_HOSTNAME: '${SYSTEM_HOSTNAME:-NOT_SET}'"
    _log_info "  TIMEZONE: '${TIMEZONE:-NOT_SET}'"
    _log_info "  LOCALE: '${LOCALE:-NOT_SET}'"

    # --- Phase 1: Basic System Configuration ---
    _log_info "Configuring pacman for better user experience..."
    configure_pacman_chroot || _log_error "Pacman configuration failed."
    
    _log_info "Configuring system localization..."
    configure_localization_chroot || _log_error "Localization configuration failed."

    _log_info "Configuring hostname and basic user setup."
    configure_hostname_chroot || _log_error "Hostname configuration failed."

    _log_info "Setting root password..."
    
    # Debug: Check if ROOT_PASSWORD is set
    if [ -z "$ROOT_PASSWORD" ]; then
        _log_error "ROOT_PASSWORD is empty! Cannot set root password."
        _log_error "Available environment variables:"
        env | grep -E "(ROOT|USER|PASSWORD)" || _log_error "No password variables found in environment"
        exit 1
    fi
    
    # Use the simple, reliable method from the working version
    _log_info "Setting root password using echo method..."
    if ! echo "root:$ROOT_PASSWORD" | chpasswd; then
        _log_error "Failed to set root password using chpasswd"
        exit 1
    fi
    _log_info "Root password set successfully."

    _log_info "Creating main user: $MAIN_USERNAME..."
    
    # Debug: Check if MAIN_USERNAME is set
    if [ -z "$MAIN_USERNAME" ]; then
        _log_error "MAIN_USERNAME is empty! Cannot create user."
        _log_error "Available variables: ROOT_PASSWORD=${ROOT_PASSWORD:0:3}***, MAIN_USER_PASSWORD=${MAIN_USER_PASSWORD:0:3}***"
        error_exit "MAIN_USERNAME variable is not set in chroot environment"
    fi
    
    # Create user using the proven approach from second revision
    useradd -m -G wheel,power,storage,uucp,network -s /bin/bash "$MAIN_USERNAME" || _log_error "Failed to create user '$MAIN_USERNAME'."
    
    # Debug: Check if MAIN_USER_PASSWORD is set
    if [ -z "$MAIN_USER_PASSWORD" ]; then
        _log_error "MAIN_USER_PASSWORD is empty! Cannot set user password."
        exit 1
    fi
    
    # Use the simple, reliable method from the working version
    _log_info "Setting password for user '$MAIN_USERNAME' using echo method..."
    if ! echo "$MAIN_USERNAME:$MAIN_USER_PASSWORD" | chpasswd; then
        _log_error "Failed to set password for user '$MAIN_USERNAME' using chpasswd"
        exit 1
    fi
    _log_info "User password set successfully."
    
    # Configure sudoers (simplified approach)
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel-sudo || _log_error "Failed to configure sudoers."
    chmod 0440 /etc/sudoers.d/10-wheel-sudo || _log_error "Failed to set permissions on sudoers file."

    # --- Phase 2: Bootloader & Initramfs ---
    _log_info "Configuring bootloader, GRUB defaults, theme, and mkinitpio hooks."
    configure_bootloader_chroot || _log_error "Bootloader installation failed."

    configure_grub_defaults_chroot || _log_error "GRUB default configuration failed."

    # Configure GRUB-specific options only if GRUB is selected
    if [ "$BOOTLOADER_TYPE" == "grub" ]; then
        configure_grub_theme_chroot || _log_error "GRUB theme configuration failed."
        configure_grub_cmdline_chroot || _log_error "GRUB kernel command line configuration failed."
    else
        _log_info "Skipping GRUB-specific configurations (systemd-boot selected)"
    fi

    configure_mkinitpio_hooks_chroot || _log_error "Mkinitpio hooks configuration or initramfs rebuild failed."

    # Configure Plymouth only if GRUB is selected (systemd-boot has limited Plymouth support)
    if [ "$WANT_PLYMOUTH" == "yes" ]; then
        if [ "$BOOTLOADER_TYPE" == "grub" ]; then
            _log_info "Configuring Plymouth boot splash..."
            configure_plymouth_chroot || _log_error "Plymouth configuration failed."
        else
            _log_warn "Plymouth requested but systemd-boot selected - limited Plymouth support"
            _log_info "Configuring Plymouth boot splash..."
            configure_plymouth_chroot || _log_error "Plymouth configuration failed."
        fi
    else
        _log_info "Skipping Plymouth configuration (not requested)"
    fi

    _log_info "Configuring Secure Boot..."
    configure_secure_boot_chroot || _log_error "Secure Boot configuration failed."


    # --- Phase 3: Desktop Environment & Drivers ---
    _log_info "Installing Desktop Environment: $DESKTOP_ENVIRONMENT..."
    case "$DESKTOP_ENVIRONMENT" in
        "gnome") install_packages_chroot "${DESKTOP_ENVIRONMENTS_GNOME_PACKAGES[@]}" || _log_error "Desktop Environment packages installation failed." ;;
        "kde") install_packages_chroot "${DESKTOP_ENVIRONMENTS_KDE_PACKAGES[@]}" || _log_error "Desktop Environment packages installation failed." ;;
        "hyprland") install_packages_chroot "${DESKTOP_ENVIRONMENTS_HYPRLAND_PACKAGES[@]}" || _log_error "Desktop Environment packages installation failed." ;;
        "none") _log_info "No desktop environment to install" ;;
    esac

    _log_info "Installing Display Manager: $DISPLAY_MANAGER..."
    case "$DISPLAY_MANAGER" in
        "gdm") 
            install_packages_chroot "${DISPLAY_MANAGERS_GDM_PACKAGES[@]}" || _log_error "Display Manager packages installation failed."
            enable_systemd_service_chroot "$DISPLAY_MANAGER" || _log_error "Failed to enable Display Manager service."
            ;;
        "sddm") 
            install_packages_chroot "${DISPLAY_MANAGERS_SDDM_PACKAGES[@]}" || _log_error "Display Manager packages installation failed."
            enable_systemd_service_chroot "$DISPLAY_MANAGER" || _log_error "Failed to enable Display Manager service."
            ;;
        "none") _log_info "No display manager to install" ;;
    esac
    
    _log_info "Installing GPU Drivers..."
    install_gpu_drivers_chroot || _log_error "GPU driver installation failed."

    _log_info "Installing CPU Microcode..."
    install_microcode_chroot || _log_error "CPU Microcode installation failed."


    # --- Phase 4: Optional Software & User Customization ---
    # Multilib repository is now handled in configure_pacman_chroot()

    _log_info "Installing AUR Helper..."
    install_aur_helper_chroot || _log_error "AUR Helper installation failed."

    _log_info "Installing Flatpak..."
    install_flatpak_chroot || _log_error "Flatpak installation failed."

    _log_info "Installing Custom Packages..."
    install_custom_packages_chroot || _log_error "Custom packages installation failed."

    _log_info "Installing Custom AUR Packages..."
    install_custom_aur_packages_chroot || _log_error "Custom AUR packages installation failed."

    _log_info "Installing AUR Numlock on Boot..."
    configure_numlock_chroot || _log_error "Numlock on boot configuration failed."

    _log_info "Deploying Dotfiles..."
    deploy_dotfiles_chroot || _log_error "Dotfile deployment failed."

    _log_info "Saving mdadm.conf for RAID arrays..."
    save_mdadm_conf_chroot || _log_error "Mdadm.conf saving failed."

    # --- Phase 5: Final System Services ---
    _log_info "Enabling essential system services..."
    enable_systemd_service_chroot "NetworkManager" || _log_error "Failed to enable NetworkManager service."
    # Enable time synchronization service based on user choice
    case "$TIME_SYNC_CHOICE" in
        "ntpd")
            enable_systemd_service_chroot "ntpd" || _log_error "Failed to enable ntpd service."
            ;;
        "chrony")
            enable_systemd_service_chroot "chronyd" || _log_error "Failed to enable chronyd service."
            ;;
        "systemd-timesyncd")
            enable_systemd_service_chroot "systemd-timesyncd" || _log_error "Failed to enable systemd-timesyncd service."
            ;;
    esac
    enable_systemd_service_chroot "fstrim.timer" || _log_error "Failed to enable SSD trim timer."

    # --- Phase 6: Btrfs Snapshot Configuration ---
    _log_info "Configuring Btrfs snapshots..."
    configure_btrfs_snapshots_chroot || _log_error "Btrfs snapshots configuration failed."

    # --- Phase 7: Desktop Environment Configuration ---
    _log_info "Configuring desktop environment and display manager..."
    configure_desktop_environment_chroot || _log_error "Desktop environment configuration failed."

    _log_success "Chroot configuration complete."
    
    # Preserve logs in the chroot environment
    if [[ -n "${LOG_FILE:-}" ]]; then
        _log_info "Preserving chroot logs..."
        mkdir -p "/var/log"
        if [[ -f "$LOG_FILE" ]]; then
            cp "$LOG_FILE" "/var/log/archinstall-chroot.log"
            _log_info "Chroot logs preserved at: /var/log/archinstall-chroot.log"
        fi
    fi
}

# Call the main function
main_chroot_config
