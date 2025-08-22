#!/bin/bash
# utils.sh - General helper functions for Archl4tm rewrite (Bash 3.x Compatible)

# ANSI escape codes for colors
readonly C_INFO='\e[32m'
readonly C_WARN='\e[33m'
readonly C_ERROR='\e[31m'
readonly C_HEADER='\e[36;1m'
readonly C_SUCCESS='\e[32;1m'
readonly C_RESET='\e[0m'

log_info() {
    echo -e "${C_INFO}[INFO]${C_RESET} $(date +%T) $*"
}

log_warn() {
    echo -e "${C_WARN}[WARN]${C_RESET} $(date +%T) $*" >&2
}

error_exit() {
    echo -e "${C_ERROR}[ERROR]${C_RESET} $(date +%T) $*" >&2
    exit 1
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
        vfat)   mkfs.vfat -F 32 "$dev_path" || error_exit "Failed to format $dev_path as vfat.";;
        swap)   mkswap "$dev_path" || error_exit "Failed to create swap on $dev_path.";;
        *)      error_exit "Unsupported filesystem type for formatting: $fs_type.";;
    esac
    log_info "$dev_path formatted as $fs_type."
}

# Safely mounts a device to a mount point.
# Args: $1 = device_path, $2 = mount_point
safe_mount() {
    local dev="$1"
    local mnt="$2"
    mkdir -p "$mnt" || error_exit "Failed to create mount point $mnt."
    log_info "Mounting $dev to $mnt..."
    mount "$dev" "$mnt" || error_exit "Failed to mount $dev to $mnt."
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
    log_info "Running pacstrap to install base system with ${KERNEL_TYPE} kernel..."

    local kernel_packages=""
    if [ "$KERNEL_TYPE" == "linux" ]; then
        kernel_packages="linux linux-firmware linux-headers"
    elif [ "$KERNEL_TYPE" == "linux-lts" ]; then
        kernel_packages="linux-lts linux-lts-headers"
    else
        error_exit "Unsupported KERNEL_TYPE: $KERNEL_TYPE."
    fi

    # Pass all arguments passed to run_pacstrap_base_install directly to pacstrap
    # This expects arguments to be individual package names.
    pacstrap -K /mnt "$@" --noconfirm --needed || error_exit "Pacstrap failed to install base system."

    log_info "Pacstrap base system complete."
}

# Installs packages inside the chroot environment.
# Args: $@ = packages to install (e.g., "plasma sddm")
install_packages_chroot() {
    local packages="$@"
    log_info "Installing packages inside chroot: '$packages'..."
    arch-chroot /mnt pacman -S --noconfirm --needed $packages || error_exit "Failed to install packages inside chroot: '$packages'."
    log_info "Packages installed inside chroot: '$packages'."
}

# Updates the entire system inside the chroot.
update_system_chroot() {
    log_info "Updating entire system inside chroot..."
    arch-chroot /mnt pacman -Syu --noconfirm || error_exit "Failed to update system inside chroot."
    log_info "System updated inside chroot."
}

# Installs CPU microcode packages inside the chroot.
# Global: CPU_MICROCODE_TYPE (e.g., "intel", "amd")
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
    arch-chroot /mnt pacman -Sy --noconfirm --needed "$microcode_package" || error_exit "Failed to install $microcode_package inside chroot."
    log_info "$microcode_package installed."
}


# --- File System / Chroot Configuration Utilities ---

# Generates /etc/fstab using UUIDs.
generate_fstab() {
    log_info "Generating fstab using UUIDs..."
    genfstab -U /mnt > /mnt/etc/fstab || error_exit "Failed to generate fstab."
    log_info "fstab generated successfully at /mnt/etc/fstab."
}

# Edits a file inside the chroot using sed.
# Args: $1 = file_path_in_chroot, $2 = sed_expression
edit_file_in_chroot() {
    local file_path="$1"
    local sed_expr="$2"
    log_info "Editing $file_path inside chroot with sed: '$sed_expr'"
    
    # Create a backup before editing
    arch-chroot /mnt cp "$file_path" "${file_path}.bak" || log_warn "Failed to create backup of $file_path."

    arch-chroot /mnt sed -i "$sed_expr" "$file_path" || error_exit "Failed to edit $file_path inside chroot."
    log_info "File $file_path modified."
}

# Enables a systemd service inside the chroot.
# Args: $1 = service_name (e.g., "NetworkManager.service", "gdm")
enable_systemd_service_chroot() {
    local service_name="$1"
    log_info "Enabling systemd service $service_name inside chroot..."
    arch-chroot /mnt systemctl enable "$service_name" || error_exit "Failed to enable service $service_name inside chroot."
    log_info "Service $service_name enabled."
}

# --- Security / Credential Handling ---

