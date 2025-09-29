#!/bin/bash
# utils.sh - Utility functions for Arch Linux installer

# Logging configuration
LOG_FILE="/tmp/archinstall.log"

# Enhanced logging with automatic log file creation
setup_logging() {
    # Create log file
    {
        echo "=========================================="
        echo "ArchInstall Log - $(date)"
        echo "System: $(uname -a)"
        echo "User: $(whoami)"
        echo "Working Directory: $(pwd)"
        echo "=========================================="
        echo ""
    } > "$LOG_FILE" 2>/dev/null || {
        echo "Warning: Could not create log file, logging to stdout only"
    }
}

# Log functions
log_info() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] INFO: $message"
    echo "[$timestamp] INFO: $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] ERROR: $message" >&2
    echo "[$timestamp] ERROR: $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] SUCCESS: $message"
    echo "[$timestamp] SUCCESS: $message" >> "$LOG_FILE" 2>/dev/null || true
}

# Error handling
error_exit() {
    local message="$1"
    log_error "$message"
    exit 1
}

# Validation functions
validate_disk() {
    local disk="$1"
    if [ -z "$disk" ]; then
        log_error "Disk path is empty"
        return 1
    fi
    
    if [ ! -b "$disk" ]; then
        log_error "Disk $disk does not exist or is not a block device"
        return 1
    fi
    
    log_info "Disk $disk validated successfully"
    return 0
}

validate_username() {
    local username="$1"
    if [ -z "$username" ]; then
        log_error "Username is empty"
        return 1
    fi
    
    if ! echo "$username" | grep -qE '^[a-zA-Z0-9._-]+$'; then
        log_error "Username contains invalid characters"
        return 1
    fi
    
    log_info "Username $username validated successfully"
    return 0
}

validate_hostname() {
    local hostname="$1"
    if [ -z "$hostname" ]; then
        log_error "Hostname is empty"
        return 1
    fi
    
    if ! echo "$hostname" | grep -qE '^[a-zA-Z0-9.-]+$'; then
        log_error "Hostname contains invalid characters"
        return 1
    fi
    
    log_info "Hostname $hostname validated successfully"
    return 0
}

# Device and UUID management functions
get_device_uuid() {
    local device="$1"
    if [ -z "$device" ]; then
        log_error "Device path is empty"
        return 1
    fi
    
    if [ ! -b "$device" ]; then
        log_error "Device $device does not exist or is not a block device"
        return 1
    fi
    
    local uuid=$(blkid -s UUID -o value "$device" 2>/dev/null)
    if [ -z "$uuid" ]; then
        log_error "Could not get UUID for device $device"
        return 1
    fi
    
    echo "$uuid"
}

get_device_partuuid() {
    local device="$1"
    if [ -z "$device" ]; then
        log_error "Device path is empty"
        return 1
    fi
    
    if [ ! -b "$device" ]; then
        log_error "Device $device does not exist or is not a block device"
        return 1
    fi
    
    local partuuid=$(blkid -s PARTUUID -o value "$device" 2>/dev/null)
    if [ -z "$partuuid" ]; then
        log_error "Could not get PARTUUID for device $device"
        return 1
    fi
    
    echo "$partuuid"
}

# Global variables for storing device information
declare -g ROOT_DEVICE=""
declare -g ROOT_UUID=""
declare -g EFI_DEVICE=""
declare -g EFI_UUID=""
declare -g XBOOTLDR_DEVICE=""
declare -g XBOOTLDR_UUID=""
declare -g SWAP_DEVICE=""
declare -g SWAP_UUID=""
declare -g HOME_DEVICE=""
declare -g HOME_UUID=""

# Function to capture device information
capture_device_info() {
    local device_type="$1"  # "root", "efi", "xbootldr", "swap", "home"
    local device_path="$2"
    
    if [ -z "$device_type" ] || [ -z "$device_path" ]; then
        log_error "Device type and path are required"
        return 1
    fi
    
    local uuid=$(get_device_uuid "$device_path")
    if [ $? -ne 0 ]; then
        log_error "Failed to get UUID for $device_type device $device_path"
        return 1
    fi
    
    case "$device_type" in
        "root")
            ROOT_DEVICE="$device_path"
            ROOT_UUID="$uuid"
            log_info "Captured root device: $device_path (UUID: $uuid)"
            ;;
        "efi")
            EFI_DEVICE="$device_path"
            EFI_UUID="$uuid"
            log_info "Captured EFI device: $device_path (UUID: $uuid)"
            ;;
        "xbootldr")
            XBOOTLDR_DEVICE="$device_path"
            XBOOTLDR_UUID="$uuid"
            log_info "Captured XBOOTLDR device: $device_path (UUID: $uuid)"
            ;;
        "swap")
            SWAP_DEVICE="$device_path"
            SWAP_UUID="$uuid"
            log_info "Captured swap device: $device_path (UUID: $uuid)"
            ;;
        "home")
            HOME_DEVICE="$device_path"
            HOME_UUID="$uuid"
            log_info "Captured home device: $device_path (UUID: $uuid)"
            ;;
        *)
            log_error "Unknown device type: $device_type"
            return 1
            ;;
    esac
    
    return 0
}

# Package dependency checking and installation
check_and_install_dependencies() {
    log_info "Checking required packages for installation..."
    
    local required_packages=(
        "dosfstools"      # For mkfs.fat (FAT32 formatting)
        "exfatprogs"      # For exFAT support and FAT32 utilities
        "e2fsprogs"       # For mkfs.ext4
        "xfsprogs"        # For mkfs.xfs
        "btrfs-progs"     # For mkfs.btrfs
        "parted"          # For disk partitioning
        "gptfdisk"        # For sgdisk (GPT partitioning)
        "lvm2"            # For LVM operations
        "mdadm"           # For RAID operations
        "cryptsetup"      # For LUKS encryption
        "grub"            # For GRUB bootloader
        "efibootmgr"      # For UEFI boot management
    )
    
    local missing_packages=()
    
    for package in "${required_packages[@]}"; do
        if ! pacman -Qi "$package" &>/dev/null; then
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        log_info "Installing missing packages: ${missing_packages[*]}"
        pacman -Sy --noconfirm "${missing_packages[@]}" || {
            log_error "Failed to install required packages: ${missing_packages[*]}"
            return 1
        }
        log_success "All required packages installed successfully"
    else
        log_info "All required packages are already installed"
    fi
    
    return 0
}

# Check for specific package before running commands
check_package_available() {
    local package="$1"
    local command="$2"
    
    if ! pacman -Qi "$package" &>/dev/null; then
        log_error "Package '$package' is required for '$command' but not installed"
        log_info "Installing $package..."
        pacman -Sy --noconfirm "$package" || {
            log_error "Failed to install $package"
            return 1
        }
    fi
    
    return 0
}
