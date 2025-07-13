#!/bin/bash
# dialogs.sh - Functions for user interaction and validation

# Select a single item from a list of options.
# Args: prompt_message, array_name_containing_options, result_variable_name
select_option() {
    local prompt_msg="$1"
    local -n options_array="$2"
    local -n result_var="$3"

    if [ ${#options_array[@]} -eq 0 ]; then
        error_exit "No options provided for selection: $prompt_msg"
    fi

    log_info "$prompt_msg"
    local i=1
    for opt in "${options_array[@]}"; do
        echo "  $((i++)). $opt"
    done

    local choice
    while true; do
        read -rp "Enter choice number (1-${#options_array[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options_array[@]} )); then
            result_var="${options_array[$((choice-1))]}"
            log_info "Selected: ${result_var}"
            return 0
        else
            log_warn "Invalid choice."
        fi
    done
}

# Prompt for yes/no question.
# Args: prompt_message, result_variable_name
prompt_yes_no() {
    local prompt_msg="$1"
    local -n result_var="$2"

    while true; do
        read -rp "$prompt_msg (y/n): " yn_choice
        case "$yn_choice" in
            [Yy]* ) result_var="yes"; return 0;;
            [Nn]* ) result_var="no"; return 0;;
            * ) log_warn "Please answer yes or no.";;
        esac
    done
}

# Helper to get available block devices (disks).
get_available_disks() {
    local disks=()
    while IFS= read -r line; do
        disks+=("/dev/$line")
    done < <(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -v 'loop' | grep -v 'ram')
    echo "${disks[@]}"
}

