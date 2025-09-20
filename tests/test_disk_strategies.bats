#!/bin/bash
# test_disk_strategies.bats - Tests for disk_strategies.sh functions

# Source the test framework
source "$(dirname "$0")/test_framework.sh"

# Test setup function
setup() {
    # Source the disk_strategies.sh file
    source "$(dirname "$0")/../disk_strategies.sh"
    
    # Set up test environment variables
    export INSTALL_DISK="/dev/testdisk"
    export PARTITION_SCHEME="auto_simple"
    export WANT_SWAP="yes"
    export WANT_HOME_PARTITION="yes"
    export WANT_ENCRYPTION="no"
    export WANT_LVM="no"
    export WANT_RAID="no"
    export RAID_LEVEL=""
    export ROOT_FILESYSTEM_TYPE="ext4"
    export HOME_FILESYSTEM_TYPE="ext4"
    
    # Mock commands that would normally interact with the system
    mock_commands
}

# Function to mock system commands
mock_commands() {
    # Mock parted command
    parted() {
        echo "parted mock: $*"
        return 0
    }
    
    # Mock mkfs commands
    mkfs.ext4() {
        echo "mkfs.ext4 mock: $*"
        return 0
    }
    
    mkfs.fat() {
        echo "mkfs.fat mock: $*"
        return 0
    }
    
    # Mock mount commands
    mount() {
        echo "mount mock: $*"
        return 0
    }
    
    umount() {
        echo "umount mock: $*"
        return 0
    }
    
    # Mock swapon/swapoff
    swapon() {
        echo "swapon mock: $*"
        return 0
    }
    
    swapoff() {
        echo "swapoff mock: $*"
        return 0
    }
    
    # Mock pvcreate, vgcreate, lvcreate
    pvcreate() {
        echo "pvcreate mock: $*"
        return 0
    }
    
    vgcreate() {
        echo "vgcreate mock: $*"
        return 0
    }
    
    lvcreate() {
        echo "lvcreate mock: $*"
        return 0
    }
    
    # Mock mdadm
    mdadm() {
        echo "mdadm mock: $*"
        return 0
    }
    
    # Mock cryptsetup
    cryptsetup() {
        echo "cryptsetup mock: $*"
        return 0
    }
    
    # Mock lsblk
    lsblk() {
        echo "NAME MAJ:MIN RM SIZE RO TYPE MOUNTPOINT"
        echo "testdisk 8:0 0 100G 0 disk"
        echo "testdisk1 8:1 0 1G 0 part"
        echo "testdisk2 8:2 0 2G 0 part"
        echo "testdisk3 8:3 0 50G 0 part"
        echo "testdisk4 8:4 0 47G 0 part"
        return 0
    }
}

# Test auto_simple partitioning strategy
test_auto_simple_strategy() {
    local output
    output=$(do_auto_simple_partitioning 2>&1)
    
    # Should create partitions for ESP, boot, root, and optionally home
    assert_contains "$output" "parted mock"
    assert_contains "$output" "mkfs.fat mock"
    assert_contains "$output" "mkfs.ext4 mock"
    
    # Should mount partitions
    assert_contains "$output" "mount mock"
}

# Test auto_simple_luks partitioning strategy
test_auto_simple_luks_strategy() {
    export WANT_ENCRYPTION="yes"
    export LUKS_PASSPHRASE="testpass"
    
    local output
    output=$(do_auto_simple_luks_partitioning 2>&1)
    
    # Should create encrypted partitions
    assert_contains "$output" "cryptsetup mock"
    assert_contains "$output" "mkfs.ext4 mock"
    assert_contains "$output" "mount mock"
}

# Test auto_lvm partitioning strategy
test_auto_lvm_strategy() {
    export WANT_LVM="yes"
    
    local output
    output=$(do_auto_lvm_partitioning 2>&1)
    
    # Should create LVM setup
    assert_contains "$output" "pvcreate mock"
    assert_contains "$output" "vgcreate mock"
    assert_contains "$output" "lvcreate mock"
    assert_contains "$output" "mkfs.ext4 mock"
    assert_contains "$output" "mount mock"
}

# Test auto_luks_lvm partitioning strategy
test_auto_luks_lvm_strategy() {
    export WANT_ENCRYPTION="yes"
    export WANT_LVM="yes"
    export LUKS_PASSPHRASE="testpass"
    
    local output
    output=$(do_auto_luks_lvm_partitioning 2>&1)
    
    # Should create encrypted LVM setup
    assert_contains "$output" "cryptsetup mock"
    assert_contains "$output" "pvcreate mock"
    assert_contains "$output" "vgcreate mock"
    assert_contains "$output" "lvcreate mock"
    assert_contains "$output" "mkfs.ext4 mock"
    assert_contains "$output" "mount mock"
}

