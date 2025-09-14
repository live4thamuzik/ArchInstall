#!/bin/bash
# utils.sh - General helper functions for Archl4tm rewrite (Bash 3.x Compatible)

# ANSI escape codes for colors
readonly C_INFO='\e[32m'
readonly C_WARN='\e[33m'
readonly C_ERROR='\e[31m'
readonly C_HEADER='\e[36;1m'
readonly C_SUCCESS='\e[32;1m'
readonly C_RESET='\e[0m'

# Enhanced logging system
log_message() {
    local level="$1"
    local message="$2"
    local exit_code="${3:-0}"  # Default to 0 if not provided
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Get function name and line number
    local caller_info="${FUNCNAME[2]:-main}:${BASH_LINENO[1]:-0}"

    # Capture last command output if error
    local last_cmd_output=""
    if [[ "$level" == "ERROR" && "$exit_code" -ne 0 ]]; then
        last_cmd_output=$(journalctl -n 3 --no-pager 2>/dev/null || echo "No journal output available")
    fi

    # Determine log level color
    local color=""
    case "$level" in
        INFO) color="$C_INFO" ;;
        WARN) color="$C_WARN" ;;
        ERROR) color="$C_ERROR" ;;
        DEBUG) color="$C_HEADER" ;;
        *) color="$C_RESET" ;;
    esac

    # Format log message
    local log_entry="[$timestamp] [$level] [$caller_info] Exit Code: $exit_code - $message"

    # Append command output for errors
    if [[ "$level" == "ERROR" && "$last_cmd_output" != "" ]]; then
        log_entry+=" | Last Output: $last_cmd_output"
    fi

    # Print to terminal (with color)
    echo -e "${color}${log_entry}${C_RESET}"

    # Append to log file if LOG_FILE is set
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "$log_entry" >> "$LOG_FILE"
    fi
}

log_info() { log_message "INFO" "$1"; }
log_warn() { log_message "WARN" "$1"; }
log_error() { log_message "ERROR" "$1" "$?"; }
log_debug() { log_message "DEBUG" "$1"; }

error_exit() {
    log_error "$*"
    exit 1
}

# Enhanced command execution with automatic error capture
run() {
    local cmd="$*"
    log_debug "Executing: $cmd"
    
    # Execute command and capture output
    if "$@" 2>/tmp/last_command_output; then
        log_debug "Command succeeded: $cmd"
        return 0
    else
        local exit_code=$?
        local output=""
        if [[ -f /tmp/last_command_output ]]; then
            output=$(cat /tmp/last_command_output)
        fi
        log_error "Command failed: $cmd (exit code: $exit_code)"
        if [[ -n "$output" ]]; then
            log_error "Command output: $output"
        fi
        return $exit_code
    fi
}

log_header() {
    echo -e "\n${C_HEADER}==================================================${C_RESET}"
    echo -e "${C_HEADER} $* ${C_RESET}"
    echo -e "${C_HEADER}==================================================${C_RESET}\n"
}

log_success() {
    echo -e "\n${C_SUCCESS}==================================================${C_RESET}"
    echo -e "${C_SUCCESS} $* ${C_RESET}"
    echo -e "${C_SUCCESS}==================================================${C_RESET}\n"
}

# Progress indicator function
show_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    local percentage=$((current * 100 / total))
    local bar_length=50
    local filled_length=$((percentage * bar_length / 100))
    
    # Create progress bar
    local bar=""
    for ((i=0; i<filled_length; i++)); do
        bar+="█"
    done
    for ((i=filled_length; i<bar_length; i++)); do
        bar+="░"
    done
    
    # Print progress
    printf "\r${C_INFO}[%3d%%]${C_RESET} [%s] %s (%d/%d)" "$percentage" "$bar" "$description" "$current" "$total"
    
    # Add newline when complete
    if [[ "$current" -eq "$total" ]]; then
        echo ""
    fi
}

# --- Password Management ---
# Robust password setting function
set_password_chroot() {
    local username="$1"
    local password="$2"
    
    log_info "Setting password for user: $username"
    
    # Method 1: Try the standard chpasswd approach first
    if echo "$username:$password" | chpasswd 2>/dev/null; then
        log_info "Password set successfully for $username using chpasswd."
        return 0
    fi
    
    # Method 2: If chpasswd fails, try using passwd with expect (more reliable in chroot)
    log_info "chpasswd failed, trying alternative method with passwd..."
    
    # Check if expect is available, install if needed
    if ! command -v expect >/dev/null 2>&1; then
        log_info "Installing expect for password setting..."
        pacman -S --noconfirm expect >/dev/null 2>&1 || log_warn "Failed to install expect"
    fi
    
    # Use expect to handle the interactive passwd command
    if command -v expect >/dev/null 2>&1; then
        log_info "Using expect to set password for $username..."
        expect << EOF
spawn passwd $username
expect "New password:"
send "$password\r"
expect "Retype new password:"
send "$password\r"
expect eof
EOF
        if [ $? -eq 0 ]; then
            log_info "Password set successfully for $username using expect."
            return 0
        fi
    fi
    
    # Method 3: Direct shadow file manipulation (last resort)
    log_info "Trying direct shadow file manipulation..."
    if [ -f /etc/shadow ]; then
        # Generate password hash using openssl
        local password_hash
        password_hash=$(openssl passwd -6 "$password" 2>/dev/null)
        if [ -n "$password_hash" ]; then
            # Update shadow file
            local shadow_line
            shadow_line=$(grep "^$username:" /etc/shadow)
            if [ -n "$shadow_line" ]; then
                local new_shadow_line
                new_shadow_line=$(echo "$shadow_line" | sed "s|^$username:[^:]*|$username:$password_hash|")
                sed -i "s|^$username:.*|$new_shadow_line|" /etc/shadow
                log_info "Password set successfully for $username using shadow file manipulation."
                return 0
            fi
        fi
    fi
    
    # All methods failed
    log_error "All password setting methods failed for '$username'."
    log_error "Tried: chpasswd, expect, and shadow file manipulation."
    return 1
}

# --- System Checks ---
check_prerequisites() {
    log_info "Checking prerequisites..."
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root."
    fi

    log_info "Checking internet connection (pinging archlinux.org)..."
    if ! ping -c 1 -W 2 archlinux.org &>/dev/null; then
        error_exit "No active internet connection detected."
    fi
    log_info "Prerequisites met."
}

# Enhanced validation functions

validate_disk() {
    local disk="$1"
    if [ -b "$disk" ]; then
        return 0  # True
    else
        log_error "Invalid disk path: $disk"
        return 1  # False
    fi
}

# Enhanced confirmation function
confirm_action() {
    local message="$1"
    read -r -p "$message (Y/n) " confirm
    confirm=${confirm,,}  # Convert to lowercase

    # Check if confirm is "y" or empty
    if [[ "$confirm" == "y" ]] || [[ -z "$confirm" ]]; then
        log_info "User confirmed: $message"
        return 0  # True
    else
        log_warn "User declined: $message"
        return 1  # False
    fi
}

# --- Disk Utilities ---

# Returns "nvme" or "sd" or "unknown" based on device path.
get_device_type() {
    local dev_path="$1"
    # Bash 3.x compatible regex
    if echo "$dev_path" | grep -q "^/dev/nvme[0-9]\+n[0-9]\+$"; then
        echo "nvme"
    elif echo "$dev_path" | grep -q "^/dev/sd[a-z]\+$"; then
        echo "sd"
    else
        echo "unknown"
    fi
}

# Constructs the full partition path based on disk type.
# Args: $1 = base_disk (e.g., /dev/sda, /dev/nvme0n1), $2 = partition_number (e.g., 1, 2)
get_partition_path() {
    local base_disk="$1"
    local part_num="$2"
    local full_path=""

    local dev_type=$(get_device_type "$base_disk")
    if [ "$dev_type" == "nvme" ]; then
        full_path="${base_disk}p${part_num}"
    elif [ "$dev_type" == "sd" ]; then
        full_path="${base_disk}${part_num}"
    else
        error_exit "Unsupported disk type for partition path construction: $base_disk."
    fi
    echo "$full_path"
}

# Wipes a disk of signatures and partition tables.
# Args: $1 = disk_path (e.g., /dev/sda)
wipe_disk() {
    local disk_path="$1"
    log_info "Wiping existing data and signatures from $disk_path..."
    wipefs -af "$disk_path" &>/dev/null || log_warn "wipefs failed for $disk_path."

    if [ -b "$disk_path" ]; then
        sgdisk -Z "$disk_path" &>/dev/null || log_warn "sgdisk -Z failed for $disk_path."
        dd if=/dev/zero of="$disk_path" bs=512 count=1 conv=notrunc &>/dev/null || log_warn "dd zeroing MBR failed for $disk_path."
    else
        error_exit "Disk device $disk_path not found or not a block device."
    fi
    log_info "Disk $disk_path wiped."
}

# Formats a device with a specified filesystem.
# Args: $1 = dev_path, $2 = fs_type (e.g., "ext4", "vfat", "swap")
format_filesystem() {
    local dev_path="$1"
    local fs_type="$2"

    log_info "Formatting $dev_path as $fs_type..."
    case "$fs_type" in
        ext4)   mkfs.ext4 -F "$dev_path" || error_exit "Failed to format $dev_path as ext4.";;
        xfs)    mkfs.xfs -f "$dev_path" || error_exit "Failed to format $dev_path as xfs.";;
        btrfs)  mkfs.btrfs -f "$dev_path" || error_exit "Failed to format $dev_path as btrfs.";;
        vfat)   mkfs.fat -F32 "$dev_path" || error_exit "Failed to format $dev_path as vfat.";;
        swap)   mkswap "$dev_path" || error_exit "Failed to create swap on $dev_path.";;
        *)      error_exit "Unsupported filesystem type for formatting: $fs_type.";;
    esac
    log_info "$dev_path formatted as $fs_type."
}

# Creates Btrfs subvolumes for root and home
# Args: $1 = mount_point (e.g., "/mnt")
create_btrfs_subvolumes() {
    local mount_point="$1"
    
    log_info "Creating Btrfs subvolumes..."
    
    # Create root subvolume
    btrfs subvolume create "$mount_point/@root" || error_exit "Failed to create @root subvolume"
    log_info "Created @root subvolume"
    
    # Create home subvolume
    btrfs subvolume create "$mount_point/@home" || error_exit "Failed to create @home subvolume"
    log_info "Created @home subvolume"
    
    # Create snapshots subvolume
    btrfs subvolume create "$mount_point/@snapshots" || error_exit "Failed to create @snapshots subvolume"
    log_info "Created @snapshots subvolume"
    
    # Create var/log subvolume (for system logs)
    btrfs subvolume create "$mount_point/@var_log" || error_exit "Failed to create @var_log subvolume"
    log_info "Created @var_log subvolume"
    
    # Create var/cache subvolume (for package cache)
    btrfs subvolume create "$mount_point/@var_cache" || error_exit "Failed to create @var_cache subvolume"
    log_info "Created @var_cache subvolume"
    
    log_success "Btrfs subvolumes created successfully"
}

# Safely mounts a device to a mount point.
# Args: $1 = device_path, $2 = mount_point
safe_mount() {
    local dev="$1"
    local mnt="$2"
    
    if [ ! -b "$dev" ]; then
        error_exit "Device $dev does not exist or is not a block device."
    fi
    
    mkdir -p "$mnt" || error_exit "Failed to create mount point $mnt."
    
    # For EFI partitions, use specific mount options
    if [[ "$mnt" == *"/boot/efi"* ]]; then
        mount -t vfat -o rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro "$dev" "$mnt" || error_exit "Failed to mount EFI partition $dev to $mnt."
    else
        mount "$dev" "$mnt" || error_exit "Failed to mount $dev to $mnt."
    fi
}