# Prompts user for a password securely and validates minimum length.
# Args: $1 = prompt_message, $2 = name_of_variable_to_store_password (string)
secure_password_input() {
    local prompt_msg="$1"
    local result_var_name="$2" # This is now the string name of the result variable

    while true; do
        read -rsp "$prompt_msg (min 8 chars): " "$result_var_name" # Direct expansion here
        echo
        if [ -n "${!result_var_name}" ] && [ ${#result_var_name} -ge 8 ]; then # Check length of expanded value
            break
        else
            log_warn "Password too short or empty. Please enter at least 8 characters."
        fi
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

# --- Final Cleanup ---
final_cleanup() {
    log_info "Performing final cleanup..."
    safe_umount /mnt/boot/efi || true
    safe_umount /mnt/boot || true
    safe_umount /mnt || true
    log_info "Cleanup complete."
}
}
{
type: uploaded file
fileName: install_arch.sh
fullContent:
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
    local chroot_target_dir="/archl4tm"
    local install_script_path_in_chroot="/mnt/$chroot_target_dir"

    mkdir -p "$install_script_path_in_chroot" || error_exit "Failed to create target directory '$install_script_path_in_chroot'."
    
    # Copy chroot_config.sh
    if [ ! -f "$script_root_dir/chroot_config.sh" ]; then
        error_exit "Source file not found: $script_root_dir/chroot_config.sh. Cannot proceed."
    fi
    log_info "Attempting to copy $script_root_dir/chroot_config.sh..."
    cp "$script_root_dir/chroot_config.sh" "$install_script_path_in_chroot/" || error_exit "Failed to copy chroot_config.sh."
    if [ ! -f "$install_script_path_in_chroot/chroot_config.sh" ]; then
        error_exit "Destination file NOT FOUND after copying: $install_script_path_in_chroot/chroot_config.sh."
    fi

    # Copy config.sh
    if [ ! -f "$script_root_dir/config.sh" ]; then
        error_exit "Source file not found: $script_root_dir/config.sh. Cannot proceed."
    fi
    log_info "Attempting to copy $script_root_dir/config.sh..."
    cp "$script_root_dir/config.sh" "$install_script_path_in_chroot/" || error_exit "Failed to copy config.sh to chroot."
    if [ ! -f "$install_script_path_in_chroot/config.sh" ]; then
        error_exit "Destination file NOT FOUND after copying: $install_script_path_in_chroot/config.sh."
    fi

    # Copy utils.sh
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
    
    # Use 'env' to explicitly pass the variables to the chroot session
    env INSTALL_DISK="$INSTALL_DISK" \
    BOOT_MODE="$BOOT_MODE" \
    WANT_ENCRYPTION="$WANT_ENCRYPTION" \
    LUKS_PASSPHRASE="$LUKS_PASSPHRASE" \
    VG_NAME="$VG_NAME" \
    WANT_LVM="$WANT_LVM" \
    WANT_RAID="$WANT_RAID" \
    RAID_LEVEL="$RAID_LEVEL" \
    KERNEL_TYPE="$KERNEL_TYPE" \
    CPU_MICROCODE_TYPE="$CPU_MICROCODE_TYPE" \
    TIMEZONE="$TIMEZONE" \
    LOCALE="$LOCALE" \
    KEYMAP="$KEYMAP" \
    REFLECTOR_COUNTRY_CODE="$REFLECTOR_COUNTRY_CODE" \
    SYSTEM_HOSTNAME="$SYSTEM_HOSTNAME" \
    ROOT_PASSWORD="$ROOT_PASSWORD" \
    MAIN_USERNAME="$MAIN_USERNAME" \
    MAIN_USER_PASSWORD="$MAIN_USER_PASSWORD" \
    DESKTOP_ENVIRONMENT="$DESKTOP_ENVIRONMENT" \
    DISPLAY_MANAGER="$DISPLAY_MANAGER" \
    GPU_DRIVER_TYPE="$GPU_DRIVER_TYPE" \
    BOOTLOADER_TYPE="$BOOTLOADER_TYPE" \
    ENABLE_OS_PROBER="$ENABLE_OS_PROBER" \
    WANT_MULTILIB="$WANT_MULTILIB" \
    WANT_AUR_HELPER="$WANT_AUR_HELPER" \
    AUR_HELPER_CHOICE="$AUR_HELPER_CHOICE" \
    WANT_FLATPAK="$WANT_FLATPAK" \
    INSTALL_CUSTOM_PACKAGES="$INSTALL_CUSTOM_PACKAGES" \
    CUSTOM_PACKAGES="$CUSTOM_PACKAGES" \
    INSTALL_CUSTOM_AUR_PACKAGES="$INSTALL_CUSTOM_AUR_PACKAGES" \
    CUSTOM_AUR_PACKAGES="$CUSTOM_AUR_PACKAGES" \
    WANT_GRUB_THEME="$WANT_GRUB_THEME" \
    GRUB_THEME_CHOICE="$GRUB_THEME_CHOICE" \
    WANT_NUMLOCK_ON_BOOT="$WANT_NUMLOCK_ON_BOOT" \
    WANT_DOTFILES_DEPLOYMENT="$WANT_DOTFILES_DEPLOYMENT" \
    DOTFILES_REPO_URL="$DOTFILES_REPO_URL" \
    DOTFILES_BRANCH="$DOTFILES_BRANCH" \
    EFI_PART_SIZE_MIB="$EFI_PART_SIZE_MIB" \
    BOOT_PART_SIZE_MIB="$BOOT_PART_SIZE_MIB" \
    ROOT_FILESYSTEM_TYPE="$ROOT_FILESYSTEM_TYPE" \
    HOME_FILESYSTEM_TYPE="$HOME_FILESYSTEM_TYPE" \
    WANT_SWAP="$WANT_SWAP" \
    WANT_HOME_PARTITION="$WANT_HOME_PARTITION" \
    PARTITION_UUIDS_EFI_UUID="$PARTITION_UUIDS_EFI_UUID" \
    PARTITION_UUIDS_EFI_PARTUUID="$PARTITION_UUIDS_EFI_PARTUUID" \
    PARTITION_UUIDS_ROOT_UUID="$PARTITION_UUIDS_ROOT_UUID" \
    PARTITION_UUIDS_BOOT_UUID="$PARTITION_UUIDS_BOOT_UUID" \
    PARTITION_UUIDS_SWAP_UUID="$PARTITION_UUIDS_SWAP_UUID" \
    PARTITION_UUIDS_HOME_UUID="$PARTITION_UUIDS_HOME_UUID" \
    PARTITION_UUIDS_LUKS_CONTAINER_UUID="$PARTITION_UUIDS_LUKS_CONTAINER_UUID" \
    PARTITION_UUIDS_LV_ROOT_UUID="$PARTITION_UUIDS_LV_ROOT_UUID" \
    PARTITION_UUIDS_LV_SWAP_UUID="$PARTITION_UUIDS_LV_SWAP_UUID" \
    PARTITION_UUIDS_LV_HOME_UUID="$PARTITION_UUIDS_LV_HOME_UUID" \
    LV_ROOT_PATH="$LV_ROOT_PATH" \
    LV_SWAP_PATH="$LV_SWAP_PATH" \
    LV_HOME_PATH="$LV_HOME_PATH" \
    /usr/bin/arch-chroot /mnt /bin/bash "$chroot_target_dir/chroot_config.sh" || error_exit "Chroot configuration failed."

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
    
    local packages_to_install=() # Initialize an array to hold all packages

    # Add essential base packages
    if [[ ${#BASE_PACKAGES_ESSENTIAL[@]} -gt 0 ]]; then
        packages_to_install+=(${BASE_PACKAGES_ESSENTIAL[@]})
    fi

    local kernel_packages=()
    if [ "$KERNEL_TYPE" == "linux" ]; then
        kernel_packages+=(${BASE_PACKAGES_KERNEL_LINUX[@]})
    elif [ "$KERNEL_TYPE" == "linux-lts" ]; then
        kernel_packages+=(${BASE_PACKAGES_KERNEL_LTS[@]})
    else
        error_exit "Unsupported KERNEL_TYPE: $KERNEL_TYPE."
    fi
    if [[ ${#kernel_packages[@]} -gt 0 ]]; then
        packages_to_install+=(${kernel_packages[@]})
    fi
    
    # Add bootloader, network, and general system utilities
    if [ "$BOOTLOADER_TYPE" == "grub" ]; then
        packages_to_install+=(${BASE_PACKAGES_BOOTLOADER_GRUB[@]})
    fi
    if [ "$BOOTLOADER_TYPE" == "systemd-boot" ]; then
        packages_to_install+=(${BASE_PACKAGES_BOOTLOADER_SYSTEMDBOOT[@]})
    fi
    packages_to_install+=(${BASE_PACKAGES_NETWORK[@]})
    packages_to_install+=(${BASE_PACKAGES_SYSTEM_UTILS[@]})

    # Install LVM/RAID tools if chosen
    if [ "$WANT_LVM" == "yes" ]; then
        packages_to_install+=(${BASE_PACKAGES_LVM[@]})
    fi
    if [ "$WANT_RAID" == "yes" ]; then
        packages_to_install+=(${BASE_PACKAGES_RAID[@]})
    fi
    
    # Add Filesystem utilities based on user choice
    if [ "$ROOT_FILESYSTEM_TYPE" == "btrfs" ]; then
        packages_to_install+=(${BASE_PACKAGES_FS_BTRFS[@]})
    elif [ "$ROOT_FILESYSTEM_TYPE" == "xfs" ]; then
        packages_to_install+=(${BASE_PACKAGES_FS_XFS[@]})
    fi
    
    if [ "$WANT_HOME_PARTITION" == "yes" ]; then
        if [ "$HOME_FILESYSTEM_TYPE" == "btrfs" ]; then
            packages_to_install+=(${BASE_PACKAGES_FS_BTRFS[@]})
        elif [ "$HOME_FILESYSTEM_TYPE" == "xfs" ]; then
            packages_to_install+=(${BASE_PACKAGES_FS_XFS[@]})
        fi
    fi
    
    if [ ${#packages_to_install[@]} -eq 0 ]; then
        error_exit "No packages compiled for base system installation. This should not happen."
    fi

    run_pacstrap_base_install "${packages_to_install[@]}" || error_exit "Base system installation failed."

    generate_fstab # Call the fstab generation after base install, before chroot.

    log_info "Base system installation complete on target."
}

# --- Call the main function ---
main "$@"
}
{
type: uploaded file
fileName: chroot_config.sh
fullContent:
#!/bin/bash
# chroot_config.sh - Functions for post-base-install (chroot) configurations
# This script is designed to be copied into the /mnt environment and executed by arch-chroot.

# Strict mode for this script
set -euo pipefail

# Source its own copy of config.sh and utils.sh from its copied location
SOURCE_DIR_IN_CHROOT="/archl4tm" # Path where install_arch.sh copies these scripts
source "$SOURCE_DIR_IN_CHROOT/config.sh"
source "$SOURCE_DIR_IN_CHROOT/utils.sh"

# Note: Variables like INSTALL_DISK, ROOT_PASSWORD, etc. are now populated from the environment passed by install_arch.sh
# Associative arrays like PARTITION_UUIDs are also exported (-A).
# So, they will be directly available in this script's scope.

# Re-define basic logging functions to ensure they are available within this script's context.
# These will override the log_* from utils.sh that might be sourced, but are safer for this context
# and ensure consistency if utils.sh is modified.
_log_info() { echo -e "\e[32m[INFO]\e[0m $(date +%T) $*"; }
_log_warn() { echo -e "\e[33m[WARN]\e[0m $(date +%T) $*" >&2; }
_log_error() { echo -e "\e[31m[ERROR]\e[0m $(date +%T) $*" >&2; exit 1; }
_log_success() { echo -e "\n\e[32;1m==================================================\e[0m\n\e[32;1m $* \e[0m\n\e[32;1m==================================================\e[0m\n"; }


# Main function for chroot configuration - this is now the entry point for this script
main_chroot_config() {
    _log_info "Starting chroot configurations within target system."

    # --- Phase 1: Basic System Configuration ---
    _log_info "Configuring time, locale, hostname, and basic user setup."

    _log_info "Setting system clock and timezone..."
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime || _log_error "Failed to set timezone symlink."
    hwclock --systohc || _log_error "Failed to sync hardware clock."

    _log_info "Setting localization (locale, keymap)..."
    echo "LANG=$LOCALE" > /etc/locale.conf || _log_error "Failed to set locale.conf."
    sed -i "/^#$(echo "$LOCALE" | sed 's/\./\\./g')/s/^#//" /etc/locale.gen || _log_error "Failed to uncomment locale in locale.gen."
    locale-gen || _log_error "Failed to generate locales."
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf || _log_error "Failed to set vconsole.conf."

    _log_info "Setting hostname and /etc/hosts..."
    echo "$SYSTEM_HOSTNAME" > /etc/hostname || _log_error "Failed to set hostname."
    echo "127.0.0.1 localhost" > /etc/hosts || _log_error "Failed to write to /etc/hosts."
    echo "::1       localhost" >> /etc/hosts || _log_error "Failed to append to /etc/hosts."
    echo "127.0.1.1 $SYSTEM_HOSTNAME.localdomain $SYSTEM_HOSTNAME" >> /etc/hosts || _log_error "Failed to append to /etc/hosts."
    _log_info "/etc/hosts configured."

    _log_info "Setting root password..."
    echo "root:$ROOT_PASSWORD" | chpasswd || _log_error "Failed to set root password."

    _log_info "Creating main user: $MAIN_USERNAME..."
    if id -u "$MAIN_USERNAME" &>/dev/null; then
        _log_warn "User '$MAIN_USERNAME' already exists. Skipping user creation."
    else
        useradd -m -G wheel -s /bin/bash "$MAIN_USERNAME" || _log_error "Failed to create user '$MAIN_USERNAME'."
        echo "$MAIN_USERNAME:$MAIN_USER_PASSWORD" | chpasswd || _log_error "Failed to set password for '$MAIN_USERNAME'."
        echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel-sudo || _log_error "Failed to configure sudoers."
        chmod 0440 /etc/sudoers.d/10-wheel-sudo || _log_error "Failed to set permissions on sudoers file."
    fi

    # --- Phase 2: Bootloader & Initramfs ---
    _log_info "Configuring bootloader, GRUB defaults, theme, and mkinitpio hooks."
    configure_bootloader_chroot || _log_error "Bootloader installation failed."

    configure_grub_defaults_chroot || _log_error "GRUB default configuration failed."

    configure_grub_theme_chroot || _log_error "GRUB theme configuration failed."

    configure_grub_cmdline_chroot || _log_error "GRUB kernel command line configuration failed."

    configure_mkinitpio_hooks_chroot || _log_error "Mkinitpio hooks configuration or initramfs rebuild failed."


    # --- Phase 3: Desktop Environment & Drivers ---
    _log_info "Installing Desktop Environment: $DESKTOP_ENVIRONMENT..."
    local de_packages=""
    case "$DESKTOP_ENVIRONMENT" in
        "gnome") de_packages="${DESKTOP_ENVIRONMENTS_GNOME_PACKAGES[@]}" ;;
        "kde") de_packages="${DESKTOP_ENVIRONMENTS_KDE_PACKAGES[@]}" ;;
        "hyprland") de_packages="${DESKTOP_ENVIRONMENTS_HYPRLAND_PACKAGES[@]}" ;;
        "none") de_packages="" ;;
    esac
    if [[ -n "$de_packages" ]]; then
        install_packages_chroot "$de_packages" || _log_error "Desktop Environment packages installation failed."
    fi

    _log_info "Installing Display Manager: $DISPLAY_MANAGER..."
    local dm_packages=""
    case "$DISPLAY_MANAGER" in
        "gdm") dm_packages="${DISPLAY_MANAGERS_GDM_PACKAGES[@]}" ;;
        "sddm") dm_packages="${DISPLAY_MANAGERS_SDDM_PACKAGES[@]}" ;;
        "none") dm_packages="" ;;
    esac
    if [[ -n "$dm_packages" ]]; then
        install_packages_chroot "$dm_packages" || _log_error "Display Manager packages installation failed."
        enable_systemd_service_chroot "$DISPLAY_MANAGER" || _log_error "Failed to enable Display Manager service."
    fi
    
    _log_info "Installing GPU Drivers..."
    install_gpu_drivers_chroot || _log_error "GPU driver installation failed."

    _log_info "Installing CPU Microcode..."
    install_microcode_chroot || _log_error "CPU Microcode installation failed."


    # --- Phase 4: Optional Software & User Customization ---
    _log_info "Enabling Multilib repository..."
    enable_multilib_chroot || _log_error "Multilib repository configuration failed."

    _log_info "Installing AUR Helper..."
    install_aur_helper_chroot || _log_error "AUR Helper installation failed."

    _log_info "Installing Flatpak..."
    install_flatpak_chroot || _log_error "Flatpak installation failed."

    _log_info "Installing Custom Packages..."
    install_custom_packages_chroot || _log_error "Custom packages installation failed."

    _log_info "Installing AUR Numlock on Boot..."
    configure_numlock_chroot || _log_error "Numlock on boot configuration failed."

    _log_info "Deploying Dotfiles..."
    deploy_dotfiles_chroot || _log_error "Dotfile deployment failed."

    _log_info "Saving mdadm.conf for RAID arrays..."
    save_mdadm_conf_chroot || _log_error "Mdadm.conf saving failed."

    # --- Phase 5: Final System Services ---
    _log_info "Enabling essential system services..."
    enable_systemd_service_chroot "NetworkManager" || _log_error "Failed to enable NetworkManager service."

    _log_success "Chroot configuration complete."
}

# --- Call the main function for chroot_config.sh ---
main_chroot_config "$@"

# --- Functions called by main_chroot_config (run INSIDE chroot context) ---
# Note: These functions assume they are already running inside the chroot environment.
# They should NOT have 'arch-chroot /mnt' prefixes.
# They use the _log_* variants for logging.

configure_bootloader_chroot() {
    case "$BOOTLOADER_TYPE" in
        grub)
            _log_info "Installing GRUB for $BOOT_MODE..."
            if [ "$BOOT_MODE" == "uefi" ]; then
                grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || _log_error "GRUB UEFI installation failed."
            else
                grub-install "$INSTALL_DISK" || _log_error "GRUB BIOS installation failed."
            fi
            
            _log_info "Generating GRUB configuration file..."
            grub-mkconfig -o /boot/grub/grub.cfg || _log_error "GRUB configuration generation failed."
            ;;
        systemd-boot)
            _log_info "Installing systemd-boot..."
            bootctl install || _log_error "systemd-boot installation failed."
            configure_systemd_boot_entries_chroot || _log_error "systemd-boot configuration failed."
            ;;
        *)
            _log_warn "No bootloader selected or invalid. Skipping bootloader installation."
            ;;
    esac
}

