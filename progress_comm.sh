#!/bin/bash
# Progress communication system for TUI integration

PROGRESS_FILE="/tmp/archinstall_progress"
STATUS_FILE="/tmp/archinstall_status"
PHASE_FILE="/tmp/archinstall_phase"
CONFIG_FILE="/tmp/archinstall_config"

# Initialize progress files
init_progress() {
    echo "0" > "$PROGRESS_FILE"
    echo "Initializing..." > "$STATUS_FILE"
    echo "Starting..." > "$PHASE_FILE"
}

# Update progress (0-100)
update_progress() {
    local progress="$1"
    echo "$progress" > "$PROGRESS_FILE"
}

# Update status message
update_status() {
    local status="$1"
    # Truncate long messages to fit in TUI status box (shorter for better display)
    if [ ${#status} -gt 40 ]; then
        status="${status:0:37}..."
    fi
    echo "$status" > "$STATUS_FILE"
}

# Update phase
update_phase() {
    local phase="$1"
    echo "$phase" > "$PHASE_FILE"
}

# Update configuration
update_config() {
    local disk="$1"
    local strategy="$2"
    local boot_mode="$3"
    local desktop="$4"
    local username="$5"
    
    # Create JSON config for TUI
    cat > "$CONFIG_FILE" << EOF
{
    "disk": "$disk",
    "strategy": "$strategy",
    "boot_mode": "$boot_mode",
    "desktop": "$desktop",
    "username": "$username"
}
EOF
}

# Clean up progress files
cleanup_progress() {
    rm -f "$PROGRESS_FILE" "$STATUS_FILE" "$PHASE_FILE" "$CONFIG_FILE"
}

# Export functions for use in other scripts
export -f init_progress update_progress update_status update_phase update_config cleanup_progress