# Safely unmounts a path. Uses lazy unmount first.
# Args: $1 = mount_point
safe_umount() {
    local mnt="$1"
    if mountpoint -q "$mnt"; then
        log_info "Attempting lazy unmount for $mnt..."
        umount -l "$mnt" &>/dev/null || true
        if mountpoint -q "$mnt"; then
            log_info "Attempting forceful unmount for $mnt..."
            umount "$mnt" &>/dev/null || log_warn "Failed to unmount $mnt."
        fi
    fi
}

# Captures UUID or PARTUUID of a device and stores it in global variables (no associative array for Bash 3.x).
# Args: $1 = key_prefix (e.g., "root", "efi"), $2 = dev_path, $3 = id_type ("UUID" or "PARTUUID")
capture_id_for_config() {
    local key_prefix="$1" # e.g., "efi", "root", "luks_container", "lv_root"
    local dev_path="$2"   # e.g., /dev/sda1, /dev/mapper/cryptroot
    local id_type="$3"    # "UUID" or "PARTUUID"

    if [ ! -b "$dev_path" ]; then
        error_exit "Device $dev_path not found or not a block device for ${id_type} capture."
    fi

    log_info "Capturing ${id_type} for ${key_prefix} from ${dev_path}..."
    local id_value=$(blkid -s "$id_type" -o value "$dev_path")
    if [ -z "$id_value" ]; then
        error_exit "Could not retrieve ${id_type} for ${dev_path}. Check device formatting or type."
    fi
    # Use explicit variable names for Bash 3.x (no declare -A PARTITION_UUIDS)
    case "${key_prefix}_${id_type}" in
        efi_UUID) PARTITION_UUIDS_EFI_UUID="$id_value";;
        efi_PARTUUID) PARTITION_UUIDS_EFI_PARTUUID="$id_value";;
        root_UUID) PARTITION_UUIDS_ROOT_UUID="$id_value";;
        boot_UUID) PARTITION_UUIDS_BOOT_UUID="$id_value";;
        swap_UUID) PARTITION_UUIDS_SWAP_UUID="$id_value";;
        home_UUID) PARTITION_UUIDS_HOME_UUID="$id_value";;
        luks_container_UUID) PARTITION_UUIDS_LUKS_CONTAINER_UUID="$id_value";;
        lv_root_UUID) PARTITION_UUIDS_LV_ROOT_UUID="$id_value";;
        lv_swap_UUID) PARTITION_UUIDS_LV_SWAP_UUID="$id_value";;
        lv_home_UUID) PARTITION_UUIDS_LV_HOME_UUID="$id_value";;
        *) log_warn "Attempted to capture unknown UUID/PARTUUID for key_prefix=$key_prefix, id_type=$id_type.";;
    esac
    log_info "Captured ${id_type} for ${key_prefix}: ${id_value}"
}

# Gets the UUID of an opened LUKS device.
# Args: $1 = luks_dev_mapper_path (e.g., /dev/mapper/cryptroot)
get_luks_uuid() {
    local luks_mapper_path="$1"
    local luks_uuid=$(blkid -s UUID -o value "$luks_mapper_path")
    if [ -z "$luks_uuid" ]; then
        error_exit "Could not get UUID for opened LUKS device: $luks_mapper_path."
    fi
    echo "$luks_uuid"
}

# Gets the full path to an LVM Logical Volume.
# Args: $1 = volume_group_name, $2 = logical_volume_name
get_lvm_lv_path() {
    local vg_name="$1"
    local lv_name="$2"
    local lv_path=""

    if [ -b "/dev/mapper/${vg_name}-${lv_name}" ]; then
        lv_path="/dev/mapper/${vg_name}-${lv_name}"
    elif [ -b "/dev/${vg_name}/${lv_name}" ]; then
        lv_path="/dev/${vg_name}/${lv_name}"
    else
        error_exit "Logical Volume ${vg_name}/${lv_name} not found."
    fi
    echo "$lv_path"
}


# --- Complex Storage Operations ---

# Encrypts a device with LUKS.
# Args: $1 = dev_path (e.g., /dev/sda2), $2 = luks_name (e.g., cryptroot)
# Global: LUKS_PASSPHRASE (read from config.sh)
# Global: LUKS_CRYPTROOT_DEV (Bash 3.x way to store opened device path)
encrypt_device() {
    local dev_path="$1"
    local luks_name="$2"
    log_info "Encrypting $dev_path with LUKS as $luks_name..."
    echo -n "$LUKS_PASSPHRASE" | cryptsetup luksFormat --type luks2 --cipher "aes-xts-plain64" --key-size "512" --hash "sha512" "$dev_path" -d - \
        --verbose --verify-passphrase || error_exit "LUKS format failed for $dev_path."
    
    # Open the LUKS device
    echo -n "$LUKS_PASSPHRASE" | cryptsetup open "$dev_path" "$luks_name" -d - || error_exit "LUKS open failed for $dev_path."
    
    capture_id_for_config "luks_container" "$dev_path" "UUID"
    LUKS_CRYPTROOT_DEV="/dev/mapper/$luks_name" # Store opened path in global scalar var for Bash 3.x
    log_info "$dev_path encrypted and opened as /dev/mapper/$luks_name."
}

# Sets up LVM Physical Volume, Volume Group, and Logical Volumes.
# Args: $1 = pv_dev (e.g., /dev/mapper/cryptroot), $2 = vg_name (e.g., volgroup0)
# Global: LV_LAYOUT_LV_ROOT, LV_LAYOUT_LV_SWAP, LV_LAYOUT_LV_HOME (from config.sh)
# Global: DEFAULT_LV_MOUNTPOINTS_LV_ROOT, DEFAULT_LV_MOUNTPOINTS_LV_SWAP, DEFAULT_LV_MOUNTPOINTS_LV_HOME (from config.sh)
# Global: DEFAULT_LV_FSTYPES_LV_ROOT, DEFAULT_LV_FSTYPES_LV_SWAP, DEFAULT_LV_FSTYPES_LV_HOME (from config.sh)
# Global: WANT_SWAP, WANT_HOME_PARTITION (from config.sh, user choices)
# Global: LV_ROOT_PATH, LV_SWAP_PATH, LV_HOME_PATH (Bash 3.x way to store LV paths)
setup_lvm() {
    local pv_dev="$1"
    local vg_name="$2"
    log_info "Setting up LVM on $pv_dev in Volume Group $vg_name..."

    pvcreate -y "$pv_dev" || error_exit "pvcreate failed for $pv_dev."
    vgcreate "$vg_name" "$pv_dev" || error_exit "vgcreate failed for $vg_name."

    # Root LV
    local lv_name="lv_root"
    local lv_size="${LV_LAYOUT_LV_ROOT}"
    local lv_mnt_point="${DEFAULT_LV_MOUNTPOINTS_LV_ROOT}"
    local lv_fs_type="${DEFAULT_LV_FSTYPES_LV_ROOT}"
    local lv_path=""

    log_info "Creating Logical Volume $lv_name ($lv_size) in VG $vg_name..."
    if echo "$lv_size" | grep -q '%'; then
        lvcreate -l "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
    else
        lvcreate -L "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
    fi

    # Check for the existence of the LV device file
    log_info "Waiting for logical volume device to appear..."
    local check_path=""
    for i in $(seq 1 10); do
        check_path=$(get_lvm_lv_path "$vg_name" "$lv_name")
        if [ -b "$check_path" ]; then
            lv_path="$check_path"
            break
        fi
        sleep 0.5
    done

    if [ -z "$lv_path" ]; then
        error_exit "Logical volume device file for $lv_name did not appear."
    fi

    LV_ROOT_PATH="$lv_path" # Assign to global variable
    
    format_filesystem "$lv_path" "$lv_fs_type"
    capture_id_for_config "$lv_name" "$lv_path" "UUID"
    safe_mount "$lv_path" "$lv_mnt_point"


    # Swap LV (if desired)
    if [ "$WANT_SWAP" == "yes" ]; then
        lv_name="lv_swap"
        lv_size="${LV_LAYOUT_LV_SWAP}"
        
        log_info "Creating Logical Volume $lv_name ($lv_size) in VG $vg_name..."
        if echo "$lv_size" | grep -q '%'; then
            lvcreate -l "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
        else
            lvcreate -L "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
        fi
        
        # Check for the existence of the LV device file
        local swap_path=""
        for i in $(seq 1 10); do
            swap_path=$(get_lvm_lv_path "$vg_name" "$lv_name")
            if [ -b "$swap_path" ]; then
                break
            fi
            sleep 0.5
        done
        if [ -z "$swap_path" ]; then
            error_exit "Logical volume device file for $lv_name did not appear."
        fi

        LV_SWAP_PATH="$swap_path" # Assign to global variable
        lv_fs_type="${DEFAULT_LV_FSTYPES_LV_SWAP}"
        
        format_filesystem "$swap_path" "$lv_fs_type"
        capture_id_for_config "$lv_name" "$swap_path" "UUID"
        swapon "$swap_path" || error_exit "Failed to activate swap LV: $swap_path."
    fi

    # Home LV (if desired)
    if [ "$WANT_HOME_PARTITION" == "yes" ]; then
        lv_name="lv_home"
        lv_size="${LV_LAYOUT_LV_HOME}"
        
        log_info "Creating Logical Volume $lv_name ($lv_size) in VG $vg_name..."
        if echo "$lv_size" | grep -q '%'; then
            lvcreate -l "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
        else
            lvcreate -L "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
        fi

        # Check for the existence of the LV device file
        local home_path=""
        for i in $(seq 1 10); do
            home_path=$(get_lvm_lv_path "$vg_name" "$lv_name")
            if [ -b "$home_path" ]; then
                break
            fi
            sleep 0.5
        done
        if [ -z "$home_path" ]; then
            error_exit "Logical volume device file for $lv_name did not appear."
        fi

        LV_HOME_PATH="$home_path" # Assign to global variable
        lv_mnt_point="${DEFAULT_LV_MOUNTPOINTS_LV_HOME}"
        lv_fs_type="${DEFAULT_LV_FSTYPES_LV_HOME}"
        
        format_filesystem "$home_path" "$lv_fs_type"
        capture_id_for_config "$lv_name" "$home_path" "UUID"
        safe_mount "$home_path" "$lv_mnt_point"
    fi

    log_info "LVM setup complete for $vg_name."
}

# Sets up a software RAID array.
# Args: $1 = raid_level, $2 = md_name (e.g., md0), $3... = component_devices (e.g., /dev/sdb1 /dev/sdc1)
setup_raid() {
    local raid_level="$1"
    local md_name="$2"
    shift 2
    local component_devices=("$@")

    log_info "Setting up RAID$raid_level for $md_name with devices: ${component_devices[*]}..."
    mdadm --create "$md_name" --level="$raid_level" --raid-devices="${#component_devices[@]}" "${component_devices[@]}" --force || error_exit "mdadm create failed for $md_name."
    
    # Do NOT save mdadm.conf here. That happens in chroot_config.sh
    log_info "RAID setup complete for $md_name."
}


# --- Pacman / Package Management Wrappers ---

# Installs prerequisite packages on the live ISO.
install_reflector_prereqs_live() {
    log_info "Installing prerequisite packages on Live ISO (pacman-contrib, reflector, rsync)..."
    pacman -Sy --noconfirm --needed pacman-contrib reflector rsync || error_exit "Failed to install prerequisite packages on Live ISO."
    log_info "Prerequisite packages installed."
}

# Configures pacman mirrorlist using reflector on the live ISO.
# Args: $1 = country code (e.g., "US", "DE")
configure_mirrors_live() {
    local country_code="$1"
    log_info "Configuring pacman mirrors for faster downloads using reflector for country: $country_code..."
    local mirrorlist_path="/etc/pacman.d/mirrorlist"

    if [ -f "$mirrorlist_path" ]; then
        log_info "Backing up current mirrorlist."
        cp "$mirrorlist_path" "${mirrorlist_path}.backup" || log_warn "Failed to backup mirrorlist."
    fi

    log_info "Running reflector to generate new mirrorlist..."
    reflector -c "$country_code" -a 72 -f 10 -l 10 --sort rate --save "$mirrorlist_path" || error_exit "Reflector failed to update mirrorlist."
    log_info "Pacman mirrorlist configured successfully."
}

