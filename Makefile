# Makefile for archinstall-tui development

# Variables
CARGO = cargo
RUST_VERSION = stable
TARGET = release
BINARY_NAME = archinstall-tui
VERSION = $(shell grep '^version' Cargo.toml | cut -d'"' -f2)
BUILD_DIR = target/$(TARGET)
DIST_DIR = dist
PACKAGE_NAME = archinstall-tui-$(VERSION)

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
NC = \033[0m # No Color

# Default target
.PHONY: all
all: build test

# Help target
.PHONY: help
help:
	@echo "$(BLUE)archinstall-tui Development Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Build Commands:$(NC)"
	@echo "  build          - Build release binary"
	@echo "  build-dev      - Build debug binary"
	@echo "  clean          - Clean build artifacts"
	@echo ""
	@echo "$(GREEN)Test Commands:$(NC)"
	@echo "  test           - Run all tests"
	@echo "  test-rust      - Run Rust tests only"
	@echo "  test-shell     - Run shell script tests only"
	@echo "  test-yaml      - Run YAML parser tests"
	@echo ""
	@echo "$(GREEN)Development Commands:$(NC)"
	@echo "  fmt            - Format Rust code"
	@echo "  lint           - Run Rust clippy"
	@echo "  check          - Check Rust code compiles"
	@echo "  doc            - Generate documentation"
	@echo ""
	@echo "$(GREEN)Package Commands:$(NC)"
	@echo "  package        - Create distribution package"
	@echo "  install        - Install binary to /usr/local/bin"
	@echo "  uninstall      - Remove binary from /usr/local/bin"
	@echo ""
	@echo "$(GREEN)Docker Commands:$(NC)"
	@echo "  docker-build   - Build Docker image"
	@echo "  docker-test    - Run tests in Docker"
	@echo "  docker-run     - Run archinstall in Docker"
	@echo ""
	@echo "$(GREEN)CI/CD Commands:$(NC)"
	@echo "  ci-setup       - Setup CI environment"
	@echo "  ci-test        - Run CI test suite"
	@echo "  pre-commit     - Run pre-commit hooks"
	@echo ""
	@echo "$(GREEN)Cleanup Commands:$(NC)"
	@echo "  clean-all      - Clean all generated files"
	@echo "  clean-deps     - Clean dependency cache"

# Build targets
.PHONY: build
build:
	@echo "$(BLUE)Building $(BINARY_NAME) $(VERSION)...$(NC)"
	$(CARGO) build --$(TARGET)
	@echo "$(GREEN)Build complete!$(NC)"

.PHONY: build-dev
build-dev:
	@echo "$(BLUE)Building debug version...$(NC)"
	$(CARGO) build
	@echo "$(GREEN)Debug build complete!$(NC)"

.PHONY: clean
clean:
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	$(CARGO) clean
	@echo "$(GREEN)Clean complete!$(NC)"

# Test targets
.PHONY: test
test:
	@echo "$(BLUE)Running all tests...$(NC)"
	./run_tests.sh
	@echo "$(GREEN)All tests completed!$(NC)"

.PHONY: test-rust
test-rust:
	@echo "$(BLUE)Running Rust tests...$(NC)"
	$(CARGO) test --verbose
	@echo "$(GREEN)Rust tests completed!$(NC)"

.PHONY: test-shell
test-shell:
	@echo "$(BLUE)Running shell script tests...$(NC)"
	./tests/run_shell_tests.sh
	@echo "$(GREEN)Shell tests completed!$(NC)"

.PHONY: test-yaml
test-yaml:
	@echo "$(BLUE)Running YAML parser tests...$(NC)"
	source yaml_parser.sh && parse_yaml_config config.yaml
	@echo "$(GREEN)YAML tests completed!$(NC)"

# Development targets
.PHONY: fmt
fmt:
	@echo "$(BLUE)Formatting Rust code...$(NC)"
	$(CARGO) fmt --all
	@echo "$(GREEN)Formatting complete!$(NC)"

.PHONY: lint
lint:
	@echo "$(BLUE)Running clippy...$(NC)"
	$(CARGO) clippy --all-targets --all-features -- -D warnings
	@echo "$(GREEN)Clippy complete!$(NC)"

.PHONY: check
check:
	@echo "$(BLUE)Checking Rust code...$(NC)"
	$(CARGO) check --all-targets --all-features
	@echo "$(GREEN)Check complete!$(NC)"

.PHONY: doc
doc:
	@echo "$(BLUE)Generating documentation...$(NC)"
	$(CARGO) doc --no-deps --document-private-items --open
	@echo "$(GREEN)Documentation generated!$(NC)"

# Package targets
.PHONY: package
package: build
	@echo "$(BLUE)Creating package...$(NC)"
	@mkdir -p $(DIST_DIR)/$(PACKAGE_NAME)
	@cp $(BUILD_DIR)/$(BINARY_NAME) $(DIST_DIR)/$(PACKAGE_NAME)/
	@cp config.yaml $(DIST_DIR)/$(PACKAGE_NAME)/
	@cp *.sh $(DIST_DIR)/$(PACKAGE_NAME)/
	@cp -r Source/ $(DIST_DIR)/$(PACKAGE_NAME)/
	@cp README.md LICENSE $(DIST_DIR)/$(PACKAGE_NAME)/
	@cd $(DIST_DIR) && tar -czf $(PACKAGE_NAME).tar.gz $(PACKAGE_NAME)
	@echo "$(GREEN)Package created: $(DIST_DIR)/$(PACKAGE_NAME).tar.gz$(NC)"

.PHONY: install
install: build
	@echo "$(BLUE)Installing $(BINARY_NAME)...$(NC)"
	sudo cp $(BUILD_DIR)/$(BINARY_NAME) /usr/local/bin/
	sudo chmod +x /usr/local/bin/$(BINARY_NAME)
	@echo "$(GREEN)Installation complete!$(NC)"

.PHONY: uninstall
uninstall:
	@echo "$(BLUE)Uninstalling $(BINARY_NAME)...$(NC)"
	sudo rm -f /usr/local/bin/$(BINARY_NAME)
	@echo "$(GREEN)Uninstallation complete!$(NC)"

# Docker targets
.PHONY: docker-build
docker-build:
	@echo "$(BLUE)Building Docker image...$(NC)"
	docker build -t archinstall-tui:$(VERSION) .
	docker build -t archinstall-tui:latest .
	@echo "$(GREEN)Docker build complete!$(NC)"

.PHONY: docker-test
docker-test:
	@echo "$(BLUE)Running tests in Docker...$(NC)"
	docker-compose --profile test run --rm archinstall-test
	@echo "$(GREEN)Docker tests complete!$(NC)"

.PHONY: docker-run
docker-run:
	@echo "$(BLUE)Running archinstall in Docker...$(NC)"
	docker-compose --profile install run --rm archinstall-tui
	@echo "$(GREEN)Docker run complete!$(NC)"

# CI/CD targets
.PHONY: ci-setup
ci-setup:
	@echo "$(BLUE)Setting up CI environment...$(NC)"
	@if command -v pre-commit >/dev/null 2>&1; then \
		pre-commit install; \
		echo "$(GREEN)Pre-commit hooks installed!$(NC)"; \
	else \
		echo "$(YELLOW)pre-commit not found, installing...$(NC)"; \
		pip install pre-commit; \
		pre-commit install; \
	fi
	@echo "$(GREEN)CI setup complete!$(NC)"

.PHONY: ci-test
ci-test: fmt lint check test
	@echo "$(GREEN)CI test suite completed!$(NC)"

.PHONY: pre-commit
pre-commit:
	@echo "$(BLUE)Running pre-commit hooks...$(NC)"
	pre-commit run --all-files
	@echo "$(GREEN)Pre-commit hooks completed!$(NC)"

# Cleanup targets
.PHONY: clean-all
clean-all: clean
	@echo "$(BLUE)Cleaning all generated files...$(NC)"
	rm -rf $(DIST_DIR)
	rm -rf target/
	rm -rf .cargo/
	docker system prune -f
	@echo "$(GREEN)Complete cleanup done!$(NC)"

.PHONY: clean-deps
clean-deps:
	@echo "$(BLUE)Cleaning dependency cache...$(NC)"
	$(CARGO) clean --release
	rm -rf ~/.cargo/registry
	@echo "$(GREEN)Dependency cache cleaned!$(NC)"

# Development workflow targets
.PHONY: dev-setup
dev-setup: ci-setup
	@echo "$(BLUE)Setting up development environment...$(NC)"
	@if ! command -v cargo >/dev/null 2>&1; then \
		echo "$(YELLOW)Rust not found, please install Rust first$(NC)"; \
		exit 1; \
	fi
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "$(YELLOW)Docker not found, please install Docker first$(NC)"; \
	fi
	@echo "$(GREEN)Development environment setup complete!$(NC)"

.PHONY: quick-test
quick-test: fmt lint test-rust
	@echo "$(GREEN)Quick test completed!$(NC)"

.PHONY: full-test
full-test: ci-test test-shell docker-test
	@echo "$(GREEN)Full test suite completed!$(NC)"

# Version management
.PHONY: version
version:
	@echo "$(BLUE)Current version: $(VERSION)$(NC)"

.PHONY: bump-version
bump-version:
	@echo "$(BLUE)Bumping version...$(NC)"
	@read -p "Enter new version: " new_version; \
	sed -i "s/^version = \".*\"/version = \"$$new_version\"/" Cargo.toml; \
	echo "$(GREEN)Version bumped to $$new_version$(NC)"

# Release preparation
.PHONY: release-prep
release-prep: clean test package
	@echo "$(BLUE)Release preparation complete!$(NC)"
	@echo "$(GREEN)Package ready: $(DIST_DIR)/$(PACKAGE_NAME).tar.gz$(NC)"

# Show status
.PHONY: status
status:
	@echo "$(BLUE)Project Status:$(NC)"
	@echo "  Version: $(VERSION)"
	@echo "  Rust version: $$(rustc --version)"
	@echo "  Cargo version: $$(cargo --version)"
	@echo "  Binary: $(BUILD_DIR)/$(BINARY_NAME)"
	@if [ -f "$(BUILD_DIR)/$(BINARY_NAME)" ]; then \
		echo "  Status: $(GREEN)Built$(NC)"; \
	else \
		echo "  Status: $(RED)Not built$(NC)"; \
	fi
