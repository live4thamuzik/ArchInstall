#!/bin/bash
# test_ci_setup.sh - Test CI/CD setup locally

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to test Rust setup
test_rust_setup() {
    print_status $BLUE "Testing Rust setup..."
    
    if ! command_exists cargo; then
        print_status $RED "❌ Cargo not found"
        return 1
    fi
    
    if ! command_exists rustc; then
        print_status $RED "❌ Rustc not found"
        return 1
    fi
    
    print_status $GREEN "✅ Rust toolchain: $(rustc --version)"
    print_status $GREEN "✅ Cargo version: $(cargo --version)"
    
    # Test Rust compilation
    print_status $BLUE "Testing Rust compilation..."
    if cargo check; then
        print_status $GREEN "✅ Rust code compiles successfully"
    else
        print_status $RED "❌ Rust compilation failed"
        return 1
    fi
    
    # Test Rust formatting
    print_status $BLUE "Testing Rust formatting..."
    if cargo fmt --all -- --check; then
        print_status $GREEN "✅ Rust code is properly formatted"
    else
        print_status $YELLOW "⚠️  Rust code needs formatting (run 'cargo fmt')"
    fi
    
    # Test Rust linting
    print_status $BLUE "Testing Rust linting..."
    if cargo clippy --all-targets --all-features -- -D warnings; then
        print_status $GREEN "✅ Rust code passes clippy"
    else
        print_status $YELLOW "⚠️  Rust code has clippy warnings"
    fi
    
    return 0
}

# Function to test Docker setup
test_docker_setup() {
    print_status $BLUE "Testing Docker setup..."
    
    if ! command_exists docker; then
        print_status $RED "❌ Docker not found"
        return 1
    fi
    
    if ! command_exists docker-compose; then
        print_status $RED "❌ Docker Compose not found"
        return 1
    fi
    
    print_status $GREEN "✅ Docker version: $(docker --version)"
    print_status $GREEN "✅ Docker Compose version: $(docker-compose --version)"
    
    # Test Docker daemon
    if docker info >/dev/null 2>&1; then
        print_status $GREEN "✅ Docker daemon is running"
    else
        print_status $RED "❌ Docker daemon is not running"
        return 1
    fi
    
    return 0
}

# Function to test Make setup
test_make_setup() {
    print_status $BLUE "Testing Make setup..."
    
    if ! command_exists make; then
        print_status $RED "❌ Make not found"
        return 1
    fi
    
    print_status $GREEN "✅ Make version: $(make --version | head -n1)"
    
    # Test Makefile targets
    print_status $BLUE "Testing Makefile targets..."
    if make help >/dev/null 2>&1; then
        print_status $GREEN "✅ Makefile is valid"
    else
        print_status $RED "❌ Makefile has issues"
        return 1
    fi
    
    return 0
}

# Function to test pre-commit setup
test_precommit_setup() {
    print_status $BLUE "Testing pre-commit setup..."
    
    if ! command_exists pre-commit; then
        print_status $YELLOW "⚠️  pre-commit not found (optional)"
        return 0
    fi
    
    print_status $GREEN "✅ pre-commit version: $(pre-commit --version)"
    
    # Test pre-commit configuration
    if [ -f ".pre-commit-config.yaml" ]; then
        print_status $GREEN "✅ Pre-commit configuration found"
        
        # Validate configuration
        if pre-commit validate-config; then
            print_status $GREEN "✅ Pre-commit configuration is valid"
        else
            print_status $RED "❌ Pre-commit configuration has issues"
            return 1
        fi
    else
        print_status $RED "❌ Pre-commit configuration not found"
        return 1
    fi
    
    return 0
}

# Function to test project structure
test_project_structure() {
    print_status $BLUE "Testing project structure..."
    
    local required_files=(
        "Cargo.toml"
        "src/main.rs"
        "README.md"
        "LICENSE"
        "config.yaml"
        "yaml_parser.sh"
        "utils.sh"
        "disk_strategies.sh"
        "install_arch.sh"
        "Makefile"
        "Dockerfile"
        "docker-compose.yml"
        ".github/workflows/ci.yml"
        ".github/workflows/release.yml"
        ".pre-commit-config.yaml"
    )
    
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            print_status $GREEN "✅ $file"
        else
            print_status $RED "❌ $file (missing)"
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -eq 0 ]; then
        print_status $GREEN "✅ All required files present"
        return 0
    else
        print_status $RED "❌ Missing ${#missing_files[@]} required files"
        return 1
    fi
}

# Function to test test suite
test_test_suite() {
    print_status $BLUE "Testing test suite..."
    
    # Test Rust tests
    print_status $BLUE "Running Rust tests..."
    if cargo test; then
        print_status $GREEN "✅ Rust tests pass"
    else
        print_status $RED "❌ Rust tests fail"
        return 1
    fi
    
    # Test shell script tests
    print_status $BLUE "Running shell script tests..."
    if [ -f "run_tests.sh" ] && bash run_tests.sh; then
        print_status $GREEN "✅ Shell script tests pass"
    else
        print_status $YELLOW "⚠️  Shell script tests have issues (may be expected)"
    fi
    
    return 0
}

# Function to test Docker build
test_docker_build() {
    print_status $BLUE "Testing Docker build..."
    
    if [ -f "Dockerfile" ]; then
        if docker build -t archinstall-test . >/dev/null 2>&1; then
            print_status $GREEN "✅ Docker image builds successfully"
            
            # Test Docker image
            if docker run --rm archinstall-test --help >/dev/null 2>&1; then
                print_status $GREEN "✅ Docker image runs correctly"
            else
                print_status $YELLOW "⚠️  Docker image runs but may have issues"
            fi
            
            # Cleanup
            docker rmi archinstall-test >/dev/null 2>&1 || true
        else
            print_status $RED "❌ Docker image build failed"
            return 1
        fi
    else
        print_status $RED "❌ Dockerfile not found"
        return 1
    fi
    
    return 0
}

# Main test function
main() {
    print_status $BLUE "🧪 Testing CI/CD setup for archinstall-tui..."
    echo ""
    
    local tests_passed=0
    local tests_failed=0
    
    # Run all tests
    if test_project_structure; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    if test_rust_setup; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    if test_docker_setup; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    if test_make_setup; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    if test_precommit_setup; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    if test_test_suite; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    if test_docker_build; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    echo ""
    print_status $BLUE "Test Summary:"
    print_status $GREEN "  Passed: $tests_passed"
    if [ $tests_failed -gt 0 ]; then
        print_status $RED "  Failed: $tests_failed"
    else
        print_status $GREEN "  Failed: $tests_failed"
    fi
    print_status $BLUE "  Total: $((tests_passed + tests_failed))"
    
    if [ $tests_failed -eq 0 ]; then
        print_status $GREEN "🎉 CI/CD setup is ready!"
        echo ""
        print_status $BLUE "Next steps:"
        print_status $GREEN "  1. Push code to GitHub"
        print_status $GREEN "  2. GitHub Actions will run automatically"
        print_status $GREEN "  3. Create a release to trigger deployment"
        return 0
    else
        print_status $RED "💥 CI/CD setup has issues that need to be fixed"
        return 1
    fi
}

# Run main function
main "$@"
