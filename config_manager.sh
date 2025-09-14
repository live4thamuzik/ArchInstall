#!/bin/bash

# Simple config manager for package selection
CONFIG_FILE="/tmp/archinstall_config.json"

# Initialize config file if it doesn't exist
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "selected_pacman_packages": [],
  "selected_aur_packages": []
}
EOF
    fi
}

# Add a package to the config
add_package() {
    local package_type="$1"  # "pacman" or "aur"
    local package_name="$2"
    
    init_config
    
    # Use jq to add the package to the appropriate array
    if command -v jq >/dev/null 2>&1; then
        if [ "$package_type" = "pacman" ]; then
            rm -f "$CONFIG_FILE.tmp"
            jq --arg pkg "$package_name" '.selected_pacman_packages += [$pkg]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        else
            rm -f "$CONFIG_FILE.tmp"
            jq --arg pkg "$package_name" '.selected_aur_packages += [$pkg]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        fi
    else
        echo "Warning: jq not available, using fallback method"
        echo "Added $package_name to $package_type packages"
    fi
}

# Remove a package from the config
remove_package() {
    local package_type="$1"  # "pacman" or "aur"
    local package_name="$2"
    
    init_config
    
    if command -v jq >/dev/null 2>&1; then
        if [ "$package_type" = "pacman" ]; then
            rm -f "$CONFIG_FILE.tmp"
            jq --arg pkg "$package_name" 'del(.selected_pacman_packages[] | select(. == $pkg))' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        else
            rm -f "$CONFIG_FILE.tmp"
            jq --arg pkg "$package_name" 'del(.selected_aur_packages[] | select(. == $pkg))' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        fi
    else
        echo "Warning: jq not available, using fallback method"
        echo "Removed $package_name from $package_type packages"
    fi
}

# Get the list of selected packages
get_packages() {
    local package_type="$1"  # "pacman" or "aur"
    
    init_config
    
    if command -v jq >/dev/null 2>&1; then
        if [ "$package_type" = "pacman" ]; then
            jq -r '.selected_pacman_packages | join(", ")' "$CONFIG_FILE"
        else
            jq -r '.selected_aur_packages | join(", ")' "$CONFIG_FILE"
        fi
    else
        echo "No packages selected"
    fi
}

# Get the raw config file path
get_config_file() {
    init_config
    echo "$CONFIG_FILE"
}

# Main function to handle commands
case "$1" in
    "add")
        add_package "$2" "$3"
        ;;
    "remove")
        remove_package "$2" "$3"
        ;;
    "get")
        get_packages "$2"
        ;;
    "init")
        init_config
        ;;
    "file")
        get_config_file
        ;;
    *)
        echo "Usage: $0 {add|remove|get|init|file} [package_type] [package_name]"
        echo "  add pacman firefox    - Add firefox to pacman packages"
        echo "  remove aur yay        - Remove yay from aur packages"
        echo "  get pacman            - Get list of selected pacman packages"
        echo "  get aur               - Get list of selected aur packages"
        echo "  init                  - Initialize config file"
        echo "  file                  - Get config file path"
        exit 1
        ;;
esac