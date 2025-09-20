#!/bin/bash
# test_simple_fixed.bats - Simple test with working runner

# Source the assertion functions from the main framework
source "$(dirname "$0")/test_framework.sh"

# Simple test function
test_basic_functionality() {
    # Test basic assertions
    assert_equal "hello" "hello" "Strings should be equal"
    assert_not_equal "hello" "world" "Strings should not be equal"
    assert_true "true" "True should be true"
    assert_false "false" "False should be false"
    
    # Test file operations
    echo "test content" > "/tmp/test_file_$$"
    assert_file_exists "/tmp/test_file_$$"
    rm -f "/tmp/test_file_$$"
    
    # Test string operations
    assert_contains "hello world" "world"
    assert_not_contains "hello world" "goodbye"
}

# Run the test using the simple runner
run_simple_test "Basic Functionality" test_basic_functionality
