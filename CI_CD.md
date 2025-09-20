# CI/CD Pipeline Documentation

This document describes the continuous integration and deployment pipeline for the archinstall-tui project.

## Overview

The project uses GitHub Actions for CI/CD with multiple stages:
- **Testing** - Automated testing across different environments
- **Security** - Vulnerability scanning and security checks
- **Building** - Automated builds and packaging
- **Deployment** - Docker image creation and release management

## Pipeline Stages

### 1. Test Stage

**Triggers**: Push to main/develop, Pull requests
**Runs on**: Ubuntu Latest
**Rust Versions**: stable, beta, nightly

#### Steps:
- **Checkout Code** - Clone repository
- **Install Rust** - Setup Rust toolchain
- **Cache Dependencies** - Cache Cargo registry and git dependencies
- **Install System Dependencies** - Install build tools and libraries
- **Run Rust Tests** - Execute all Rust unit tests
- **Format Check** - Verify code formatting with rustfmt
- **Clippy Lint** - Run Rust linter with strict warnings
- **Build Release** - Create optimized release binary
- **Shell Script Tests** - Run custom shell script test suite

### 2. Integration Test Stage

**Triggers**: After successful test stage
**Runs on**: Ubuntu Latest with QEMU

#### Steps:
- **Setup QEMU** - Install virtualization tools
- **Download Arch ISO** - Get latest Arch Linux installation media
- **Create VM** - Setup test virtual machine
- **Run Integration Tests** - Test installation process in VM
- **Cleanup** - Remove test artifacts

### 3. Security Scan Stage

**Triggers**: After successful test stage
**Runs on**: Ubuntu Latest

#### Steps:
- **Trivy Scan** - Run vulnerability scanner on filesystem
- **Upload Results** - Submit SARIF results to GitHub Security
- **Security Alerts** - Generate security alerts for vulnerabilities

### 4. Build and Package Stage

**Triggers**: On release creation
**Runs on**: Ubuntu Latest

#### Steps:
- **Build Binary** - Create release binary
- **Create Package** - Generate distribution package
- **Package Manifest** - Create package metadata
- **Create Tarball** - Compress package for distribution
- **Upload Assets** - Attach to GitHub release

### 5. Docker Build Stage

**Triggers**: Push to main branch
**Runs on**: Ubuntu Latest

#### Steps:
- **Setup Buildx** - Configure Docker buildx
- **Login to Registry** - Authenticate with Docker Hub
- **Build and Push** - Create and publish Docker images
- **Cache Management** - Optimize build caching

### 6. Documentation Stage

**Triggers**: After successful test stage
**Runs on**: Ubuntu Latest

#### Steps:
- **Generate Rust Docs** - Create API documentation
- **Generate Shell Docs** - Extract documentation from scripts
- **Upload Artifacts** - Store documentation for 30 days

### 7. Performance Benchmark Stage

**Triggers**: Push to main branch
**Runs on**: Ubuntu Latest

#### Steps:
- **Install Criterion** - Setup benchmarking tool
- **Run Benchmarks** - Execute performance tests
- **Upload Results** - Store benchmark data

### 8. Notification Stage

**Triggers**: After all stages complete
**Runs on**: Ubuntu Latest

#### Steps:
- **Check Results** - Evaluate all stage outcomes
- **Notify Success** - Report successful builds
- **Notify Failure** - Report failed builds with details

## Workflow Files

### `.github/workflows/ci.yml`
Main CI/CD pipeline configuration with all stages.

### `Dockerfile`
Multi-stage Docker build for containerized deployment.

### `docker-compose.yml`
Development and testing environments with different profiles:
- `test` - Run tests in container
- `install` - Run installer in container
- `dev` - Development environment
- `ci` - CI/CD test runner

## Local Development

### Prerequisites
- Rust toolchain (stable, beta, or nightly)
- Docker and Docker Compose
- Make (for using Makefile)
- Git

### Quick Start
```bash
# Clone repository
git clone <repository-url>
cd archinstall

# Setup development environment
make dev-setup

# Run tests
make test

# Build binary
make build

# Run in Docker
make docker-run
```

### Development Commands

#### Build Commands
```bash
make build          # Build release binary
make build-dev      # Build debug binary
make clean          # Clean build artifacts
```

#### Test Commands
```bash
make test           # Run all tests
make test-rust      # Run Rust tests only
make test-shell     # Run shell script tests
make test-yaml      # Run YAML parser tests
```

