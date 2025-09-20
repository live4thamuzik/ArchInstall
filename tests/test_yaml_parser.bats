#!/bin/bash
# test_yaml_parser.bats - Tests for yaml_parser.sh functions

# Source the test framework
source "$(dirname "$0")/test_framework.sh"

# Test setup function
setup() {
    # Source the yaml_parser.sh file
    source "$(dirname "$0")/../yaml_parser.sh"
    
    # Create a test YAML file
    cat > "$TEST_TEMP_DIR/test_config.yaml" << 'EOF'
# Test YAML configuration
logging:
  log_file: "/var/log/test.log"
  log_backup: "/tmp/test.log"
  log_final: "/mnt/var/log/test.log"

system:
  main_username: "testuser"
  root_password: "rootpass"
  main_user_password: "userpass"
  system_hostname: "testhost"
  timezone: "UTC"
  locale: "en_US.UTF-8"
  keymap: "us"
  reflector_country_code: "US"
  want_wifi_connection: "no"

storage:
  install_disk: "/dev/sda"
  override_boot_mode: "no"
  boot_mode: "uefi"
  partition_scheme: "auto_simple"
  want_swap: "yes"
  want_home_partition: "yes"
  want_encryption: "no"
  want_lvm: "no"
  want_raid: "no"
  luks_passphrase: ""
  raid_level: ""
  raid_devices: []
  root_filesystem_type: "ext4"
  home_filesystem_type: "ext4"

kernel:
  kernel_type: "linux"
  cpu_microcode_type: "intel"

bootloader:
  bootloader_type: "grub"
  want_secure_boot: "no"
  enable_os_prober: "yes"
  want_grub_theme: "no"
  grub_theme_choice: ""
  grub_timeout_default: 5

plymouth:
  want_plymouth: "no"
  want_plymouth_theme: "no"
  plymouth_theme_choice: ""

btrfs:
  want_btrfs: "no"
  want_btrfs_snapshots: "no"
  btrfs_snapshot_frequency: "daily"
  btrfs_keep_snapshots: 7
  want_btrfs_assistant: "no"

services:
  time_sync_choice: "systemd-timesyncd"
  want_numlock_on_boot: "no"

desktop_environment:
  desktop_environment: "none"
  display_manager: "none"
  gpu_driver_type: "none"

packages:
  want_multilib: "no"
  want_flatpak: "no"
  install_custom_packages: "no"
  custom_packages: ""
  want_aur_helper: "no"
  aur_helper_choice: ""
  install_custom_aur_packages: "no"
  custom_aur_packages: ""

dotfiles:
  want_dotfiles_deployment: "no"
  dotfiles_repo_url: ""
  dotfiles_branch: "main"

# Package Lists (Arrays)
package_lists:
  desktop_environments:
    gnome: ["gnome", "gnome-extra"]
    kde: ["plasma", "kde-applications"]
    xfce: ["xfce4", "xfce4-goodies"]
    hyprland: ["hyprland", "kitty", "waybar", "wofi"]
  display_managers:
    gdm: ["gdm"]
    sddm: ["sddm"]
    lightdm: ["lightdm", "lightdm-gtk-greeter"]
  gpu_drivers:
    amd: ["xf86-video-amdgpu", "vulkan-radeon", "mesa"]
    nvidia: ["nvidia", "nvidia-utils", "nvidia-settings"]
    intel: ["xf86-video-intel", "vulkan-intel", "mesa"]
  bootloader_grub: ["grub", "efibootmgr", "os-prober"]
  bootloader_systemd_boot: ["systemd-boot"]
  filesystem_packages: ["dosfstools", "e2fsprogs", "btrfs-progs"]
  base_extras: ["vim", "nano", "git", "wget", "curl", "rsync"]
  time_sync_packages:
    ntpd: ["ntp"]
    chrony: ["chrony"]
    systemd_timesyncd: []
  aur_helpers:
    yay: ["yay"]
    paru: ["paru"]
  flatpak: ["flatpak"]
  grub_themes:
    poly_dark: ["grub-theme-poly-dark"]
    cyberexs: ["grub-theme-cyberexs"]
EOF
}

# Test YAML parsing function
test_parse_yaml_config() {
    # Test parsing valid YAML file
    parse_yaml_config "$TEST_TEMP_DIR/test_config.yaml"
    assert_true $? "Parsing valid YAML should succeed"
    
    # Test parsing non-existent file
    parse_yaml_config "$TEST_TEMP_DIR/nonexistent.yaml"
    assert_false $? "Parsing non-existent file should fail"
    
    # Test parsing invalid YAML file
    echo "invalid: yaml: content: [" > "$TEST_TEMP_DIR/invalid.yaml"
    parse_yaml_config "$TEST_TEMP_DIR/invalid.yaml"
    # Should still succeed as our parser is simple
    assert_true $? "Parsing invalid YAML should still succeed (simple parser)"
}

