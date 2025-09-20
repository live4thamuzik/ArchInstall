#!/bin/bash
# run_shell_tests.sh - Comprehensive shell script test runner

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to run individual test file
run_test_file() {
    local test_file=$1
    local test_name=$(basename "$test_file" .bats)
    
    print_status $BLUE "Running $test_name tests..."
    
    # Run the test file directly using the test framework
    if bash -c "cd '$(dirname "$0")' && bash test_framework.sh '$(basename "$test_file")'"; then
        print_status $GREEN "✅ $test_name tests completed"
        return 0
    else
        print_status $RED "❌ $test_name tests failed"
        return 1
    fi
}

# Function to run all shell tests
run_all_shell_tests() {
    local test_dir="$(dirname "$0")"
    # If we're running from the root directory, adjust the path
    if [ "$test_dir" = "./tests" ]; then
        test_dir="tests"
    fi
    local exit_code=0
    local tests_run=0
    local tests_passed=0
    local tests_failed=0
    
    print_status $BLUE "🧪 Starting shell script test suite..."
    echo
    # Find all test files
    local test_files=()
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$test_dir" -name "test_*.bats" -print0 2>/dev/null || true)
    
    if [ ${#test_files[@]} -eq 0 ]; then
        print_status $YELLOW "No shell test files found"
        return 0
    fi
    
    # Run each test file
    for test_file in "${test_files[@]}"; do
        ((tests_run++))
        if run_test_file "$test_file"; then
            ((tests_passed++))
        else
            ((tests_failed++))
            exit_code=1
        fi
        echo
    done
    
    # Print summary
    print_status $BLUE "Shell Test Summary:"
    print_status $GREEN "  Passed: $tests_passed"
    if [ $tests_failed -gt 0 ]; then
        print_status $RED "  Failed: $tests_failed"
    else
        print_status $GREEN "  Failed: $tests_failed"
    fi
    print_status $BLUE "  Total: $tests_run"
    
    if [ $tests_failed -eq 0 ]; then
        print_status $GREEN "🎉 All shell tests passed!"
    else
        print_status $RED "💥 Some shell tests failed!"
    fi
    
    return $exit_code
}

# Function to run specific test file
run_specific_test() {
    local test_name=$1
    local test_file="$(dirname "$0")/${test_name}.bats"
    
    if [ ! -f "$test_file" ]; then
        print_status $RED "Test file not found: $test_file"
        return 1
    fi
    
    run_test_file "$test_file"
    return $?
}

# Function to list available tests
list_tests() {
    local test_dir="$(dirname "$0")"
    
    print_status $BLUE "Available shell tests:"
    
    while IFS= read -r -d '' file; do
        local test_name=$(basename "$file" .bats)
        print_status $GREEN "  - $test_name"
    done < <(find "$test_dir" -name "*.bats" -print0 2>/dev/null || true)
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS] [TEST_NAME]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -l, --list     List available tests"
    echo "  -v, --verbose  Verbose output"
    echo
    echo "Arguments:"
    echo "  TEST_NAME      Run specific test file (without .bats extension)"
    echo
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 test_utils         # Run utils tests only"
    echo "  $0 --list             # List available tests"
    echo "  $0 --help             # Show help"
}

# Main function
main() {
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_tests
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -*)
                print_status $RED "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                # Run specific test
                run_specific_test "$1"
                exit $?
                ;;
        esac
    done
    
    # Run all tests if no specific test was requested
    run_all_shell_tests
    exit $?
}

# Run main function
main "$@"