# Configures systemd-boot loader entries.
configure_systemd_boot_entries_chroot() {
    _log_info "Creating systemd-boot loader entries..."

    # Create the loader.conf file
    local loader_conf_path="/boot/loader/loader.conf"
    if [ ! -f "$loader_conf_path" ]; then
        _log_info "Creating $loader_conf_path..."
        echo "default  arch.conf" > "$loader_conf_path"
        echo "timeout  3" >> "$loader_conf_path"
    fi

    # Create the Arch Linux boot entry file
    local arch_conf_path="/boot/loader/entries/arch.conf"
    _log_info "Creating $arch_conf_path..."
    
    local grub_default_file="/etc/default/grub" # This is a dummy for the function
    local temp_kernel_cmdline=$(configure_grub_cmdline_chroot)
    local kernel_cmdline=$(echo "$temp_kernel_cmdline" | grep -E 'root=UUID=|cryptdevice=')
    
    local kernel_path="/vmlinuz-$KERNEL_TYPE"
    local initramfs_path="/initramfs-$KERNEL_TYPE.img"

    echo "title   Arch Linux" > "$arch_conf_path"
    echo "linux   $kernel_path" >> "$arch_conf_path"
    echo "initrd  $initramfs_path" >> "$arch_conf_path"
    echo "options $kernel_cmdline" >> "$arch_conf_path"

    _log_info "systemd-boot entry created."
}

