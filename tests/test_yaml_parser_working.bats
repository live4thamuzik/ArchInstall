#!/bin/bash
# test_yaml_parser_working.bats - Working tests for yaml_parser.sh functions

# Source the test framework
source "$(dirname "$0")/test_framework.sh"

# Test setup function
setup() {
    # Source the yaml_parser.sh file
    source "$(dirname "$0")/../yaml_parser.sh" || {
        echo "Failed to source yaml_parser.sh"
        return 1
    }
    
    # Create a simple test YAML file
    cat > "$TEST_TEMP_DIR/test_config.yaml" << 'EOF'
system:
  main_username: "testuser"
  system_hostname: "testhost"
storage:
  install_disk: "/dev/sda"
EOF
}

# Test YAML parsing function
test_parse_yaml_config() {
    # Test parsing valid YAML file
    parse_yaml_config "$TEST_TEMP_DIR/test_config.yaml"
    assert_true $? "Parsing valid YAML should succeed"
    
    # Test parsing non-existent file
    parse_yaml_config "$TEST_TEMP_DIR/nonexistent.yaml"
    assert_false $? "Parsing non-existent file should fail"
}

# Test environment variable export
test_export_yaml_config() {
    # Parse the YAML first
    parse_yaml_config "$TEST_TEMP_DIR/test_config.yaml"
    
    # Test export function
    export_yaml_config
    assert_true $? "Export should succeed"
    
    # Test that key variables are exported
    assert_equal "$MAIN_USERNAME" "testuser"
    assert_equal "$SYSTEM_HOSTNAME" "testhost"
    assert_equal "$INSTALL_DISK" "/dev/sda"
}

# Test complete YAML loading process
test_load_yaml_config() {
    # Test loading complete YAML config
    load_yaml_config "$TEST_TEMP_DIR/test_config.yaml"
    assert_true $? "Loading complete YAML config should succeed"
    
    # Test loading non-existent file
    load_yaml_config "$TEST_TEMP_DIR/nonexistent.yaml"
    assert_false $? "Loading non-existent file should fail"
}

# Setup test environment
setup

# Run all tests
run_test "Parse YAML Config" test_parse_yaml_config
run_test "Export YAML Config" test_export_yaml_config
run_test "Load YAML Config" test_load_yaml_config
