#!/bin/bash
# test_dialog_error.sh - Diagnostic script for unexpected token error

set -euo pipefail

# --- Dummy functions needed by prompt_yes_no ---
log_info() { echo "INFO: $1"; }
log_warn() { echo "WARN: $1" >&2; }
error_exit() { echo "ERROR: $1" >&2; exit 1; }
trim_string() { echo "$1" | xargs; }

# --- Simplified prompt_yes_no function (from dialogs.sh) ---
prompt_yes_no() {
    local prompt_msg="$1"
    local -n result_var="$2"

    while true; do
        read -rp "$prompt_msg (y/n): " yn_choice
        case "$yn_choice" in
            [Yy]* ) result_var="yes"; return 0;;
            [Nn]* ) result_var="no"; return 0;;
            * ) log_warn "Please answer yes or no.";;
        esac
    done
}

# --- Core Logic to test the problematic line ---
# Source config.sh (assuming it's in the same directory)
source ./config.sh

echo "Attempting to run the problematic line..."
# The problematic line from dialogs.sh's gather_installation_details
use_default_mirror_country="" # REMOVED 'local' keyword here
prompt_yes_no "Use default mirror country (${REFLECTOR_COUNTRY_CODE})? " use_default_mirror_country

echo "Script completed successfully."