# Helper to clone a Git repository inside the chroot.
# Args: $1 = repo_url, $2 = target_dir_in_chroot, $3 = branch (optional)
git_clone_chroot() {
    local repo_url="$1"
    local target_dir="$2"
    local branch_arg=""
    if [ -n "$3" ]; then
        branch_arg="--branch $3"
    fi
    _log_info "Cloning $repo_url into $target_dir..."
    git clone --depth 1 $branch_arg "$repo_url" "$target_dir" || _log_error "Git clone failed for $repo_url."
}

# Configures GRUB default settings.
configure_grub_defaults_chroot() {
    local grub_default_file="/etc/default/grub"

    _log_info "Setting GRUB default configurations in $grub_default_file..."

    edit_file_in_chroot "$grub_default_file" "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=saved|"
    edit_file_in_chroot "$grub_default_file" "s|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=3|"
    edit_file_in_chroot "$grub_default_file" "s|^#GRUB_SAVEDEFAULT=true|GRUB_SAVEDEFAULT=true|" || true

    if [ "$WANT_ENCRYPTION" == "yes" ]; then
        _log_info "Enabling GRUB_ENABLE_CRYPTODISK for encrypted setup."
        edit_file_in_chroot "$grub_default_file" "s|^#GRUB_ENABLE_CRYPTODISK=y|GRUB_ENABLE_CRYPTODISK=y|" || true
    fi

    # Add GRUB locale file
    local grub_locale_dir="/boot/grub/locale"
    if [ ! -d "$grub_locale_dir" ]; then
        _log_info "Creating GRUB locale directory."
        mkdir -p "$grub_locale_dir" || _log_error "Failed to create $grub_locale_dir."
    fi

    local base_locale=$(echo "$LOCALE" | cut -d'.' -f1)
    local grub_locale_source_file="/usr/share/locale/$base_locale/LC_MESSAGES/grub.mo"

    _log_info "Checking for GRUB locale file at $grub_locale_source_file."
    if [ -f "$grub_locale_source_file" ]; then
        _log_info "Copying locale file for GRUB."
        cp "$grub_locale_source_file" "$grub_locale_dir/$base_locale.mo" || _log_error "Failed to copy GRUB locale file."
    else
        _log_warn "GRUB locale file not found for '$base_locale'. Falling back to 'en'."
        # Fall back to English locale if the chosen one is not available
        cp "/usr/share/locale/en@quot/LC_MESSAGES/grub.mo" "$grub_locale_dir/en.mo" || _log_error "Failed to copy default GRUB locale file."
    fi

    _log_info "GRUB default configurations applied."
}

