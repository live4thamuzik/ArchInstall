#!/bin/bash

# Arch Linux TUI Installer Launcher
# This script launches the TUI installer that executes the bash installer directly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# TUI binary path
TUI_BINARY="$SCRIPT_DIR/archinstall-tui"

echo -e "${BLUE}Arch Linux TUI Installer${NC}"
echo -e "${BLUE}========================${NC}"

# Check if --no-tui flag is provided
if [[ "$1" == "--no-tui" || "$1" == "--bash-only" ]]; then
    echo -e "${YELLOW}Running in Bash-only mode...${NC}"
    exec "$SCRIPT_DIR/install_arch.sh"
fi

# Check if TUI binary exists
if [ -f "$TUI_BINARY" ]; then
    echo -e "${GREEN}Found pre-compiled TUI binary${NC}"
    chmod +x "$TUI_BINARY"
else
    echo -e "${YELLOW}Pre-compiled TUI binary not found${NC}"
    
    # Check if Rust is available
    if command -v cargo >/dev/null 2>&1; then
        echo -e "${YELLOW}Building TUI from source...${NC}"
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

# Launch the TUI
echo -e "${GREEN}Starting TUI installer...${NC}"
echo -e "${YELLOW}The installer will run directly in this terminal.${NC}"
echo -e "${YELLOW}Press 's' to start installation, 'q' to quit.${NC}"
echo ""

exec "$TUI_BINARY"