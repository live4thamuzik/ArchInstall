#!/bin/bash
# test_config_manager.bats - Tests for config_manager.sh functions

# Source the test framework
source "$(dirname "$0")/test_framework.sh"

# Test setup function
setup() {
    # Source the config_manager.sh file
    source "$(dirname "$0")/../config_manager.sh"
    
    # Set up test environment
    export CONFIG_FILE="$TEST_TEMP_DIR/test_config"
    
    # Create initial test config
    cat > "$CONFIG_FILE" << 'EOF'
# Test configuration file
DESKTOP_ENVIRONMENTS=("gnome" "kde" "xfce")
DISPLAY_MANAGERS=("gdm" "sddm" "lightdm")
GPU_DRIVERS=("amd" "nvidia" "intel")
BOOTLOADER_GRUB=("grub" "efibootmgr")
BASE_PACKAGES_EXTRAS=("vim" "nano" "git")
EOF
}

# Test getting configuration values
test_get_config() {
    # Test getting existing value
    local result
    result=$(get_config "DESKTOP_ENVIRONMENTS")
    assert_contains "$result" "gnome"
    assert_contains "$result" "kde"
    assert_contains "$result" "xfce"
    
    # Test getting non-existing value
    result=$(get_config "NONEXISTENT_VAR")
    assert_equal "$result" ""
    
    # Test getting empty value
    result=$(get_config "")
    assert_equal "$result" ""
}

# Test setting configuration values
test_set_config() {
    # Test setting new value
    set_config "NEW_VAR" "new_value"
    local result
    result=$(get_config "NEW_VAR")
    assert_equal "$result" "new_value"
    
    # Test updating existing value
    set_config "DESKTOP_ENVIRONMENTS" "gnome kde"
    result=$(get_config "DESKTOP_ENVIRONMENTS")
    assert_equal "$result" "gnome kde"
    
    # Test setting empty value
    set_config "EMPTY_VAR" ""
    result=$(get_config "EMPTY_VAR")
    assert_equal "$result" ""
}

# Test adding to configuration arrays
test_add_to_config() {
    # Test adding to existing array
    add_to_config "DESKTOP_ENVIRONMENTS" "hyprland"
    local result
    result=$(get_config "DESKTOP_ENVIRONMENTS")
    assert_contains "$result" "gnome"
    assert_contains "$result" "kde"
    assert_contains "$result" "xfce"
    assert_contains "$result" "hyprland"
    
    # Test adding to non-existing array
    add_to_config "NEW_ARRAY" "item1"
    result=$(get_config "NEW_ARRAY")
    assert_contains "$result" "item1"
    
    # Test adding duplicate item (should not add)
    local initial_result
    initial_result=$(get_config "DESKTOP_ENVIRONMENTS")
    add_to_config "DESKTOP_ENVIRONMENTS" "gnome"
    result=$(get_config "DESKTOP_ENVIRONMENTS")
    assert_equal "$result" "$initial_result"
}

# Test removing from configuration arrays
test_remove_from_config() {
    # Test removing existing item
    remove_from_config "DESKTOP_ENVIRONMENTS" "kde"
    local result
    result=$(get_config "DESKTOP_ENVIRONMENTS")
    assert_contains "$result" "gnome"
    assert_not_contains "$result" "kde"
    assert_contains "$result" "xfce"
    
    # Test removing non-existing item
    local initial_result
    initial_result=$(get_config "DESKTOP_ENVIRONMENTS")
    remove_from_config "DESKTOP_ENVIRONMENTS" "nonexistent"
    result=$(get_config "DESKTOP_ENVIRONMENTS")
    assert_equal "$result" "$initial_result"
    
    # Test removing from non-existing array
    remove_from_config "NONEXISTENT_ARRAY" "item"
    # Should not cause error
    assert_true $?
}

# Test listing configuration keys
test_list_config_keys() {
    local result
    result=$(list_config_keys)
    
    # Should contain the keys from our test config
    assert_contains "$result" "DESKTOP_ENVIRONMENTS"
    assert_contains "$result" "DISPLAY_MANAGERS"
    assert_contains "$result" "GPU_DRIVERS"
    assert_contains "$result" "BOOTLOADER_GRUB"
    assert_contains "$result" "BASE_PACKAGES_EXTRAS"
}

# Test showing all configuration
test_show_all_config() {
    local result
    result=$(show_all_config)
    
    # Should contain all configuration values
    assert_contains "$result" "DESKTOP_ENVIRONMENTS"
    assert_contains "$result" "gnome"
    assert_contains "$result" "kde"
    assert_contains "$result" "xfce"
    assert_contains "$result" "DISPLAY_MANAGERS"
    assert_contains "$result" "gdm"
    assert_contains "$result" "sddm"
    assert_contains "$result" "lightdm"
}

# Test clearing configuration
test_clear_config() {
    # Test clearing specific key
    clear_config "DESKTOP_ENVIRONMENTS"
    local result
    result=$(get_config "DESKTOP_ENVIRONMENTS")
    assert_equal "$result" ""
    
    # Test clearing non-existing key
    clear_config "NONEXISTENT_VAR"
    # Should not cause error
    assert_true $?
}

# Test backup and restore configuration
test_backup_restore_config() {
    # Test backup
    local backup_file
    backup_file=$(backup_config)
    assert_file_exists "$backup_file"
    
    # Modify original config
    set_config "DESKTOP_ENVIRONMENTS" "modified"
    local result
    result=$(get_config "DESKTOP_ENVIRONMENTS")
    assert_equal "$result" "modified"
    
    # Test restore
    restore_config "$backup_file"
    result=$(get_config "DESKTOP_ENVIRONMENTS")
    assert_contains "$result" "gnome"
    assert_contains "$result" "kde"
    assert_contains "$result" "xfce"
    assert_not_contains "$result" "modified"
    
    # Clean up backup file
    rm -f "$backup_file"
}

