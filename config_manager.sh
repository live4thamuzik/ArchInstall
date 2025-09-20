#!/bin/bash
# config_manager.sh - Manages package configuration for the installer

CONFIG_FILE="install_config.conf"

# Function to get current packages
get_packages() {
    local package_type="$1"
    local key="${package_type}_packages"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        grep "^${key}=" "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"'
    else
        echo ""
    fi
}

# Function to add a package
add_package() {
    local package_type="$1"
    local package_name="$2"
    local key="${package_type}_packages"
    
    # Get current packages
    local current_packages=$(get_packages "$package_type")
    
    # Check if package is already in the list (exact match only)
    for existing_package in $current_packages; do
        if [[ "$existing_package" == "$package_name" ]]; then
            echo "Package $package_name is already in the list"
            return 0
        fi
    done
    
    # Add the package
    if [[ -z "$current_packages" ]]; then
        new_packages="$package_name"
    else
        new_packages="$current_packages $package_name"
    fi
    
    # Update the config file
    if [[ -f "$CONFIG_FILE" ]]; then
        # Update existing line
        if grep -q "^${key}=" "$CONFIG_FILE"; then
            sed -i "s/^${key}=.*/${key}=\"${new_packages}\"/" "$CONFIG_FILE"
        else
            echo "${key}=\"${new_packages}\"" >> "$CONFIG_FILE"
        fi
    else
        # Create new config file
        echo "${key}=\"${new_packages}\"" > "$CONFIG_FILE"
    fi
    
    echo "Added package: $package_name"
}

# Function to remove a package
remove_package() {
    local package_type="$1"
    local package_name="$2"
    local key="${package_type}_packages"
    
    # Get current packages
    local current_packages=$(get_packages "$package_type")
    
    # Remove the package more precisely - only remove exact package names
    # Split packages into array, filter out the exact package, then rejoin
    local new_packages=""
    local found=false
    
    for package in $current_packages; do
        if [[ "$package" == "$package_name" ]]; then
            found=true
            # Skip this package (remove it)
            continue
        else
            # Keep this package
            if [[ -z "$new_packages" ]]; then
                new_packages="$package"
            else
                new_packages="$new_packages $package"
            fi
        fi
    done
    
    # Update the config file
    if [[ -f "$CONFIG_FILE" ]]; then
        if grep -q "^${key}=" "$CONFIG_FILE"; then
            sed -i "s/^${key}=.*/${key}=\"${new_packages}\"/" "$CONFIG_FILE"
        fi
    fi
    
    if [[ "$found" == "true" ]]; then
        echo "Removed package: $package_name"
    else
        echo "Package $package_name not found in list"
    fi
}

# Function to set packages (replace entire list)
set_packages() {
    local package_type="$1"
    local packages="$2"
    local key="${package_type}_packages"
    
    # Update the config file
    if [[ -f "$CONFIG_FILE" ]]; then
        if grep -q "^${key}=" "$CONFIG_FILE"; then
            sed -i "s/^${key}=.*/${key}=\"${packages}\"/" "$CONFIG_FILE"
        else
            echo "${key}=\"${packages}\"" >> "$CONFIG_FILE"
        fi
    else
        echo "${key}=\"${packages}\"" > "$CONFIG_FILE"
    fi
    
    echo "Set packages: $packages"
}

# Main command handling
case "$1" in
    "get")
        get_packages "$2"
        ;;
    "add")
        add_package "$2" "$3"
        ;;
    "remove")
        remove_package "$2" "$3"
        ;;
    "set")
        set_packages "$2" "$3"
        ;;
    *)
        echo "Usage: $0 {get|add|remove|set} <package_type> [package_name|packages]"
        echo "  get <package_type> - Get current packages"
        echo "  add <package_type> <package_name> - Add a package"
        echo "  remove <package_type> <package_name> - Remove a package"
        echo "  set <package_type> <packages> - Set entire package list"
        exit 1
        ;;
esac