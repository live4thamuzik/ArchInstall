# Shell Script Testing Infrastructure

This document describes the custom shell script testing framework implemented for the archinstall project.

## Overview

Since `bats-core` was not available in the environment, we implemented a custom testing framework that provides similar functionality without external dependencies.

## Testing Framework

### Core Components

1. **`tests/test_framework.sh`** - Custom testing framework with:
   - Assertion functions (`assert_equal`, `assert_true`, `assert_false`, etc.)
   - Test execution and reporting
   - Colored output and statistics
   - Temporary directory management

2. **`tests/run_shell_tests.sh`** - Test runner script with:
   - Individual test file execution
   - Test discovery and listing
   - Comprehensive reporting
   - Command-line options

3. **Test Files** - Individual test suites:
   - `test_utils.bats` - Tests for utility functions
   - `test_yaml_parser.bats` - Tests for YAML configuration parsing
   - `test_disk_strategies.bats` - Tests for disk partitioning strategies
   - `test_config_manager.bats` - Tests for configuration management

## Available Assertions

The framework provides comprehensive assertion functions:

### Basic Assertions
- `assert_equal actual expected [message]` - Check if two values are equal
- `assert_not_equal actual expected [message]` - Check if two values are different
- `assert_true condition [message]` - Check if condition is true
- `assert_false condition [message]` - Check if condition is false

### File System Assertions
- `assert_file_exists file [message]` - Check if file exists
- `assert_file_not_exists file [message]` - Check if file doesn't exist
- `assert_dir_exists dir [message]` - Check if directory exists

### String Assertions
- `assert_contains haystack needle [message]` - Check if string contains substring
- `assert_not_contains haystack needle [message]` - Check if string doesn't contain substring

## Test Structure

Each test file follows this pattern:

```bash
#!/bin/bash
# test_example.bats - Description of what is being tested

# Source the test framework
source "$(dirname "$0")/test_framework.sh"

# Test setup function (optional)
setup() {
    # Initialize test environment
    # Source required scripts
    # Create test data
}

# Individual test functions
test_function_name() {
    # Test implementation using assertions
    assert_equal "$actual" "$expected"
    assert_true $condition
}

# Setup test environment
setup

# Run tests
run_test "Test Description" test_function_name
```

## Running Tests

### Run All Shell Tests
```bash
./tests/run_shell_tests.sh
```

### Run Specific Test
```bash
./tests/run_shell_tests.sh test_utils
```

### List Available Tests
```bash
./tests/run_shell_tests.sh --list
```

### Get Help
```bash
./tests/run_shell_tests.sh --help
```

## Test Coverage

### Utility Functions (`test_utils.bats`)
- Logging functions (`log_info`, `log_error`, `log_warning`)
- Input validation (`validate_username`, `validate_hostname`, `validate_disk_device`)
- Error handling and logging setup
- Idempotency tests for system operations

### YAML Parser (`test_yaml_parser.bats`)
- YAML file parsing and validation
- Environment variable export
- Configuration validation
- Error handling for invalid files

### Disk Strategies (`test_disk_strategies.bats`)
- Partitioning strategy validation
- RAID level validation
- Disk device validation
- Mock system command testing

### Configuration Manager (`test_config_manager.bats`)
- Configuration value get/set operations
- Array manipulation (add/remove items)
- Configuration backup and restore
- Import/export functionality

## Mock System

The framework includes a comprehensive mocking system for system commands:

- **Disk Operations**: `parted`, `mkfs.*`, `mount`, `umount`
- **LVM Operations**: `pvcreate`, `vgcreate`, `lvcreate`
- **RAID Operations**: `mdadm`
- **Encryption**: `cryptsetup`
- **System Commands**: `useradd`, `systemctl`, `pacman`

## Benefits

1. **No External Dependencies** - Works in any Bash environment
2. **Comprehensive Coverage** - Tests all major shell script functions
3. **Easy to Extend** - Simple to add new tests and assertions
4. **CI/CD Ready** - Integrates with automated testing pipelines
5. **Clear Reporting** - Colored output and detailed test results

## Integration with Main Test Suite

The shell tests are integrated into the main test runner (`run_tests.sh`) and run alongside:
- Rust unit tests
- YAML parser tests
- Future integration tests

## Future Enhancements

1. **Performance Testing** - Add timing and performance metrics
2. **Memory Testing** - Monitor memory usage during tests
3. **Integration Tests** - Test full installation workflows
4. **Mock Improvements** - More sophisticated command mocking
5. **Test Data Management** - Better test data generation and cleanup

## Troubleshooting

### Common Issues

1. **Path Problems** - Ensure all test files use correct relative paths
2. **Sourcing Issues** - Check that required scripts are properly sourced
3. **Mock Failures** - Verify mock commands are properly defined
4. **Exit Codes** - Some tests may have exit code issues that need debugging

### Debug Mode

Run tests with debug output:
```bash
bash -x tests/test_yaml_parser_working.bats
```

## Contributing

When adding new tests:

1. Follow the established naming convention (`test_*.bats`)
2. Include comprehensive assertions
3. Add proper setup and cleanup
4. Document what is being tested
5. Update this documentation if needed

The testing framework provides a solid foundation for ensuring the reliability and correctness of the archinstall shell scripts.
