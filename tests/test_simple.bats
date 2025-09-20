#!/bin/bash
# test_simple.bats - Simple test to verify our testing framework works

# Source the test framework
source "$(dirname "$0")/test_framework.sh"

# Simple test function
test_basic_functionality() {
    # Test basic assertions
    assert_equal "hello" "hello" "Strings should be equal"
    assert_not_equal "hello" "world" "Strings should not be equal"
    assert_true "true" "True should be true"
    assert_false "false" "False should be false"
    
    # Test file operations
    echo "test content" > "$TEST_TEMP_DIR/test_file"
    assert_file_exists "$TEST_TEMP_DIR/test_file"
    
    # Test string operations
    assert_contains "hello world" "world"
    assert_not_contains "hello world" "goodbye"
}

# Run the test
run_test "Basic Functionality" test_basic_functionality
