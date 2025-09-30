#!/bin/bash
# generate_fstab.sh - Generate fstab file
# Usage: ./generate_fstab.sh --root /mnt

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/../utils.sh"

# Default values
ROOT_PATH="/mnt"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            ROOT_PATH="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 --root <path>"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate root path
if [[ ! -d "$ROOT_PATH" ]]; then
    error_exit "Root path does not exist: $ROOT_PATH"
fi

log_info "Generating fstab for $ROOT_PATH..."

# Backup existing fstab if it exists
if [[ -f "$ROOT_PATH/etc/fstab" ]]; then
    log_info "Backing up existing fstab..."
    cp "$ROOT_PATH/etc/fstab" "$ROOT_PATH/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Generate new fstab
log_info "Running genfstab..."
genfstab -U "$ROOT_PATH" >> "$ROOT_PATH/etc/fstab"

log_success "fstab generated successfully!"
log_info "Location: $ROOT_PATH/etc/fstab"

# Show the generated fstab
echo ""
log_info "Generated fstab contents:"
echo "----------------------------------------"
cat "$ROOT_PATH/etc/fstab"
echo "----------------------------------------"