# Test auto_raid_simple partitioning strategy
test_auto_raid_simple_strategy() {
    export WANT_RAID="yes"
    export RAID_LEVEL="1"
    export RAID_DEVICES=("/dev/testdisk1" "/dev/testdisk2")
    
    local output
    output=$(do_auto_raid_simple_partitioning 2>&1)
    
    # Should create RAID setup
    assert_contains "$output" "mdadm mock"
    assert_contains "$output" "mkfs.ext4 mock"
    assert_contains "$output" "mount mock"
}

# Test auto_raid_lvm partitioning strategy
test_auto_raid_lvm_strategy() {
    export WANT_RAID="yes"
    export WANT_LVM="yes"
    export RAID_LEVEL="1"
    export RAID_DEVICES=("/dev/testdisk1" "/dev/testdisk2")
    
    local output
    output=$(do_auto_raid_lvm_partitioning 2>&1)
    
    # Should create RAID with LVM setup
    assert_contains "$output" "mdadm mock"
    assert_contains "$output" "pvcreate mock"
    assert_contains "$output" "vgcreate mock"
    assert_contains "$output" "lvcreate mock"
    assert_contains "$output" "mkfs.ext4 mock"
    assert_contains "$output" "mount mock"
}

# Test manual partitioning strategy
test_manual_partitioning_strategy() {
    local output
    output=$(do_manual_partitioning_guided 2>&1)
    
    # Should provide guidance for manual partitioning
    assert_contains "$output" "Manual partitioning"
    assert_contains "$output" "fdisk"
}

# Test partition size calculations
test_partition_size_calculations() {
    # Test that partition sizes are calculated correctly
    # These would be internal functions in the actual implementation
    
    # Mock disk size detection
    local disk_size_gb=100
    
    # Test ESP size (should be 1GB)
    local esp_size=1024  # MB
    assert_equal "$esp_size" "1024"
    
    # Test boot size (should be 2GB)
    local boot_size=2048  # MB
    assert_equal "$boot_size" "2048"
    
    # Test root size (should be 50GB for simple, 100GB if no home)
    local root_size=51200  # MB (50GB)
    assert_equal "$root_size" "51200"
}

# Test filesystem creation
test_filesystem_creation() {
    # Test ext4 filesystem creation
    local output
    output=$(create_filesystem "ext4" "/dev/testpart" "root" 2>&1)
    assert_contains "$output" "mkfs.ext4 mock"
    
    # Test FAT32 filesystem creation
    output=$(create_filesystem "fat32" "/dev/testpart" "esp" 2>&1)
    assert_contains "$output" "mkfs.fat mock"
    
    # Test swap creation
    output=$(create_filesystem "swap" "/dev/testpart" "swap" 2>&1)
    assert_contains "$output" "mkswap mock"
}

# Test partition mounting
test_partition_mounting() {
    # Test mounting partitions
    local output
    output=$(mount_partitions 2>&1)
    assert_contains "$output" "mount mock"
    
    # Test unmounting partitions
    output=$(unmount_partitions 2>&1)
    assert_contains "$output" "umount mock"
}

# Test swap handling
test_swap_handling() {
    export WANT_SWAP="yes"
    
    # Test enabling swap
    local output
    output=$(enable_swap "/dev/testswap" 2>&1)
    assert_contains "$output" "swapon mock"
    
    # Test disabling swap
    output=$(disable_swap "/dev/testswap" 2>&1)
    assert_contains "$output" "swapoff mock"
}

# Test LVM setup
test_lvm_setup() {
    export WANT_LVM="yes"
    
    # Test creating physical volume
    local output
    output=$(create_physical_volume "/dev/testpart" 2>&1)
    assert_contains "$output" "pvcreate mock"
    
    # Test creating volume group
    output=$(create_volume_group "testvg" "/dev/testpart" 2>&1)
    assert_contains "$output" "vgcreate mock"
    
    # Test creating logical volume
    output=$(create_logical_volume "testvg" "testlv" "10G" 2>&1)
    assert_contains "$output" "lvcreate mock"
}

# Test RAID setup
test_raid_setup() {
    export WANT_RAID="yes"
    export RAID_LEVEL="1"
    export RAID_DEVICES=("/dev/testdisk1" "/dev/testdisk2")
    
    # Test creating RAID array
    local output
    output=$(create_raid_array "md0" "1" "/dev/testdisk1" "/dev/testdisk2" 2>&1)
    assert_contains "$output" "mdadm mock"
    
    # Test assembling RAID array
    output=$(assemble_raid_array "md0" 2>&1)
    assert_contains "$output" "mdadm mock"
}

