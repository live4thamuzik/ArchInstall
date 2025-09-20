# ArchInstall Makefile
# Provides convenient commands for development and testing

.PHONY: help build test clean install dev test-rust test-shell test-all lint format docker

# Default target
help:
	@echo "ArchInstall Development Commands:"
	@echo "  build        - Build the Rust TUI application"
	@echo "  test         - Run all tests (Rust + Shell)"
	@echo "  test-rust    - Run Rust unit tests"
	@echo "  test-shell   - Run shell script tests"
	@echo "  clean        - Clean build artifacts"
	@echo "  lint         - Run linters (clippy, shellcheck)"
	@echo "  format       - Format code (rustfmt)"
	@echo "  docker       - Build Docker image"
	@echo "  dev          - Start development environment"
	@echo "  install      - Install development dependencies"

# Build the application
build:
	@echo "Building ArchInstall TUI..."
	cargo build --release
	@echo "Build complete! Binary: target/release/archinstall-tui"

# Run all tests
test: test-rust test-shell
	@echo "All tests completed!"

# Run Rust tests
test-rust:
	@echo "Running Rust tests..."
	cargo test
	@echo "Rust tests completed!"

# Run shell tests
test-shell:
	@echo "Running shell tests..."
	@if [ -f "./run_tests.sh" ]; then \
		./run_tests.sh; \
	else \
		echo "Shell tests not available (run_tests.sh not found)"; \
	fi

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	cargo clean
	rm -rf target/
	@echo "Clean complete!"

# Run linters
lint:
	@echo "Running linters..."
	@if command -v clippy >/dev/null 2>&1; then \
		cargo clippy -- -D warnings; \
	else \
		echo "Clippy not installed, skipping Rust linting"; \
	fi
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck *.sh; \
	else \
		echo "ShellCheck not installed, skipping shell linting"; \
	fi

# Format code
format:
	@echo "Formatting code..."
	cargo fmt
	@echo "Formatting complete!"

# Docker commands
docker:
	@echo "Building Docker image..."
	docker build -t archinstall:latest .

docker-run:
	@echo "Running Docker container..."
	docker run -it --privileged archinstall:latest

# Development environment
dev:
	@echo "Starting development environment..."
	@echo "Make sure Rust toolchain is installed:"
	@echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
	@echo ""
	@echo "Install development dependencies:"
	@echo "  make install"
	@echo ""
	@echo "Build the application:"
	@echo "  make build"
	@echo ""
	@echo "Run tests:"
	@echo "  make test"

# Install development dependencies
install:
	@echo "Installing development dependencies..."
	@if command -v pacman >/dev/null 2>&1; then \
		echo "Installing Arch Linux packages..."; \
		sudo pacman -S --needed rust cargo shellcheck git; \
	elif command -v apt >/dev/null 2>&1; then \
		echo "Installing Ubuntu/Debian packages..."; \
		sudo apt update && sudo apt install -y rustc cargo shellcheck git; \
	elif command -v dnf >/dev/null 2>&1; then \
		echo "Installing Fedora packages..."; \
		sudo dnf install -y rust cargo ShellCheck git; \
	else \
		echo "Please install Rust toolchain and shellcheck manually"; \
		echo "Rust: https://rustup.rs/"; \
		echo "ShellCheck: https://github.com/koalaman/shellcheck#installing"; \
	fi

# Quick development setup
setup: install build
	@echo "Development setup complete!"
	@echo "Run 'make test' to verify everything works"

# Release build with optimizations
release:
	@echo "Building optimized release..."
	cargo build --release --target x86_64-unknown-linux-gnu
	@echo "Release build complete!"

# Check for common issues
check:
	@echo "Running checks..."
	@echo "Checking Rust toolchain..."
	@rustc --version || (echo "Rust not installed!" && exit 1)
	@echo "Checking cargo..."
	@cargo --version || (echo "Cargo not installed!" && exit 1)
	@echo "All checks passed!"

# Show project info
info:
	@echo "ArchInstall Project Information:"
	@echo "  Rust version: $(shell rustc --version)"
	@echo "  Cargo version: $(shell cargo --version)"
	@echo "  Project size: $(shell du -sh . 2>/dev/null | cut -f1)"
	@echo "  Files: $(shell find . -name "*.rs" -o -name "*.sh" | wc -l)"