# Test environment variable export
test_export_yaml_config() {
    # Parse the YAML first
    parse_yaml_config "$TEST_TEMP_DIR/test_config.yaml"
    
    # Test export function
    export_yaml_config
    assert_true $? "Export should succeed"
    
    # Test that key variables are exported
    assert_equal "$LOG_FILE" "/var/log/test.log"
    assert_equal "$MAIN_USERNAME" "testuser"
    assert_equal "$ROOT_PASSWORD" "rootpass"
    assert_equal "$MAIN_USER_PASSWORD" "userpass"
    assert_equal "$SYSTEM_HOSTNAME" "testhost"
    assert_equal "$TIMEZONE" "UTC"
    assert_equal "$LOCALE" "en_US.UTF-8"
    assert_equal "$KEYMAP" "us"
    assert_equal "$REFLECTOR_COUNTRY_CODE" "US"
    assert_equal "$WANT_WIFI_CONNECTION" "no"
    
    # Test storage variables
    assert_equal "$INSTALL_DISK" "/dev/sda"
    assert_equal "$OVERRIDE_BOOT_MODE" "no"
    assert_equal "$BOOT_MODE" "uefi"
    assert_equal "$PARTITION_SCHEME" "auto_simple"
    assert_equal "$WANT_SWAP" "yes"
    assert_equal "$WANT_HOME_PARTITION" "yes"
    assert_equal "$WANT_ENCRYPTION" "no"
    assert_equal "$WANT_LVM" "no"
    assert_equal "$WANT_RAID" "no"
    assert_equal "$ROOT_FILESYSTEM_TYPE" "ext4"
    assert_equal "$HOME_FILESYSTEM_TYPE" "ext4"
    
    # Test kernel variables
    assert_equal "$KERNEL_TYPE" "linux"
    assert_equal "$CPU_MICROCODE_TYPE" "intel"
    
    # Test bootloader variables
    assert_equal "$BOOTLOADER_TYPE" "grub"
    assert_equal "$WANT_SECURE_BOOT" "no"
    assert_equal "$ENABLE_OS_PROBER" "yes"
    assert_equal "$WANT_GRUB_THEME" "no"
    assert_equal "$GRUB_TIMEOUT_DEFAULT" "5"
    
    # Test other variables
    assert_equal "$WANT_PLYMOUTH" "no"
    assert_equal "$WANT_BTRFS" "no"
    assert_equal "$TIME_SYNC_CHOICE" "systemd-timesyncd"
    assert_equal "$DESKTOP_ENVIRONMENT" "none"
    assert_equal "$WANT_MULTILIB" "no"
    assert_equal "$WANT_FLATPAK" "no"
    assert_equal "$WANT_AUR_HELPER" "no"
    assert_equal "$WANT_DOTFILES_DEPLOYMENT" "no"
}

# Test YAML validation function
test_validate_yaml_config() {
    # Parse and export YAML first
    parse_yaml_config "$TEST_TEMP_DIR/test_config.yaml"
    export_yaml_config
    
    # Test validation with valid config
    validate_yaml_config
    assert_true $? "Valid config should pass validation"
    
    # Test validation with missing required variables
    unset SYSTEM_MAIN_USERNAME
    validate_yaml_config
    assert_false $? "Config missing required variables should fail validation"
}

# Test complete YAML loading process
test_load_yaml_config() {
    # Test loading complete YAML config
    load_yaml_config "$TEST_TEMP_DIR/test_config.yaml"
    assert_true $? "Loading complete YAML config should succeed"
    
    # Test loading non-existent file
    load_yaml_config "$TEST_TEMP_DIR/nonexistent.yaml"
    assert_false $? "Loading non-existent file should fail"
}