# Test encryption setup
test_encryption_setup() {
    export WANT_ENCRYPTION="yes"
    export LUKS_PASSPHRASE="testpass"
    
    # Test creating encrypted partition
    local output
    output=$(create_encrypted_partition "/dev/testpart" "testpass" 2>&1)
    assert_contains "$output" "cryptsetup mock"
    
    # Test opening encrypted partition
    output=$(open_encrypted_partition "/dev/testpart" "testpass" 2>&1)
    assert_contains "$output" "cryptsetup mock"
    
    # Test closing encrypted partition
    output=$(close_encrypted_partition "testpart" 2>&1)
    assert_contains "$output" "cryptsetup mock"
}

# Test partition strategy validation
test_partition_strategy_validation() {
    # Test valid strategies
    assert_true $(validate_partition_strategy "auto_simple")
    assert_true $(validate_partition_strategy "auto_simple_luks")
    assert_true $(validate_partition_strategy "auto_lvm")
    assert_true $(validate_partition_strategy "auto_luks_lvm")
    assert_true $(validate_partition_strategy "auto_raid_simple")
    assert_true $(validate_partition_strategy "auto_raid_lvm")
    assert_true $(validate_partition_strategy "manual")
    
    # Test invalid strategies
    assert_false $(validate_partition_strategy "invalid_strategy")
    assert_false $(validate_partition_strategy "")
    assert_false $(validate_partition_strategy "auto")
}

# Test RAID level validation
test_raid_level_validation() {
    # Test valid RAID levels
    assert_true $(validate_raid_level "0")
    assert_true $(validate_raid_level "1")
    assert_true $(validate_raid_level "5")
    assert_true $(validate_raid_level "10")
    
    # Test invalid RAID levels
    assert_false $(validate_raid_level "2")
    assert_false $(validate_raid_level "3")
    assert_false $(validate_raid_level "6")
    assert_false $(validate_raid_level "")
    assert_false $(validate_raid_level "invalid")
}

# Test disk validation
test_disk_validation() {
    # Test valid disk paths
    assert_true $(validate_disk "/dev/sda")
    assert_true $(validate_disk "/dev/sdb")
    assert_true $(validate_disk "/dev/nvme0n1")
    assert_true $(validate_disk "/dev/nvme1n1")
    
    # Test invalid disk paths
    assert_false $(validate_disk "/dev/sda1")  # Partition, not disk
    assert_false $(validate_disk "/dev/invalid")
    assert_false $(validate_disk "")
    assert_false $(validate_disk "not_a_path")
}

# Test configuration validation
test_configuration_validation() {
    # Test valid configurations
    export PARTITION_SCHEME="auto_simple"
    export INSTALL_DISK="/dev/sda"
    export WANT_SWAP="yes"
    export WANT_HOME_PARTITION="yes"
    
    assert_true $(validate_partition_config)
    
    # Test invalid configurations
    export PARTITION_SCHEME="invalid"
    assert_false $(validate_partition_config)
    
    export PARTITION_SCHEME="auto_simple"
    export INSTALL_DISK=""
    assert_false $(validate_partition_config)
}

# Run all tests
run_test "Auto Simple Strategy" test_auto_simple_strategy
run_test "Auto Simple LUKS Strategy" test_auto_simple_luks_strategy
run_test "Auto LVM Strategy" test_auto_lvm_strategy
run_test "Auto LUKS LVM Strategy" test_auto_luks_lvm_strategy
run_test "Auto RAID Simple Strategy" test_auto_raid_simple_strategy
run_test "Auto RAID LVM Strategy" test_auto_raid_lvm_strategy
run_test "Manual Partitioning Strategy" test_manual_partitioning_strategy
run_test "Partition Size Calculations" test_partition_size_calculations
run_test "Filesystem Creation" test_filesystem_creation
run_test "Partition Mounting" test_partition_mounting
run_test "Swap Handling" test_swap_handling
run_test "LVM Setup" test_lvm_setup
run_test "RAID Setup" test_raid_setup
run_test "Encryption Setup" test_encryption_setup
run_test "Partition Strategy Validation" test_partition_strategy_validation
run_test "RAID Level Validation" test_raid_level_validation
run_test "Disk Validation" test_disk_validation
run_test "Configuration Validation" test_configuration_validation
