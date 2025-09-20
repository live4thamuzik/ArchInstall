# Testing Guide

This document describes the testing infrastructure for the archinstall project.

## Overview

The project uses a comprehensive testing approach with multiple layers:

1. **Rust Unit Tests** - Test the TUI logic and state management
2. **Shell Script Tests** - Test the Bash backend (planned)
3. **YAML Parser Tests** - Test the configuration parsing
4. **Integration Tests** - Test the full installation process (planned)

## Running Tests

### Quick Test Run

Run all available tests with a single command:

```bash
./run_tests.sh
```

This script will:
- Run Rust unit tests
- Test YAML configuration parsing
- Run shell script tests (when available)
- Provide colored output and summary

### Individual Test Suites

#### Rust Unit Tests

```bash
cargo test
```

Run with verbose output:
```bash
cargo test -- --nocapture
```

Run specific test:
```bash
cargo test test_package_creation
```

#### YAML Parser Tests

```bash
source yaml_parser.sh && parse_yaml_config config.yaml
```

## Test Coverage

### Rust Unit Tests (20 tests)

The Rust tests cover:

- **Data Structure Tests**
  - Package creation and validation
  - InstallerState creation and initialization
  - PopupState creation and navigation
  - ProgressUpdate serialization/deserialization

- **Function Tests**
  - Text input field detection (`is_text_input_field`)
  - Package selection retrieval (`get_selected_packages`)
  - Popup type options (`get_popup_options`)

- **Enum Tests**
  - InstallationPhase enum variants
  - MessageType enum variants
  - PopupType enum variants

- **State Management Tests**
  - Configuration step navigation
  - Config values initialization
  - Installer state mutex operations
  - Field editing and input mode

- **Serialization Tests**
  - JSON serialization/deserialization
  - ProgressUpdate parsing
  - Package data serialization

### Shell Script Tests (Planned)

Future shell script tests will cover:

- Configuration validation functions
- Disk detection and validation
- Package installation functions
- User creation and management
- Service configuration
- Bootloader setup

## Test Structure

### Rust Tests

Located in `src/main.rs` under the `#[cfg(test)]` module:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    // Helper functions for creating test data
    fn create_test_package() -> Package { ... }
    fn create_test_installer_state() -> InstallerState { ... }
    
    // Individual test functions
    #[test]
    fn test_package_creation() { ... }
    
    // ... more tests
}
```

### Test Helper Functions

- `create_test_package()` - Creates a test Package struct
- `create_test_installer_state()` - Creates a test InstallerState struct

## Adding New Tests

### Rust Tests

1. Add test functions to the `tests` module in `src/main.rs`
2. Use descriptive test names starting with `test_`
3. Use helper functions for creating test data
4. Test both success and failure cases
5. Include assertions with clear error messages

Example:
```rust
#[test]
fn test_new_functionality() {
    let state = create_test_installer_state();
    
    // Test initial state
    assert_eq!(state.some_field, expected_value);
    
    // Test state changes
    state.some_field = new_value;
    assert_eq!(state.some_field, new_value);
}
```

### Shell Script Tests (Future)

1. Create `.bats` files in the `tests/` directory
2. Use bats-core testing framework
3. Test functions in isolation
4. Mock external dependencies
5. Test error conditions

## Continuous Integration

The test suite is designed to work with CI/CD systems:

- All tests run automatically
- Exit codes indicate success/failure
- Colored output for better readability
- Comprehensive test coverage

## Best Practices

1. **Test Isolation** - Each test should be independent
2. **Clear Naming** - Test names should describe what they test
3. **Comprehensive Coverage** - Test both happy path and error cases
4. **Fast Execution** - Tests should run quickly
5. **Maintainable** - Tests should be easy to understand and modify

## Troubleshooting

### Common Issues

1. **Tests fail after code changes**
   - Update test expectations to match new behavior
   - Check if struct fields have changed
   - Verify function signatures

2. **YAML parser tests fail**
   - Ensure `config.yaml` exists and is valid
   - Check that `yaml_parser.sh` is executable
   - Verify YAML syntax

3. **Rust compilation errors**
   - Run `cargo check` to see detailed errors
   - Ensure all dependencies are available
   - Check for syntax errors in test code

### Debug Mode

Run tests with debug output:
```bash
RUST_BACKTRACE=1 cargo test
```

## Future Enhancements

- Integration tests for full installation process
- Performance tests for large configurations
- Memory leak detection
- Automated test coverage reporting
- Test result visualization
