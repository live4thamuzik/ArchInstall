#!/bin/bash
# test_framework.sh - Simple testing framework for shell scripts
# This provides bats-core-like functionality without external dependencies

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test statistics
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print test results
print_test_result() {
    local test_name=$1
    local status=$2
    local message=$3
    
    if [ "$status" = "PASS" ]; then
        print_status $GREEN "✓ $test_name"
        ((TESTS_PASSED++))
    else
        print_status $RED "✗ $test_name: $message"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
    fi
    ((TESTS_RUN++))
}

# Assertion functions
assert_equal() {
    local actual=$1
    local expected=$2
    local message=${3:-""}
    
    if [ "$actual" = "$expected" ]; then
        return 0
    else
        echo "Assertion failed: expected '$expected', got '$actual'"
        if [ -n "$message" ]; then
            echo "Message: $message"
        fi
        return 1
    fi
}

assert_not_equal() {
    local actual=$1
    local expected=$2
    local message=${3:-""}
    
    if [ "$actual" != "$expected" ]; then
        return 0
    else
        echo "Assertion failed: expected '$actual' to not equal '$expected'"
        if [ -n "$message" ]; then
            echo "Message: $message"
        fi
        return 1
    fi
}

assert_true() {
    local condition=$1
    local message=${2:-""}
    
    if [ "$condition" = "true" ] || [ "$condition" = "0" ]; then
        return 0
    else
        echo "Assertion failed: expected true, got '$condition'"
        if [ -n "$message" ]; then
            echo "Message: $message"
        fi
        return 1
    fi
}

assert_false() {
    local condition=$1
    local message=${2:-""}
    
    if [ "$condition" = "false" ] || [ "$condition" != "0" ]; then
        return 0
    else
        echo "Assertion failed: expected false, got '$condition'"
        if [ -n "$message" ]; then
            echo "Message: $message"
        fi
        return 1
    fi
}

assert_file_exists() {
    local file=$1
    local message=${2:-""}
    
    if [ -f "$file" ]; then
        return 0
    else
        echo "Assertion failed: file '$file' does not exist"
        if [ -n "$message" ]; then
            echo "Message: $message"
        fi
        return 1
    fi
}

assert_file_not_exists() {
    local file=$1
    local message=${2:-""}
    
    if [ ! -f "$file" ]; then
        return 0
    else
        echo "Assertion failed: file '$file' exists but should not"
        if [ -n "$message" ]; then
            echo "Message: $message"
        fi
        return 1
    fi
}

assert_dir_exists() {
    local dir=$1
    local message=${2:-""}
    
    if [ -d "$dir" ]; then
        return 0
    else
        echo "Assertion failed: directory '$dir' does not exist"
        if [ -n "$message" ]; then
            echo "Message: $message"
        fi
        return 1
    fi
}

assert_contains() {
    local haystack=$1
    local needle=$2
    local message=${3:-""}
    
    if echo "$haystack" | grep -q "$needle"; then
        return 0
    else
        echo "Assertion failed: '$haystack' does not contain '$needle'"
        if [ -n "$message" ]; then
            echo "Message: $message"
        fi
        return 1
    fi
}

assert_not_contains() {
    local haystack=$1
    local needle=$2
    local message=${3:-""}
    
    if ! echo "$haystack" | grep -q "$needle"; then
        return 0
    else
        echo "Assertion failed: '$haystack' contains '$needle' but should not"
        if [ -n "$message" ]; then
            echo "Message: $message"
        fi
        return 1
    fi
}

# Test runner function
run_test() {
    local test_name=$1
    local test_function=$2
    
    print_status $BLUE "Running test: $test_name"
    
    # Run the test in a subshell to catch errors
    if (set -e; $test_function); then
        print_test_result "$test_name" "PASS" ""
    else
        local exit_code=$?
        print_test_result "$test_name" "FAIL" "Exit code: $exit_code"
    fi
}

# Function to run all tests in a file
run_test_file() {
    local test_file=$1
    
    if [ ! -f "$test_file" ]; then
        print_status $RED "Test file not found: $test_file"
        return 1
    fi
    
    print_status $BLUE "Running test file: $test_file"
    
    # Source the test file
    source "$test_file"
    
    return 0
}

# Function to print test summary
print_summary() {
    echo
    print_status $BLUE "Test Summary:"
    print_status $GREEN "  Passed: $TESTS_PASSED"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        print_status $RED "  Failed: $TESTS_FAILED"
        print_status $RED "  Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            print_status $RED "    - $test"
        done
    else
        print_status $GREEN "  Failed: $TESTS_FAILED"
    fi
    
    print_status $BLUE "  Total: $TESTS_RUN"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        print_status $GREEN "🎉 All tests passed!"
        return 0
    else
        print_status $RED "💥 Some tests failed!"
        return 1
    fi
}

# Function to clean up test environment
cleanup() {
    # Remove any temporary files or directories created during tests
    if [ -n "${TEST_TEMP_DIR:-}" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Create temporary directory for tests
TEST_TEMP_DIR=$(mktemp -d)
export TEST_TEMP_DIR

# Export assertion functions so they're available in test files
export -f assert_equal assert_not_equal assert_true assert_false
export -f assert_file_exists assert_file_not_exists assert_dir_exists
export -f assert_contains assert_not_contains
export -f run_test print_status

# Main execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # If this script is run directly, run all test files
    if [ $# -eq 0 ]; then
        # Find all test files
        test_files=()
        if [ -d "tests" ]; then
            while IFS= read -r -d '' file; do
                test_files+=("$file")
            done < <(find tests -name "*.bats" -print0 2>/dev/null || true)
        fi
        
        if [ ${#test_files[@]} -eq 0 ]; then
            print_status $YELLOW "No test files found"
            exit 0
        fi
        
        # Run all test files
        for test_file in "${test_files[@]}"; do
            run_test_file "$test_file"
        done
        
        print_summary
        exit $?
    else
        # Run specific test file
        run_test_file "$1"
        print_summary
        exit $?
    fi
fi
