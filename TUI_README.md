# Arch Linux Installer TUI

A modern, professional Terminal User Interface (TUI) for the Arch Linux Installer, built with Rust and `ratatui`.

## Features

- **Professional Design**: Clean, modern interface with ASCII Arch logo
- **Interactive Configuration**: Full configuration interface with highlighting and navigation
- **Text Input Fields**: Username, passwords, hostname with proper input handling
- **Popup Selections**: Disk selection, desktop environment, timezone, and more
- **Auto-selection Logic**: Display manager automatically selected based on desktop environment
- **Package Management**: Interactive package selection for both Pacman and AUR packages
- **Plymouth Theme Selection**: Choose between arch-glow and arch-mac-style themes
- **Real-time Progress**: Live progress bars and status updates during installation
- **Fast Performance**: Built with Rust for maximum speed

## Screenshot

```
┌─────────────────────────────────────────────────────────┐
│  ╔═══════════════════════════════════════════════════╗  │
│  ║                                                   ║  │
│  ║    █████╗ ██████╗  ██████╗██╗  ██╗    ██╗     ██╗██╗  ██╗██╗   ██╗ ║  │
│  ║   ██╔══██╗██╔══██╗██╔════╝██║  ██║    ██║     ██║██║ ██╔╝██║   ██║ ║  │
│  ║   ███████║██████╔╝██║     ███████║    ██║     ██║█████╔╝ ██║   ██║ ║  │
│  ║   ██╔══██║██╔══██╗██║     ██╔══██║    ██║     ██║██╔═██╗ ██║   ██║ ║  │
│  ║   ██║  ██║██║  ██║╚██████╗██║  ██║    ███████╗██║██║  ██╗╚██████╔╝ ║  │
│  ║   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚══════╝╚═╝╚═╝  ╚═╝ ╚═════╝ ║  │
│  ║                                                   ║  │
│  ║                    Linux Installer v2.0            ║  │
│  ╚═══════════════════════════════════════════════════╝  │
├─────────────────────────────────────────────────────────┤
│  [✓] Disk: /dev/nvme0n1 (500GB)                         │
│  [✓] Strategy: LUKS+LVM                                 │
│  [✓] Boot: UEFI                                         │
│  [✓] Desktop: KDE Plasma                                │
│  [✓] User: l4tm                                         │
├─────────────────────────────────────────────────────────┤
│  [████████████████████████████████████████████████] 75% │
│  Installing GRUB...                                     │
├─────────────────────────────────────────────────────────┤
│  [ESC] Exit  [H] Help  [L] Logs                         │
└─────────────────────────────────────────────────────────┘

```

## Requirements

- Rust 1.70+ (install from [rustup.rs](https://rustup.rs/))
- Linux terminal with Unicode support

## Building

```bash
# Build the TUI
./build_tui.sh

# Or manually with Cargo
cargo build --release
```

## Running

```bash
# Build the TUI
cargo build --release

# Copy to root directory
cp target/release/archinstall-tui .

# Run the TUI (requires sudo for installation)
sudo ./archinstall-tui
```

**Note**: The TUI requires sudo privileges to perform system installation tasks.

## Controls

### Main Navigation
- **↑/↓**: Navigate through configuration options
- **Enter**: Open popup or start text input for selected option
- **q**: Quit the application

### Text Input Mode
- **Type**: Enter text for username, passwords, hostname
- **Backspace**: Delete characters
- **Enter**: Confirm input

### Popup Selections
- **↑/↓**: Navigate through options
- **Enter**: Select option
- **ESC**: Cancel and return to main menu

### Package Selection
- **search <term>**: Search for packages
- **add <package>**: Add package to selection
- **remove <package>**: Remove package from selection
- **list**: Show selected packages
- **done**: Finish package selection

## Architecture

The TUI is built with:

- **`ratatui`**: Modern TUI library for Rust
- **`crossterm`**: Cross-platform terminal manipulation
- **`tokio`**: Async runtime for future features

## Current Status

- [x] **Interactive Configuration**: Full configuration interface with highlighting
- [x] **Text Input Fields**: Username, passwords, hostname with proper input handling
- [x] **Popup Selections**: Disk, desktop environment, timezone, and more
- [x] **Auto-selection Logic**: Display manager based on desktop environment
- [x] **Package Management**: Interactive package selection for Pacman and AUR
- [x] **Plymouth Theme Selection**: arch-glow and arch-mac-style themes
- [x] **Integration with Bash installer**: Full integration with existing scripts

## Future Features

- [ ] **Scrollable Package Search**: Enhanced package search with arrow key navigation
- [ ] **Real-time log display**: Live installation logs during setup
- [ ] **Progress tracking**: Real-time progress from actual installation
- [ ] **Error handling and recovery**: Better error messages and recovery options
- [ ] **Multiple themes**: Additional color schemes and layouts
- [ ] **Help system**: Built-in help and documentation

## Development

The TUI is a complete wrapper around the existing Bash installer. Development phases:

1. **Phase 1**: ✅ Standalone TUI demo
2. **Phase 2**: ✅ Integration with Bash installer
3. **Phase 3**: ✅ Full interactive configuration
4. **Phase 4**: 🔄 Advanced features and customization (in progress)

### Current Implementation

- **Rust Frontend**: Handles all user interaction and display
- **Bash Backend**: Executes actual installation tasks
- **JSON Communication**: Structured data exchange between frontend and backend
- **Modular Design**: Easy to extend with new features

## Why Rust + ratatui?

- **Performance**: Rust is fast and memory-safe
- **Modern**: ratatui is actively maintained and feature-rich
- **Cross-platform**: Works on Linux, macOS, and Windows
- **Professional**: Creates polished, modern TUIs
- **Maintainable**: Clean, readable code structure

This TUI will make the Arch Linux Installer look more professional than the official `archinstall` tool!