# Helper to get timezones within a selected region.
# Args: $1 = region (e.g., "America")
# Returns: Space-separated list of full timezone names (e.g., "America/New_York", "America/Los_Angeles")
get_timezones_in_region() {
    local region="$1"
    local zoneinfo_base_path="/usr/share/zoneinfo"
    local region_path="$zoneinfo_base_path/$region"
    local timezones=()

    if [ ! -d "$region_path" ]; then
        log_warn "Timezone region directory not found: $region_path"
        echo ""
        return 0
    fi

    while IFS= read -r -d '' tz_file_path; do
        local full_tz_name="${tz_file_path#"$zoneinfo_base_path/"}"
        if [[ "$full_tz_name" != posix/* ]] && [[ "$full_tz_name" != Etc/* ]] && [[ "$full_tz_name" != zone.tab ]]; then
            timezones+=("$full_tz_name")
        fi
    done < <(find -L "$region_path" -type f -print0)

    IFS=$'\n' timezones=($(sort <<<"${timezones[*]}"))
    unset IFS
    echo "${timezones[@]}"
}

# Helper for Wi-Fi connection (called from gather_installation_details)
configure_wifi_live_dialog() {
    log_info "Initiating Wi-Fi setup using iwctl."
    log_info "Running 'iwctl device list' to find Wi-Fi devices..."
    local wifi_devices=$(iwctl device list | grep 'wireless' | awk '{print $1}')
    if [ -z "$wifi_devices" ]; then
        log_warn "No wireless devices found. Skipping Wi-Fi setup."
        return 0
    fi

    local wifi_device=""
    if [[ $(echo "$wifi_devices" | wc -w) -gt 1 ]]; then
        local wifi_dev_options=($(echo "$wifi_devices"))
        select_option "Select Wi-Fi device:" wifi_dev_options wifi_device || return 1
    else
        wifi_device="$wifi_devices"
        log_info "Using Wi-Fi device: $wifi_device"
    fi

    log_info "Scanning for networks on $wifi_device..."
    iwctl station "$wifi_device" scan || log_warn "Wi-Fi scan failed. Try again or check device."

    log_info "Available Wi-Fi networks:"
    local networks=$(iwctl station "$wifi_device" get-networks | grep '^-' | awk '{print $2}')
    if [ -z "$networks" ]; then
        log_warn "No Wi-Fi networks found. Try scanning again or check surroundings."
        return 0
    fi
    local network_options=($(echo "$networks"))
    local selected_ssid=""
    select_option "Select Wi-Fi network (SSID):" network_options selected_ssid || return 1

    local password=""
    read -rsp "Enter password for '$selected_ssid' (leave blank if none): " password
    echo

    log_info "Connecting to '$selected_ssid'..."
    if [ -n "$password" ]; then
        iwctl --passphrase "$password" station "$wifi_device" connect "$selected_ssid" || error_exit "Wi-Fi connection failed."
    else
        iwctl station "$wifi_device" connect "$selected_ssid" || error_exit "Wi-Fi connection failed."
    fi

    log_info "Verifying Wi-Fi connection..."
    if ping -c 1 -W 2 archlinux.org &>/dev/null; then
        log_success "Wi-Fi connected successfully!"
        return 0
    else
        error_exit "Wi-Fi connected but no internet access. Check password or network."
    fi
}

# Prompts the user to load a configuration file.
# Returns: The path to the config file to load, or empty string if none.
prompt_load_config() {
    local config_to_load=""
    
    local script_dir="$(dirname "${BASH_SOURCE[0]}")"
    local available_configs=()
    while IFS= read -r -d $'\0' f; do
        local filename=$(basename "$f")
        if [[ "$filename" == *.sh ]] && [[ "$filename" != "install_arch.sh" ]] && [[ "$filename" != "config.sh" ]] && \
           [[ "$filename" != "utils.sh" ]] && [[ "$filename" != "dialogs.sh" ]] && \
           [[ "$filename" != "disk_strategies.sh" ]] && [[ "$filename" != "chroot_config.sh" ]]; then
            available_configs+=("$filename")
        fi
    done < <(find "$script_dir" -maxdepth 1 -type f -name "*.sh" -print0)

    if [ ${#available_configs[@]} -gt 0 ]; then
        log_info "Found existing configuration files:"
        select_option "Select a configuration file to load (or choose 'None' to configure manually):" available_configs config_to_load_choice
        if [ "$config_to_load_choice" != "" ]; then
             echo "$script_dir/$config_to_load_choice"
             return 0
        fi
    else
        log_info "No saved configuration files found in the current directory."
    fi

    local load_manual_path=""
    prompt_yes_no "Do you want to load a configuration file from a specific path?" load_manual_path
    if [ "$load_manual_path" == "yes" ]; then
        read -rp "Enter the full path to the configuration file: " config_path_input
        config_path_input=$(trim_string "$config_path_input")
        if [ -f "$config_path_input" ]; then
            echo "$config_path_input"
            return 0
        else
            log_warn "File not found: $config_path_input. Will proceed with manual configuration."
        fi
    fi

    echo ""
    return 0
}


# --- Core User Input Gathering Function ---
gather_installation_details() {
    log_header "SYSTEM & STORAGE CONFIGURATION"

    # Wi-Fi Connection (early, as it might be needed for reflector prereqs)
    prompt_yes_no "Do you want to connect to a Wi-Fi network now?" WANT_WIFI_CONNECTION
    if [ "$WANT_WIFI_CONNECTION" == "yes" ]; then
        configure_wifi_live_dialog || error_exit "Wi-Fi connection setup failed. Cannot proceed without internet."
    fi

    # Auto-detect boot mode, allow override for BIOS.
    log_info "Detecting system boot mode..."
    if [[ -d "/sys/firmware/efi" ]]; then
        BOOT_MODE="uefi"
        log_info "Detected UEFI boot mode."

        local fw_platform_size_file="/sys/firmware/efi/fw_platform_size"
        if [ -f "$fw_platform_size_file" ]; then
            local uefi_bitness=$(cat "$fw_platform_size_file")
            if [ "$uefi_bitness" == "32" ]; then
                error_exit "Detected 32-bit UEFI firmware. Arch Linux x86_64 requires 64-bit UEFI or BIOS boot mode. Please switch to BIOS/Legacy boot in your firmware settings or perform a manual installation."
            fi
            log_info "Detected ${uefi_bitness}-bit UEFI firmware."
        else
            log_warn "Could not determine UEFI firmware bitness (missing $fw_platform_size_file)."
            log_warn "Proceeding assuming 64-bit UEFI, but manual verification is recommended if issues arise."
        fi

        prompt_yes_no "Force BIOS/Legacy boot mode instead of UEFI? (For specific VM setups or troubleshooting)" OVERRIDE_BOOT_MODE
        if [ "$OVERRIDE_BOOT_MODE" == "yes" ]; then
            BOOT_MODE="bios"
            log_warn "Forcing BIOS/Legacy boot mode."
        fi
    else
        BOOT_MODE="bios"
        log_info "Detected BIOS/Legacy boot mode."
    fi

    # Select primary installation disk.
    local available_disks=($(get_available_disks))
    if [ ${#available_disks[@]} -eq 0 ]; then
        error_exit "No suitable disks found for installation. Exiting."
    fi
    select_option "Select the primary installation disk:" available_disks INSTALL_DISK

    # Select partitioning scheme.
    local scheme_options=("auto_simple" "auto_luks_lvm")
    local other_disks_for_raid=()
    for d in "${available_disks[@]}"; do
        if [ "$d" != "$INSTALL_DISK" ]; then
            other_disks_for_raid+=("$d")
        fi
    done

    if [ ${#other_disks_for_raid[@]} -ge 1 ]; then
        scheme_options+=("auto_raid_luks_lvm")
    else
        log_warn "Not enough additional disks for RAID options. Skipping RAID schemes."
    fi
    scheme_options+=("manual")

    select_option "Select partitioning scheme:" scheme_options PARTITION_SCHEME

    # Conditional prompts based on selected scheme.
    case "$PARTITION_SCHEME" in
        auto_simple)
            WANT_ENCRYPTION="no"
            WANT_LVM="no"
            WANT_RAID="no"
            prompt_yes_no "Do you want a swap partition?" WANT_SWAP
            prompt_yes_no "Do you want a separate /home partition?" WANT_HOME_PARTITION
            ;;
        auto_luks_lvm)
            WANT_ENCRYPTION="yes"
            WANT_LVM="yes"
            WANT_RAID="no"
            prompt_yes_no "Do you want a swap Logical Volume?" WANT_SWAP
            prompt_yes_no "Do you want a separate /home Logical Volume?" WANT_HOME_PARTITION
            secure_password_input "Enter LUKS encryption passphrase: " LUKS_PASSPHRASE
            ;;
        auto_raid_luks_lvm)
            WANT_RAID="yes"
            WANT_ENCRYPTION="yes"
            WANT_LVM="yes"

            log_warn "RAID device selection requires additional disks. You must select them now."
            log_info "Available additional disks for RAID:"
            local i=1
            local display_other_disks=()
            for d in "${other_disks_for_raid[@]}"; do
                display_other_disks+=("($i) $d")
                i=$((i+1))
            done
            select_option "Select additional disk(s) for RAID (space-separated numbers, e.g., '1 3'):" display_other_disks selected_raid_disk_numbers_str

            IFS=' ' read -r -a selected_nums_array <<< "$(trim_string "$selected_raid_disk_numbers_str")"
            
            RAID_DEVICES=("$INSTALL_DISK")
            for num_str in "${selected_nums_array[@]}"; do
                local index=$((num_str - 1))
                if (( index >= 0 && index < ${#other_disks_for_raid[@]} )); then
                    RAID_DEVICES+=("${other_disks_for_raid[$index]}")
                else
                    log_warn "Invalid RAID disk number: $num_str. Skipping."
                fi
            done
            if [ ${#RAID_DEVICES[@]} -lt 2 ]; then error_exit "RAID requires at least 2 disks. Please re-run and select more."; fi

            select_option "Select RAID level:" RAID_LEVEL_OPTIONS RAID_LEVEL
            prompt_yes_no "Do you want a swap Logical Volume?" WANT_SWAP
            prompt_yes_no "Do you want a separate /home Logical Volume?" WANT_HOME_PARTITION
            secure_password_input "Enter LUKS encryption passphrase: " LUKS_PASSPHRASE
            ;;
        manual)
            log_warn "Manual partitioning selected. You will be guided to perform partitioning steps yourself."
            log_warn "Ensure you create and mount /mnt, /mnt/boot (and /mnt/boot/efi if UEFI) correctly."
            WANT_SWAP="no"
            WANT_HOME_PARTITION="no"
            WANT_ENCRYPTION="no"
            WANT_LVM="no"
            WANT_RAID="no"
            ;;
    esac

    # Filesystem Type Selection (for Root and Home if applicable)
    if [ "$PARTITION_SCHEME" != "manual" ]; then
        log_info "Configuring filesystem types for root and home partitions."
        select_option "Select filesystem for the root (/) partition:" FILESYSTEM_OPTIONS ROOT_FILESYSTEM_TYPE || error_exit "Root filesystem selection failed."

        if [ "$WANT_HOME_PARTITION" == "yes" ]; then
            local default_home_fs_choice="$ROOT_FILESYSTEM_TYPE"
            select_option "Select filesystem for the /home partition (default: $default_home_fs_choice):" FILESYSTEM_OPTIONS HOME_FILESYSTEM_TYPE_TEMP || error_exit "Home filesystem selection failed."
            if [ -z "$HOME_FILESYSTEM_TYPE_TEMP" ]; then
                HOME_FILESYSTEM_TYPE="$default_home_fs_choice"
            else
                HOME_FILESYSTEM_TYPE="$HOME_FILESYSTEM_TYPE_TEMP"
            fi
        fi
    fi


    log_header "BASE SYSTEM & USER CONFIGURATION"

    # Kernel Type (rolling vs. LTS).
    select_option "Choose your preferred kernel:" KERNEL_TYPES_OPTIONS KERNEL_TYPE || error_exit "Kernel type selection failed."

    # Timezone Configuration.
    log_info "Configuring system timezone."
    local selected_region=""
    select_option "Select your primary geographical region:" TIMEZONE_REGIONS selected_region || error_exit "Timezone region selection failed."
    local available_timezones=($(get_timezones_in_region "$selected_region"))
    if [ ${#available_timezones[@]} -eq 0 ]; then
        log_warn "No specific timezones found for region '$selected_region'. Using default."
        TIMEZONE="$TIMEZONE_DEFAULT"
    else
        select_option "Select your city/timezone:" available_timezones TIMEZONE || error_exit "Timezone selection failed."
    fi

    # Localization (Locale & Keymap).
    log_info "Setting system locale."
    select_option "Select primary system locale:" LOCALE_OPTIONS LOCALE || error_exit "Locale selection failed."

    log_info "Setting console keymap."
    select_option "Select console keymap:" KEYMAP_OPTIONS KEYMAP || error_exit "Keymap selection failed."

    # Reflector Country Code (Mirrorlist).
    log_info "Configuring pacman mirror country."
    local use_default_mirror_country=""
    prompt_yes_no "Use default mirror country (${REFLECTOR_COUNTRY_CODE})? " use_default_mirror_country

    if [ "$use_default_mirror_country" == "no" ]; then
        log_info "Available common countries for reflector:"
        local temp_reflector_country_choice=""
        select_option "Select preferred mirror country code:" REFLECTOR_COMMON_COUNTRIES temp_reflector_country_choice
        REFLECTOR_COUNTRY_CODE="$temp_reflector_country_choice"
        if [ -z "$REFLECTOR_COUNTRY_CODE" ]; then
            log_warn "No country code selected. Sticking with default: US"
            REFLECTOR_COUNTRY_CODE="US"
        fi
    fi

    log_header "DESKTOP & USER ACCOUNT CONFIGURATION"

    # User Credentials.
    read -rp "Enter hostname: " SYSTEM_HOSTNAME
    secure_password_input "Enter root password: " ROOT_PASSWORD
    read -rp "Enter main username: " MAIN_USERNAME
    secure_password_input "Enter password for $MAIN_USERNAME: " MAIN_USER_PASSWORD

    # Desktop Environment and Display Manager.
    select_option "Select Desktop Environment:" "${!DESKTOP_ENVIRONMENTS[@]}" DESKTOP_ENVIRONMENT
    if [ "$DESKTOP_ENVIRONMENT" != "none" ]; then
        case "$DESKTOP_ENVIRONMENT" in
            gnome) DISPLAY_MANAGER="gdm";;
            kde|hyprland) DISPLAY_MANAGER="sddm";;
            * ) DISPLAY_MANAGER="none";;
        esac
        select_option "Select Display Manager (default: $DISPLAY_MANAGER):" "${!DISPLAY_MANAGERS[@]}" DISPLAY_MANAGER
    else
        DISPLAY_MANAGER="none"
    fi

    # Bootloader.
    select_option "Select Bootloader:" BOOTLOADER_TYPES_OPTIONS BOOTLOADER_TYPE
    if [ "$BOOTLOADER_TYPE" == "grub" ]; then
        prompt_yes_no "Enable OS Prober for dual-boot detection (recommended for dual-boot systems)?" ENABLE_OS_PROBER
    fi

    # Multilib Support (32-bit).
    prompt_yes_no "Enable 32-bit support (multilib repository)?" WANT_MULTILIB

    # AUR Helper.
    prompt_yes_no "Install an AUR helper (e.g., yay)?" WANT_AUR_HELPER
    if [ "$WANT_AUR_HELPER" == "yes" ]; then
        select_option "Select AUR Helper:" AUR_HELPERS_OPTIONS AUR_HELPER_CHOICE
    fi

    # Flatpak Support.
    prompt_yes_no "Install Flatpak support?" WANT_FLATPAK

    # Custom Packages (from config.sh).
    prompt_yes_no "Do you want to install additional custom packages from the list in config.sh?" INSTALL_CUSTOM_PACKAGES

    # Custom AUR Packages (from config.sh).
    if [ "$WANT_AUR_HELPER" == "yes" ]; then
        prompt_yes_no "Do you want to install additional custom AUR packages from the list in config.sh?" INSTALL_CUSTOM_AUR_PACKAGES
    fi

    # GRUB Theming.
    if [ "$BOOTLOADER_TYPE" == "grub" ]; then
        prompt_yes_no "Install a GRUB theme?" WANT_GRUB_THEME
        if [ "$WANT_GRUB_THEME" == "yes" ]; then
            select_option "Select GRUB Theme:" GRUB_THEME_OPTIONS GRUB_THEME_CHOICE
        fi
    fi

    # Numlock on Boot.
    prompt_yes_no "Enable Numlock on boot?" WANT_NUMLOCK_ON_BOOT

    # Dotfile Deployment.
    prompt_yes_no "Do you want to deploy dotfiles from a Git repository?" WANT_DOTFILES_DEPLOYMENT
    if [ "$WANT_DOTFILES_DEPLOYMENT" == "yes" ]; then
        read -rp "Enter the Git repository URL for your dotfiles: " DOTFILES_REPO_URL
        read -rp "Enter the branch to clone (default: main): " DOTFILES_BRANCH_INPUT
        if [ -z "$DOTFILES_BRANCH_INPUT" ]; then
            DOTFILES_BRANCH="main"
        else
            DOTFILES_BRANCH="$DOTFILES_BRANCH_INPUT"
        fi
    fi

    log_info "All installation details gathered."
}

# --- Summary and Confirmation ---
display_summary_and_confirm() {
    log_header "Installation Summary"
    echo "  Disk:                 $INSTALL_DISK"
    echo "  Boot Mode:            $BOOT_MODE"
    echo "  Partitioning:         $PARTITION_SCHEME"
    echo "    Root FS Type:       $ROOT_FILESYSTEM_TYPE"
    if [ "$WANT_HOME_PARTITION" == "yes" ]; then
        echo "    Home FS Type:       $HOME_FILESYSTEM_TYPE"
    fi
    echo "    Swap:               $WANT_SWAP"
    echo "    /home:              $WANT_HOME_PARTITION"
    echo "    Encryption:         $WANT_ENCRYPTION"
    if [ "$WANT_ENCRYPTION" == "yes" ]; then
        echo "    LUKS Passphrase:    ***ENCRYPTED***"
    fi
    echo "    LVM:                $WANT_LVM"
    if [ "$WANT_RAID" == "yes" ]; then
        echo "    RAID Level:         $RAID_LEVEL"
        echo "    RAID Disks:         ${RAID_DEVICES[*]}"
    fi
    echo "  Kernel:               $KERNEL_TYPE"
    echo "  CPU Microcode:        $CPU_MICROCODE_TYPE (auto-installed)"
    echo "  Timezone:             $TIMEZONE"
    echo "  Locale:               $LOCALE"
    echo "  Keymap:               $KEYMAP"
    echo "  Reflector Country:    $REFLECTOR_COUNTRY_CODE"
    echo "  Hostname:             $SYSTEM_HOSTNAME"
    echo "  Main User:            $MAIN_USERNAME"
    echo "  Desktop Env:          $DESKTOP_ENVIRONMENT"
    echo "  Display Manager:      $DISPLAY_MANAGER"
    echo "  GPU Driver:           $GPU_DRIVER_TYPE (auto-installed)"
    echo "  Bootloader:           $BOOTLOADER_TYPE"
    if [ "$BOOTLOADER_TYPE" == "grub" ]; then
        echo "    OS Prober:          $ENABLE_OS_PROBER"
        if [ "$WANT_GRUB_THEME" == "yes" ]; then
            echo "    GRUB Theme:         $GRUB_THEME_CHOICE"
        fi
    fi
    echo "  Multilib:             $WANT_MULTILIB"
    echo "  AUR Helper:           $WANT_AUR_HELPER"
    if [ "$WANT_AUR_HELPER" == "yes" ]; then
        echo "    AUR Helper Type:    $AUR_HELPER_CHOICE"
    fi
    echo "  Flatpak:              $WANT_FLATPAK"
    echo "  Custom Packages:      $INSTALL_CUSTOM_PACKAGES"
    if [ "$INSTALL_CUSTOM_PACKAGES" == "yes" ]; then
        echo "    List:               See config.sh"
    fi
    echo "  Custom AUR Packages:  $INSTALL_CUSTOM_AUR_PACKAGES"
    if [ "$INSTALL_CUSTOM_AUR_PACKAGES" == "yes" ]; then
        echo "    List:               See config.sh"
    fi
    echo "  Numlock on Boot:      $WANT_NUMLOCK_ON_BOOT"
    echo "  Dotfiles Deployment:  $WANT_DOTFILES_DEPLOYMENT"
    if [ "$WANT_DOTFILES_DEPLOYMENT" == "yes" ]; then
        echo "    Repo URL:           $DOTFILES_REPO_URL"
        echo "    Branch:             $DOTFILES_BRANCH"
    fi

    prompt_yes_no "Do you want to proceed with the installation (THIS WILL WIPE $INSTALL_DISK)? " CONFIRM_INSTALL
    if [ "$CONFIRM_INSTALL" == "no" ]; then
        return 1
    fi
    return 0
}

prompt_reboot_system() {
    prompt_yes_no "Installation complete. Reboot now?" REBOOT_NOW
    if [ "$REBOOT_NOW" == "yes" ]; then
        log_info "Rebooting..."
        reboot
    else
        log_info "Please reboot manually when ready. Exiting."
    fi
}