# Configures and installs the chosen GRUB theme within the chroot.
configure_grub_theme_chroot() {
    if [ "$WANT_GRUB_THEME" == "no" ] || [ "$GRUB_THEME_CHOICE" == "Default" ]; then
        _log_info "GRUB theming not requested or default theme chosen. Skipping."
        return 0
    fi

    local theme_name="$GRUB_THEME_CHOICE"
    local theme_info_string=""

    # Correctly get the theme URL and file path using case statement and eval
    case "$theme_name" in
        "PolyDark")         eval "theme_info_string=\"\${GRUB_THEME_SOURCES_POLY_DARK[*]}\"";;
        "CyberEXS")         eval "theme_info_string=\"\${GRUB_THEME_SOURCES_CYBEREXS[*]}\"";;
        "CyberPunk")        eval "theme_info_string=\"\${GRUB_THEME_SOURCES_CYBERPUNK[*]}\"";;
        "HyperFluent")      eval "theme_info_string=\"\${GRUB_THEME_SOURCES_HYPERFLUENT[*]}\"";;
        *)                  _log_warn "No source info defined for GRUB theme '$theme_name'. Skipping theming."; return 0;;
    esac

    IFS='|' read -r theme_repo_url theme_file_in_repo_relative <<< "$theme_info_string"
    local theme_clone_dir="/tmp/grub_theme_clone" # Temporary clone location
    
    _log_info "Installing GRUB theme: $theme_name from $theme_repo_url..."

    git_clone_chroot "$theme_repo_url" "$theme_clone_dir" || return 1

    local actual_theme_source_dir_in_clone=""
    if [ "$(dirname "$theme_file_in_repo_relative")" == "." ]; then
        actual_theme_source_dir_in_clone="$theme_clone_dir"
    else
        actual_theme_source_dir_in_clone="${theme_clone_dir}/$(dirname "$theme_file_in_repo_relative")"
    fi

    # Check if the calculated source directory actually exists in the chroot
    if [ ! -d "$actual_theme_source_dir_in_clone" ]; then
        _log_error "Calculated theme source directory '$actual_theme_source_dir_in_clone' not found in cloned repo."
    fi

    local final_grub_theme_install_dir="/boot/grub/themes/$theme_name"
    local final_theme_txt_path="${final_grub_theme_install_dir}/$(basename "$theme_file_in_repo_relative")" # Path for GRUB_THEME=

    _log_info "Copying theme files from '$actual_theme_source_dir_in_clone' to '$final_grub_theme_install_dir'..."
    mkdir -p "$final_grub_theme_install_dir" || _log_error "Failed to create theme directory $final_grub_theme_install_dir."
    rsync -av "${actual_theme_source_dir_in_clone}/" "$final_grub_theme_install_dir/" || _log_error "Failed to copy GRUB theme files."

    local grub_default_file="/etc/default/grub"
    local theme_config_line="GRUB_THEME=\"$final_theme_txt_path\""

    _log_info "Updating $grub_default_file with GRUB_THEME: $theme_config_line"
    edit_file_in_chroot "$grub_default_file" "s|^GRUB_THEME=.*|$theme_config_line|" || \
    edit_file_in_chroot "$grub_default_file" "/^GRUB_CMDLINE_LINUX_DEFAULT=/a $theme_config_line" || \
    edit_file_in_chroot "$grub_default_file" "$ a $theme_config_line"

    rm -rf "$theme_clone_dir" || _log_warn "Failed to remove temporary GRUB theme clone directory."

    _log_info "GRUB theme $theme_name installed and configured."
    
    chown -R root:root "$final_grub_theme_install_dir" || _log_warn "Failed to set ownership for GRUB theme directory."
}