# Runs pacstrap to install the base system into /mnt.
# Global: KERNEL_TYPE (e.g., "linux", "linux-lts")
run_pacstrap_base_install() {
    echo "=== PHASE 2: Package Installation ==="
    log_info "Running pacstrap to install base system packages..."
    
    # Pass all arguments passed to run_pacstrap_base_install directly to pacstrap
    # This expects arguments to be individual package names.
    pacstrap -K /mnt "$@" --noconfirm --needed || error_exit "Pacstrap failed to install base system."

    log_info "Pacstrap base system complete."
}

# Installs packages inside the chroot environment using pacman.
# Args: $@ = packages to install (e.g., "plasma sddm")
# Global: Uses pacman with --noconfirm --needed flags for automated installation
install_packages_chroot() {
    local packages="$@"
    log_info "Installing packages inside chroot: '$packages'..."
    pacman -S --noconfirm --needed $packages || error_exit "Failed to install packages inside chroot: '$packages'."
    log_info "Packages installed inside chroot: '$packages'."
}

# Installs essential extras inside chroot (beyond base, linux, linux-firmware)
# Includes editors, docs, networking, fs utils, and storage stacks based on config
install_essential_extras_chroot() {
    local packages="sudo man-db man-pages texinfo nano neovim bash-completion git curl networkmanager network-manager-applet iwd archlinux-keyring base-devel pipewire btop openssh parallel exfat-utils unzip p7zip rsync wget tree which less dfc"

    # Filesystem utilities
    if [ "$ROOT_FILESYSTEM_TYPE" == "btrfs" ] || [ "$HOME_FILESYSTEM_TYPE" == "btrfs" ]; then
        packages="$packages btrfs-progs"
    fi
    if [ "$ROOT_FILESYSTEM_TYPE" == "ext4" ] || [ "$HOME_FILESYSTEM_TYPE" == "ext4" ]; then
        packages="$packages e2fsprogs"
    fi
    if [ "$ROOT_FILESYSTEM_TYPE" == "xfs" ] || [ "$HOME_FILESYSTEM_TYPE" == "xfs" ]; then
        packages="$packages xfsprogs"
    fi

    # LVM / RAID utilities
    if [ "$WANT_LVM" == "yes" ]; then
        packages="$packages lvm2"
    fi
    if [ "$WANT_RAID" == "yes" ]; then
        packages="$packages mdadm"
    fi

    log_info "Installing essential extra packages inside chroot: $packages"
    install_packages_chroot $packages
}

# Installs time sync package in chroot according to TIME_SYNC_CHOICE
install_time_sync_chroot() {
    case "$TIME_SYNC_CHOICE" in
        ntpd)
            log_info "Installing NTP (ntp) for time synchronization..."
            install_packages_chroot ntp ;;
        chrony)
            log_info "Installing Chrony for time synchronization..."
            install_packages_chroot chrony ;;
        systemd-timesyncd)
            log_info "Using systemd-timesyncd (already part of systemd), no package install needed." ;;
        *)
            log_warn "Unknown TIME_SYNC_CHOICE '$TIME_SYNC_CHOICE'. Skipping time sync package install." ;;
    esac
}

# Sets Neovim as the default system editor inside chroot
configure_default_editor_chroot() {
    log_info "Configuring Neovim as the default system editor..."

    # Create a profile.d file to export EDITOR and VISUAL for all users
    local profile_d_file="/etc/profile.d/00-editor.sh"
    {
        echo "export EDITOR=/usr/bin/nvim"
        echo "export VISUAL=/usr/bin/nvim"
        echo "export SUDO_EDITOR=/usr/bin/nvim"
    } > "$profile_d_file" || error_exit "Failed to write $profile_d_file"
    chmod 644 "$profile_d_file" || error_exit "Failed to set permissions on $profile_d_file"

    # Provide common editor aliases when vim is not installed
    if [ ! -e "/usr/bin/vi" ]; then
        ln -sf /usr/bin/nvim /usr/bin/vi || log_warn "Could not create vi symlink to nvim"
    fi
    if [ ! -e "/usr/bin/vim" ]; then
        ln -sf /usr/bin/nvim /usr/bin/vim || log_warn "Could not create vim symlink to nvim"
    fi

    # Ensure visudo/sudoedit use nvim irrespective of environment
    local sudoers_editor_file="/etc/sudoers.d/00-editor"
    {
        echo "Defaults editor=/usr/bin/nvim"
        echo "Defaults env_editor"
    } > "$sudoers_editor_file" || error_exit "Failed to write $sudoers_editor_file"
    chmod 440 "$sudoers_editor_file" || error_exit "Failed to set permissions on $sudoers_editor_file"

    # Validate sudoers configuration
    if ! visudo -cf /etc/sudoers; then
        log_error "sudoers validation failed after editor configuration"
        return 1
    fi

    log_success "Default editor configured to Neovim"
}

# Updates the entire system inside the chroot environment.
# Global: Uses pacman -Syu to update all packages
update_system_chroot() {
    log_info "Updating entire system inside chroot..."
    pacman -Syu --noconfirm || error_exit "Failed to update system inside chroot."
    log_info "System updated inside chroot."
}

# Installs CPU microcode packages inside the chroot environment.
# Global: CPU_MICROCODE_TYPE (e.g., "intel", "amd", "none")
# Installs intel-ucode or amd-ucode based on detected CPU type
install_microcode_chroot() {
    local microcode_package=""
    if [ "$CPU_MICROCODE_TYPE" == "intel" ]; then
        microcode_package="intel-ucode"
    elif [ "$CPU_MICROCODE_TYPE" == "amd" ]; then
        microcode_package="amd-ucode"
    else
        log_info "No specific CPU microcode type detected or needed. Skipping."
        return 0
    fi

    log_info "Installing $microcode_package inside chroot..."
    pacman -Sy --noconfirm --needed "$microcode_package" || error_exit "Failed to install $microcode_package inside chroot."
    log_info "$microcode_package installed."
}


# --- File System / Chroot Configuration Utilities ---

# Generates /etc/fstab using UUIDs.
generate_fstab() {
    log_info "Generating fstab using UUIDs..."
    genfstab -U /mnt > /mnt/etc/fstab || error_exit "Failed to generate fstab."
    log_info "fstab generated successfully at /mnt/etc/fstab."
}

# Edits a file inside the chroot environment using sed.
# Args: $1 = file_path_in_chroot, $2 = sed_expression
# Creates a backup before editing and applies sed expression
edit_file_in_chroot() {
    local file_path="$1"
    local sed_expr="$2"
    log_info "Editing $file_path inside chroot with sed: '$sed_expr'"
    
    # Create a backup before editing
    cp "$file_path" "${file_path}.bak" || log_warn "Failed to create backup of $file_path."

    sed -i "$sed_expr" "$file_path" || error_exit "Failed to edit $file_path inside chroot."
    log_info "File $file_path modified."
}

# Enables a systemd service inside the chroot environment.
# Args: $1 = service_name (e.g., "NetworkManager.service", "gdm")
# Uses systemctl enable to set service for auto-start on boot
enable_systemd_service_chroot() {
    local service_name="$1"
    log_info "Enabling systemd service $service_name inside chroot..."
    systemctl enable "$service_name" || error_exit "Failed to enable service $service_name inside chroot."
    log_info "Service $service_name enabled."
}

# --- Security / Credential Handling ---

# Simple password input with confirmation (based on proven ArchL4TM approach)
# Args: $1 = prompt_message, $2 = variable_name_to_store_password
secure_password_input() {
    local prompt_msg="$1"
    local result_var_name="$2"
    local password1
    local password2

    while true; do
        read -rs -p "$prompt_msg: " password1
        echo
        read -rs -p "Confirm password: " password2
        echo

        if [ "$password1" != "$password2" ]; then
            log_warn "Passwords do not match. Please try again."
            continue
        fi

        # Direct variable assignment (no eval needed)
        case "$result_var_name" in
            "ROOT_PASSWORD") 
                ROOT_PASSWORD="$password1"
                log_info "ROOT_PASSWORD set to: ${ROOT_PASSWORD:0:3}***"
                ;;
            "MAIN_USER_PASSWORD") 
                MAIN_USER_PASSWORD="$password1"
                log_info "MAIN_USER_PASSWORD set to: ${MAIN_USER_PASSWORD:0:3}***"
                ;;
            "LUKS_PASSPHRASE") 
                LUKS_PASSPHRASE="$password1"
                log_info "LUKS_PASSPHRASE set to: ${LUKS_PASSPHRASE:0:3}***"
                ;;
            *) log_error "Unknown password variable: $result_var_name" ;;
        esac
        
        log_info "Password set successfully."
        break
    done
}

# --- General Utility / String Manipulation ---

# Trims leading/trailing whitespace from a string.
trim_string() {
    local s="$1"
    echo "$s" | xargs
}

