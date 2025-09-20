# Git Branching Strategy

## Branch Structure

This repository follows a professional **Git Flow** branching strategy with three main branches:

### 🌟 **Main Branches**

#### `main` (Production - Live ISO Ready)
- **Purpose**: Minimal installer for live ISO users
- **Size**: ~15 files, optimized for fast cloning
- **Content**: Core installer scripts, Rust TUI, essential files only
- **Protection**: Direct pushes are disabled
- **Merges**: Only from `testing` branch via Pull Requests

#### `develop` (Development)
- **Purpose**: Full development environment
- **Size**: ~35 files, includes development tools
- **Content**: Everything from main + development tools, documentation
- **Protection**: Direct pushes allowed for developers
- **Merges**: Feature branches merge here first

#### `testing` (Quality Assurance)
- **Purpose**: Testing and validation branch
- **Size**: ~45 files, includes test suite
- **Content**: Everything from main + comprehensive test suite
- **Protection**: Direct pushes allowed for testing
- **Merges**: Stable features from `develop`

### 🔄 **Workflow**

```mermaid
graph LR
    A[Feature Branch] --> B[develop]
    B --> C[testing]
    C --> D[main]
    
    style A fill:#e1f5fe
    style B fill:#f3e5f5
    style C fill:#fff3e0
    style D fill:#e8f5e8
```

### 📋 **Branch Contents**

#### **Main Branch (Live ISO Optimized):**
- Core installer scripts (9 files)
- Rust TUI application (3 files)
- Launch script
- Basic README
- License
- **Total: ~15 files, <10MB**

#### **Develop Branch (Full Development):**
- Everything from main
- Development tools (Docker, Makefile, pre-commit)
- Documentation (BRANCHING_STRATEGY.md)
- **Total: ~35 files**

#### **Testing Branch (Complete Testing):**
- Everything from main
- Test suite (8+ files)
- Test runners
- CI/CD configurations
- **Total: ~45 files**

### 🚀 **Usage Guidelines**

#### **For Live ISO Users:**
```bash
# Clone main branch (minimal, fast)
git clone https://github.com/live4thamuzik/ArchInstall.git
cd ArchInstall
./launch_tui_installer.sh
```

#### **For Developers:**
```bash
# Clone develop branch
git clone -b develop https://github.com/live4thamuzik/ArchInstall.git
cd ArchInstall
make build
make test
```

#### **For Testing:**
```bash
# Clone testing branch
git clone -b testing https://github.com/live4thamuzik/ArchInstall.git
cd ArchInstall
./run_tests.sh
```

### 📁 **File Organization by Branch**

| File Type | Main | Develop | Testing |
|-----------|------|---------|---------|
| Core Scripts | ✅ | ✅ | ✅ |
| Rust TUI | ✅ | ✅ | ✅ |
| Launch Script | ✅ | ✅ | ✅ |
| README | ✅ (minimal) | ✅ (full) | ✅ (full) |
| License | ✅ | ✅ | ✅ |
| Development Tools | ❌ | ✅ | ✅ |
| Documentation | ❌ | ✅ | ✅ |
| Test Suite | ❌ | ❌ | ✅ |
| CI/CD | ❌ | ❌ | ✅ |

### 🔧 **Commands**

```bash
# Switch between branches
git checkout main          # Live ISO ready
git checkout develop       # Full development
git checkout testing       # Complete testing

# Clone specific branch
git clone -b main https://github.com/live4thamuzik/ArchInstall.git
git clone -b develop https://github.com/live4thamuzik/ArchInstall.git
git clone -b testing https://github.com/live4thamuzik/ArchInstall.git

# Create feature branch
git checkout develop
git checkout -b feature/new-feature
```

### 📝 **Best Practices**

1. **Live ISO users**: Always use `main` branch
2. **Developers**: Use `develop` branch for new features
3. **Testers**: Use `testing` branch for validation
4. **Releases**: Merge from `testing` to `main`
5. **Keep main minimal**: No development tools or tests
6. **Document changes**: Update relevant documentation

### 🎯 **Benefits of This Strategy**

- ✅ **Fast cloning** on live ISO (main branch <10MB)
- ✅ **Clean separation** of concerns
- ✅ **Optimized for users** vs developers
- ✅ **Professional structure** for collaboration
- ✅ **Easy maintenance** with clear boundaries
- ✅ **Live ISO friendly** - minimal download required