# Configures GRUB kernel command line.
configure_grub_cmdline_chroot() {
    local kernel_cmdline=""

    # Add NVMe specific parameter if applicable
    if [[ "$(get_device_type "$INSTALL_DISK")" == "nvme" ]]; then
        kernel_cmdline+=" nvme_load=YES"
    fi

    # Add GPU specific parameters for modesetting
    case "$GPU_DRIVER_TYPE" in
        "amd")      kernel_cmdline+=" amdgpu.modeset=1 amdgpu.dc=1";;
        "nvidia")   kernel_cmdline+=" nvidia-drm.modeset=1";;
        "intel")    kernel_cmdline+=" i915.modeset=1";;
    esac

    if [ "$WANT_ENCRYPTION" == "yes" ]; then
        local luks_container_uuid="${PARTITION_UUIDS_LUKS_CONTAINER_UUID}"
        if [ -z "$luks_container_uuid" ]; then
            _log_error "LUKS UUID not found for GRUB command line."
        fi
        kernel_cmdline+=" ${GRUB_CMDLINE_LUKS_BASE/<LUKS_CONTAINER_UUID>/$luks_container_uuid}"
    fi

    if [ "$WANT_LVM" == "yes" ]; then
        kernel_cmdline+=" ${GRUB_CMDLINE_LVM_ON_LUKS}"
    fi

    local root_fs_uuid="${PARTITION_UUIDS_LV_ROOT_UUID}"
    if [ -z "$root_fs_uuid" ]; then
        root_fs_uuid="${PARTITION_UUIDS_ROOT_UUID}"
    fi

    if [ -z "$root_fs_uuid" ]; then
        _log_error "Could not determine root filesystem UUID for GRUB_CMDLINE_LINUX_DEFAULT."
    fi
    kernel_cmdline+=" root=UUID=$root_fs_uuid"

    kernel_cmdline+=" loglevel=3 quiet"

    if [ "$ENABLE_OS_PROBER" == "yes" ]; then
        _log_info "Enabling OS Prober in GRUB."
        edit_file_in_chroot "/etc/default/grub" "s|^#GRUB_DISABLE_OS_PROBER=true|GRUB_DISABLE_OS_PROBER=false|" || true
    fi

    kernel_cmdline=$(echo "$kernel_cmdline" | xargs)

    if [ -n "$kernel_cmdline" ]; then
        _log_info "Setting GRUB_CMDLINE_LINUX_DEFAULT=\"$kernel_cmdline\""
        edit_file_in_chroot "$grub_default_file" "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$kernel_cmdline\"|"
    fi

    _log_info "GRUB command line configured."
}

# Configures mkinitcpio hooks and rebuilds initramfs.
configure_mkinitcpio_hooks_chroot() {
    local hooks_string="$INITCPIO_BASE_HOOKS"
    local modules_string=""

    if [[ "$(get_device_type "$INSTALL_DISK")" == "nvme" ]]; then
        hooks_string+=" $INITCPIO_NVME_HOOK"
    fi
    if [ "$WANT_ENCRYPTION" == "yes" ]; then
        hooks_string+=" $INITCPIO_LUKS_HOOK"
    fi
    if [ "$WANT_LVM" == "yes" ]; then
        hooks_string+=" $INITCPIO_LVM_HOOK"
    fi
    if [ "$WANT_RAID" == "yes" ]; then
        hooks_string+=" $INITCPIO_RAID_HOOK"
    fi

    # Add NVIDIA modules if applicable
    if [ "$GPU_DRIVER_TYPE" == "nvidia" ]; then
        modules_string="MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)"
    fi

    hooks_string=$(echo "$hooks_string" | xargs)

    _log_info "Setting mkinitcpio HOOKS=($hooks_string)..."
    edit_file_in_chroot "/etc/mkinitcpio.conf" "s/^HOOKS=.*/HOOKS=($hooks_string)/"

    # Add NVIDIA modules if they exist
    if [ -n "$modules_string" ]; then
        _log_info "Setting mkinitcpio modules for NVIDIA..."
        edit_file_in_chroot "/etc/mkinitcpio.conf" "s|^#MODULES=()|$modules_string|"
    fi

    _log_info "Running mkinitcpio -P to rebuild initramfs..."
    mkinitcpio -P || return 1
    _log_info "Initramfs rebuilt."
}