# Saves the current configuration variables to a file.
# Args: $1 = output_file_path
# Global: All config.sh variables populated by dialogs.
save_current_config() {
    local output_file="$1"
    log_info "Saving current installation configuration to $output_file (excluding passwords)."

    {
        echo "#!/bin/bash"
        echo "# Archl4tm User Configuration - Generated on $(date)"
        echo "# This file can be sourced by install_arch.sh to load previous choices."
        echo "# Edit it to pre-configure future installations."
        echo ""

        # List all simple variables that are populated by dialogs
        local vars_to_save=(
            "INSTALL_DISK" "BOOT_MODE" "OVERRIDE_BOOT_MODE" "WANT_WIFI_CONNECTION"
            "PARTITION_SCHEME" "WANT_SWAP" "WANT_HOME_PARTITION" "WANT_ENCRYPTION"
            "WANT_LVM" "WANT_RAID" "RAID_LEVEL" "KERNEL_TYPE" "CPU_MICROCODE_TYPE"
            "TIMEZONE" "LOCALE" "KEYMAP" "REFLECTOR_COUNTRY_CODE" "SYSTEM_HOSTNAME"
            "DESKTOP_ENVIRONMENT" "DISPLAY_MANAGER" "GPU_DRIVER_TYPE" "BOOTLOADER_TYPE"
            "ENABLE_OS_PROBER" "WANT_MULTILIB" "WANT_AUR_HELPER" "AUR_HELPER_CHOICE"
            "WANT_FLATPAK" "INSTALL_CUSTOM_PACKAGES" "INSTALL_CUSTOM_AUR_PACKAGES"
            "WANT_GRUB_THEME" "GRUB_THEME_CHOICE" "WANT_NUMLOCK_ON_BOOT"
        )

        for var_name in "${vars_to_save[@]}"; do
            # Check if the variable exists and is a simple variable (Bash 3.x compat)
            # Use indirect expansion for checking variable existence
            if eval "test -n \"\${$var_name+defined}\""; then # Check if var is set
                # Ensure it's not an array, as declare -a for arrays is different from scalars
                # Bash 3.x doesn't have declare -p for types robustly. This check will be simplified.
                local is_array=0
                # Crude check for Bash 3.x - assume simple variables unless explicitly managed
                # If we rely on specific array checks, Bash 3.x won't work well here for declare -a.
                # For `save_current_config`, we just dump what we know are scalar and RAID_DEVICES (explicitly handled).
                
                # Check if it's RAID_DEVICES, which is an array
                if [ "$var_name" == "RAID_DEVICES" ]; then
                    is_array=1
                fi

                if [ "$is_array" -eq 0 ]; then
                    printf '%s="%s"\n' "$var_name" "$(printf %s "${!var_name}" | sed 's/"/\\"/g')"
                fi
            fi
        done
        
        # Specifically save RAID_DEVICES array if it's populated (Bash 3.x explicit array dump)
        if [ ${#RAID_DEVICES[@]} -gt 0 ]; then
            echo ""
            echo "declare -a RAID_DEVICES=("
            for element in "${RAID_DEVICES[@]}"; do
                printf '    "%s"\n' "$(printf %s "$element" | sed 's/"/\\"/g')"
            done
            echo ")"
        fi

        echo ""
        echo "# NOTE: Passwords (ROOT_PASSWORD, MAIN_USER_PASSWORD, LUKS_PASSPHRASE) are NOT saved here for security reasons."
        echo "#       You will be prompted for them during script execution."

    } > "$output_file" || error_exit "Failed to save configuration to $output_file."
    
    chmod 600 "$output_file"
    log_info "Configuration saved successfully to $output_file."
}

# --- Chroot Configuration Functions ---

# Installs GRUB packages and bootloader (simplified ArchL4TM approach)
# Global: BOOT_MODE, BOOTLOADER_TYPE, WANT_ENCRYPTION
install_grub_chroot() {
    log_info "Installing GRUB (ArchL4TM approach)..."
    
    if [ "$BOOTLOADER_TYPE" != "grub" ]; then
        log_info "Skipping GRUB installation (not selected)"
        return 0
    fi
    
    # Install GRUB packages first (creates /etc/default/grub)
    if [ "$BOOT_MODE" == "uefi" ]; then
        log_info "Installing GRUB UEFI packages and dependencies..."
        install_packages_chroot "${BASE_PACKAGES_BOOTLOADER_GRUB[@]}" "${BASE_PACKAGES_FILESYSTEM[@]}" || error_exit "Failed to install GRUB UEFI packages"
    else
        log_info "Installing GRUB BIOS packages..."
        install_packages_chroot "grub" || error_exit "Failed to install GRUB package"
    fi
    
    # Configure GRUB defaults (including encryption support)
    configure_grub_defaults_chroot || error_exit "GRUB configuration failed"
    
    # Install GRUB bootloader (ArchL4TM approach)
    if [ "$BOOT_MODE" == "uefi" ]; then
        # Simple UEFI installation (no --efi-directory, auto-detection)
        grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck || error_exit "GRUB EFI installation failed"
    else
        # BIOS installation
        grub-install --target=i386-pc "$INSTALL_DISK" --recheck || error_exit "GRUB BIOS installation failed"
    fi
    
    # Generate GRUB configuration
    grub-mkconfig -o /boot/grub/grub.cfg || error_exit "GRUB configuration generation failed"
    
    log_info "GRUB installed successfully."
}

# Configures bootloader installation inside chroot environment.
# Global: BOOTLOADER_TYPE, BOOT_MODE, INSTALL_DISK, PARTITION_SCHEME
# Installs GRUB (EFI/BIOS) or systemd-boot based on configuration
configure_bootloader_chroot() {
    log_info "Installing bootloader: $BOOTLOADER_TYPE"
    
    # Validate boot mode and bootloader compatibility
    if [ "$BOOTLOADER_TYPE" == "systemd-boot" ] && [ "$BOOT_MODE" != "uefi" ]; then
        error_exit "systemd-boot requires UEFI mode, but BIOS mode detected"
    fi
    
    case "$BOOTLOADER_TYPE" in
        "grub")
            install_grub_bootloader || error_exit "GRUB installation failed"
            ;;
        "systemd-boot")
            install_systemd_bootloader || error_exit "systemd-boot installation failed"
            ;;
        *)
            error_exit "Unknown bootloader type: $BOOTLOADER_TYPE"
            ;;
    esac
    log_info "Bootloader configuration complete."
}

# Legacy function - redirects to simplified approach
install_grub_bootloader() {
    install_grub_chroot
}

# Installs systemd-boot with comprehensive validation
install_systemd_bootloader() {
    log_info "Installing systemd-boot..."
    
    # Validate UEFI mode
    if [ "$BOOT_MODE" != "uefi" ]; then
        error_exit "systemd-boot requires UEFI mode"
    fi
    
    # Validate EFI directory
    if [ ! -d "/boot/efi" ]; then
        log_error "EFI directory /boot/efi not found. Attempting to create it..."
        mkdir -p "/boot/efi" || error_exit "Failed to create /boot/efi directory"
    fi
    
    if ! mountpoint -q "/boot/efi"; then
        log_error "EFI partition not mounted at /boot/efi. Attempting to remount..."
        
        # Try to find and remount the EFI partition
        if [ -n "${PARTITION_UUIDS_EFI_UUID:-}" ]; then
            local efi_dev="/dev/disk/by-uuid/$PARTITION_UUIDS_EFI_UUID"
            if [ -b "$efi_dev" ]; then
                log_info "Remounting EFI partition from UUID: $efi_dev"
                mount -t vfat -o rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro "$efi_dev" "/boot/efi" || error_exit "Failed to remount EFI partition"
            else
                error_exit "EFI partition device not found: $efi_dev"
            fi
        else
            error_exit "EFI partition UUID not available for remounting"
        fi
    fi
    
    # Verify EFI partition is accessible
    if [ ! -d "/boot/efi/EFI" ]; then
        log_info "Creating EFI directory structure..."
        mkdir -p "/boot/efi/EFI" || error_exit "Failed to create EFI directory structure"
    fi
    
    # Install systemd-boot - match working approach from previous project
    bootctl install || error_exit "systemd-boot installation failed"
    
    # Create boot entry
    create_systemd_boot_entry || error_exit "Failed to create systemd-boot entry"
    
    log_info "systemd-boot installation complete."
}

# Configures Secure Boot using sbctl
configure_secure_boot_chroot() {
    log_info "Configuring Secure Boot..."
    
    if [ "$WANT_SECURE_BOOT" != "yes" ]; then
        log_info "Secure Boot not requested, skipping configuration"
        return 0
    fi
    
    # Check if sbctl is installed
    if ! command -v sbctl &>/dev/null; then
        log_warn "sbctl not found, skipping Secure Boot configuration"
        return 0
    fi
    
    # Check if we're in UEFI mode
    if [ "$BOOT_MODE" != "uefi" ]; then
        log_warn "Secure Boot requires UEFI mode, skipping configuration"
        return 0
    fi
    
    # Initialize Secure Boot keys
    log_info "Initializing Secure Boot keys..."
    sbctl create-keys || log_warn "Failed to create Secure Boot keys"
    
    # Sign the bootloader
    case "$BOOTLOADER_TYPE" in
        "grub")
            log_info "Signing GRUB bootloader..."
            sbctl sign /boot/efi/EFI/GRUB/grubx64.efi || log_warn "Failed to sign GRUB bootloader"
            ;;
        "systemd-boot")
            log_info "Signing systemd-boot..."
            sbctl sign /boot/efi/EFI/systemd/systemd-bootx64.efi || log_warn "Failed to sign systemd-boot"
            ;;
    esac
    
    # Sign the kernel
    log_info "Signing kernel..."
    sbctl sign /boot/vmlinuz-linux || log_warn "Failed to sign kernel"
    
    # Sign microcode if present
    if [ -f "/boot/intel-ucode.img" ]; then
        log_info "Signing Intel microcode..."
        sbctl sign /boot/intel-ucode.img || log_warn "Failed to sign Intel microcode"
    elif [ -f "/boot/amd-ucode.img" ]; then
        log_info "Signing AMD microcode..."
        sbctl sign /boot/amd-ucode.img || log_warn "Failed to sign AMD microcode"
    fi
    
    # Sign initramfs
    log_info "Signing initramfs..."
    sbctl sign /boot/initramfs-linux.img || log_warn "Failed to sign initramfs"
    
    # Install Secure Boot keys to EFI
    log_info "Installing Secure Boot keys to EFI..."
    sbctl install || log_warn "Failed to install Secure Boot keys to EFI"
    
    # Enable Secure Boot
    log_info "Enabling Secure Boot..."
    sbctl verify || log_warn "Secure Boot verification failed"
    
    log_info "Secure Boot configuration complete."
    
    # Create comprehensive documentation
    cat > /root/SECURE_BOOT_SETUP.md << 'EOF'
# Secure Boot Setup Instructions

## ⚠️ CRITICAL: Read This Before Rebooting!

Your system has been configured for Secure Boot, but you MUST complete the setup
manually in your UEFI firmware or your system will NOT boot!

## Prerequisites (Should be done BEFORE installation):
1. **Disable Secure Boot** in your UEFI firmware
2. **Clear all existing Secure Boot keys** (PK, KEK, DB, DBX)
3. **Enable "Custom Key" or "Other OS" mode** in UEFI
4. **Ensure your motherboard supports custom key enrollment**

## Post-Installation Steps:

### Step 1: Boot into your installed system
- The system should boot normally (Secure Boot is not yet enabled)

### Step 2: Enroll the Secure Boot keys
```bash
# Check current status
sbctl status

# Enroll the keys (this will require UEFI firmware access)
sbctl enroll-keys

# Verify everything is signed
sbctl verify
```

### Step 3: Enable Secure Boot in UEFI
1. Reboot and enter UEFI firmware
2. Navigate to Security/Secure Boot settings
3. Enable Secure Boot
4. Save and exit

### Step 4: Test the system
- System should boot with Secure Boot enabled
- If it fails, disable Secure Boot in UEFI and troubleshoot

## Troubleshooting:

### If system won't boot after enabling Secure Boot:
1. **Disable Secure Boot** in UEFI firmware immediately
2. Boot into the system
3. Check what's not signed: `sbctl verify`
4. Re-sign missing components: `sbctl sign /path/to/component`
5. Try again

### Common issues:
- **Motherboard doesn't support custom keys**: Use Microsoft keys instead
- **Keys not enrolled properly**: Clear keys and re-enroll
- **Missing signatures**: Re-sign all boot components

## When to use Secure Boot:
- ✅ Dual-booting with Windows 11
- ✅ Gaming (some games require TPM/Secure Boot)
- ✅ Enterprise security requirements
- ❌ Single-boot Linux systems (usually not needed)
- ❌ If you don't understand the risks

## Alternative: Use Microsoft Keys
If custom keys don't work, you can use Microsoft's keys:
```bash
# Install pre-signed bootloader
pacman -S grub-efi-x86_64-signed

# Or use systemd-boot with Microsoft keys
bootctl install --esp-path=/boot/efi
```

## Support:
- Arch Wiki: https://wiki.archlinux.org/title/Secure_Boot
- sbctl documentation: https://github.com/Foxboron/sbctl
EOF

    log_warn "=========================================="
    log_warn "SECURE BOOT SETUP REQUIRED!"
    log_warn "=========================================="
    log_warn "Your system will NOT boot with Secure Boot enabled"
    log_warn "until you complete the manual setup process."
    log_warn ""
    log_warn "IMPORTANT: Read /root/SECURE_BOOT_SETUP.md"
    log_warn "This file contains detailed instructions."
    log_warn ""
    log_warn "Quick steps after installation:"
    log_warn "1. Boot into your system"
    log_warn "2. Run: sbctl enroll-keys"
    log_warn "3. Enable Secure Boot in UEFI firmware"
    log_warn "4. Test boot"
    log_warn "=========================================="
}