# Test configuration validation
test_validate_config() {
    # Test valid configuration
    assert_true $(validate_config)
    
    # Test with corrupted config (invalid syntax)
    echo "INVALID_SYNTAX = " > "$CONFIG_FILE"
    assert_false $(validate_config)
    
    # Restore valid config
    setup
}

# Test configuration search
test_search_config() {
    # Test searching for existing values
    local result
    result=$(search_config "gnome")
    assert_contains "$result" "DESKTOP_ENVIRONMENTS"
    
    result=$(search_config "gdm")
    assert_contains "$result" "DISPLAY_MANAGERS"
    
    # Test searching for non-existing values
    result=$(search_config "nonexistent")
    assert_equal "$result" ""
}

# Test configuration export
test_export_config() {
    # Test exporting to environment variables
    export_config
    
    # Check that variables are exported
    assert_not_equal "${DESKTOP_ENVIRONMENTS:-}" ""
    assert_not_equal "${DISPLAY_MANAGERS:-}" ""
    assert_not_equal "${GPU_DRIVERS:-}" ""
    assert_not_equal "${BOOTLOADER_GRUB:-}" ""
    assert_not_equal "${BASE_PACKAGES_EXTRAS:-}" ""
}

# Test configuration import
test_import_config() {
    # Create temporary config file
    local temp_config="$TEST_TEMP_DIR/temp_config"
    cat > "$temp_config" << 'EOF'
IMPORTED_VAR="imported_value"
IMPORTED_ARRAY=("item1" "item2" "item3")
EOF
    
    # Import configuration
    import_config "$temp_config"
    
    # Check that values are imported
    local result
    result=$(get_config "IMPORTED_VAR")
    assert_equal "$result" "imported_value"
    
    result=$(get_config "IMPORTED_ARRAY")
    assert_contains "$result" "item1"
    assert_contains "$result" "item2"
    assert_contains "$result" "item3"
}

# Test configuration merge
test_merge_config() {
    # Create temporary config file to merge
    local temp_config="$TEST_TEMP_DIR/merge_config"
    cat > "$temp_config" << 'EOF'
DESKTOP_ENVIRONMENTS=("hyprland" "sway")
NEW_VAR="new_value"
EOF
    
    # Merge configuration
    merge_config "$temp_config"
    
    # Check that values are merged
    local result
    result=$(get_config "DESKTOP_ENVIRONMENTS")
    assert_contains "$result" "gnome"  # Original value
    assert_contains "$result" "kde"    # Original value
    assert_contains "$result" "xfce"   # Original value
    assert_contains "$result" "hyprland"  # Merged value
    assert_contains "$result" "sway"   # Merged value
    
    result=$(get_config "NEW_VAR")
    assert_equal "$result" "new_value"
}

# Test configuration statistics
test_config_stats() {
    local result
    result=$(config_stats)
    
    # Should contain statistics about the configuration
    assert_contains "$result" "Total keys"
    assert_contains "$result" "Array keys"
    assert_contains "$result" "String keys"
}

# Test configuration help
test_config_help() {
    local result
    result=$(config_help)
    
    # Should contain help information
    assert_contains "$result" "Usage"
    assert_contains "$result" "Commands"
    assert_contains "$result" "get"
    assert_contains "$result" "set"
    assert_contains "$result" "add"
    assert_contains "$result" "remove"
}

# Test error handling
test_config_error_handling() {
    # Test with non-existent config file
    export CONFIG_FILE="$TEST_TEMP_DIR/nonexistent"
    
    # These should handle missing file gracefully
    local result
    result=$(get_config "SOME_VAR")
    assert_equal "$result" ""
    
    set_config "SOME_VAR" "value"
    assert_true $?
    
    # Restore valid config file
    export CONFIG_FILE="$TEST_TEMP_DIR/test_config"
    setup
}

# Test configuration file locking
test_config_file_locking() {
    # Test that configuration operations are atomic
    # This is a simplified test - in real implementation, file locking would be used
    
    # Perform multiple operations simultaneously
    set_config "TEST_VAR1" "value1" &
    set_config "TEST_VAR2" "value2" &
    set_config "TEST_VAR3" "value3" &
    
    # Wait for all operations to complete
    wait
    
    # Check that all values were set correctly
    local result1 result2 result3
    result1=$(get_config "TEST_VAR1")
    result2=$(get_config "TEST_VAR2")
    result3=$(get_config "TEST_VAR3")
    
    assert_equal "$result1" "value1"
    assert_equal "$result2" "value2"
    assert_equal "$result3" "value3"
}

# Run all tests
run_test "Get Config" test_get_config
run_test "Set Config" test_set_config
run_test "Add to Config" test_add_to_config
run_test "Remove from Config" test_remove_from_config
run_test "List Config Keys" test_list_config_keys
run_test "Show All Config" test_show_all_config
run_test "Clear Config" test_clear_config
run_test "Backup Restore Config" test_backup_restore_config
run_test "Validate Config" test_validate_config
run_test "Search Config" test_search_config
run_test "Export Config" test_export_config
run_test "Import Config" test_import_config
run_test "Merge Config" test_merge_config
run_test "Config Stats" test_config_stats
run_test "Config Help" test_config_help
run_test "Config Error Handling" test_config_error_handling
run_test "Config File Locking" test_config_file_locking