# Installs GPU drivers based on detected type.
install_gpu_drivers_chroot() {
    if [ "$GPU_DRIVER_TYPE" == "none" ]; then
        _log_info "No specific GPU driver type detected or needed. Skipping GPU driver installation."
        return 0
    fi

    local gpu_packages=""
    case "$GPU_DRIVER_TYPE" in
        "amd")      gpu_packages="${GPU_DRIVERS_AMD_PACKAGES[@]}";;
        "nvidia")   gpu_packages="${GPU_DRIVERS_NVIDIA_PACKAGES[@]}";;
        "intel")    gpu_packages="${GPU_DRIVERS_INTEL_PACKAGES[@]}";;
        "none")     gpu_packages="";;
    esac

    if [ -z "$gpu_packages" ]; then
        _log_warn "No packages defined for GPU driver type '$GPU_DRIVER_TYPE'. Skipping installation."
        return 0
    fi

    _log_info "Installing $GPU_DRIVER_TYPE GPU drivers: '$gpu_packages'..."
    install_packages_chroot "$gpu_packages" || return 1
    _log_info "GPU driver installation complete."
}

# Enables the Multilib repository in pacman.conf.
enable_multilib_chroot() {
    if [ "$WANT_MULTILIB" == "no" ]; then
        log_info "Multilib repository not requested. Skipping."
        return 0
    fi

    _log_info "Enabling Multilib repository in /etc/pacman.conf..."
    edit_file_in_chroot "/etc/pacman.conf" "s|^#\[multilib\]|\\[multilib\]|"
    edit_file_in_chroot "/etc/pacman.conf" "s|^#Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/mirrorlist|"

    _log_info "Syncing pacman databases for Multilib."
    pacman -Sy --noconfirm || return 1
    _log_info "Multilib repository enabled."
}