# Creates systemd-boot loader entry
create_systemd_boot_entry() {
    log_info "Creating systemd-boot loader entry..."
    
    local loader_entry="/boot/loader/entries/arch.conf"
    local loader_conf="/boot/loader/loader.conf"
    local root_uuid=""
    local cmdline_params=""
    local microcode_initrd=""
    
    # Get root partition UUID
    if [ "$WANT_LVM" == "yes" ]; then
        root_uuid="$PARTITION_UUIDS_LV_ROOT_UUID"
    else
        root_uuid="$PARTITION_UUIDS_ROOT_UUID"
    fi
    
    if [ -z "$root_uuid" ]; then
        error_exit "Root partition UUID not found"
    fi
    
    # Build kernel command line
    cmdline_params="root=UUID=$root_uuid rw"
    
    # Add LUKS parameters if encryption is used
    if [ "$WANT_ENCRYPTION" == "yes" ] && [ -n "$PARTITION_UUIDS_LUKS_CONTAINER_UUID" ]; then
        cmdline_params="$cmdline_params cryptdevice=UUID=$PARTITION_UUIDS_LUKS_CONTAINER_UUID:cryptroot"
    fi
    
    # Add LVM parameters if LVM is used
    if [ "$WANT_LVM" == "yes" ]; then
        cmdline_params="$cmdline_params rd.lvm.vg=$VG_NAME"
    fi
    
    # Add quiet parameter
    cmdline_params="$cmdline_params quiet"
    
    # Determine microcode initrd based on CPU
    if [ -f "/boot/intel-ucode.img" ]; then
        microcode_initrd="initrd  /intel-ucode.img"
    elif [ -f "/boot/amd-ucode.img" ]; then
        microcode_initrd="initrd  /amd-ucode.img"
    else
        log_warn "No microcode image found, skipping microcode initrd"
    fi
    
    # Create loader.conf for systemd-boot configuration
    cat > "$loader_conf" << EOF
default arch.conf
timeout 5
editor  no
EOF
    
    # Create loader entry
    cat > "$loader_entry" << EOF
title   Arch Linux
linux   /vmlinuz-linux
$microcode_initrd
initrd  /initramfs-linux.img
options $cmdline_params
EOF
    
    log_info "systemd-boot entry created: $loader_entry"
    log_info "systemd-boot loader configuration created: $loader_conf"
}

# Configures Plymouth boot splash screen
configure_plymouth_chroot() {
    log_info "Configuring Plymouth boot splash..."
    
    # Check if Plymouth is installed
    if ! pacman -Qi plymouth &>/dev/null; then
        log_info "Plymouth not installed, skipping configuration"
        return 0
    fi
    
    # Install Arch Glow theme from Source directory
    local theme_source="/Source/arch-glow"
    local theme_dest="/usr/share/plymouth/themes/arch-glow"
    
    if [ -d "$theme_source" ]; then
        log_info "Installing Arch Glow Plymouth theme..."
        mkdir -p "$theme_dest" || error_exit "Failed to create Plymouth themes directory"
        
        # Copy all theme files
        cp -r "$theme_source"/* "$theme_dest"/ || error_exit "Failed to copy Arch Glow theme"
        
        # Set proper permissions for theme files
        chmod -R 755 "$theme_dest" || log_warn "Failed to set theme permissions"
        chmod 644 "$theme_dest"/*.png 2>/dev/null || log_warn "Failed to set image permissions"
        chmod 644 "$theme_dest"/*.plymouth 2>/dev/null || log_warn "Failed to set plymouth file permissions"
        chmod 755 "$theme_dest"/*.script 2>/dev/null || log_warn "Failed to set script permissions"
        
        # Ensure the main script is executable
        if [ -f "$theme_dest/arch-glow.script" ]; then
            chmod +x "$theme_dest/arch-glow.script" || log_warn "Failed to make arch-glow.script executable"
            log_info "Made arch-glow.script executable"
        fi
        
        log_info "Arch Glow theme installed successfully with $(ls -1 "$theme_dest"/*.png | wc -l) image files"
    else
        log_warn "Arch Glow theme source not found at $theme_source"
    fi
    
    # Set Plymouth theme based on user choice
    local plymouth_theme=""
    if [ "$WANT_PLYMOUTH_THEME" == "yes" ] && [ -n "$PLYMOUTH_THEME_CHOICE" ]; then
        plymouth_theme="$PLYMOUTH_THEME_CHOICE"
    else
        plymouth_theme="arch-glow"  # Default to arch-glow if no specific choice
    fi
    
    if [ -d "/usr/share/plymouth/themes/$plymouth_theme" ]; then
        plymouth-set-default-theme -R "$plymouth_theme" || log_warn "Failed to set Plymouth theme"
        log_info "Plymouth theme set to: $plymouth_theme"
    else
        log_warn "Plymouth theme $plymouth_theme not found, using default"
    fi
    
    # Note: Plymouth hook is added to mkinitcpio in configure_mkinitcpio_hooks_chroot()
    # to avoid duplicate initramfs regenerations
    
    log_info "Plymouth configuration complete."
}

# Configures GRUB defaults inside chroot environment.
# Global: BOOTLOADER_TYPE, ENABLE_OS_PROBER, GRUB_TIMEOUT_DEFAULT, WANT_ENCRYPTION
# Sets GRUB timeout, OS prober, and encryption support configuration
configure_grub_defaults_chroot() {
    log_info "Configuring GRUB defaults..."
    if [ "$BOOTLOADER_TYPE" == "grub" ]; then
        # Set GRUB timeout
        edit_file_in_chroot "/etc/default/grub" "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$GRUB_TIMEOUT_DEFAULT/"
        
        # Enable OS prober if requested
        if [ "$ENABLE_OS_PROBER" == "yes" ]; then
            edit_file_in_chroot "/etc/default/grub" "s/^#GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/"
        fi
        
        # Enable cryptodisk support for encrypted systems (required before grub-install)
        if [ "$WANT_ENCRYPTION" == "yes" ]; then
            log_info "Enabling GRUB cryptodisk support for encrypted system..."
            # Try to uncomment existing line first, then add if not found
            if grep -q "^#GRUB_ENABLE_CRYPTODISK=" "/etc/default/grub"; then
                edit_file_in_chroot "/etc/default/grub" "s/^#GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/"
            elif grep -q "^GRUB_ENABLE_CRYPTODISK=" "/etc/default/grub"; then
                edit_file_in_chroot "/etc/default/grub" "s/^GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/"
            else
                # Add the line if it doesn't exist
                echo "GRUB_ENABLE_CRYPTODISK=y" >> "/etc/default/grub"
                log_info "Added GRUB_ENABLE_CRYPTODISK=y to /etc/default/grub"
            fi
        fi
    fi
    log_info "GRUB defaults configured."
}

# Configures GRUB theme inside chroot environment.
# Global: WANT_GRUB_THEME, GRUB_THEME_CHOICE, BOOTLOADER_TYPE
# Downloads and configures GRUB themes from GitHub repositories
configure_grub_theme_chroot() {
    log_info "Configuring GRUB theme: $GRUB_THEME_CHOICE"
    if [ "$WANT_GRUB_THEME" == "yes" ] && [ "$BOOTLOADER_TYPE" == "grub" ]; then
        local theme_dir="/boot/grub/themes"
        local theme_name="$GRUB_THEME_CHOICE"
        
        mkdir -p "$theme_dir" || error_exit "Failed to create GRUB themes directory"
        
        case "$GRUB_THEME_CHOICE" in
            "PolyDark")
                git clone "${GRUB_THEME_SOURCES_POLY_DARK[0]}" "$theme_dir/$theme_name" || error_exit "Failed to clone PolyDark theme"
                ;;
            "CyberEXS")
                git clone "${GRUB_THEME_SOURCES_CYBEREXS[0]}" "$theme_dir/$theme_name" || error_exit "Failed to clone CyberEXS theme"
                ;;
            "CyberPunk")
                git clone "${GRUB_THEME_SOURCES_CYBERPUNK[0]}" "$theme_dir/$theme_name" || error_exit "Failed to clone CyberPunk theme"
                ;;
            "HyperFluent")
                git clone "${GRUB_THEME_SOURCES_HYPERFLUENT[0]}" "$theme_dir/$theme_name" || error_exit "Failed to clone HyperFluent theme"
                ;;
        esac
        
        # Set theme in GRUB config (regeneration happens in configure_grub_cmdline_chroot)
        edit_file_in_chroot "/etc/default/grub" "s/^#GRUB_THEME=.*/GRUB_THEME=\"\/boot\/grub\/themes\/$theme_name\/theme.txt\"/"
    fi
    log_info "GRUB theme configuration complete."
}

# Configures GRUB kernel command line parameters inside chroot environment.
# Global: BOOTLOADER_TYPE, WANT_ENCRYPTION, WANT_LVM, PARTITION_UUIDS_LUKS_CONTAINER_UUID, VG_NAME
# Adds LUKS, LVM, and other kernel parameters to GRUB configuration
configure_grub_cmdline_chroot() {
    log_info "Configuring GRUB kernel command line..."
    if [ "$BOOTLOADER_TYPE" == "grub" ]; then
        local cmdline_params=""
        local root_uuid=""
        
        # Get root partition UUID
        if [ "$WANT_LVM" == "yes" ]; then
            root_uuid="$PARTITION_UUIDS_LV_ROOT_UUID"
        else
            root_uuid="$PARTITION_UUIDS_ROOT_UUID"
        fi
        
        if [ -z "$root_uuid" ]; then
            error_exit "Root partition UUID not found for GRUB configuration"
        fi
        
        # Add root parameter with UUID
        cmdline_params="root=UUID=$root_uuid rw"
        
        # Add LUKS parameters if encryption is used
        if [ "$WANT_ENCRYPTION" == "yes" ] && [ -n "$PARTITION_UUIDS_LUKS_CONTAINER_UUID" ]; then
            cmdline_params="$cmdline_params cryptdevice=UUID=$PARTITION_UUIDS_LUKS_CONTAINER_UUID:cryptroot"
        fi
        
        # Add LVM parameters if LVM is used
        if [ "$WANT_LVM" == "yes" ]; then
            cmdline_params="$cmdline_params rd.lvm.vg=$VG_NAME"
        fi
        
        # Add quiet parameter for cleaner boot
        cmdline_params="$cmdline_params quiet"
        
        # Add splash parameter for Plymouth if Plymouth is enabled
        if [ "$WANT_PLYMOUTH" == "yes" ]; then
            cmdline_params="$cmdline_params splash"
            log_info "Added splash parameter for Plymouth"
        fi
        
        if [ -n "$cmdline_params" ]; then
            edit_file_in_chroot "/etc/default/grub" "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline_params\"/"
            grub-mkconfig -o /boot/grub/grub.cfg || error_exit "Failed to regenerate GRUB config with kernel parameters"
        fi
    fi
    log_info "GRUB kernel command line configured."
}

# Configures mkinitcpio hooks and regenerates initramfs inside chroot environment.
# Global: WANT_ENCRYPTION, WANT_LVM, WANT_RAID, INSTALL_DISK, INITCPIO_*_HOOK variables
# Adds encryption, LVM, RAID, and NVME hooks as needed and rebuilds initramfs
# Verifies boot mode and UEFI bitness according to Arch Linux installation guide
verify_boot_mode() {
    log_info "Verifying boot mode and UEFI bitness..."
    
    # Check if user has overridden boot mode to BIOS
    if [ "$OVERRIDE_BOOT_MODE" == "yes" ]; then
        log_info "User has overridden boot mode to BIOS/Legacy - skipping UEFI bitness check"
        BOOT_MODE="bios"
        log_info "Boot mode verification complete: $BOOT_MODE (user override)"
        return 0
    fi
    
    # Only perform UEFI bitness check if we're in UEFI mode
    if [ "$BOOT_MODE" == "uefi" ]; then
        if [ -d "/sys/firmware/efi" ]; then
            log_info "Verifying UEFI firmware bitness..."
            local fw_platform_size_file="/sys/firmware/efi/fw_platform_size"
            if [ -f "$fw_platform_size_file" ]; then
                local uefi_bitness=$(cat "$fw_platform_size_file")
                if [ "$uefi_bitness" == "32" ]; then
                    error_exit "Detected 32-bit UEFI firmware. Arch Linux x86_64 requires 64-bit UEFI or BIOS boot mode. Please switch to BIOS/Legacy boot in your firmware settings or perform a manual installation."
                fi
                log_info "Verified ${uefi_bitness}-bit UEFI firmware."
            else
                log_warn "Could not determine UEFI firmware bitness (missing $fw_platform_size_file)."
                log_warn "Proceeding assuming 64-bit UEFI, but manual verification is recommended if issues arise."
            fi
        else
            log_warn "UEFI mode selected but /sys/firmware/efi not found - this may cause issues"
        fi
    else
        log_info "BIOS/Legacy boot mode selected - no UEFI bitness check needed"
    fi
    
    log_info "Boot mode verification complete: $BOOT_MODE"
    return 0
}


