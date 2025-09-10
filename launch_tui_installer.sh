#!/bin/bash
# launch_tui_installer.sh - Launcher for TUI + Bash Installer

set -euo pipefail

# Parse command line arguments
SKIP_TUI=false
if [ "${1:-}" = "--no-tui" ] || [ "${1:-}" = "--bash-only" ]; then
    SKIP_TUI=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we're in the right directory
if [ ! -f "$SCRIPT_DIR/install_arch.sh" ]; then
    echo -e "${RED}Error: This script must be run from the archinstall directory${NC}"
    echo "Expected file: install_arch.sh"
    exit 1
fi

# If skipping TUI, just run the Bash installer
if [ "$SKIP_TUI" = true ]; then
    echo -e "${BLUE}Running Arch Linux installer in Bash-only mode...${NC}"
    exec "$SCRIPT_DIR/install_arch.sh"
fi

# Check for Cargo.toml only if we're using TUI
if [ ! -f "$SCRIPT_DIR/Cargo.toml" ]; then
    echo -e "${RED}Error: Cargo.toml not found. TUI mode requires Rust project files.${NC}"
    echo "Use --no-tui or --bash-only to run without TUI"
    exit 1
fi

# Check for pre-compiled TUI binary first
TUI_BINARY="$SCRIPT_DIR/archinstall-tui"
if [ -f "$TUI_BINARY" ]; then
    # Ensure binary is executable
    chmod +x "$TUI_BINARY"
elif [ ! -f "$TUI_BINARY" ]; then
    # Fallback: check if Rust is available and build
    if command -v cargo &> /dev/null; then
        echo -e "${YELLOW}Pre-compiled TUI not found. Building from source...${NC}"
        cd "$SCRIPT_DIR"
        cargo build --release
        if [ $? -eq 0 ]; then
            cp target/release/archinstall-tui .
            echo -e "${GREEN}TUI built successfully${NC}"
        else
            echo -e "${RED}Error: Failed to build TUI${NC}"
            echo -e "${YELLOW}Falling back to Bash-only mode...${NC}"
            exec "$SCRIPT_DIR/install_arch.sh"
        fi
    else
        echo -e "${RED}Error: No pre-compiled TUI binary found and Rust not available${NC}"
        echo -e "${YELLOW}Falling back to Bash-only mode...${NC}"
        exec "$SCRIPT_DIR/install_arch.sh"
    fi
fi

# Function to cleanup on exit
cleanup() {
    # Kill any remaining processes
    jobs -p | xargs -r kill 2>/dev/null || true
    # Clean up progress files
    rm -f /tmp/archinstall_progress /tmp/archinstall_status /tmp/archinstall_phase
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Start TUI in background (suppress launcher output)
"$TUI_BINARY" &
TUI_PID=$!

# Give TUI a moment to start
sleep 2

# Start Bash installer in a separate terminal (suppress launcher output)
# Try to detect available terminal emulator
if command -v xterm &> /dev/null; then
    TERMINAL_CMD="xterm -e"
elif command -v gnome-terminal &> /dev/null; then
    TERMINAL_CMD="gnome-terminal --"
elif command -v konsole &> /dev/null; then
    TERMINAL_CMD="konsole -e"
elif command -v alacritty &> /dev/null; then
    TERMINAL_CMD="alacritty -e"
else
    # Suppress warning messages - TUI will show status
    TERMINAL_CMD=""
fi

if [ -n "$TERMINAL_CMD" ]; then
    # Run installer in separate terminal
    $TERMINAL_CMD "$SCRIPT_DIR/install_arch.sh" &
    INSTALLER_PID=$!
else
    # Fallback: run in background with output to log
    "$SCRIPT_DIR/install_arch.sh" > /tmp/installer_output.log 2>&1 &
    INSTALLER_PID=$!
fi

# Wait for either process to finish
wait $INSTALLER_PID
INSTALLER_EXIT_CODE=$?

# Kill TUI
kill $TUI_PID 2>/dev/null || true
wait $TUI_PID 2>/dev/null || true

# Check installer exit code and update TUI status
if [ $INSTALLER_EXIT_CODE -eq 0 ]; then
    echo "Installation completed successfully!" > /tmp/archinstall_status
    echo "100" > /tmp/archinstall_progress
else
    echo "Installation failed with exit code: $INSTALLER_EXIT_CODE" > /tmp/archinstall_status
fi

exit $INSTALLER_EXIT_CODE
