#!/bin/bash
# yaml_parser.sh - Simple YAML parser for Bash (placeholder for testing)

# Simple logging function for YAML parser
log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# Parse YAML file and export variables to environment
parse_yaml_config() {
    local yaml_file="$1"
    log_info "Parsing YAML configuration from: $yaml_file"

    if [ ! -f "$yaml_file" ]; then
        log_error "YAML configuration file not found: $yaml_file"
        return 1
    fi

    # Simple parsing for testing
    local current_section=""
    
    while IFS= read -r line; do
        # Remove leading/trailing whitespace
        local trimmed_line=$(echo "$line" | xargs)
        
        # Skip empty lines and comments
        if [[ -z "$trimmed_line" || "$trimmed_line" =~ ^# ]]; then
            continue
        fi

        # Detect sections (e.g., "system:")
        if [[ "$trimmed_line" =~ ^([a-zA-Z0-9_]+):$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi

        # Detect subsections (e.g., "  main_username:")
        if [[ "$trimmed_line" =~ ^[[:space:]]{2}([a-zA-Z0-9_]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value=$(echo "${BASH_REMATCH[2]}" | xargs)
            
            # Create variable name from section and key
            local var_name=$(echo "${current_section}_${key}" | tr '[:lower:]' '[:upper:]')
            export "$var_name"="$value"
        fi
    done < "$yaml_file"
    
    log_info "YAML configuration parsed successfully"
    return 0
}

# Function to export all configuration as environment variables
export_yaml_config() {
    log_info "Exporting YAML configuration to environment variables..."
    
    # Export variables that were parsed
    export MAIN_USERNAME="${SYSTEM_MAIN_USERNAME:-}"
    export SYSTEM_HOSTNAME="${SYSTEM_SYSTEM_HOSTNAME:-}"
    export INSTALL_DISK="${STORAGE_INSTALL_DISK:-}"
    
    return 0
}

# Function to validate essential configuration values
validate_yaml_config() {
    log_info "Validating YAML configuration..."
    
    if [ -z "${MAIN_USERNAME:-}" ]; then
        log_error "Validation failed: MAIN_USERNAME is not set in config.yaml"
        return 1
    fi
    if [ -z "${INSTALL_DISK:-}" ]; then
        log_error "Validation failed: INSTALL_DISK is not set in config.yaml"
        return 1
    fi
    if [ -z "${SYSTEM_HOSTNAME:-}" ]; then
        log_error "Validation failed: SYSTEM_HOSTNAME is not set in config.yaml"
        return 1
    fi

    log_info "Configuration validation passed"
    return 0
}

# Function to load and validate YAML configuration
load_yaml_config() {
    local yaml_file="$1"
    parse_yaml_config "$yaml_file" || return 1
    export_yaml_config || return 1
    validate_yaml_config || return 1
    return 0
}