# Sets console keymap in live environment
set_console_keymap_live() {
    log_info "Setting console keymap to $KEYMAP..."
    loadkeys "$KEYMAP" || log_warn "Failed to set console keymap (continuing anyway)"
}

# Suggests mirror country based on timezone
suggest_mirror_country_from_timezone() {
    local timezone="$1"
    local suggested_country=""
    
    # Extract region from timezone (e.g., "Europe/London" -> "Europe")
    local region=$(echo "$timezone" | cut -d'/' -f1)
    local city=$(echo "$timezone" | cut -d'/' -f2)
    
    case "$region" in
        "America")
            case "$city" in
                "New_York"|"Detroit"|"Toronto"|"Montreal") suggested_country="US";;
                "Los_Angeles"|"Denver"|"Chicago") suggested_country="US";;
                "Sao_Paulo"|"Rio_de_Janeiro") suggested_country="BR";;
                "Buenos_Aires") suggested_country="AR";;
                "Mexico_City") suggested_country="MX";;
                *) suggested_country="US";; # Default to US for America
            esac
            ;;
        "Europe")
            case "$city" in
                "London") suggested_country="GB";;
                "Berlin"|"Frankfurt"|"Munich") suggested_country="DE";;
                "Paris"|"Lyon") suggested_country="FR";;
                "Madrid"|"Barcelona") suggested_country="ES";;
                "Rome"|"Milan") suggested_country="IT";;
                "Amsterdam") suggested_country="NL";;
                "Stockholm") suggested_country="SE";;
                "Oslo") suggested_country="NO";;
                "Copenhagen") suggested_country="DK";;
                "Helsinki") suggested_country="FI";;
                "Zurich"|"Geneva") suggested_country="CH";;
                "Vienna") suggested_country="AT";;
                "Moscow") suggested_country="RU";;
                *) suggested_country="DE";; # Default to Germany for Europe
            esac
            ;;
        "Asia")
            case "$city" in
                "Tokyo") suggested_country="JP";;
                "Seoul") suggested_country="KR";;
                "Shanghai"|"Beijing") suggested_country="CN";;
                "Hong_Kong") suggested_country="HK";;
                "Singapore") suggested_country="SG";;
                "Bangkok") suggested_country="TH";;
                "Mumbai"|"Delhi"|"Kolkata") suggested_country="IN";;
                *) suggested_country="JP";; # Default to Japan for Asia
            esac
            ;;
        "Australia")
            case "$city" in
                "Sydney"|"Melbourne"|"Perth") suggested_country="AU";;
                *) suggested_country="AU";;
            esac
            ;;
        "Africa")
            suggested_country="ZA";; # Default to South Africa
        "Pacific")
            suggested_country="NZ";; # Default to New Zealand
        *)
            suggested_country="US";; # Global default
    esac
    
    echo "$suggested_country"
}

# Configures mirrors using reflector
configure_mirrors_live() {
    local country_code="$1"
    log_info "Configuring mirrors for country: $country_code"
    
    # Install reflector if not present
    if ! command -v reflector &>/dev/null; then
        pacman -Sy reflector --noconfirm || error_exit "Failed to install reflector"
    fi
    
    # Update mirrorlist with reflector
    reflector --country "$country_code" --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || error_exit "Failed to update mirrorlist"
    
    log_info "Mirror configuration complete."
}

# Generates fstab file
generate_fstab() {
    log_info "Generating fstab file..."
    genfstab -U /mnt >> /mnt/etc/fstab || error_exit "Failed to generate fstab"
    
    # Verify fstab was created and has content
    if [ ! -s /mnt/etc/fstab ]; then
        error_exit "Generated fstab file is empty"
    fi
    
    log_info "Fstab generation complete."
}

# Configures system hostname and hosts file
configure_hostname_chroot() {
    log_info "Configuring system hostname: $SYSTEM_HOSTNAME"
    
    # Set hostname
    echo "$SYSTEM_HOSTNAME" > /etc/hostname || error_exit "Failed to set hostname"
    
    # Configure /etc/hosts
    cat > /etc/hosts << EOF
127.0.0.1	localhost
::1		localhost
127.0.1.1	$SYSTEM_HOSTNAME.localdomain	$SYSTEM_HOSTNAME
EOF
    [ $? -eq 0 ] || error_exit "Failed to configure /etc/hosts"
    
    log_info "Hostname configuration complete."
}

# Configures desktop environment and display manager
configure_desktop_environment_chroot() {
    log_info "Configuring desktop environment: $DESKTOP_ENVIRONMENT"
    
    # Configure display manager
    if [ "$DISPLAY_MANAGER" != "none" ]; then
        log_info "Enabling display manager: $DISPLAY_MANAGER"
        enable_systemd_service_chroot "$DISPLAY_MANAGER" || log_warn "Failed to enable display manager"
    fi
    
    # Desktop environment specific configuration
    case "$DESKTOP_ENVIRONMENT" in
        "gnome")
            log_info "Configuring GNOME desktop environment..."
            # GNOME-specific configuration can be added here
            ;;
        "kde")
            log_info "Configuring KDE Plasma desktop environment..."
            # KDE-specific configuration can be added here
            ;;
        "hyprland")
            log_info "Configuring Hyprland window manager..."
            # Create basic Hyprland configuration
            mkdir -p /home/"$MAIN_USERNAME"/.config/hypr
            cat > /home/"$MAIN_USERNAME"/.config/hypr/hyprland.conf << 'EOF'
# Basic Hyprland configuration
# See https://wiki.hyprland.org/Getting-Started/Master-Tutorial/

# Monitor configuration
monitor=,preferred,auto,1

# Input configuration
input {
    kb_layout=us
    kb_variant=
    kb_model=
    kb_options=
    kb_rules=

    follow_mouse=1

    touchpad {
        natural_scroll=no
    }

    sensitivity=0 # -1.0 - 1.0, 0 means no modification.
}

# General configuration
general {
    gaps_in=5
    gaps_out=20
    border_size=2
    col.active_border=rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border=rgba(595959aa)

    layout=dwindle

    allow_tearing=false
}

# Decoration
decoration {
    rounding=10
    
    blur {
        enabled=true
        size=3
        passes=1
    }

    drop_shadow=yes
    shadow_range=4
    shadow_render_power=3
    col.shadow=rgba(1a1a1aee)
}

# Animations
animations {
    enabled=yes

    bezier=myBezier, 0.05, 0.9, 0.1, 1.05

    animation=windows, 1, 7, myBezier
    animation=windowsOut, 1, 7, default, popin 80%
    animation=border, 1, 10, default
    animation=borderangle, 1, 8, default
    animation=fade, 1, 7, default
    animation=workspaces, 1, 6, default
}

# Dwindle layout
dwindle {
    pseudotile=yes
    preserve_split=yes
}

# Master layout
master {
    new_is_master=true
}

# Gestures
gestures {
    workspace_swipe=off
}

# Window rules
windowrule=float, ^(pavucontrol)$
windowrule=float, ^(blueman-manager)$
windowrule=float, ^(nm-connection-editor)$
windowrule=float, ^(chromium)$
windowrule=float, ^(thunar)$
windowrule=float, ^(org.kde.polkit-kde-authentication-agent-1)$

# Environment variables
env=XCURSOR_SIZE,24
env=QT_QPA_PLATFORMTHEME,qt5ct

# Autostart
exec-once=waybar
exec-once=dunst
exec-once=hyprpaper
exec-once=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
EOF
            chown -R "$MAIN_USERNAME:$MAIN_USERNAME" /home/"$MAIN_USERNAME"/.config
            ;;
        "none")
            log_info "No desktop environment configured (server installation)"
            ;;
    esac
    
    log_info "Desktop environment configuration complete."
}

# Configures system localization (timezone, locale, keymap)
configure_localization_chroot() {
    log_info "Configuring system localization..."
    
    # Set timezone
    log_info "Setting timezone to $TIMEZONE..."
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime || error_exit "Failed to set timezone"
    
    # Generate /etc/adjtime
    log_info "Generating /etc/adjtime..."
    hwclock --systohc || error_exit "Failed to generate /etc/adjtime"
    
    # Configure locale
    log_info "Configuring locale: $LOCALE..."
    
    # Always ensure English is available as fallback
    log_info "Ensuring English locale is available as fallback..."
    sed -i "s/^#\(en_US.UTF-8\)/\1/" /etc/locale.gen || error_exit "Failed to uncomment en_US.UTF-8 in /etc/locale.gen"
    
    # Uncomment the selected locale in /etc/locale.gen (if not already English)
    if [ "$LOCALE" != "en_US.UTF-8" ]; then
        log_info "Adding selected locale: $LOCALE..."
        sed -i "s/^#\($LOCALE\)/\1/" /etc/locale.gen || error_exit "Failed to uncomment locale in /etc/locale.gen"
    fi
    
    # Generate locales
    locale-gen || error_exit "Failed to generate locales"
    
    # Set LANG in /etc/locale.conf
    echo "LANG=$LOCALE" > /etc/locale.conf || error_exit "Failed to set LANG in /etc/locale.conf"
    
    # Configure console keymap
    log_info "Configuring console keymap: $KEYMAP..."
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf || error_exit "Failed to set keymap in /etc/vconsole.conf"
    
    log_info "Localization configuration complete."
}

configure_mkinitcpio_hooks_chroot() {
    log_info "Configuring mkinitcpio hooks..."
    local hooks="$INITCPIO_BASE_HOOKS"
    
    # Add encryption hook if LUKS is used
    if [ "$WANT_ENCRYPTION" == "yes" ]; then
        hooks="$hooks $INITCPIO_LUKS_HOOK"
    fi
    
    # Add LVM hook if LVM is used
    if [ "$WANT_LVM" == "yes" ]; then
        hooks="$hooks $INITCPIO_LVM_HOOK"
    fi
    
    # Add RAID hook if RAID is used
    if [ "$WANT_RAID" == "yes" ]; then
        hooks="$hooks $INITCPIO_RAID_HOOK"
    fi
    
    # Add NVME hook if NVME device is detected
    if echo "$INSTALL_DISK" | grep -q "nvme"; then
        hooks="$hooks $INITCPIO_NVME_HOOK"
    fi
    
    # Add Plymouth hook if Plymouth is requested
    if [ "$WANT_PLYMOUTH" == "yes" ]; then
        hooks="$hooks plymouth"
        log_info "Added Plymouth hook to mkinitcpio"
    fi
    
    # Update mkinitcpio.conf
    edit_file_in_chroot "/etc/mkinitcpio.conf" "s/^HOOKS=.*/HOOKS=\"$hooks\"/"
    
    # Regenerate initramfs (single regeneration for all hooks)
    mkinitcpio -P || error_exit "Failed to regenerate initramfs"
    log_info "mkinitcpio hooks configured and initramfs regenerated."
}

# Installs GPU drivers inside chroot environment.
# Global: GPU_DRIVER_TYPE, GPU_DRIVERS_*_PACKAGES arrays
# Installs AMD, NVIDIA, or Intel GPU drivers based on configuration
install_gpu_drivers_chroot() {
    log_info "Installing GPU drivers for: $GPU_DRIVER_TYPE"
    case "$GPU_DRIVER_TYPE" in
        "amd")
            install_packages_chroot "${GPU_DRIVERS_AMD_PACKAGES[@]}" || error_exit "AMD GPU driver installation failed"
            ;;
        "nvidia")
            install_packages_chroot "${GPU_DRIVERS_NVIDIA_PACKAGES[@]}" || error_exit "NVIDIA GPU driver installation failed"
            ;;
        "intel")
            install_packages_chroot "${GPU_DRIVERS_INTEL_PACKAGES[@]}" || error_exit "Intel GPU driver installation failed"
            ;;
        "none")
            log_info "No GPU drivers to install"
            ;;
    esac
    log_info "GPU driver installation complete."
}

