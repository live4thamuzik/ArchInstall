# Arch Linux Installer TUI

A modern, professional Terminal User Interface (TUI) for the Arch Linux Installer, built with Rust and `ratatui`.

## Features

- **Professional Design**: Clean, modern interface with ASCII Arch logo
- **Real-time Progress**: Live progress bars and status updates
- **Configuration Display**: Shows all installation settings
- **Interactive Controls**: Keyboard shortcuts for navigation
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
# Run the demo TUI
./target/release/archinstall-tui
```

## Controls

- **ESC**: Exit the TUI
- **H**: Show help
- **L**: Show logs

## Architecture

The TUI is built with:

- **`ratatui`**: Modern TUI library for Rust
- **`crossterm`**: Cross-platform terminal manipulation
- **`tokio`**: Async runtime for future features

## Future Features

- [ ] Integration with Bash installer
- [ ] Real-time log display
- [ ] Interactive configuration
- [ ] Progress tracking from actual installation
- [ ] Error handling and recovery
- [ ] Multiple themes
- [ ] Help system

## Development

The TUI is designed to be a wrapper around the existing Bash installer. The plan is to:

1. **Phase 1**: Standalone TUI demo (current)
2. **Phase 2**: Integration with Bash installer
3. **Phase 3**: Full interactive configuration
4. **Phase 4**: Advanced features and customization

## Why Rust + ratatui?

- **Performance**: Rust is fast and memory-safe
- **Modern**: ratatui is actively maintained and feature-rich
- **Cross-platform**: Works on Linux, macOS, and Windows
- **Professional**: Creates polished, modern TUIs
- **Maintainable**: Clean, readable code structure

This TUI will make the Arch Linux Installer look more professional than the official `archinstall` tool!