# Installs the chosen AUR helper.
install_aur_helper_chroot() {
    if [ "$WANT_AUR_HELPER" == "no" ] || [ -z "$AUR_HELPER_CHOICE" ]; then
        _log_info "AUR helper not requested. Skipping."
        return 0
    fi

    local helper_package_name=""
    case "$AUR_HELPER_CHOICE" in
        "yay") helper_package_name="${AUR_HELPERS_YAY_PACKAGES[@]}" ;;
        "paru") helper_package_name="${AUR_HELPERS_PARU_PACKAGES[@]}" ;;
    esac

    if [ -z "$helper_package_name" ]; then
        _log_error "AUR helper package name not defined for '$AUR_HELPER_CHOICE'."
    fi

    _log_info "Installing AUR helper: $AUR_HELPER_CHOICE ($helper_package_name)..."
    
    local user_home="/home/$MAIN_USERNAME"
    local temp_aur_dir="$user_home/aur_build_temp"

    # Define logging functions within this subshell for su -c context
    # This ensures logging works within the non-root execution
    bash -c "
        _log_info() { echo -e \"\e[32m[INFO]\e[0m $(date +%T) \$1\"; }
        _log_warn() { echo -e \"\e[33m[WARN]\e[0m $(date +%T) \$1\" >&2; }
        _log_error() { echo -e \"\e[31m[ERROR]\e[0m $(date +%T) \$1\" >&2; exit 1; }

        _log_info \"Building and installing $AUR_HELPER_CHOICE as user $MAIN_USERNAME...\"
        mkdir -p \"$temp_aur_dir\" || _log_error \"Failed to create temporary AUR directory.\"
        cd \"$temp_aur_dir\" || _log_error \"Failed to navigate to temporary AUR directory.\"
        git clone https://aur.archlinux.org/${helper_package_name}.git || _log_error \"Failed to clone AUR helper repository.\"
        cd \"$helper_package_name\" || _log_error \"Failed to navigate into cloned AUR helper directory.\"
        makepkg -si --noconfirm || _log_error \"makepkg failed for $AUR_HELPER_CHOICE.\"
        _log_info \"Cleaning up temporary AUR directory.\"
        rm -rf \"$temp_aur_dir\" || _log_warn \"Failed to remove temporary AUR build directory.\"
    " || return 1
    log_info "AUR helper $AUR_HELPER_CHOICE installed."
}

# Installs Flatpak and adds Flathub remote.
install_flatpak_chroot() {
    if [ "$WANT_FLATPAK" == "no" ]; then
        log_info "Flatpak support not requested. Skipping."
        return 0
    fi

    _log_info "Installing Flatpak..."
    install_packages_chroot "$FLATPAK_PACKAGE" || return 1

    _log_info "Adding Flathub remote..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || return 1
    _log_info "Flatpak installed and Flathub remote added."
}

# Installs custom packages from official repos and AUR.
install_custom_packages_chroot() {
    if [ "$INSTALL_CUSTOM_PACKAGES" == "yes" ] && [ -n "$CUSTOM_PACKAGES" ]; then
        log_info "Installing custom official packages: '$CUSTOM_PACKAGES'..."
        install_packages_chroot "$CUSTOM_PACKAGES" || return 1
    else
        log_info "No custom official packages requested. Skipping."
    fi

    if [ "$INSTALL_CUSTOM_AUR_PACKAGES" == "yes" ] && [ -n "$CUSTOM_AUR_PACKAGES" ]; then
        if [ "$WANT_AUR_HELPER" == "no" ]; then
            log_warn "Custom AUR packages requested, but no AUR helper selected. Skipping AUR package installation."
            return 0
        fi
        
        local aur_install_cmd="${AUR_HELPER_CHOICE} -S --noconfirm --needed"
        log_info "Installing custom AUR packages: '$CUSTOM_AUR_PACKAGES' using $AUR_HELPER_CHOICE..."
        
        # Define logging functions within this subshell for su -c context
        bash -c "
            _log_info() { echo -e \"\e[32m[INFO]\e[0m $(date +%T) \$1\"; }
            _log_warn() { echo -e \"\e[33m[WARN]\e[0m $(date +%T) \$1\" >&2; }
            _log_error() { echo -e \"\e[31m[ERROR]\e[0m $(date +%T) \$1\" >&2; exit 1; }

            _log_info \"Running $AUR_HELPER_CHOICE to install custom AUR packages as user $MAIN_USERNAME...\"
            $aur_install_cmd $CUSTOM_AUR_PACKAGES || _log_error \"Failed to install custom AUR packages.\"
        " || return 1
        log_info "Custom AUR packages installed."
    else
        log_info "No custom AUR packages requested. Skipping."
    fi
}

# Deploys dotfiles from a Git repository to the main user's home directory.
# Global: MAIN_USERNAME, DOTFILES_REPO_URL, DOTFILES_BRANCH, WANT_DOTFILES_DEPLOYMENT (from config.sh)
deploy_dotfiles_chroot() {
    if [ "$WANT_DOTFILES_DEPLOYMENT" == "no" ] || [ -z "$DOTFILES_REPO_URL" ]; then
        log_info "Dotfile deployment not requested or repository URL not provided. Skipping."
        return 0
    fi

    log_info "Deploying dotfiles for user '$MAIN_USERNAME' from $DOTFILES_REPO_URL (branch: $DOTFILES_BRANCH)..."

    local user_home="/home/$MAIN_USERNAME"
    local dotfiles_clone_dir="$user_home/dotfiles_repo_temp"

    # Run commands as the new user, using a new login shell to ensure correct environment
    # Define logging functions within this subshell for su -c context
    bash -c "
        _log_info() { echo -e \"\e[32m[INFO]\e[0m $(date +%T) \$1\"; }
        _log_warn() { echo -e \"\e[33m[WARN]\e[0m $(date +%T) \$1\" >&2; }
        _log_error() { echo -e \"\e[31m[ERROR]\e[0m $(date +%T) \$1\" >&2; exit 1; }

        _log_info \"Cloning dotfiles repository...\"
        git clone --depth 1 --branch \"$DOTFILES_BRANCH\" \"$DOTFILES_REPO_URL\" \"$dotfiles_clone_dir\" || _log_error \"Failed to clone dotfiles repository.\"
        
        if [ ! -d \"$dotfiles_clone_dir\" ]; then
            _log_error \"Dotfiles repository did not clone correctly to $dotfiles_clone_dir.\"
            exit 1
        fi

        _log_info \"Running dotfiles deployment script...\"
        if [ -f \"$dotfiles_clone_dir/install.sh\" ]; then
            bash \"$dotfiles_clone_dir/install.sh\" || _log_error \"Dotfiles install.sh script failed.\"
        elif [ -f \"$dotfiles_clone_dir/setup.sh\" ]; then
            bash \"$dotfiles_clone_dir/setup.sh\" || _log_error \"Dotfiles setup.sh script failed.\"
        elif [ -f \"$dotfiles_clone_dir/bootstrap.sh\" ]; then
            bash \"$dotfiles_clone_dir/bootstrap.sh\" || _log_error \"Dotfiles bootstrap.sh script failed.\"
        else
            _log_warn \"No common dotfile deployment script (install.sh, setup.sh, bootstrap.sh) found in repo. User might need to manually deploy dotfiles.\"
        fi

        _log_info \"Cleaning up temporary dotfiles clone directory.\"
        rm -rf \"$dotfiles_clone_dir\" || _log_warn \"Failed to remove temporary dotfiles clone directory.\"
        
        _log_info \"Dotfile deployment for '$MAIN_USERNAME' complete.\"
    " || return 1
}

# Configures Numlock to be enabled on boot.
configure_numlock_chroot() {
    if [ "$WANT_NUMLOCK_ON_BOOT" == "no" ] || [ "$WANT_AUR_HELPER" == "no" ] || [ -z "$AUR_HELPER_CHOICE" ]; then
        log_info "Numlock on boot not requested, or AUR helper is not installed. Skipping."
        return 0
    fi

    log_info "Installing AUR package 'mkinitcpio-numlock' using '$AUR_HELPER_CHOICE'..."
    local numlock_install_cmd="${AUR_HELPER_CHOICE} -S mkinitcpio-numlock --noconfirm --needed"

    # Run commands as the main user to install from AUR
    bash -c "
        _log_info() { echo -e \"\e[32m[INFO]\e[0m $(date +%T) \$1\"; }
        _log_warn() { echo -e \"\e[33m[WARN]\e[0m $(date +%T) \$1\" >&2; }
        _log_error() { echo -e \"\e[31m[ERROR]\e[0m $(date +%T) \$1\" >&2; exit 1; }
        
        _log_info \"Running $AUR_HELPER_CHOICE as user $MAIN_USERNAME...\"
        cd /home/$MAIN_USERNAME || _log_error \"Failed to navigate to user's home directory.\"
        $numlock_install_cmd || _log_error \"Failed to install mkinitcpio-numlock from AUR.\"
    " || return 1

    log_info "Editing /etc/mkinitcpio.conf to add numlock hook..."
    edit_file_in_chroot "/etc/mkinitcpio.conf" "s/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap numlock filesystems fsck)/" || return 1
    
    log_info "Rebuilding initramfs with new hook..."
    mkinitcpio -p linux || return 1

    log_info "Numlock on boot enabled."
}

# Saves mdadm.conf for RAID arrays.
save_mdadm_conf_chroot() {
    if [ "$WANT_RAID" == "no" ]; then
        log_info "RAID not configured. Skipping mdadm.conf saving."
        return 0
    fi

    log_info "Saving mdadm.conf for RAID arrays..."
    mdadm --detail --scan > /etc/mdadm.conf || log_error "Failed to save mdadm.conf."
    log_info "mdadm.conf saved."
}

# --- Final Cleanup ---
final_cleanup() {
    log_info "Performing final cleanup..."
    safe_umount /mnt/boot/efi || true
    safe_umount /mnt/boot || true
    safe_umount /mnt || true
    log_info "Cleanup complete."
}