# Configures pacman for better user experience inside chroot environment.
# Global: WANT_MULTILIB
# Enables Color, ILoveCandy, VerbosePkgLists, ParallelDownloads, and multilib
configure_pacman_chroot() {
    log_info "Configuring pacman for better user experience..."
    
    # Enable Color output
    sed -i "/^#Color/c\Color" /etc/pacman.conf
    
    # Enable ILoveCandy (pacman progress bar)
    sed -i "/^#ILoveCandy/c\ILoveCandy" /etc/pacman.conf
    
    # Enable VerbosePkgLists (show package info)
    sed -i "/^#VerbosePkgLists/c\VerbosePkgLists" /etc/pacman.conf
    
    # Enable ParallelDownloads
    sed -i "/^#ParallelDownloads/c\ParallelDownloads = 5" /etc/pacman.conf
    
    # Enable multilib repository if requested
    if [ "$WANT_MULTILIB" == "yes" ]; then
        sed -i '/^#\[multilib\]/,+1 s/^#//' /etc/pacman.conf
        pacman -Sy || error_exit "Failed to sync package database after enabling multilib"
    fi
    
    log_info "Pacman configuration complete."
}

# Enables multilib repository inside chroot environment.
# Global: WANT_MULTILIB
# Uncomments multilib repository in /etc/pacman.conf and syncs package database
enable_multilib_chroot() {
    log_info "Enabling multilib repository..."
    if [ "$WANT_MULTILIB" == "yes" ]; then
        sed -i '/^#\[multilib\]/,+1 s/^#//' /etc/pacman.conf
        pacman -Sy || error_exit "Failed to sync package database after enabling multilib"
    fi
    log_info "Multilib repository configuration complete."
}

# Installs AUR helper (yay or paru) inside chroot environment.
# Global: WANT_AUR_HELPER, AUR_HELPER_CHOICE, MAIN_USERNAME
# Downloads, builds, and installs the selected AUR helper from AUR using proper user context
install_aur_helper_chroot() {
    log_info "Installing AUR helper: $AUR_HELPER_CHOICE"
    if [ "$WANT_AUR_HELPER" == "yes" ]; then
        # Install dependencies first
        install_packages_chroot "base-devel git" || error_exit "Failed to install AUR helper dependencies"
        
        # Create build directory with proper permissions
        local build_dir="/tmp/aur-build"
        mkdir -p "$build_dir"
        chown "$MAIN_USERNAME:$MAIN_USERNAME" "$build_dir"
        
        case "$AUR_HELPER_CHOICE" in
            "yay")
                # Clone and build yay as the main user
                sudo -u "$MAIN_USERNAME" git clone https://aur.archlinux.org/yay.git "$build_dir/yay" || error_exit "Failed to clone yay"
                cd "$build_dir/yay"
                sudo -u "$MAIN_USERNAME" makepkg -si --noconfirm || error_exit "Failed to build yay"
                cd /
                rm -rf "$build_dir/yay"
                ;;
            "paru")
                # Clone and build paru as the main user
                sudo -u "$MAIN_USERNAME" git clone https://aur.archlinux.org/paru.git "$build_dir/paru" || error_exit "Failed to clone paru"
                cd "$build_dir/paru"
                sudo -u "$MAIN_USERNAME" makepkg -si --noconfirm || error_exit "Failed to build paru"
                cd /
                rm -rf "$build_dir/paru"
                ;;
        esac
        
        # Clean up build directory
        rm -rf "$build_dir"
    fi
    log_info "AUR helper installation complete."
}

# Installs Flatpak inside chroot environment.
# Global: WANT_FLATPAK, FLATPAK_PACKAGE
# Installs Flatpak package and enables system helper service
install_flatpak_chroot() {
    log_info "Installing Flatpak..."
    if [ "$WANT_FLATPAK" == "yes" ]; then
        install_packages_chroot "$FLATPAK_PACKAGE" || error_exit "Flatpak installation failed"
        systemctl enable flatpak-system-helper.service || log_warn "Failed to enable flatpak-system-helper service"
    fi
    log_info "Flatpak installation complete."
}

# Installs custom packages inside chroot environment.
# Global: INSTALL_CUSTOM_PACKAGES, CUSTOM_PACKAGES
# Installs user-specified packages from official Arch repositories
install_custom_packages_chroot() {
    log_info "Installing custom packages..."
    if [ "$INSTALL_CUSTOM_PACKAGES" == "yes" ] && [ -n "$CUSTOM_PACKAGES" ]; then
        install_packages_chroot $CUSTOM_PACKAGES || error_exit "Custom packages installation failed"
    fi
    log_info "Custom packages installation complete."
}

# Installs custom AUR packages inside chroot environment.
# Global: INSTALL_CUSTOM_AUR_PACKAGES, CUSTOM_AUR_PACKAGES, AUR_HELPER_CHOICE, MAIN_USERNAME
# Installs user-specified packages from AUR using the selected AUR helper with proper user context
install_custom_aur_packages_chroot() {
    log_info "Installing custom AUR packages..."
    if [ "$INSTALL_CUSTOM_AUR_PACKAGES" == "yes" ] && [ -n "$CUSTOM_AUR_PACKAGES" ]; then
        # Check if AUR helper is available
        if ! command -v "$AUR_HELPER_CHOICE" &>/dev/null; then
            log_warn "AUR helper $AUR_HELPER_CHOICE not found, skipping AUR package installation"
            return 0
        fi
        
        # Create build directory with proper permissions for AUR packages
        local build_dir="/tmp/aur-packages"
        mkdir -p "$build_dir"
        chown "$MAIN_USERNAME:$MAIN_USERNAME" "$build_dir"
        
        # Install AUR packages using the selected helper as the main user
        case "$AUR_HELPER_CHOICE" in
            "yay")
                sudo -u "$MAIN_USERNAME" yay -S --noconfirm --builddir "$build_dir" $CUSTOM_AUR_PACKAGES || log_warn "Some AUR packages failed to install"
                ;;
            "paru")
                sudo -u "$MAIN_USERNAME" paru -S --noconfirm --builddir "$build_dir" $CUSTOM_AUR_PACKAGES || log_warn "Some AUR packages failed to install"
                ;;
            *)
                log_warn "Unknown AUR helper: $AUR_HELPER_CHOICE"
                return 1
                ;;
        esac
        
        # Clean up build directory
        rm -rf "$build_dir"
    fi
    log_info "Custom AUR packages installation complete."
}

# Searches for AUR packages inside chroot environment using the installed AUR helper
# Args: $1 = search term
# Global: AUR_HELPER_CHOICE, MAIN_USERNAME
# Returns search results to stdout for interactive package selection
search_aur_packages_chroot() {
    local search_term="$1"
    local results_file="/tmp/aur_search_chroot.txt"
    
    if [ -z "$search_term" ]; then
        echo "Usage: search_aur_packages_chroot <search_term>"
        return 1
    fi
    
    # Check if AUR helper is available
    if ! command -v "$AUR_HELPER_CHOICE" &>/dev/null; then
        echo "AUR helper $AUR_HELPER_CHOICE not available for search"
        return 1
    fi
    
    echo "Searching AUR for packages matching: $search_term"
    
    # Search using the AUR helper as the main user
    case "$AUR_HELPER_CHOICE" in
        "yay")
            sudo -u "$MAIN_USERNAME" yay -Ss "$search_term" > "$results_file" 2>/dev/null
            ;;
        "paru")
            sudo -u "$MAIN_USERNAME" paru -Ss "$search_term" > "$results_file" 2>/dev/null
            ;;
        *)
            echo "Unknown AUR helper: $AUR_HELPER_CHOICE"
            return 1
            ;;
    esac
    
    if [ ! -s "$results_file" ]; then
        echo "No AUR packages found matching: $search_term"
        return 1
    fi
    
    # Display results with line numbers
    echo "AUR search results:"
    echo "=================="
    nl -w3 -s': ' "$results_file"
    echo "=================="
    
    # Clean up
    rm -f "$results_file"
    return 0
}

# Configures numlock on boot inside chroot environment.
# Global: WANT_NUMLOCK_ON_BOOT
# Installs numlockx package for numlock functionality on boot
configure_numlock_chroot() {
    log_info "Configuring numlock on boot..."
    if [ "$WANT_NUMLOCK_ON_BOOT" == "yes" ]; then
        install_packages_chroot "numlockx" || error_exit "numlockx installation failed"
        # Add numlockx to autostart (this would need desktop-specific configuration)
        log_info "numlockx installed - desktop-specific autostart configuration may be needed"
    fi
    log_info "Numlock configuration complete."
}

# Deploys dotfiles inside chroot environment.
# Global: WANT_DOTFILES_DEPLOYMENT, DOTFILES_REPO_URL, DOTFILES_BRANCH, MAIN_USERNAME
# Clones dotfiles repository and runs installation script if available
deploy_dotfiles_chroot() {
    log_info "Deploying dotfiles..."
    if [ "$WANT_DOTFILES_DEPLOYMENT" == "yes" ] && [ -n "$DOTFILES_REPO_URL" ]; then
        # Install git if not already installed
        install_packages_chroot "git" || error_exit "Git installation failed for dotfiles deployment"
        
        # Clone dotfiles to home directory
        local dotfiles_dir="/home/$MAIN_USERNAME/dotfiles"
        sudo -u "$MAIN_USERNAME" git clone -b "$DOTFILES_BRANCH" "$DOTFILES_REPO_URL" "$dotfiles_dir" || error_exit "Failed to clone dotfiles repository"
        
        # Run dotfiles deployment script if it exists
        if [ -f "$dotfiles_dir/install.sh" ]; then
            sudo -u "$MAIN_USERNAME" bash "$dotfiles_dir/install.sh" || log_warn "Dotfiles installation script failed"
        fi
    fi
    log_info "Dotfiles deployment complete."
}

# Saves mdadm.conf for RAID arrays inside chroot environment.
# Global: WANT_RAID
# Generates mdadm.conf from current RAID array configuration
save_mdadm_conf_chroot() {
    log_info "Saving mdadm.conf for RAID arrays..."
    if [ "$WANT_RAID" == "yes" ]; then
        mdadm --detail --scan > /etc/mdadm.conf || error_exit "Failed to save mdadm.conf"
        edit_file_in_chroot "/etc/mdadm.conf" "s/^#MAILADDR root@mydomain.tld/MAILADDR root/"
    fi
    log_info "mdadm.conf saved."
}

run_in_chroot() {
    local script_to_run="$1"
    
    log_info "Executing chroot script: ${script_to_run}"
    
    # arch-chroot handles mounting /proc, /sys, /dev, etc. automatically
    arch-chroot /mnt /bin/bash -c "${script_to_run}" || error_exit "Chroot script execution failed: ${script_to_run}"
    
    log_info "Chroot script executed successfully."
    return 0
}

# --- Final Cleanup Function ---
final_cleanup() {
    log_info "Cleaning up temporary files..."
    
    # Preserve logs before cleanup
    log_info "Preserving installation logs..."
    if [[ -f "$LOG_FILE" ]]; then
        # Copy to backup location
        cp "$LOG_FILE" "$LOG_BACKUP"
        log_info "Log backup created: $LOG_BACKUP"
        
        # Copy to installed system if still mounted
        if mountpoint -q "/mnt" 2>/dev/null; then
            mkdir -p "/mnt/var/log"
            cp "$LOG_FILE" "/mnt/var/log/archinstall.log"
            log_info "Log copied to installed system: /mnt/var/log/archinstall.log"
        fi
    fi
    
    # Remove Source directory from /mnt
    if [ -d "/mnt/Source" ]; then
        rm -rf /mnt/Source || log_warn "Failed to remove Source directory"
        log_info "Source directory cleaned up"
    fi
    
    log_info "Unmounting all filesystems under /mnt..."
    # The -R flag recursively unmounts all filesystems rooted at the specified directory.
    # The script will exit if this command fails due to 'set -e'.
    umount -R /mnt
    log_success "All temporary filesystems unmounted successfully."
}

