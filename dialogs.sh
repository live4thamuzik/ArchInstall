#!/bin/bash
# dialogs.sh - Functions for user interaction and validation (Bash 3.x Compatible)

# Select a single item from a list of options.
# Args: $1 = prompt_message, $2 = array_name_containing_options (string name), $3 = result_variable_name (string name)
select_option() {
    local prompt_msg="$1"
    local array_name="$2"
    local result_var_name="$3" # This is now the string name, not a nameref

    # Get array content using indirect expansion (Bash 3.x compatible)
    local options_array_content=()
    eval "options_array_content=( \"\${${array_name}[@]}\" )"

    if [ ${#options_array_content[@]} -eq 0 ]; then
        error_exit "No options provided for selection: $prompt_msg"
    fi

    log_info "$prompt_msg"
    local i=1
    local opt_keys=() # Will hold the options to display and map back to result

    # For Bash 3.x, we don't have declare -A, so all our "maps" are simulated with naming convention
    # and passed as string names to select_option (e.g., DESKTOP_ENVIRONMENTS).
    # If the array name passed is for a package list (which are now indexed arrays),
    # we just use its content.
    # We're simplifying this to assume all arrays passed here are indexed arrays of strings.

    for opt in "${options_array_content[@]}"; do
        opt_keys+=("$opt") # Directly populate opt_keys from options_array_content
    done

    for opt in "${opt_keys[@]}"; do
        echo "  $((i++)). $opt"
    done

    local choice
    while true; do
        read -rp "Enter choice number (1-${#opt_keys[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#opt_keys[@]} )); then
            # Assign result using indirect expansion (Bash 3.x compatible)
            eval "${result_var_name}=\"${opt_keys[$((choice-1))]}\""
            log_info "Selected: ${!result_var_name}"
            return 0
        else
            log_warn "Invalid choice."
        fi
    done
}

# Prompt for yes/no question.
# Args: $1 = prompt_message, $2 = result_variable_name (string name)
prompt_yes_no() {
    local prompt_msg="$1"
    local result_var_name="$2" # This is now the string name

    while true; do
        read -rp "$prompt_msg (y/n): " temp_yn_choice # Read into a temporary var
        case "$temp_yn_choice" in
            [Yy]* ) eval "${result_var_name}=\"yes\""; return 0;; # Assign using eval
            [Nn]* ) eval "${result_var_name}=\"no\""; return 0;;  # Assign using eval
            * ) log_warn "Please answer yes or no.";;
        esac
    done
}

get_available_disks() {
    local disks=()
    # Replace read -r -d '' with read -r and process newlines from find
    # find ... -print0 is Bash 4.4+
    # For Bash 3.x, use find ... -print | while read -r line
    # Or, rely on lsblk output directly
    # Original get_available_disks using awk prints with newlines, so read -r is fine.
    while IFS= read -r line; do
        disks+=("/dev/$line")
    done < <(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -v 'loop' | grep -v 'ram')
    echo "${disks[@]}"
}