# Test array handling in YAML
test_yaml_array_handling() {
    # Parse the YAML
    parse_yaml_config "$TEST_TEMP_DIR/test_config.yaml"
    
    # Test that array variables are exported as space-separated strings
    # (Our parser converts arrays to space-separated strings)
    
    # Test desktop environment packages
    assert_contains "${PACKAGE_LISTS_DESKTOP_ENVIRONMENTS_GNOME:-}" "gnome"
    assert_contains "${PACKAGE_LISTS_DESKTOP_ENVIRONMENTS_GNOME:-}" "gnome-extra"
    
    # Test display manager packages
    assert_contains "${PACKAGE_LISTS_DISPLAY_MANAGERS_GDM:-}" "gdm"
    assert_contains "${PACKAGE_LISTS_DISPLAY_MANAGERS_SDDM:-}" "sddm"
    
    # Test GPU driver packages
    assert_contains "${PACKAGE_LISTS_GPU_DRIVERS_AMD:-}" "xf86-video-amdgpu"
    assert_contains "${PACKAGE_LISTS_GPU_DRIVERS_NVIDIA:-}" "nvidia"
    assert_contains "${PACKAGE_LISTS_GPU_DRIVERS_INTEL:-}" "xf86-video-intel"
}

# Test YAML with empty values
test_yaml_empty_values() {
    # Create YAML with empty values
    cat > "$TEST_TEMP_DIR/empty_config.yaml" << 'EOF'
system:
  main_username: ""
  root_password: ""
  system_hostname: ""
storage:
  install_disk: ""
  partition_scheme: ""
EOF
    
    # Parse and export
    parse_yaml_config "$TEST_TEMP_DIR/empty_config.yaml"
    export_yaml_config
    
    # Test that empty values are handled correctly
    assert_equal "$MAIN_USERNAME" ""
    assert_equal "$ROOT_PASSWORD" ""
    assert_equal "$SYSTEM_HOSTNAME" ""
    assert_equal "$INSTALL_DISK" ""
    assert_equal "$PARTITION_SCHEME" ""
}

# Test YAML with missing sections
test_yaml_missing_sections() {
    # Create YAML with only some sections
    cat > "$TEST_TEMP_DIR/partial_config.yaml" << 'EOF'
system:
  main_username: "testuser"
  system_hostname: "testhost"
EOF
    
    # Parse and export
    parse_yaml_config "$TEST_TEMP_DIR/partial_config.yaml"
    export_yaml_config
    
    # Test that present values are exported
    assert_equal "$MAIN_USERNAME" "testuser"
    assert_equal "$SYSTEM_HOSTNAME" "testhost"
    
    # Test that missing values get defaults
    assert_equal "$LOG_FILE" "/var/log/archinstall.log"  # Default value
    assert_equal "$TIMEZONE" "UTC"  # Default value
    assert_equal "$LOCALE" "en_US.UTF-8"  # Default value
}

# Test YAML with comments and empty lines
test_yaml_comments_and_empty_lines() {
    # Create YAML with comments and empty lines
    cat > "$TEST_TEMP_DIR/commented_config.yaml" << 'EOF'
# This is a comment
system:
  # Another comment
  main_username: "testuser"
  
  # Empty line above
  system_hostname: "testhost"

# More comments
storage:
  install_disk: "/dev/sda"
EOF
    
    # Parse and export
    parse_yaml_config "$TEST_TEMP_DIR/commented_config.yaml"
    export_yaml_config
    
    # Test that values are still parsed correctly
    assert_equal "$MAIN_USERNAME" "testuser"
    assert_equal "$SYSTEM_HOSTNAME" "testhost"
    assert_equal "$INSTALL_DISK" "/dev/sda"
}

# Test YAML parser error handling
test_yaml_parser_error_handling() {
    # Test with directory instead of file
    parse_yaml_config "$TEST_TEMP_DIR"
    assert_false $? "Parsing directory should fail"
    
    # Test with non-readable file
    echo "test" > "$TEST_TEMP_DIR/unreadable.yaml"
    chmod 000 "$TEST_TEMP_DIR/unreadable.yaml"
    parse_yaml_config "$TEST_TEMP_DIR/unreadable.yaml"
    assert_false $? "Parsing unreadable file should fail"
    
    # Restore permissions
    chmod 644 "$TEST_TEMP_DIR/unreadable.yaml"
}

# Run all tests
run_test "Parse YAML Config" test_parse_yaml_config
run_test "Export YAML Config" test_export_yaml_config
run_test "Validate YAML Config" test_validate_yaml_config
run_test "Load YAML Config" test_load_yaml_config
run_test "YAML Array Handling" test_yaml_array_handling
run_test "YAML Empty Values" test_yaml_empty_values
run_test "YAML Missing Sections" test_yaml_missing_sections
run_test "YAML Comments and Empty Lines" test_yaml_comments_and_empty_lines
run_test "YAML Parser Error Handling" test_yaml_parser_error_handling
