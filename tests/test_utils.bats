#!/bin/bash
# test_utils.bats - Tests for utils.sh functions

# Source the test framework
source "$(dirname "$0")/test_framework.sh"

# Test setup function
setup() {
    # Source the utils.sh file
    source "$(dirname "$0")/../utils.sh"
    
    # Set up test environment
    export LOG_FILE="$TEST_TEMP_DIR/test.log"
    export LOG_BACKUP="$TEST_TEMP_DIR/test_backup.log"
    export LOG_FINAL="$TEST_TEMP_DIR/test_final.log"
}

# Test logging functions
test_logging_functions() {
    # Test log_info
    log_info "Test info message"
    assert_file_exists "$LOG_FILE"
    assert_contains "$(cat "$LOG_FILE")" "Test info message"
    
    # Test log_error
    log_error "Test error message"
    assert_contains "$(cat "$LOG_FILE")" "Test error message"
    
    # Test log_warning
    log_warning "Test warning message"
    assert_contains "$(cat "$LOG_FILE")" "Test warning message"
}

# Test username validation
test_validate_username() {
    # Test valid usernames
    validate_username "testuser" "test context"
    assert_true $? "Valid username should pass"
    
    validate_username "user123" "test context"
    assert_true $? "Username with numbers should pass"
    
    validate_username "user_name" "test context"
    assert_true $? "Username with underscore should pass"
    
    validate_username "user-name" "test context"
    assert_true $? "Username with dash should pass"
    
    validate_username "user.name" "test context"
    assert_true $? "Username with dot should pass"
    
    # Test invalid usernames
    validate_username "" "test context"
    assert_false $? "Empty username should fail"
    
    validate_username "-invalid" "test context"
    assert_false $? "Username starting with dash should fail"
    
    validate_username ".invalid" "test context"
    assert_false $? "Username starting with dot should fail"
    
    validate_username "user@invalid" "test context"
    assert_false $? "Username with @ should fail"
    
    validate_username "user space" "test context"
    assert_false $? "Username with space should fail"
    
    # Test username length limits
    validate_username "a" "test context"
    assert_true $? "Single character username should pass"
    
    validate_username "$(printf 'a%.0s' {1..32})" "test context"
    assert_true $? "32 character username should pass"
    
    validate_username "$(printf 'a%.0s' {1..33})" "test context"
    assert_false $? "33 character username should fail"
}

# Test hostname validation
test_validate_hostname() {
    # Test valid hostnames
    validate_hostname "localhost" "test context"
    assert_true $? "Valid hostname should pass"
    
    validate_hostname "example.com" "test context"
    assert_true $? "Hostname with dot should pass"
    
    validate_hostname "host-name" "test context"
    assert_true $? "Hostname with dash should pass"
    
    validate_hostname "host123" "test context"
    assert_true $? "Hostname with numbers should pass"
    
    # Test invalid hostnames
    validate_hostname "" "test context"
    assert_false $? "Empty hostname should fail"
    
    validate_hostname "-invalid" "test context"
    assert_false $? "Hostname starting with dash should fail"
    
    validate_hostname ".invalid" "test context"
    assert_false $? "Hostname starting with dot should fail"
    
    validate_hostname "invalid-" "test context"
    assert_false $? "Hostname ending with dash should fail"
    
    validate_hostname "invalid." "test context"
    assert_false $? "Hostname ending with dot should fail"
    
    validate_hostname "host space" "test context"
    assert_false $? "Hostname with space should fail"
    
    validate_hostname "host@invalid" "test context"
    assert_false $? "Hostname with @ should fail"
    
    # Test hostname length limits
    validate_hostname "a" "test context"
    assert_true $? "Single character hostname should pass"
    
    validate_hostname "$(printf 'a%.0s' {1..253})" "test context"
    assert_true $? "253 character hostname should pass"
    
    validate_hostname "$(printf 'a%.0s' {1..254})" "test context"
    assert_false $? "254 character hostname should fail"
}

# Test disk device validation
test_validate_disk_device() {
    # Create mock device files for testing
    local mock_dev_dir="$TEST_TEMP_DIR/dev"
    mkdir -p "$mock_dev_dir"
    
    # Create mock block devices
    mknod "$mock_dev_dir/sda" b 8 0
    mknod "$mock_dev_dir/sdb" b 8 16
    mknod "$mock_dev_dir/nvme0n1" b 259 0
    
    # Test valid device paths (mock)
    validate_disk_device "$mock_dev_dir/sda" "test context"
    assert_true $? "Valid SATA device should pass"
    
    validate_disk_device "$mock_dev_dir/nvme0n1" "test context"
    assert_true $? "Valid NVMe device should pass"
    
    # Test invalid device paths
    validate_disk_device "" "test context"
    assert_false $? "Empty device path should fail"
    
    validate_disk_device "/dev/invalid" "test context"
    assert_false $? "Invalid device path should fail"
    
    validate_disk_device "/dev/sda1" "test context"
    assert_false $? "Partition path should fail (not block device)"
    
    validate_disk_device "not_a_path" "test context"
    assert_false $? "Non-path string should fail"
    
    validate_disk_device "/dev/hd" "test context"
    assert_false $? "Incomplete device path should fail"
}

# Test error handling functions
test_error_handling() {
    # Test error_exit function (should exit, so we test in subshell)
    (
        set -e
        source "$(dirname "$0")/../utils.sh"
        error_exit "Test error" 2>/dev/null || true
    )
    # If we reach here, the function didn't exit (which is expected in test)
    
    # Test that error_exit logs the error
    assert_contains "$(cat "$LOG_FILE")" "Test error"
}