#### Development Commands
```bash
make fmt            # Format Rust code
make lint           # Run Rust clippy
make check          # Check code compiles
make doc            # Generate documentation
```

#### Docker Commands
```bash
make docker-build   # Build Docker image
make docker-test    # Run tests in Docker
make docker-run     # Run archinstall in Docker
```

#### CI/CD Commands
```bash
make ci-setup       # Setup CI environment
make ci-test        # Run CI test suite
make pre-commit     # Run pre-commit hooks
```

## Pre-commit Hooks

### Installation
```bash
pip install pre-commit
pre-commit install
```

### Configuration
The `.pre-commit-config.yaml` file includes:
- **Rust formatting** with rustfmt
- **Rust linting** with clippy
- **Shell script linting** with shellcheck
- **File validation** for YAML, JSON, TOML
- **Security scanning** for secrets
- **Custom hooks** for project-specific checks

### Running Hooks
```bash
pre-commit run --all-files    # Run on all files
pre-commit run                # Run on staged files
```

## Docker Environments

### Development Environment
```bash
docker-compose --profile dev up
```
- Mounts source code for live editing
- Includes cargo cache volume
- Provides interactive bash shell

### Testing Environment
```bash
docker-compose --profile test up
```
- Runs all tests in isolated container
- Includes test data volume
- Automated test execution

### Installation Environment
```bash
docker-compose --profile install up
```
- Runs archinstall in container
- Mounts system devices for disk access
- Provides installation environment

## Security Considerations

### Container Security
- Non-root user execution
- Minimal base image (Debian slim)
- No unnecessary privileges
- Security options enabled
- Regular base image updates

### Code Security
- Dependency vulnerability scanning
- Secret detection in commits
- Input validation and sanitization
- Secure coding practices

### Runtime Security
- Privilege separation
- Capability dropping
- Read-only root filesystem
- Network isolation

## Performance Optimization

### Build Optimization
- Multi-stage Docker builds
- Dependency caching
- Parallel test execution
- Incremental compilation

### Runtime Optimization
- Release binary optimization
- Static linking where possible
- Minimal runtime dependencies
- Efficient resource usage

## Monitoring and Alerting

### Build Status
- GitHub Actions status badges
- Email notifications for failures
- Slack/Discord integration (configurable)
- Detailed failure logs

### Security Alerts
- GitHub Security tab integration
- Automated vulnerability reports
- Dependency update notifications
- Security policy enforcement

## Troubleshooting

### Common Issues

#### Build Failures
```bash
# Check Rust toolchain
rustc --version
cargo --version

# Clean and rebuild
make clean
make build

# Check dependencies
cargo check
```

#### Test Failures
```bash
# Run specific test suites
make test-rust
make test-shell

# Debug with verbose output
cargo test --verbose
./tests/run_shell_tests.sh --verbose
```

#### Docker Issues
```bash
# Check Docker installation
docker --version
docker-compose --version

# Rebuild images
make docker-build

# Check container logs
docker-compose logs
```

### Debug Mode
```bash
# Enable debug logging
export RUST_LOG=debug
export ARCHINSTALL_LOG_LEVEL=DEBUG

# Run with debug binary
make build-dev
cargo run
```

## Contributing

### Pull Request Process
1. Fork repository
2. Create feature branch
3. Make changes with tests
4. Run pre-commit hooks
5. Submit pull request
6. CI/CD pipeline runs automatically
7. Address any failures
8. Merge after approval

### Code Standards
- Follow Rust formatting guidelines
- Include comprehensive tests
- Update documentation
- Follow security best practices
- Maintain backward compatibility

## Release Process

### Automated Release
1. Create GitHub release
2. CI/CD pipeline triggers automatically
3. Builds and packages binary
4. Creates Docker images
5. Uploads distribution artifacts
6. Publishes to registries

### Manual Release
```bash
# Prepare release
make release-prep

# Create distribution
make package

# Build Docker images
make docker-build

# Test installation
make docker-test
```

## Maintenance

### Regular Tasks
- Update dependencies monthly
- Review security advisories
- Update base Docker images
- Monitor build performance
- Review test coverage

### Dependency Updates
```bash
# Update Rust dependencies
cargo update

# Update system dependencies
# (handled in Dockerfile)

# Update pre-commit hooks
pre-commit autoupdate
```

This CI/CD pipeline provides comprehensive testing, security scanning, automated building, and deployment capabilities for the archinstall-tui project.
