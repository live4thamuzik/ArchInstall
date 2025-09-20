#!/bin/bash
# test-locally.sh - Run tests locally without CI/CD complexity

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Test configuration
TEST_CONFIGS=(
    "auto_simple:uefi:ext4"
    "auto_simple:bios:ext4"
    "auto_simple_luks:uefi:ext4"
    "auto_lvm:uefi:ext4"
)

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    sudo umount -R /mnt 2>/dev/null || true
    sudo swapoff -a 2>/dev/null || true
    for loop in /dev/loop*; do
        if [ -b "$loop" ]; then
            sudo losetup -d "$loop" 2>/dev/null || true
        fi
    done
    sudo rm -rf /tmp/archinstall-test
}

trap cleanup EXIT

# Set up test environment
setup_test_environment() {
    log_info "Setting up test environment..."
    
    # Create test directory
    sudo mkdir -p /tmp/archinstall-test
    
    # Create test disk images
    sudo truncate -s 10G /tmp/archinstall-test/test-disk1.img
    sudo truncate -s 10G /tmp/archinstall-test/test-disk2.img
    
    # Create loop devices
    sudo losetup /dev/loop1 /tmp/archinstall-test/test-disk1.img
    sudo losetup /dev/loop2 /tmp/archinstall-test/test-disk2.img
    
    log_success "Test environment set up successfully"
}

# Run Rust tests
run_rust_tests() {
    log_info "Running Rust tests..."
    
    if cargo test --verbose; then
        log_success "Rust tests passed"
    else
        log_error "Rust tests failed"
        return 1
    fi
}

# Run shell script syntax tests
run_shell_syntax_tests() {
    log_info "Running shell script syntax tests..."
    
    local scripts=("install_arch.sh" "disk_strategies.sh" "utils.sh" "yaml_parser.sh")
    
    for script in "${scripts[@]}"; do
        if bash -n "$script"; then
            log_success "Syntax check passed for $script"
        else
            log_error "Syntax check failed for $script"
            return 1
        fi
    done
}

# Test a specific partitioning strategy
test_partitioning_strategy() {
    local strategy="$1"
    local boot_mode="$2"
    local filesystem="$3"
    
    log_info "Testing strategy: $strategy (boot: $boot_mode, fs: $filesystem)"
    
    # Set up environment variables
    export TEST_MODE=true
    export INSTALL_DISK="/dev/loop1"
    export PARTITION_SCHEME="$strategy"
    export BOOT_MODE="$boot_mode"
    export ROOT_FILESYSTEM_TYPE="$filesystem"
    export HOME_FILESYSTEM_TYPE="$filesystem"
    export WANT_SWAP="yes"
    export WANT_HOME_PARTITION="yes"
    
    # Set up RAID devices if needed
    if [[ "$strategy" =~ raid ]]; then
        export RAID_DEVICES=("/dev/loop1" "/dev/loop2")
        export RAID_LEVEL="raid1"
    fi
    
    # Set up LVM if needed
    if [[ "$strategy" =~ lvm ]]; then
        export VG_NAME="testvg"
    fi
    
    # Set up LUKS if needed
    if [[ "$strategy" =~ luks ]]; then
        export LUKS_PASSPHRASE="testpass123"
    fi
    
    # Source the scripts
    source ./utils.sh
    source ./disk_strategies.sh
    
    # Test the partitioning strategy
    case "$strategy" in
        "auto_simple")
            do_auto_simple_partitioning
            ;;
        "auto_simple_luks")
            do_auto_simple_luks_partitioning
            ;;
        "auto_lvm")
            do_auto_lvm_partitioning
            ;;
        *)
            log_error "Unknown strategy: $strategy"
            return 1
            ;;
    esac
    
    log_success "Partitioning test passed for $strategy"
    
    # Clean up for next test
    sudo umount -R /mnt 2>/dev/null || true
    sudo swapoff -a 2>/dev/null || true
    
    # Recreate loop devices
    sudo losetup -d /dev/loop1 2>/dev/null || true
    sudo losetup -d /dev/loop2 2>/dev/null || true
    sudo losetup /dev/loop1 /tmp/archinstall-test/test-disk1.img
    sudo losetup /dev/loop2 /tmp/archinstall-test/test-disk2.img
}

# Run integration tests
run_integration_tests() {
    log_info "Running integration tests..."
    
    local passed=0
    local failed=0
    
    for config in "${TEST_CONFIGS[@]}"; do
        IFS=':' read -r strategy boot_mode filesystem <<< "$config"
        
        if test_partitioning_strategy "$strategy" "$boot_mode" "$filesystem"; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    log_info "Integration test results:"
    log_success "Passed: $passed"
    if [ $failed -gt 0 ]; then
        log_error "Failed: $failed"
        return 1
    else
        log_success "Failed: $failed"
    fi
}

# Test TUI functionality
test_tui_functionality() {
    log_info "Testing TUI functionality..."
    
    # Test TUI compilation
    if cargo build --release; then
        log_success "TUI compilation successful"
    else
        log_error "TUI compilation failed"
        return 1
    fi
    
    # Test TUI with help flag
    if ./target/release/archinstall-tui --help 2>/dev/null; then
        log_success "TUI help command works"
    else
        log_warning "TUI help command failed (may not be implemented)"
    fi
}

# Main test runner
main() {
    log_info "Starting comprehensive local testing..."
    
    # Set up test environment
    setup_test_environment
    
    # Run tests
    run_rust_tests
    run_shell_syntax_tests
    run_integration_tests
    test_tui_functionality
    
    log_success "All tests completed successfully!"
}

# Run main function
main "$@"

