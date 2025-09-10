#!/bin/bash
# Progress communication system for TUI integration

PROGRESS_FILE="/tmp/archinstall_progress"
STATUS_FILE="/tmp/archinstall_status"
PHASE_FILE="/tmp/archinstall_phase"

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

# Clean up progress files
cleanup_progress() {
    rm -f "$PROGRESS_FILE" "$STATUS_FILE" "$PHASE_FILE"
}

# Export functions for use in other scripts
export -f init_progress update_progress update_status update_phase cleanup_progress