# --- Custom Package Installation Functions ---
# Install custom official packages in chroot environment
install_custom_packages_chroot() {
    if [ "$INSTALL_CUSTOM_PACKAGES" == "yes" ] && [ -n "$CUSTOM_PACKAGES" ]; then
        log_info "Installing custom official packages: $CUSTOM_PACKAGES"
        install_packages_chroot "$CUSTOM_PACKAGES" || error_exit "Custom packages installation failed"
        log_info "Custom official packages installed successfully"
    else
        log_info "No custom official packages to install"
    fi
}

# Install custom AUR packages in chroot environment
install_custom_aur_packages_chroot() {
    local aur_packages_to_install=""
    
    # Add user-selected custom AUR packages
    if [ "$INSTALL_CUSTOM_AUR_PACKAGES" == "yes" ] && [ -n "$CUSTOM_AUR_PACKAGES" ]; then
        aur_packages_to_install="$CUSTOM_AUR_PACKAGES"
    fi
    
    # Add btrfs-assistant if user wants it
    if [ "$WANT_BTRFS_ASSISTANT" == "yes" ]; then
        if [ -n "$aur_packages_to_install" ]; then
            aur_packages_to_install="$aur_packages_to_install btrfs-assistant"
        else
            aur_packages_to_install="btrfs-assistant"
        fi
    fi
    
    if [ -n "$aur_packages_to_install" ]; then
        log_info "Installing AUR packages: $aur_packages_to_install"
        
        # Check if AUR helper is available
        if [ "$WANT_AUR_HELPER" == "yes" ] && [ -n "$AUR_HELPER_CHOICE" ]; then
            # Install AUR packages using the selected helper
            case "$AUR_HELPER_CHOICE" in
                "yay")
                    sudo -u "$MAIN_USERNAME" yay -S --noconfirm $aur_packages_to_install || error_exit "AUR packages installation failed with yay"
                    ;;
                "paru")
                    sudo -u "$MAIN_USERNAME" paru -S --noconfirm $aur_packages_to_install || error_exit "AUR packages installation failed with paru"
                    ;;
                *)
                    error_exit "Unknown AUR helper: $AUR_HELPER_CHOICE"
                    ;;
            esac
            log_info "AUR packages installed successfully"
        else
            log_warn "AUR helper not available, skipping AUR packages installation"
        fi
    else
        log_info "No AUR packages to install"
    fi
}

# --- Btrfs Snapshot Configuration Functions ---
# Configure Btrfs snapshots with snapper in chroot environment
configure_btrfs_snapshots_chroot() {
    if [ "$WANT_BTRFS" == "yes" ] && [ "$WANT_BTRFS_SNAPSHOTS" == "yes" ]; then
        log_info "Configuring Btrfs snapshots with snapper..."
        
        # Create snapper configuration for root
        snapper -c root create-config / || error_exit "Failed to create snapper config for root"
        log_info "Created snapper configuration for root"
        
        # Configure snapper settings
        local snapper_config="/etc/snapper/configs/root"
        if [ -f "$snapper_config" ]; then
            # Set snapshot frequency
            case "$BTRFS_SNAPSHOT_FREQUENCY" in
                "hourly")
                    sed -i 's/TIMELINE_CREATE="no"/TIMELINE_CREATE="yes"/' "$snapper_config"
                    sed -i 's/TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="'$BTRFS_KEEP_SNAPSHOTS'"/' "$snapper_config"
                    ;;
                "daily")
                    sed -i 's/TIMELINE_CREATE="no"/TIMELINE_CREATE="yes"/' "$snapper_config"
                    sed -i 's/TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="'$BTRFS_KEEP_SNAPSHOTS'"/' "$snapper_config"
                    ;;
                "weekly")
                    sed -i 's/TIMELINE_CREATE="no"/TIMELINE_CREATE="yes"/' "$snapper_config"
                    sed -i 's/TIMELINE_LIMIT_WEEKLY="0"/TIMELINE_LIMIT_WEEKLY="'$BTRFS_KEEP_SNAPSHOTS'"/' "$snapper_config"
                    ;;
                "monthly")
                    sed -i 's/TIMELINE_CREATE="no"/TIMELINE_CREATE="yes"/' "$snapper_config"
                    sed -i 's/TIMELINE_LIMIT_MONTHLY="10"/TIMELINE_LIMIT_MONTHLY="'$BTRFS_KEEP_SNAPSHOTS'"/' "$snapper_config"
                    ;;
            esac
            
            # Enable automatic cleanup
            sed -i 's/NUMBER_CLEANUP="no"/NUMBER_CLEANUP="yes"/' "$snapper_config"
            sed -i 's/NUMBER_LIMIT="50"/NUMBER_LIMIT="'$BTRFS_KEEP_SNAPSHOTS'"/' "$snapper_config"
            
            log_info "Configured snapper settings for $BTRFS_SNAPSHOT_FREQUENCY snapshots"
        fi
        
        # Enable snapper services
        systemctl enable snapper-timeline.timer || log_warn "Failed to enable snapper-timeline.timer"
        systemctl enable snapper-cleanup.timer || log_warn "Failed to enable snapper-cleanup.timer"
        systemctl enable snapper-boot.timer || log_warn "Failed to enable snapper-boot.timer"
        
        # Configure grub-btrfs for boot menu integration
        if [ "$BOOTLOADER_TYPE" == "grub" ]; then
            log_info "Configuring grub-btrfs for snapshot boot menu..."
            
            # Enable grub-btrfs service
            systemctl enable grub-btrfsd.service || log_warn "Failed to enable grub-btrfsd.service"
            
            # Create initial snapshot
            snapper -c root create --description "Initial system snapshot" || log_warn "Failed to create initial snapshot"
            log_info "Created initial system snapshot"
        fi
        
        log_success "Btrfs snapshots configured successfully"
    else
        log_info "Btrfs snapshots not requested, skipping configuration"
    fi
}

# =============================================================================
# USER ACCOUNT MANAGEMENT FUNCTIONS
# =============================================================================

# --- Input Validation Functions ---
validate_username() {
    local username="$1"
    if [[ "${username,,}" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$ ]]; then
        return 0
    else
        log_error "Invalid username format: $username"
        return 1
    fi
}

validate_hostname() {
    local hostname="$1"
    if [[ "${hostname,,}" =~ ^[a-z][a-z0-9_.-]{0,62}[a-z0-9]$ ]]; then
        return 0
    else
        log_error "Invalid hostname format: $hostname"
        return 1
    fi
}

# --- User Input Functions ---
get_username() {
    log_info "DEBUG: get_username function called"
    log_info "Prompting for username..."
    while true; do
        read -r -p "Enter a username: " username

        if ! validate_username "$username"; then
            continue
        fi

        export USERNAME="$username"
        log_success "Username validation successful: $USERNAME"
        break
    done
}

get_user_password() {
    log_info "DEBUG: get_user_password function called"
    log_info "Prompting for user password..."
    while true; do
        read -rs -p "Set a password for $USERNAME: " USER_PASSWORD1
        echo
        read -rs -p "Confirm password: " USER_PASSWORD2
        echo

        if [[ "$USER_PASSWORD1" != "$USER_PASSWORD2" ]]; then
            log_error "Password confirmation failed - passwords do not match"
            continue
        fi

        if [[ -z "$USER_PASSWORD1" ]]; then
            log_error "Password cannot be empty"
            continue
        fi

        export USER_PASSWORD="$USER_PASSWORD1"
        log_success "User password set successfully for $USERNAME"
        break
    done
}

get_root_password() {
    log_info "DEBUG: get_root_password function called"
    log_info "Prompting for root password..."
    while true; do
        read -rs -p "Set root password: " ROOT_PASSWORD1
        echo
        read -rs -p "Confirm root password: " ROOT_PASSWORD2
        echo

        if [[ "$ROOT_PASSWORD1" != "$ROOT_PASSWORD2" ]]; then
            log_error "Root password confirmation failed - passwords do not match"
            continue
        fi

        if [[ -z "$ROOT_PASSWORD1" ]]; then
            log_error "Root password cannot be empty"
            continue
        fi

        export ROOT_PASSWORD="$ROOT_PASSWORD1"
        log_success "Root password set successfully"
        break
    done
}

get_hostname() {
    log_info "Prompting for hostname..."
    while true; do
        read -r -p "Enter a hostname: " hostname

        if ! validate_hostname "$hostname"; then
            continue
        fi

        export HOSTNAME="$hostname"
        log_success "Hostname validation successful: $HOSTNAME"
        break
    done
}

get_encryption_password() {
    log_info "Prompting for encryption password..."
    while true; do
        read -rs -p "Enter encryption password: " password
        echo
        read -rs -p "Confirm encryption password: " confirm_password
        echo

        if [[ "$password" != "$confirm_password" ]]; then
            log_error "Encryption password confirmation failed - passwords do not match"
            continue
        fi

        if [[ -z "$password" ]]; then
            log_error "Encryption password cannot be empty"
            continue
        fi

        export ENCRYPTION_PASSWORD="$password"
        log_success "Encryption password set successfully"
        break
    done
}

# --- User Account Creation Functions ---
create_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        log_error "create_user: Username parameter is empty"
        return 1
    fi
    
    log_info "Creating user account: $username"
    
    if useradd -m -G wheel,power,storage,uucp,network -s /bin/bash "$username"; then
        log_success "User account created successfully: $username"
        return 0
    else
        log_error "Failed to create user account: $username (exit code: $?)"
        return 1
    fi
}

set_passwords() {
    log_info "Setting passwords in correct order..."

    # Support both parameter-based and environment-variable-based invocation
    local username_param="${1:-}"
    local user_password_param="${2:-}"
    local root_password_param="${3:-}"

    # Resolve effective values with clear precedence: parameters > env vars
    local effective_username="${username_param:-$USERNAME}"
    local effective_user_password="${user_password_param:-$USER_PASSWORD}"
    local effective_root_password="${root_password_param:-$ROOT_PASSWORD}"

    # Validate required values
    if [[ -z "$effective_username" ]]; then
        log_error "set_passwords: username is empty"
        return 1
    fi

    if [[ -z "$effective_user_password" ]]; then
        log_error "set_passwords: user password is empty"
        return 1
    fi

    if [[ -z "$effective_root_password" ]]; then
        log_error "set_passwords: root password is empty"
        return 1
    fi

    # Set root password first to ensure system security
    log_info "Setting root password..."
    if echo "root:$effective_root_password" | chpasswd; then
        log_success "Root password set successfully"
    else
        log_error "Failed to set root password (exit code: $?)"
        return 1
    fi

    # Set user password after root password is secured
    log_info "Setting user password for: $effective_username"
    if echo "$effective_username:$effective_user_password" | chpasswd; then
        log_success "User password set successfully for: $effective_username"
    else
        log_error "Failed to set user password for: $effective_username (exit code: $?)"
        return 1
    fi

    log_success "All passwords set successfully"
    return 0
}

# --- Update sudoers file ---
update_sudoers() {
    log_info "Configuring sudoers file..."
    
    # Create backup of original sudoers file
    if ! cp /etc/sudoers /etc/sudoers.backup; then
        log_error "Failed to create sudoers backup"
        return 1
    fi
    
    # Uncomment the wheel group line in sudoers
    if ! sed -i 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers; then
        log_error "Failed to uncomment wheel group in sudoers"
        return 1
    fi
    
    # Add targetpw default for password prompting
    if ! echo 'Defaults targetpw' >> /etc/sudoers; then
        log_error "Failed to add targetpw default to sudoers"
        return 1
    fi
    
    # Validate sudoers file syntax
    if ! visudo -c; then
        log_error "sudoers file validation failed - restoring backup"
        cp /etc/sudoers.backup /etc/sudoers
        return 1
    fi
    
    log_success "sudoers file configured successfully"
    return 0
}