get_timezones_in_region() {
    local region="$1"
    local zoneinfo_base_path="/usr/share/zoneinfo"
    local region_path="$zoneinfo_base_path/$region"
    local timezones=()

    # Special case for US regional timezones
    if [ "$region" == "US" ]; then
        timezones=("US/Eastern" "US/Central" "US/Mountain" "US/Pacific" "US/Alaska" "US/Hawaii")
        echo "${timezones[@]}"
        return 0
    fi

    if [ ! -d "$region_path" ]; then
        log_warn "Timezone region directory not found: $region_path"
        echo ""
        return 0
    fi

    # For Bash 3.x, replace find -print0 | while IFS= read -r -d ''
    # Use find -print | while IFS= read -r (standard for newlines)
    while IFS= read -r tz_file_path; do
        # Remove the base path and ensure correct formatting
        local full_tz_name="${tz_file_path#"$zoneinfo_base_path/"}"
        if [[ "$full_tz_name" != posix/* ]] && [[ "$full_tz_name" != Etc/* ]] && [[ "$full_tz_name" != zone.tab ]]; then
            timezones+=("$full_tz_name")
        fi
    done < <(find -L "$region_path" -type f -print) # Changed -print0 to -print for Bash 3.x

    IFS=$'\n' timezones=($(sort <<<"${timezones[*]}"))
    unset IFS
    echo "${timezones[@]}"
}

# Specialized timezone selection with pagination for long lists
# Args: $1 = region_name, $2 = array_name_containing_timezones, $3 = result_variable_name
select_timezone_from_list() {
    local region_name="$1"
    local array_name="$2"
    local result_var_name="$3"

    # Get array content using indirect expansion
    local timezone_array_content=()
    eval "timezone_array_content=( \"\${${array_name}[@]}\" )"

    if [ ${#timezone_array_content[@]} -eq 0 ]; then
        error_exit "No timezones provided for selection in region: $region_name"
    fi

    local total_timezones=${#timezone_array_content[@]}
    local items_per_page=20
    local current_page=0
    local total_pages=$(( (total_timezones + items_per_page - 1) / items_per_page ))

    log_info "Available timezones in $region_name:"
    
    if [ $total_timezones -gt $items_per_page ]; then
        log_info "Showing page 1 of $total_pages (20 items per page)"
        log_info "Commands: 'n' (next page), 'p' (previous page), 's' (search), or enter number (1-$total_timezones)"
    else
        log_info "Enter choice number (1-$total_timezones):"
    fi

    while true; do
        # Clear screen and show current page
        clear
        log_info "Available timezones in $region_name:"
        
        if [ $total_timezones -gt $items_per_page ]; then
            log_info "Page $((current_page + 1)) of $total_pages (showing items $((current_page * items_per_page + 1))-$(( (current_page + 1) * items_per_page < total_timezones ? (current_page + 1) * items_per_page : total_timezones )) of $total_timezones)"
        fi

        # Display current page
        local start_idx=$((current_page * items_per_page))
        local end_idx=$(( (current_page + 1) * items_per_page < total_timezones ? (current_page + 1) * items_per_page : total_timezones ))
        
        for ((i=start_idx; i<end_idx; i++)); do
            echo "  $((i+1)). ${timezone_array_content[$i]}"
        done

        if [ $total_timezones -gt $items_per_page ]; then
            echo ""
            echo "Commands: 'n' (next), 'p' (previous), 's' (search), 'q' (quit), or enter number (1-$total_timezones)"
        else
            echo ""
            echo "Enter choice number (1-$total_timezones):"
        fi

        local choice
        read -rp "> " choice
        choice=$(trim_string "$choice")

        # Handle navigation commands
        if [ "$choice" == "n" ] && [ $total_timezones -gt $items_per_page ]; then
            if [ $current_page -lt $((total_pages - 1)) ]; then
                current_page=$((current_page + 1))
                continue
            else
                log_warn "Already on the last page."
                sleep 1
                continue
            fi
        elif [ "$choice" == "p" ] && [ $total_timezones -gt $items_per_page ]; then
            if [ $current_page -gt 0 ]; then
                current_page=$((current_page - 1))
                continue
            else
                log_warn "Already on the first page."
                sleep 1
                continue
            fi
        elif [ "$choice" == "s" ] && [ $total_timezones -gt $items_per_page ]; then
            # Search functionality
            local search_term=""
            read -rp "Enter search term (case-insensitive): " search_term
            search_term=$(trim_string "$search_term")
            
            if [ -n "$search_term" ]; then
                log_info "Searching for timezones containing '$search_term'..."
                local found_count=0
                for ((i=0; i<total_timezones; i++)); do
                    if echo "${timezone_array_content[$i]}" | grep -qi "$search_term"; then
                        echo "  $((i+1)). ${timezone_array_content[$i]}"
                        found_count=$((found_count + 1))
                    fi
                done
                
                if [ $found_count -eq 0 ]; then
                    log_warn "No timezones found containing '$search_term'"
                else
                    log_info "Found $found_count matching timezone(s). Enter the number to select:"
                    read -rp "> " choice
                    choice=$(trim_string "$choice")
                fi
            fi
        elif [ "$choice" == "q" ]; then
            error_exit "Timezone selection cancelled by user."
        fi

        # Handle numeric selection
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total_timezones )); then
            # Assign result using indirect expansion
            eval "${result_var_name}=\"${timezone_array_content[$((choice-1))]}\""
            log_info "Selected: ${!result_var_name}"
            return 0
        else
            log_warn "Invalid choice. Please enter a number between 1 and $total_timezones"
            if [ $total_timezones -gt $items_per_page ]; then
                log_warn "or use 'n' (next), 'p' (previous), 's' (search), 'q' (quit)"
            fi
            sleep 2
        fi
    done
}

configure_wifi_live_dialog() {
    log_info "Initiating Wi-Fi setup using iwctl."
    log_info "Running 'iwctl device list' to find Wi-Fi devices..."
    local wifi_devices=$(iwctl device list | grep 'wireless' | awk '{print $1}')
    if [ -z "$wifi_devices" ]; then
        log_warn "No wireless devices found. Skipping Wi-Fi setup."
        return 0
    fi

    local wifi_device=""
    if [ $(echo "$wifi_devices" | wc -w) -gt 1 ]; then
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
    read -rp "Enter password for '$selected_ssid' (leave blank if none): " password
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


prompt_load_config() {
    local config_to_load=""
    
    local script_dir="$(dirname "${BASH_SOURCE[0]}")"
    local available_configs=()
    # For Bash 3.x, find -print0 | while IFS= read -r -d '' is problematic.
    # Use find -print | while IFS= read -r, but it's not robust for filenames with newlines.
    # For config files, newlines are highly unlikely in names.
    while IFS= read -r f; do
        local filename=$(basename "$f")
        if [[ "$filename" == *.sh ]] && \
           [[ "$filename" != "install_arch.sh" ]] && \
           [[ "$filename" != "config.sh" ]] && \
           [[ "$filename" != "utils.sh" ]] && \
           [[ "$filename" != "dialogs.sh" ]] && \
           [[ "$filename" != "disk_strategies.sh" ]] && \
           [[ "$filename" != "chroot_config.sh" ]]; then
            available_configs+=("$filename")
        fi
    done < <(find "$script_dir" -maxdepth 1 -type f -name "*.sh" -print) # Changed -print0 to -print

    if [ ${#available_configs[@]} -gt 0 ]; then
        available_configs+=("None (configure manually)")
        local config_choice_result=""
        select_option "Select a configuration file to load (or choose 'None' to configure manually):" available_configs config_choice_result

        if [ "$config_choice_result" == "None (configure manually)" ] || [ -z "$config_choice_result" ]; then
            log_info "Proceeding with manual configuration."
        else
            echo "$script_dir/$config_choice_result"
            return 0
        fi
    else
        log_info "No saved configuration files found in the current directory."
    fi

    local load_manual_path_choice=""
    prompt_yes_no "Do you want to load a configuration file from a specific path?" load_manual_path_choice
    if [ "$load_manual_path_choice" == "yes" ]; then
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


gather_installation_details() {
    log_header "SYSTEM & STORAGE CONFIGURATION"

    # Wi-Fi Connection (early, as it might be needed for reflector prereqs)
    prompt_yes_no "Do you want to connect to a Wi-Fi network now?" WANT_WIFI_CONNECTION
    if [ "$WANT_WIFI_CONNECTION" == "yes" ]; then
        configure_wifi_live_dialog || error_exit "Wi-Fi connection setup failed. Cannot proceed without internet."
    fi

    # Auto-detect boot mode, allow override for BIOS.
    # Boot mode is now detected and verified earlier in the installation process
    # This allows the user to override the detected boot mode if needed
    log_info "Current boot mode: $BOOT_MODE"
    
    prompt_yes_no "Force BIOS/Legacy boot mode instead of UEFI?" OVERRIDE_BOOT_MODE
    if [ "$OVERRIDE_BOOT_MODE" == "yes" ]; then
        BOOT_MODE="bios"
        log_warn "Forcing BIOS/Legacy boot mode."
    fi

    # Select primary installation disk.
    local available_disks=($(get_available_disks))
    if [ ${#available_disks[@]} -eq 0 ]; then
        error_exit "No suitable disks found for installation. Exiting."
    fi
    select_option "Select the primary installation disk:" available_disks INSTALL_DISK
    
    # Update TUI with disk selection
    local disk_size=$(lsblk -d -n -o SIZE "$INSTALL_DISK" 2>/dev/null || echo "Unknown")
    update_config "$INSTALL_DISK ($disk_size)" "Not selected" "$BOOT_MODE" "Not selected" "Not selected"

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

    # Update TUI with partitioning scheme
    local strategy_name=""
    case "$PARTITION_SCHEME" in
        auto_simple) strategy_name="Simple" ;;
        auto_luks_lvm) strategy_name="LUKS+LVM" ;;
        auto_raid_luks_lvm) strategy_name="RAID+LUKS+LVM" ;;
        manual) strategy_name="Manual" ;;
        *) strategy_name="$PARTITION_SCHEME" ;;
    esac
    local disk_size=$(lsblk -d -n -o SIZE "$INSTALL_DISK" 2>/dev/null || echo "Unknown")
    update_config "$INSTALL_DISK ($disk_size)" "$strategy_name" "$BOOT_MODE" "Not selected" "Not selected"

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
            if get_encryption_password; then
                LUKS_PASSPHRASE="$ENCRYPTION_PASSWORD"
                log_success "Encryption password input completed successfully"
            else
                error_exit "Encryption password input failed"
            fi
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
            if get_encryption_password; then
                LUKS_PASSPHRASE="$ENCRYPTION_PASSWORD"
                log_success "Encryption password input completed successfully"
            else
                error_exit "Encryption password input failed"
            fi
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
        select_option "Select filesystem for the root (/) partition:" FILESYSTEM_OPTIONS ROOT_FILESYSTEM_TYPE
        if [ "$?" -ne 0 ]; then
            error_exit "Root filesystem selection failed."
        fi

        if [ "$WANT_HOME_PARTITION" == "yes" ]; then
            local default_home_fs_choice="$ROOT_FILESYSTEM_TYPE"
            select_option "Select filesystem for the /home partition (default: $default_home_fs_choice):" FILESYSTEM_OPTIONS HOME_FILESYSTEM_TYPE_TEMP
            if [ "$?" -ne 0 ]; then
                error_exit "Home filesystem selection failed."
            fi
            if [ -z "$HOME_FILESYSTEM_TYPE_TEMP" ]; then
                HOME_FILESYSTEM_TYPE="$default_home_fs_choice"
            else
                HOME_FILESYSTEM_TYPE="$HOME_FILESYSTEM_TYPE_TEMP"
            fi
        fi
    fi

    # Btrfs Snapshot Configuration
    if [ "$ROOT_FILESYSTEM_TYPE" == "btrfs" ] || [ "$HOME_FILESYSTEM_TYPE" == "btrfs" ]; then
        log_info "Btrfs filesystem detected. Configuring snapshot options."
        
        prompt_yes_no "Do you want to enable automatic Btrfs snapshots?" WANT_BTRFS_SNAPSHOTS
        if [ "$WANT_BTRFS_SNAPSHOTS" == "yes" ]; then
            log_info "Btrfs snapshots provide system recovery capabilities and automatic backups."
            log_info "This will install snapper and grub-btrfs for snapshot management."
            
            select_option "Select snapshot frequency:" BTRFS_SNAPSHOT_FREQUENCY_OPTIONS BTRFS_SNAPSHOT_FREQUENCY
            
            prompt_number "How many snapshots should be kept? (default: 10)" BTRFS_KEEP_SNAPSHOTS "10"
            
            prompt_yes_no "Do you want to install btrfs-assistant (AUR) for GUI snapshot management?" WANT_BTRFS_ASSISTANT
            
            if [ "$BOOTLOADER_TYPE" == "grub" ]; then
                log_info "GRUB bootloader detected. Snapshots will be available in the boot menu for system recovery."
            else
                log_warn "systemd-boot detected. Snapshot boot menu integration is limited."
                log_warn "Consider using GRUB for better snapshot recovery options."
            fi
        fi
    fi

    log_header "BASE SYSTEM & USER CONFIGURATION"

    # Kernel Type (rolling vs. LTS).
    select_option "Choose your preferred kernel:" KERNEL_TYPES_OPTIONS KERNEL_TYPE
    if [ "$?" -ne 0 ]; then
        error_exit "Kernel type selection failed."
    fi

    # Timezone Configuration.
    log_info "Configuring system timezone."
    local selected_region=""
    select_option "Select your primary geographical region:" TIMEZONE_REGIONS selected_region
    if [ "$?" -ne 0 ]; then
        error_exit "Timezone region selection failed."
    fi

    # Get all timezones for the selected region
    local region_timezones=($(get_timezones_in_region "$selected_region"))
    
    if [ ${#region_timezones[@]} -eq 0 ]; then
        error_exit "No timezones found for region '$selected_region'"
    fi

    # Use specialized timezone selection for long lists
    local selected_timezone=""
    select_timezone_from_list "$selected_region" region_timezones selected_timezone
    if [ "$?" -ne 0 ]; then
        error_exit "Timezone selection failed."
    fi

    TIMEZONE="$selected_timezone"
    log_info "System timezone set to: $TIMEZONE"

    # Localization (Locale & Keymap).
    log_info "Setting system locale."
    select_option "Select primary system locale:" LOCALE_OPTIONS LOCALE
    if [ "$?" -ne 0 ]; then # Check for select_option failure
        error_exit "Locale selection failed."
    fi

    log_info "Setting console keymap."
    select_option "Select console keymap:" KEYMAP_OPTIONS KEYMAP
    if [ "$?" -ne 0 ]; then # Check for select_option failure
        error_exit "Keymap selection failed."
    fi

    # Reflector Country Code (Mirrorlist) - Intelligent suggestion based on timezone.
    log_info "Configuring pacman mirror country."
    
    # Suggest mirror country based on selected timezone
    local suggested_country=$(suggest_mirror_country_from_timezone "$TIMEZONE")
    log_info "Based on your timezone ($TIMEZONE), I suggest using $suggested_country mirrors for faster downloads."
    
    local use_suggested_mirror_country=""
    prompt_yes_no "Use suggested mirror country ($suggested_country) for faster downloads? " use_suggested_mirror_country

    if [ "$use_suggested_mirror_country" == "yes" ]; then
        REFLECTOR_COUNTRY_CODE="$suggested_country"
        log_info "Using suggested mirror country: $REFLECTOR_COUNTRY_CODE"
    else
        log_info "Available countries for reflector:"
        local temp_reflector_country_choice=""
        select_option "Select preferred mirror country code:" REFLECTOR_COMMON_COUNTRIES temp_reflector_country_choice
        if [ "$?" -ne 0 ]; then # Check for select_option failure
            error_exit "Mirror country selection failed."
        fi
        REFLECTOR_COUNTRY_CODE="$temp_reflector_country_choice"
        if [ -z "$REFLECTOR_COUNTRY_CODE" ]; then
            log_warn "No country code selected. Using suggested country: $suggested_country"
            REFLECTOR_COUNTRY_CODE="$suggested_country"
        fi
    fi

    log_header "DESKTOP & USER ACCOUNT CONFIGURATION"

    # User Credentials - Gather user account information
    log_info "Gathering user account information..."
    log_info "DEBUG: About to call get_username function..."
    
    if get_username; then
        log_success "Username input completed successfully"
    else
        error_exit "Username input failed"
    fi
    
    if get_user_password; then
        log_success "User password input completed successfully"
    else
        error_exit "User password input failed"
    fi
    
    if get_root_password; then
        log_success "Root password input completed successfully"
    else
        error_exit "Root password input failed"
    fi
    
    if get_hostname; then
        log_success "Hostname input completed successfully"
    else
        error_exit "Hostname input failed"
    fi
    
    # Map user management variables to archinstall variables
    MAIN_USERNAME="$USERNAME"
    MAIN_USER_PASSWORD="$USER_PASSWORD"
    SYSTEM_HOSTNAME="$HOSTNAME"
    
    # Export the credentials immediately
    export MAIN_USERNAME
    export MAIN_USER_PASSWORD
    export ROOT_PASSWORD
    export SYSTEM_HOSTNAME
    
    # Update TUI with username
    local disk_size=$(lsblk -d -n -o SIZE "$INSTALL_DISK" 2>/dev/null || echo "Unknown")
    local strategy_name=""
    case "$PARTITION_SCHEME" in
        auto_simple) strategy_name="Simple" ;;
        auto_luks_lvm) strategy_name="LUKS+LVM" ;;
        auto_raid_luks_lvm) strategy_name="RAID+LUKS+LVM" ;;
        manual) strategy_name="Manual" ;;
        *) strategy_name="$PARTITION_SCHEME" ;;
    esac
    local desktop_name=""
    case "$DESKTOP_ENVIRONMENT" in
        gnome) desktop_name="GNOME" ;;
        kde) desktop_name="KDE Plasma" ;;
        hyprland) desktop_name="Hyprland" ;;
        none) desktop_name="None" ;;
        *) desktop_name="$DESKTOP_ENVIRONMENT" ;;
    esac
    update_config "$INSTALL_DISK ($disk_size)" "$strategy_name" "$BOOT_MODE" "$desktop_name" "$MAIN_USERNAME"

    # Debug: Show what we just set
    log_info "Debug - Variables set in dialogs:"
    log_info "  MAIN_USERNAME: '${MAIN_USERNAME:-NOT_SET}'"
    log_info "  ROOT_PASSWORD: '${ROOT_PASSWORD:+SET}' (length: ${#ROOT_PASSWORD})"
    log_info "  MAIN_USER_PASSWORD: '${MAIN_USER_PASSWORD:+SET}' (length: ${#MAIN_USER_PASSWORD})"
    log_info "  SYSTEM_HOSTNAME: '${SYSTEM_HOSTNAME:-NOT_SET}'"

    log_success "User account configuration completed successfully"

    # Desktop Environment and Display Manager.
    select_option "Select Desktop Environment:" DESKTOP_ENVIRONMENTS_OPTIONS DESKTOP_ENVIRONMENT
    if [ "$?" -ne 0 ]; then # Check for select_option failure
        error_exit "Desktop Environment selection failed."
    fi
    
    # Update TUI with desktop environment selection
    local desktop_name=""
    case "$DESKTOP_ENVIRONMENT" in
        gnome) desktop_name="GNOME" ;;
        kde) desktop_name="KDE Plasma" ;;
        hyprland) desktop_name="Hyprland" ;;
        none) desktop_name="None" ;;
        *) desktop_name="$DESKTOP_ENVIRONMENT" ;;
    esac
    local disk_size=$(lsblk -d -n -o SIZE "$INSTALL_DISK" 2>/dev/null || echo "Unknown")
    local strategy_name=""
    case "$PARTITION_SCHEME" in
        auto_simple) strategy_name="Simple" ;;
        auto_luks_lvm) strategy_name="LUKS+LVM" ;;
        auto_raid_luks_lvm) strategy_name="RAID+LUKS+LVM" ;;
        manual) strategy_name="Manual" ;;
        *) strategy_name="$PARTITION_SCHEME" ;;
    esac
    update_config "$INSTALL_DISK ($disk_size)" "$strategy_name" "$BOOT_MODE" "$desktop_name" "Not selected"
    if [ "$DESKTOP_ENVIRONMENT" != "none" ]; then
        case "$DESKTOP_ENVIRONMENT" in
            gnome) DISPLAY_MANAGER="gdm";;
            kde|hyprland) DISPLAY_MANAGER="sddm";;
            * ) DISPLAY_MANAGER="none";;
        esac
        select_option "Select Display Manager (default: $DISPLAY_MANAGER):" DISPLAY_MANAGER_OPTIONS DISPLAY_MANAGER
        if [ "$?" -ne 0 ]; then # Check for select_option failure
            error_exit "Display Manager selection failed."
        fi
    else
        DISPLAY_MANAGER="none"
    fi

    # Bootloader.
    select_option "Select Bootloader:" BOOTLOADER_TYPES_OPTIONS BOOTLOADER_TYPE
    if [ "$?" -ne 0 ]; then # Check for select_option failure
        error_exit "Bootloader selection failed."
    fi
    if [ "$BOOTLOADER_TYPE" == "grub" ]; then
        prompt_yes_no "Enable OS Prober for dual-boot detection (recommended for dual-boot systems)?" ENABLE_OS_PROBER
    fi
    
    # Time Synchronization Choice
    echo ""
    echo "=== Time Synchronization ==="
    echo "Choose your time synchronization method:"
    echo "  1) ntpd - Traditional NTP daemon (recommended for precision)"
    echo "  2) chrony - Modern NTP client with better accuracy"
    echo "  3) systemd-timesyncd - Lightweight built-in option"
    echo ""
    while true; do
        echo -n "Enter choice (1-3) [1]: "
        read -r choice
        case "$choice" in
            "1"|"")
                TIME_SYNC_CHOICE="ntpd"
                break
                ;;
            "2")
                TIME_SYNC_CHOICE="chrony"
                break
                ;;
            "3")
                TIME_SYNC_CHOICE="systemd-timesyncd"
                break
                ;;
            *)
                echo "Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
    echo "Selected: $TIME_SYNC_CHOICE"
    
    
    
    
    # Secure Boot (only for UEFI systems)
    if [ "$BOOT_MODE" == "uefi" ]; then
        echo ""
        echo "=== SECURE BOOT WARNING ==="
        echo "Secure Boot is ONLY needed if:"
        echo "  - You dual-boot with Windows 11"
        echo "  - You play games that require TPM/Secure Boot"
        echo "  - You have enterprise security requirements"
        echo ""
        echo "IMPORTANT: Before enabling Secure Boot:"
        echo "  1. Disable Secure Boot in your UEFI firmware"
        echo "  2. Clear all existing Secure Boot keys"
        echo "  3. Ensure your motherboard supports custom key enrollment"
        echo ""
        echo "WARNING: If not configured properly, your system may not boot!"
        echo "Most users should answer 'no' to this question."
        echo ""
        prompt_yes_no "Do you understand the risks and want to enable Secure Boot?" WANT_SECURE_BOOT
    fi


    # Multilib Support (32-bit).
    prompt_yes_no "Enable 32-bit support (multilib repository)?" WANT_MULTILIB

    # AUR Helper.
    prompt_yes_no "Install an AUR helper (e.g., yay)?" WANT_AUR_HELPER
    if [ "$WANT_AUR_HELPER" == "yes" ]; then
        select_option "Select AUR Helper:" AUR_HELPERS_OPTIONS AUR_HELPER_CHOICE
        if [ "$?" -ne 0 ]; then # Check for select_option failure
            error_exit "AUR Helper selection failed."
        fi
    fi

    # Flatpak Support.
    prompt_yes_no "Install Flatpak support?" WANT_FLATPAK

    # Interactive Package Selection
    prompt_yes_no "Do you want to install additional packages interactively?" INSTALL_CUSTOM_PACKAGES
    if [ "$INSTALL_CUSTOM_PACKAGES" == "yes" ]; then
        select_custom_packages
    fi

    # Interactive AUR Package Selection
    if [ "$WANT_AUR_HELPER" == "yes" ]; then
        prompt_yes_no "Do you want to install additional AUR packages interactively?" INSTALL_CUSTOM_AUR_PACKAGES
        if [ "$INSTALL_CUSTOM_AUR_PACKAGES" == "yes" ]; then
            select_custom_aur_packages
        fi
    fi

    # GRUB Theming.
    if [ "$BOOTLOADER_TYPE" == "grub" ]; then
        prompt_yes_no "Install a GRUB theme?" WANT_GRUB_THEME
        if [ "$WANT_GRUB_THEME" == "yes" ]; then
            select_option "Select GRUB Theme:" GRUB_THEME_OPTIONS GRUB_THEME_CHOICE
            if [ "$?" -ne 0 ]; then # Check for select_option failure
                error_exit "GRUB Theme selection failed."
            fi
        fi
    fi

    # Plymouth Boot Splash.
    prompt_yes_no "Install Plymouth boot splash screen?" WANT_PLYMOUTH
    if [ "$WANT_PLYMOUTH" == "yes" ]; then
        prompt_yes_no "Install Arch Glow Plymouth theme?" WANT_PLYMOUTH_THEME
        if [ "$WANT_PLYMOUTH_THEME" == "yes" ]; then
            select_option "Select Plymouth Theme:" PLYMOUTH_THEME_OPTIONS PLYMOUTH_THEME_CHOICE
            if [ "$?" -ne 0 ]; then # Check for select_option failure
                error_exit "Plymouth Theme selection failed."
            fi
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
    if [ "$ROOT_FILESYSTEM_TYPE" == "btrfs" ] || [ "$HOME_FILESYSTEM_TYPE" == "btrfs" ]; then
        echo "    Btrfs Snapshots:    $WANT_BTRFS_SNAPSHOTS"
        if [ "$WANT_BTRFS_SNAPSHOTS" == "yes" ]; then
            echo "      Frequency:        $BTRFS_SNAPSHOT_FREQUENCY"
            echo "      Keep Count:       $BTRFS_KEEP_SNAPSHOTS"
            echo "      GUI Tool:         $WANT_BTRFS_ASSISTANT"
        fi
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
    echo "  Plymouth Boot Splash: $WANT_PLYMOUTH"
    if [ "$WANT_PLYMOUTH" == "yes" ] && [ "$WANT_PLYMOUTH_THEME" == "yes" ]; then
        echo "    Plymouth Theme:     $PLYMOUTH_THEME_CHOICE"
    fi
    if [ "$BOOT_MODE" == "uefi" ]; then
        echo "    Secure Boot:        $WANT_SECURE_BOOT"
    fi
    echo "    Time Sync:          $TIME_SYNC_CHOICE"
    echo "    Timezone:           $TIMEZONE"
    echo "    Locale:             $LOCALE"
    echo "    Keymap:             $KEYMAP"
    echo "    Hostname:           $SYSTEM_HOSTNAME"
    echo "    Mirror Country:     $REFLECTOR_COUNTRY_CODE"
    echo "    CPU Microcode:      $CPU_MICROCODE_TYPE"
    echo "    Desktop Environment: $DESKTOP_ENVIRONMENT"
    echo "    Display Manager:    $DISPLAY_MANAGER"
    echo "  Multilib:             $WANT_MULTILIB"
    echo "  AUR Helper:           $WANT_AUR_HELPER"
    if [ "$WANT_AUR_HELPER" == "yes" ]; then
        echo "    AUR Helper Type:    $AUR_HELPER_CHOICE"
    fi
    echo "  Flatpak:              $WANT_FLATPAK"
    echo "  Custom Packages:      $INSTALL_CUSTOM_PACKAGES"
    if [ "$INSTALL_CUSTOM_PACKAGES" == "yes" ] && [ -n "$CUSTOM_PACKAGES" ]; then
        echo "    List:               $CUSTOM_PACKAGES"
    fi
    echo "  Custom AUR Packages:  $INSTALL_CUSTOM_AUR_PACKAGES"
    if [ "$INSTALL_CUSTOM_AUR_PACKAGES" == "yes" ] && [ -n "$CUSTOM_AUR_PACKAGES" ]; then
        echo "    List:               $CUSTOM_AUR_PACKAGES"
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
    if [ "$WANT_SECURE_BOOT" == "yes" ]; then
        echo ""
        echo "⚠️  SECURE BOOT WARNING ⚠️"
        echo "You enabled Secure Boot during installation."
        echo "Your system will boot normally, but Secure Boot is NOT yet enabled."
        echo ""
        echo "IMPORTANT: After first boot, you must:"
        echo "1. Read /root/SECURE_BOOT_SETUP.md"
        echo "2. Run: sbctl enroll-keys"
        echo "3. Enable Secure Boot in UEFI firmware"
        echo ""
        echo "If you don't complete these steps, Secure Boot will not work."
        echo ""
    fi
    
    # Show log access information
    echo ""
    echo "📋 LOG FILES PRESERVED:"
    echo "   Primary Log:    /var/log/archinstall.log"
    echo "   Backup Log:     /tmp/archinstall.log"
    echo "   Summary File:   /tmp/archinstall-summary.txt"
    echo ""
    echo "   To view logs:"
    echo "     cat /tmp/archinstall.log"
    echo "     tail -f /tmp/archinstall.log"
    echo ""
    
    prompt_yes_no "Installation complete. Reboot now?" REBOOT_NOW
    if [ "$REBOOT_NOW" == "yes" ]; then
        log_info "Rebooting..."
        reboot
    else
        log_info "Please reboot manually when ready. Exiting."
    fi
}





# --- Interactive Package Selection Functions ---

# Searches for packages using pacman -Ss
search_packages() {
    local search_term="$1"
    local results_file="/tmp/package_search_results.txt"
    
    echo "Searching for packages matching: $search_term"
    pacman -Ss "$search_term" > "$results_file" 2>/dev/null
    
    if [ ! -s "$results_file" ]; then
        echo "No packages found matching: $search_term"
        return 1
    fi
    
    # Display results with line numbers
    echo "Search results:"
    echo "==============="
    nl -w3 -s": " "$results_file"
    echo "==============="
    return 0
}

# Searches for AUR packages using available AUR helper or curl
search_aur_packages() {
    local search_term="$1"
    local results_file="/tmp/aur_search_results.txt"
    
    echo "Searching AUR for packages matching: $search_term"
    
    # Method 1: Try using available AUR helper
    if command -v paru &> /dev/null; then
        paru -Ss "$search_term" > "$results_file" 2>/dev/null
    elif command -v yay &> /dev/null; then
        yay -Ss "$search_term" > "$results_file" 2>/dev/null
    else
        # Method 2: Use curl to search AUR web interface (fallback)
        echo "AUR helper not available, using web search as fallback..."
        local aur_url="https://aur.archlinux.org/rpc/?v=5&type=search&arg=$search_term"
        
        if command -v curl &> /dev/null; then
            # Use curl to search AUR API
            curl -s "$aur_url" | grep -o '"Name":"[^"]*"' | sed 's/"Name":"//g' | sed 's/"//g' > "$results_file" 2>/dev/null
            
            if [ ! -s "$results_file" ]; then
                echo "No AUR packages found matching: $search_term"
                return 1
            fi
            
            # Display results
            echo "AUR search results (from web API):"
            echo "=================================="
            nl -w3 -s": " "$results_file"
            echo "=================================="
            echo "Note: This is a basic search. For detailed package info, install an AUR helper first."
            return 0
        else
            echo "Neither AUR helper nor curl available for AUR search."
            echo "Please install an AUR helper (yay/paru) or curl first."
            return 1
        fi
    fi
    
    if [ ! -s "$results_file" ]; then
        echo "No AUR packages found matching: $search_term"
        return 1
    fi
    
    # Display results with line numbers
    echo "AUR search results:"
    echo "=================="
    nl -w3 -s": " "$results_file"
    echo "=================="
    return 0
}

# Interactive package selection for official repositories
select_custom_packages() {
    echo "=== Interactive Package Selection ==="
    echo "You can search for packages and add them to your installation."
    echo "Commands:"
    echo "  search <term>  - Search for packages"
    echo "  add <package>  - Add package to installation list"
    echo "  remove <package> - Remove package from installation list"
    echo "  list           - Show current package list"
    echo "  done           - Finish package selection"
    echo ""
    
    local selected_packages=()
    local continue_selection=true
    
    while [ "$continue_selection" == "true" ]; do
        echo -n "Package selection> "
        read -r command package_name
        
        case "$command" in
            "search")
                if [ -n "$package_name" ]; then
                    search_packages "$package_name"
                else
                    echo "Usage: search <search_term>"
                fi
                ;;
            "add")
                if [ -n "$package_name" ]; then
                    # Check if package exists
                    if pacman -Si "$package_name" &>/dev/null; then
                        selected_packages+=("$package_name")
                        echo "Added: $package_name"
                    else
                        echo "Package \"$package_name\" not found in official repositories"
                    fi
                else
                    echo "Usage: add <package_name>"
                fi
                ;;
            "remove")
                if [ -n "$package_name" ]; then
                    local found=false
                    local new_packages=()
                    for pkg in "${selected_packages[@]}"; do
                        if [ "$pkg" != "$package_name" ]; then
                            new_packages+=("$pkg")
                        else
                            found=true
                        fi
                    done
                    selected_packages=("${new_packages[@]}")
                    if [ "$found" == "true" ]; then
                        echo "Removed: $package_name"
                    else
                        echo "Package \"$package_name\" not in selection list"
                    fi
                else
                    echo "Usage: remove <package_name>"
                fi
                ;;
            "list")
                if [ ${#selected_packages[@]} -eq 0 ]; then
                    echo "No packages selected"
                else
                    echo "Selected packages:"
                    for pkg in "${selected_packages[@]}"; do
                        echo "  - $pkg"
                    done
                fi
                ;;
            "done")
                continue_selection=false
                ;;
            *)
                echo "Unknown command: $command"
                echo "Available commands: search, add, remove, list, done"
                ;;
        esac
        echo ""
    done
    
    # Set the global variable
    if [ ${#selected_packages[@]} -gt 0 ]; then
        CUSTOM_PACKAGES="${selected_packages[*]}"
        echo "Final package selection: $CUSTOM_PACKAGES"
    else
        CUSTOM_PACKAGES=""
        echo "No packages selected"
    fi
}

# Interactive package selection for AUR repositories
select_custom_aur_packages() {
    echo "=== Interactive AUR Package Selection ==="
    echo "You can search for AUR packages and add them to your installation."
    echo "Commands:"
    echo "  search <term>  - Search AUR for packages"
    echo "  add <package>  - Add AUR package to installation list"
    echo "  remove <package> - Remove AUR package from installation list"
    echo "  list           - Show current AUR package list"
    echo "  done           - Finish AUR package selection"
    echo ""
    
    local selected_aur_packages=()
    local continue_selection=true
    
    while [ "$continue_selection" == "true" ]; do
        echo -n "AUR package selection> "
        read -r command package_name
        
        case "$command" in
            "search")
                if [ -n "$package_name" ]; then
                    search_aur_packages "$package_name"
                else
                    echo "Usage: search <search_term>"
                fi
                ;;
            "add")
                if [ -n "$package_name" ]; then
                    # For AUR packages, we cannot easily verify existence without the helper
                    # So we will just add it and let the installation process handle errors
                    selected_aur_packages+=("$package_name")
                    echo "Added: $package_name (will be verified during installation)"
                else
                    echo "Usage: add <package_name>"
                fi
                ;;
            "remove")
                if [ -n "$package_name" ]; then
                    local found=false
                    local new_packages=()
                    for pkg in "${selected_aur_packages[@]}"; do
                        if [ "$pkg" != "$package_name" ]; then
                            new_packages+=("$pkg")
                        else
                            found=true
                        fi
                    done
                    selected_aur_packages=("${new_packages[@]}")
                    if [ "$found" == "true" ]; then
                        echo "Removed: $package_name"
                    else
                        echo "Package \"$package_name\" not in selection list"
                    fi
                else
                    echo "Usage: remove <package_name>"
                fi
                ;;
            "list")
                if [ ${#selected_aur_packages[@]} -eq 0 ]; then
                    echo "No AUR packages selected"
                else
                    echo "Selected AUR packages:"
                    for pkg in "${selected_aur_packages[@]}"; do
                        echo "  - $pkg"
                    done
                fi
                ;;
            "done")
                continue_selection=false
                ;;
            *)
                echo "Unknown command: $command"
                echo "Available commands: search, add, remove, list, done"
                ;;
        esac
        echo ""
    done
    
    # Set the global variable
    if [ ${#selected_aur_packages[@]} -gt 0 ]; then
        CUSTOM_AUR_PACKAGES="${selected_aur_packages[*]}"
        echo "Final AUR package selection: $CUSTOM_AUR_PACKAGES"
    else
        CUSTOM_AUR_PACKAGES=""
        echo "No AUR packages selected"
    fi
}

# --- Utility Functions ---
# Prompts for a number input with default value
prompt_number() {
    local prompt_text="$1"
    local variable_name="$2"
    local default_value="$3"
    
    echo ""
    echo "$prompt_text"
    read -p "Enter number [$default_value]: " user_input
    
    if [ -z "$user_input" ]; then
        user_input="$default_value"
    fi
    
    # Validate that input is a number
    if ! [[ "$user_input" =~ ^[0-9]+$ ]]; then
        log_error "Invalid number: $user_input. Using default: $default_value"
        user_input="$default_value"
    fi
    
    # Set the variable
    eval "$variable_name=\"$user_input\""
    log_info "Set $variable_name to: $user_input"
}