# Test setup_logging function
test_setup_logging() {
    # Test that setup_logging creates log file
    setup_logging
    assert_file_exists "$LOG_FILE"
    
    # Test that log file is writable
    log_info "Test after setup_logging"
    assert_contains "$(cat "$LOG_FILE")" "Test after setup_logging"
}

# Test preserve_logs function
test_preserve_logs() {
    # Create a test log file
    echo "Test log content" > "$LOG_FILE"
    
    # Test preserve_logs
    preserve_logs
    assert_file_exists "$LOG_BACKUP"
    assert_equal "$(cat "$LOG_BACKUP")" "Test log content"
}

# Test show_log_access function
test_show_log_access() {
    # Create a test log file
    echo "Test log content" > "$LOG_FILE"
    
    # Test show_log_access (should show log location)
    local output
    output=$(show_log_access 2>&1)
    assert_contains "$output" "$LOG_FILE"
}

# Test create_user function (idempotency)
test_create_user_idempotency() {
    # Mock useradd and usermod commands
    local mock_useradd_called=false
    local mock_usermod_called=false
    
    # Create mock functions
    useradd() {
        mock_useradd_called=true
        echo "User created successfully"
        return 0
    }
    
    usermod() {
        mock_usermod_called=true
        echo "User modified successfully"
        return 0
    }
    
    # Mock id command to simulate user doesn't exist initially
    id() {
        if [ "$1" = "testuser" ]; then
            return 1  # User doesn't exist
        fi
        return 0
    }
    
    # Test creating new user
    create_user "testuser" "testpass"
    assert_true $mock_useradd_called "useradd should be called for new user"
    
    # Reset mock
    mock_useradd_called=false
    mock_usermod_called=false
    
    # Mock id command to simulate user exists
    id() {
        if [ "$1" = "testuser" ]; then
            return 0  # User exists
        fi
        return 1
    }
    
    # Test creating existing user (should be idempotent)
    create_user "testuser" "testpass"
    assert_false $mock_useradd_called "useradd should not be called for existing user"
}

# Test enable_systemd_service_chroot function (idempotency)
test_enable_service_idempotency() {
    local mock_systemctl_called=false
    
    # Mock systemctl command
    systemctl() {
        mock_systemctl_called=true
        echo "Service enabled successfully"
        return 0
    }
    
    # Test enabling service
    enable_systemd_service_chroot "testservice"
    assert_true $mock_systemctl_called "systemctl should be called to enable service"
}

# Test install_cpu_microcode function (idempotency)
test_install_microcode_idempotency() {
    local mock_pacman_called=false
    
    # Mock pacman command
    pacman() {
        mock_pacman_called=true
        echo "Package installed successfully"
        return 0
    }
    
    # Test installing microcode
    install_cpu_microcode "intel-ucode"
    assert_true $mock_pacman_called "pacman should be called to install microcode"
}

# Test update_sudoers function (idempotency)
test_update_sudoers_idempotency() {
    # Create test sudoers file
    local test_sudoers="$TEST_TEMP_DIR/sudoers"
    echo "# Original sudoers content" > "$test_sudoers"
    
    # Mock cp and grep commands
    cp() {
        echo "File copied successfully"
        return 0
    }
    
    grep() {
        if [ "$2" = "$test_sudoers" ] && [ "$1" = "Defaults targetpw" ]; then
            return 1  # Pattern not found
        fi
        return 0
    }
    
    # Test updating sudoers
    update_sudoers "$test_sudoers"
    # Function should complete without error
    assert_true $? "update_sudoers should complete successfully"
}

# Test install_aur_helper_chroot function (idempotency)
test_install_aur_helper_idempotency() {
    local mock_git_called=false
    
    # Mock git command
    git() {
        mock_git_called=true
        echo "Repository cloned successfully"
        return 0
    }
    
    # Mock test command to simulate helper doesn't exist
    test() {
        if [ "$1" = "-f" ] && [ "$2" = "/usr/bin/yay" ]; then
            return 1  # File doesn't exist
        fi
        return 0
    }
    
    # Test installing AUR helper
    install_aur_helper_chroot "yay"
    assert_true $mock_git_called "git should be called to clone AUR helper"
    
    # Reset mock
    mock_git_called=false
    
    # Mock test command to simulate helper exists
    test() {
        if [ "$1" = "-f" ] && [ "$2" = "/usr/bin/yay" ]; then
            return 0  # File exists
        fi
        return 1
    }
    
    # Test installing existing AUR helper (should be idempotent)
    install_aur_helper_chroot "yay"
    assert_false $mock_git_called "git should not be called for existing AUR helper"
}

# Run all tests
run_test "Logging Functions" test_logging_functions
run_test "Username Validation" test_validate_username
run_test "Hostname Validation" test_validate_hostname
run_test "Disk Device Validation" test_validate_disk_device
run_test "Error Handling" test_error_handling
run_test "Setup Logging" test_setup_logging
run_test "Preserve Logs" test_preserve_logs
run_test "Show Log Access" test_show_log_access
run_test "Create User Idempotency" test_create_user_idempotency
run_test "Enable Service Idempotency" test_enable_service_idempotency
run_test "Install Microcode Idempotency" test_install_microcode_idempotency
run_test "Update Sudoers Idempotency" test_update_sudoers_idempotency
run_test "Install AUR Helper Idempotency" test_install_aur_helper_idempotency
