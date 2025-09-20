#!/bin/bash
# run_tests.sh - Test runner for archinstall project
# This script runs all available tests for the project

set -euo pipefail

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

# Function to run Rust tests
run_rust_tests() {
    print_status $BLUE "Running Rust unit tests..."
    
    if command -v cargo &> /dev/null; then
        if cargo test --quiet; then
            print_status $GREEN "✅ Rust tests passed!"
            return 0
        else
            print_status $RED "❌ Rust tests failed!"
            return 1
        fi
    else
        print_status $YELLOW "⚠️  Cargo not found, skipping Rust tests"
        return 0
    fi
}

# Function to run shell script tests
run_shell_tests() {
    print_status $BLUE "Running shell script tests..."
    
    if [ -f "tests/run_shell_tests.sh" ]; then
        if ./tests/run_shell_tests.sh; then
            print_status $GREEN "✅ Shell tests passed!"
            return 0
        else
            print_status $RED "❌ Shell tests failed!"
            return 1
        fi
    else
        print_status $YELLOW "⚠️  Shell test runner not found, skipping"
        return 0
    fi
}

# Function to run YAML parser tests
run_yaml_tests() {
    print_status $BLUE "Running YAML parser tests..."
    
    if [ -f "yaml_parser.sh" ] && [ -f "config.yaml" ]; then
        if source yaml_parser.sh && parse_yaml_config config.yaml; then
            print_status $GREEN "✅ YAML parser tests passed!"
            return 0
        else
            print_status $RED "❌ YAML parser tests failed!"
            return 1
        fi
    else
        print_status $YELLOW "⚠️  YAML parser files not found, skipping"
        return 0
    fi
}

# Main test runner
main() {
    print_status $BLUE "🧪 Starting archinstall test suite..."
    echo
    
    local exit_code=0
    
    # Run Rust tests
    if ! run_rust_tests; then
        exit_code=1
    fi
    echo
    
    # Run YAML parser tests
    if ! run_yaml_tests; then
        exit_code=1
    fi
    echo
    
    # Run shell tests (when implemented)
    if ! run_shell_tests; then
        exit_code=1
    fi
    echo
    
    # Summary
    if [ $exit_code -eq 0 ]; then
        print_status $GREEN "🎉 All tests passed!"
    else
        print_status $RED "💥 Some tests failed!"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"
