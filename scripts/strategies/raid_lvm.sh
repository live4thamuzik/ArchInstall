#!/bin/bash
# raid_lvm.sh - RAID + LVM partitioning strategy
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/../disk_utils.sh"

# Execute RAID + LVM partitioning strategy
execute_raid_lvm_partitioning() {
    echo "=== RAID + LVM Partitioning ==="
    log_info "Starting RAID + LVM partitioning strategy"
    
    # Validate that we have multiple disks
    if [[ ${#INSTALL_DISKS[@]} -lt 2 ]]; then
        error_exit "RAID + LVM requires at least 2 disks, but only ${#INSTALL_DISKS[@]} provided"
    fi
    
    # Detect boot mode
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        log_info "UEFI boot mode detected - using GPT partition tables"
        PARTITION_TABLE="gpt"
        ESP_PARTITION_TYPE="$EFI_PARTITION_TYPE"
        XBOOTLDR_PARTITION_TYPE="$XBOOTLDR_PARTITION_TYPE"
    else
        log_info "BIOS boot mode detected - using MBR partition tables"
        PARTITION_TABLE="mbr"
        ESP_PARTITION_TYPE=""
        XBOOTLDR_PARTITION_TYPE=""
    fi
    
    # Create partitions on all disks
    log_info "Creating partitions on ${#INSTALL_DISKS[@]} disks"
    for disk in "${INSTALL_DISKS[@]}"; do
        log_info "Partitioning disk: $disk"
        
        if [[ "$PARTITION_TABLE" == "gpt" ]]; then
            # UEFI: ESP + XBOOTLDR + RAID member
            sgdisk --zap-all "$disk"
            sgdisk --new=1:0:+${ESP_SIZE_MIB}MiB --typecode=1:"$ESP_PARTITION_TYPE" --change-name=1:ESP "$disk"
            sgdisk --new=2:0:+${XBOOTLDR_SIZE_MIB}MiB --typecode=2:"$XBOOTLDR_PARTITION_TYPE" --change-name=2:XBOOTLDR "$disk"
            sgdisk --new=3:0:0 --typecode=3:"$LVM_PARTITION_TYPE" --change-name=3:RAID_MEMBER "$disk"
        else
            # BIOS: MBR + RAID member
            sgdisk --zap-all "$disk"
            sgdisk --new=1:0:+${BOOT_SIZE_MIB}MiB --typecode=1:8300 --change-name=1:BOOT "$disk"
            sgdisk --new=2:0:0 --typecode=2:"$LVM_PARTITION_TYPE" --change-name=2:RAID_MEMBER "$disk"
        fi
        
        sgdisk --print "$disk"
    done
    
    # Wait for partitions to be available
    sleep 2
    partprobe
    
    # Create RAID arrays
    log_info "Creating RAID arrays"
    
    if [[ "$PARTITION_TABLE" == "gpt" ]]; then
        # UEFI: Create RAID arrays for XBOOTLDR and data
        XBOOTLDR_PARTS=()
        DATA_PARTS=()
        
        for disk in "${INSTALL_DISKS[@]}"; do
            XBOOTLDR_PARTS+=("${disk}2")
            DATA_PARTS+=("${disk}3")
        done
        
        # Create XBOOTLDR RAID1 array
        log_info "Creating XBOOTLDR RAID1 array"
        mdadm --create --verbose --level=1 --raid-devices=${#INSTALL_DISKS[@]} /dev/md/XBOOTLDR "${XBOOTLDR_PARTS[@]}"
        
        # Create data RAID array
        log_info "Creating data RAID array"
        if [[ ${#INSTALL_DISKS[@]} -eq 2 ]]; then
            mdadm --create --verbose --level=1 --raid-devices=2 /dev/md/DATA "${DATA_PARTS[@]}"
        else
            mdadm --create --verbose --level=5 --raid-devices=${#INSTALL_DISKS[@]} /dev/md/DATA "${DATA_PARTS[@]}"
        fi
        
        # Format XBOOTLDR
        format_filesystem "/dev/md/XBOOTLDR" "ext4"
        
    else
        # BIOS: Create RAID arrays for boot and data
        BOOT_PARTS=()
        DATA_PARTS=()
        
        for disk in "${INSTALL_DISKS[@]}"; do
            BOOT_PARTS+=("${disk}1")
            DATA_PARTS+=("${disk}2")
        done
        
        # Create boot RAID1 array
        log_info "Creating boot RAID1 array"
        mdadm --create --verbose --level=1 --raid-devices=${#INSTALL_DISKS[@]} /dev/md/BOOT "${BOOT_PARTS[@]}"
        
        # Create data RAID array
        log_info "Creating data RAID array"
        if [[ ${#INSTALL_DISKS[@]} -eq 2 ]]; then
            mdadm --create --verbose --level=1 --raid-devices=2 /dev/md/DATA "${DATA_PARTS[@]}"
        else
            mdadm --create --verbose --level=5 --raid-devices=${#INSTALL_DISKS[@]} /dev/md/DATA "${DATA_PARTS[@]}"
        fi
        
        # Format boot
        format_filesystem "/dev/md/BOOT" "ext4"
    fi
    
    # Set up LVM on RAID array
    log_info "Setting up LVM on RAID array"
    
    # Create physical volume
    pvcreate /dev/md/DATA
    
    # Create volume group
    vgcreate archvg /dev/md/DATA
    
    # Calculate sizes
    local vg_size
    vg_size=$(vgdisplay archvg --units b --noheadings --options vg_size | tr -d ' ')
    vg_size=${vg_size%B} # Remove 'B' suffix
    
    # Reserve 10% for metadata and leave some free space
    local root_size=$((vg_size * 90 / 100))
    
    # Create root logical volume
    log_info "Creating root logical volume"
    lvcreate -l 90%FREE -n root archvg
    
    # Create swap logical volume if requested
    if [[ "$WANT_SWAP" == "yes" ]]; then
        log_info "Creating swap logical volume"
        lvcreate -L "$SWAP_SIZE" -n swap archvg
        mkswap /dev/archvg/swap
    fi
    
    # Create home logical volume if requested
    if [[ "$WANT_HOME_PARTITION" == "yes" ]]; then
        log_info "Creating home logical volume"
        lvcreate -l 100%FREE -n home archvg
        format_filesystem "/dev/archvg/home" "$HOME_FILESYSTEM_TYPE"
    fi
    
    # Format root
    format_filesystem "/dev/archvg/root" "$ROOT_FILESYSTEM_TYPE"
    
    # Mount filesystems
    log_info "Mounting filesystems"
    mount /dev/archvg/root /mnt
    
    if [[ "$PARTITION_TABLE" == "gpt" ]]; then
        # UEFI: Mount ESP and XBOOTLDR
        mkdir -p /mnt/efi /mnt/boot
        mount /dev/md/XBOOTLDR /mnt/boot
        
        # Mount ESP on first disk
        mount "${INSTALL_DISKS[0]}1" /mnt/efi
        
        # Capture UUIDs for configuration
        capture_device_info "/dev/md/XBOOTLDR" "XBOOTLDR"
        capture_device_info "/dev/archvg/root" "ROOT"
    else
        # BIOS: Mount boot
        mkdir -p /mnt/boot
        mount /dev/md/BOOT /mnt/boot
        
        # Capture UUIDs for configuration
        capture_device_info "/dev/md/BOOT" "BOOT"
        capture_device_info "/dev/archvg/root" "ROOT"
    fi
    
    # Mount home if created
    if [[ "$WANT_HOME_PARTITION" == "yes" ]]; then
        mkdir -p /mnt/home
        mount /dev/archvg/home /mnt/home
        capture_device_info "/dev/archvg/home" "HOME"
    fi
    
    # Save RAID configuration
    log_info "Saving RAID configuration"
    mkdir -p /mnt/etc/mdadm
    mdadm --detail --scan > /mnt/etc/mdadm/mdadm.conf
    
    log_info "RAID + LVM partitioning completed successfully"
}

# Export the function
export -f execute_raid_lvm_partitioning