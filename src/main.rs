use ratatui::{
    backend::CrosstermBackend,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Style, Modifier},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, List, ListItem, ListState, Paragraph, Wrap, Clear},
    Frame, Terminal,
};
use std::io::{stdout, BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};
use std::thread;
use std::time::Duration;
use crossterm::event::{Event, KeyCode, KeyEvent, KeyModifiers, MouseEvent};
use serde::{Deserialize, Serialize};

// Global interrupt flag
static INTERRUPTED: AtomicBool = AtomicBool::new(false);

// Package structure for structured package data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Package {
    pub repo: String,
    pub name: String,
    pub version: String,
    pub installed: bool,
    pub description: String,
}

// Structured communication protocol between TUI and Bash scripts
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum InstallationPhase {
    Prerequisites,
    UserInput,
    DiskPartitioning,
    PackageInstallation,
    SystemConfiguration,
    DesktopEnvironment,
    DisplayManager,
    Bootloader,
    Finalization,
    Complete,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MessageType {
    Progress,
    Status,
    Error,
    Warning,
    Info,
    UserInput,
    SystemInfo,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProgressUpdate {
    pub message_type: MessageType,
    pub phase: InstallationPhase,
    pub progress: u8, // 0-100
    pub message: String,
    pub timestamp: Option<String>,
}

impl ProgressUpdate {
    pub fn new(message_type: MessageType, phase: InstallationPhase, progress: u8, message: String) -> Self {
        Self {
            message_type,
            phase,
            progress,
            message,
            timestamp: None,
        }
    }
    
    pub fn with_timestamp(mut self, timestamp: String) -> Self {
        self.timestamp = Some(timestamp);
        self
    }
    
    // Helper functions for common progress updates
    pub fn progress(phase: InstallationPhase, progress: u8, message: String) -> Self {
        Self::new(MessageType::Progress, phase, progress, message)
    }
    
    pub fn status(phase: InstallationPhase, message: String) -> Self {
        Self::new(MessageType::Status, phase, 0, message)
    }
    
    pub fn error(phase: InstallationPhase, message: String) -> Self {
        Self::new(MessageType::Error, phase, 0, message)
    }
    
    pub fn warning(phase: InstallationPhase, message: String) -> Self {
        Self::new(MessageType::Warning, phase, 0, message)
    }
    
    pub fn info(phase: InstallationPhase, message: String) -> Self {
        Self::new(MessageType::Info, phase, 0, message)
    }
    
    // Convert to JSON string for output to stderr
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum PopupType {
    None,
    DiskSelection,
    PartitioningStrategy,
    DesktopEnvironment,
    DisplayManager,
    Encryption,
    Multilib,
    AURHelper,
    TimezoneRegion,
    Timezone,
    Locale,
    Keymap,
    Bootloader,
    GRUBTheme,
    GPUDrivers,
    Plymouth,
    PlymouthTheme,
    RAIDLevel,
    PackageSelection, // Simple bash session for package selection
    TextInput(String), // Field name
    // New popup types for missing configuration options
    WiFi,
    WiFiSession, // Interactive iwctl session
    BootOverride,
    SecureBoot,
    RootFilesystem,
    HomePartition,
    HomeFilesystem,
    Swap,
    BtrfsSnapshots,
    BtrfsFrequency,
    BtrfsKeep,
    BtrfsAssistant,
    TimeSync,
    Mirror,
    Kernel,
    Flatpak,
    OSProber,
    Numlock,
    GitRepository,
}

#[derive(Debug, Clone)]
pub struct PopupState {
    pub popup_type: PopupType,
    pub is_active: bool,
    pub selected_index: usize,
    pub options: Vec<String>,
    pub title: String,
    // Simple bash session state
    pub bash_output: Vec<String>,
    pub bash_prompt: String,
}

// Simplified theme struct
#[derive(Debug, Clone)]
pub struct Theme;

// Simplified shortcut struct  
#[derive(Debug, Clone)]
pub struct Shortcut {
    pub keys: Vec<String>,
    pub description: String,
}

// FloatContent trait for floating windows (inspired by Linutil)
pub trait FloatContent {
    fn draw(&mut self, frame: &mut Frame, area: Rect, theme: &Theme);
    fn handle_key_event(&mut self, key: &KeyEvent) -> bool;
    fn handle_mouse_event(&mut self, _event: &MouseEvent) -> bool { false }
    fn is_finished(&self) -> bool;
    fn get_shortcut_list(&self) -> (&str, Box<[Shortcut]>);
}

// Float container for floating windows
#[derive(Debug)]
pub struct Float<Content: FloatContent + ?Sized> {
    pub content: Box<Content>,
    width_percent: u16,
    height_percent: u16,
}

impl<Content: FloatContent + ?Sized> Float<Content> {
    pub fn new(content: Box<Content>, width_percent: u16, height_percent: u16) -> Self {
        Self {
            content,
            width_percent,
            height_percent,
        }
    }

    fn floating_window(&self, size: Rect) -> Rect {
        let hor_float = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Percentage((100 - self.width_percent) / 2),
                Constraint::Percentage(self.width_percent),
                Constraint::Percentage((100 - self.width_percent) / 2),
            ])
            .split(size)[1];

        Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Percentage((100 - self.height_percent) / 2),
                Constraint::Percentage(self.height_percent),
                Constraint::Percentage((100 - self.height_percent) / 2),
            ])
            .split(hor_float)[1]
    }

    pub fn draw(&mut self, frame: &mut Frame, parent_area: Rect, theme: &Theme) {
        let popup_area = self.floating_window(parent_area);
        
        // Clear the background with a semi-transparent overlay
        let overlay = Block::new()
            .style(Style::default().bg(Color::Black).fg(Color::White));
        frame.render_widget(overlay, popup_area);
        
        // Draw the content
        self.content.draw(frame, popup_area, theme);
    }

    pub fn handle_key_event(&mut self, key: &KeyEvent) -> bool {
        self.content.handle_key_event(key)
    }

    pub fn is_finished(&self) -> bool {
        self.content.is_finished()
    }
}

// PackageSelection using structured data and scrolling
pub struct PackageSelection {
    current_input: String,
    output_lines: Vec<String>,
    scroll_offset: usize,
    package_list: String,
    is_pacman: bool,
    // New fields for structured package data and scrolling
    search_results: Vec<Package>,
    list_state: ListState,
    show_search_results: bool,
}

impl PackageSelection {
    pub fn new(is_pacman: bool) -> Self {
        let mut output_lines = vec![
            "Available commands:".to_string(),
            "".to_string(),
            "search <term> - Search for packages".to_string(),
            "add <package> - Add package to installation list".to_string(),
            "remove <package> - Remove package from installation list".to_string(),
            "list - Show current package list".to_string(),
            "done - Finish package selection".to_string(),
            "".to_string(),
            "Examples:".to_string(),
        ];
        
        if is_pacman {
            output_lines.push("search firefox".to_string());
            output_lines.push("add firefox".to_string());
            output_lines.push("".to_string());
            output_lines.push("Package selection> ".to_string());
        } else {
            output_lines.push("search chromium".to_string());
            output_lines.push("add chromium".to_string());
            output_lines.push("".to_string());
            output_lines.push("AUR package selection> ".to_string());
        }
        
        Self {
            current_input: String::new(),
            output_lines,
            scroll_offset: 0,
            package_list: String::new(),
            is_pacman,
            search_results: Vec::new(),
            list_state: ListState::default(),
            show_search_results: false,
        }
    }
    
    pub fn get_package_list(&self) -> &str {
        &self.package_list
    }
}

impl FloatContent for PackageSelection {
    fn draw(&mut self, frame: &mut Frame, area: Rect, _theme: &Theme) {
        // First, clear the entire area with a solid background
        let clear_block = Block::new()
            .style(Style::default().bg(Color::Black).fg(Color::White));
        frame.render_widget(clear_block, area);
        
        let title = if self.is_pacman {
            "Interactive Pacman Package Selection"
        } else {
            "Interactive AUR Package Selection"
        };

        let block = Block::new().borders(Borders::ALL)
            .title(title)
            .title_style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
            .title_bottom("Type commands, Enter to execute, Esc to exit")
            .style(Style::default().bg(Color::Black).fg(Color::White));

        let inner_area = Rect {
            x: area.x + 1,
            y: area.y + 1,
            width: area.width.saturating_sub(2),
            height: area.height.saturating_sub(2),
        };

        if self.show_search_results {
            // Display search results with scrolling
            let package_items: Vec<ListItem> = self.search_results
                .iter()
                .map(|p| {
                    let status = if p.installed { "[I]" } else { "[ ]" };
                    
                    // Check if this package is already selected in our config
                    let is_selected = self.package_list.contains(&p.name);
                    let selection_indicator = if is_selected { "✓" } else { " " };
                    
                    let text = format!("{} {} {}/{} ({}) - {}", 
                        status, selection_indicator, p.repo, p.name, p.version, p.description);
                    
                    // Style selected packages differently
                    let style = if is_selected {
                        Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)
                    } else {
                        Style::default()
                    };
                    
                    ListItem::new(text).style(style)
                })
                .collect();

            let search_list = List::new(package_items)
                .block(block.title("Search Results - ↑↓ Navigate | Enter Toggle Selection | 'q' Exit"))
                .highlight_style(Style::default().fg(Color::LightGreen).add_modifier(Modifier::BOLD))
                .highlight_symbol(">> ");

            frame.render_stateful_widget(search_list, area, &mut self.list_state);
            
            // Add instructions at the bottom
            let instruction_text = "↑↓ Navigate | Enter Toggle Selection | 'q' Exit Search";
            let instruction_para = Paragraph::new(instruction_text)
                .style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD))
                .alignment(Alignment::Center);
            
            let instruction_area = Rect {
                x: area.x,
                y: area.y + area.height - 1,
                width: area.width,
                height: 1,
            };
            frame.render_widget(instruction_para, instruction_area);
        } else {
            // Display normal command interface
            let mut list_items: Vec<ListItem> = self.output_lines
                .iter()
                .skip(self.scroll_offset)
                .take(inner_area.height as usize)
                .map(|line| ListItem::new(line.as_str()))
                .collect();

            // Add current input line
            let prompt = if self.is_pacman { "Package selection> " } else { "AUR package selection> " };
            let input_line = format!("{}{}", prompt, self.current_input);
            list_items.push(ListItem::new(input_line).style(Style::default().fg(Color::Yellow)));

            let list = List::new(list_items)
                .block(block)
                .style(Style::default().bg(Color::Black).fg(Color::White));

            frame.render_widget(list, area);
        }
    }

    fn handle_key_event(&mut self, key: &KeyEvent) -> bool {
        // Handle scrolling when search results are shown
        if self.show_search_results {
            match key.code {
                KeyCode::Up => {
                    if let Some(selected) = self.list_state.selected() {
                        if selected > 0 {
                            self.list_state.select(Some(selected - 1));
                        }
                    }
                    return false;
                }
                KeyCode::Down => {
                    if let Some(selected) = self.list_state.selected() {
                        if selected < self.search_results.len() - 1 {
                            self.list_state.select(Some(selected + 1));
                        }
                    } else if !self.search_results.is_empty() {
                        self.list_state.select(Some(0));
                    }
                    return false;
                }
                KeyCode::Enter => {
                    // Toggle selected package (add if not selected, remove if selected)
                    if let Some(selected) = self.list_state.selected() {
                        if let Some(package) = self.search_results.get(selected) {
                            let package_type = if self.is_pacman { "pacman" } else { "aur" };
                            let is_already_selected = self.package_list.contains(&package.name);
                            
                            if is_already_selected {
                                // Remove package
                                self.output_lines.push(format!("Removing package: {} ({})", package.name, package_type));
                                match call_script("./config_manager.sh", &["remove", package_type, &package.name]) {
                                    Ok(_) => {
                                        // Remove from our local list
                                        self.package_list = self.package_list
                                            .split_whitespace()
                                            .filter(|&p| p != package.name)
                                            .collect::<Vec<&str>>()
                                            .join(" ");
                                        if !self.package_list.is_empty() {
                                            self.package_list.push(' ');
                                        }
                                        self.output_lines.push(format!("✓ Removed package: {}", package.name));
                                    }
                                    Err(e) => {
                                        self.output_lines.push(format!("Failed to remove {}: {}", package.name, e));
                                    }
                                }
                            } else {
                                // Add package
                                self.output_lines.push(format!("Adding package: {} ({})", package.name, package_type));
                                match call_script("./config_manager.sh", &["add", package_type, &package.name]) {
                                    Ok(_) => {
                                        self.package_list.push_str(&package.name);
                                        self.package_list.push(' ');
                                        self.output_lines.push(format!("✓ Added package: {}", package.name));
                                    }
                                    Err(e) => {
                                        self.output_lines.push(format!("Failed to add {}: {}", package.name, e));
                                    }
                                }
                            }
                        } else {
                            self.output_lines.push("No package found at selected index".to_string());
                        }
                    } else {
                        self.output_lines.push("No package selected".to_string());
                    }
                    return false;
                }
                KeyCode::Esc => {
                    // Exit search results view
                    self.show_search_results = false;
                    self.search_results.clear();
                    self.list_state.select(None);
                    return false;
                }
                _ => return false,
            }
        }

        // Handle normal command input
        match key.code {
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                return true; // Close the window
            }
            KeyCode::Enter => {
                // Execute command
                let command = self.current_input.trim();
                if command == "done" || command == "exit" || command == "quit" {
                    // Add the command to output so is_finished() can detect it
                    let prompt = if self.is_pacman { "Package selection> " } else { "AUR package selection> " };
                    self.output_lines.push(format!("{}{}", prompt, self.current_input));
                    
                    // Store the package list for later retrieval
                    if !self.package_list.trim().is_empty() {
                        self.output_lines.push(format!("Selected packages: {}", self.package_list.trim()));
                    }
                    
                    return true; // Close the window immediately
                }
                
                // Add command to output
                let prompt = if self.is_pacman { "Package selection> " } else { "AUR package selection> " };
                self.output_lines.push(format!("{}{}", prompt, self.current_input));
                
                // Process command
                let parts: Vec<&str> = command.split_whitespace().collect();
                if !parts.is_empty() {
                    match parts[0] {
                        "search" => {
                            if parts.len() > 1 {
                                let term = parts[1..].join(" ");
                                self.output_lines.push(format!("Searching for '{}'...", term));
                                
                                let function_name = if self.is_pacman { "search_packages" } else { "search_aur_packages" };
                                match call_bash_function("./dialogs.sh", function_name, &[&term]) {
                                    Ok(results) => {
                                        if results.is_empty() {
                                            self.output_lines.push(format!("No packages found matching: {}", term));
                                        } else {
                                            // Parse pipe-delimited format: name|version|installed|repo|description
                                            let mut packages = Vec::new();
                                            for line in results {
                                                let parts: Vec<&str> = line.split('|').collect();
                                                if parts.len() >= 5 {
                                                    let package = Package {
                                                        name: parts[0].to_string(),
                                                        version: parts[1].to_string(),
                                                        installed: parts[2] == "true",
                                                        repo: parts[3].to_string(),
                                                        description: parts[4].to_string(),
                                                    };
                                                    packages.push(package);
                                                }
                                            }
                                            
                                            if !packages.is_empty() {
                                                    self.search_results = packages;
                                                    self.show_search_results = true;
                                                    self.list_state.select(Some(0));
                                                self.output_lines.push(format!("Found {} packages. Use ↑↓ to navigate, Enter to add, Esc to exit", self.search_results.len()));
                                            } else {
                                                self.output_lines.push(format!("No packages found matching: {}", term));
                                            }
                                        }
                                    }
                                    Err(e) => {
                                        self.output_lines.push(format!("Search failed: {}", e));
                                    }
                                }
                            } else {
                                self.output_lines.push("Usage: search <term>".to_string());
                            }
                        }
                        "add" => {
                            if parts.len() > 1 {
                                let packages = parts[1..].join(" ");
                                let package_type = if self.is_pacman { "pacman" } else { "aur" };
                                
                                // Add each package to the config file
                                for package in &parts[1..] {
                                    match call_script("./config_manager.sh", &["add", package_type, package]) {
                                        Ok(_) => {
                                            self.package_list.push_str(package);
                                            self.package_list.push(' ');
                                        }
                                        Err(e) => {
                                            self.output_lines.push(format!("Failed to add {}: {}", package, e));
                                        }
                                    }
                                }
                                self.output_lines.push(format!("Added packages: {}", packages));
                            } else {
                                self.output_lines.push("Usage: add <package1> [package2] ...".to_string());
                            }
                        }
                        "remove" => {
                            if parts.len() > 1 {
                                let package = parts[1];
                                let package_type = if self.is_pacman { "pacman" } else { "aur" };
                                
                                // Remove package from the config file
                                match call_script("./config_manager.sh", &["remove", package_type, package]) {
                                    Ok(_) => {
                                        self.package_list = self.package_list.replace(&format!("{} ", package), "");
                                        self.output_lines.push(format!("Removed package: {}", package));
                                    }
                                    Err(e) => {
                                        self.output_lines.push(format!("Failed to remove {}: {}", package, e));
                                    }
                                }
                            } else {
                                self.output_lines.push("Usage: remove <package>".to_string());
                            }
                        }
                        "list" => {
                            let package_type = if self.is_pacman { "pacman" } else { "aur" };
                            match call_script("./config_manager.sh", &["get", package_type]) {
                                Ok(results) => {
                                    if results.is_empty() || results[0].trim().is_empty() {
                                        self.output_lines.push("No packages selected".to_string());
                                    } else {
                                        self.output_lines.push(format!("Selected packages: {}", results[0]));
                                    }
                                }
                                Err(e) => {
                                    self.output_lines.push(format!("Failed to get package list: {}", e));
                                }
                            }
                        }
                        _ => {
                            self.output_lines.push(format!("Unknown command: {}", parts[0]));
                            self.output_lines.push("Available commands: search, add, remove, list, done".to_string());
                        }
                    }
                }
                
                // Clear input and add new prompt
                self.current_input.clear();
                self.output_lines.push("".to_string());
                
                // Auto-scroll to bottom
                if self.output_lines.len() > 20 {
                    self.scroll_offset = self.output_lines.len().saturating_sub(15);
                }
            }
            KeyCode::Char(c) => {
                self.current_input.push(c);
            }
            KeyCode::Backspace => {
                self.current_input.pop();
            }
            KeyCode::PageUp => {
                self.scroll_offset = self.scroll_offset.saturating_add(10);
            }
            KeyCode::PageDown => {
                self.scroll_offset = self.scroll_offset.saturating_sub(10);
            }
            _ => {}
        }
        false
    }

    fn is_finished(&self) -> bool {
        // Check if the last command was 'done'
        if let Some(last_line) = self.output_lines.last() {
            last_line.contains("done")
        } else {
            false
        }
    }

    fn get_shortcut_list(&self) -> (&str, Box<[Shortcut]>) {
        if self.is_finished() {
            ("Package Selection Complete", Box::new([
                Shortcut { keys: vec!["Enter".to_string()], description: "Close window".to_string() },
            ]))
        } else {
            ("Package Selection", Box::new([
                Shortcut { keys: vec!["Esc".to_string()], description: "Exit selection".to_string() },
                Shortcut { keys: vec!["Enter".to_string()], description: "Execute command".to_string() },
            ]))
        }
    }

}


pub enum Focus {
    Configuration,
    FloatingWindow(Float<PackageSelection>),
}

pub struct InstallerState {
    pub current_phase: String,
    pub progress: u8,
    pub status_message: String,
    pub installer_output: Vec<String>,
    pub is_running: bool,
    pub is_complete: bool,
    pub is_configuring: bool,
    pub config_step: usize,
    pub config_values: Vec<String>,
    pub current_input: String,
    pub input_mode: bool,
    pub popup: PopupState,
    pub editing_field: Option<usize>, // Which field is being edited (None = not editing)
    pub focus: Focus,
}

impl Default for InstallerState {
    fn default() -> Self {
        Self {
            current_phase: "Configuration".to_string(),
            progress: 0,
            status_message: "Press 's' to start configuration...".to_string(),
            installer_output: Vec::new(),
            is_running: false,
            is_complete: false,
            is_configuring: true,
            config_step: 0,
            config_values: vec![
                // Boot Setup (0-1)
                String::new(),  // 0: Boot mode
                String::new(),  // 1: Secure boot
                
                // System Locale and Input (2-3)
                String::new(),  // 2: Locale
                String::new(),  // 3: Keymap
                
                // Disk and Storage (4-14)
                String::new(),  // 4: Disk
                String::new(),  // 5: Partitioning strategy
                String::new(),  // 6: Encryption
                String::new(),  // 7: Root filesystem
                String::new(),  // 8: Separate home partition
                String::new(),  // 9: Home filesystem
                String::new(),  // 10: Swap
                String::new(),  // 11: Btrfs snapshots
                String::new(),  // 12: Btrfs frequency
                String::new(),  // 13: Btrfs keep count
                String::new(),  // 14: Btrfs assistant
                
                // Time and Location (15-17)
                String::new(),  // 15: Timezone Region
                String::new(),  // 16: Timezone
                String::new(),  // 17: Time sync (ntp)
                
                // System Packages (18-22)
                String::new(),  // 18: Mirror country
                String::new(),  // 19: Kernel
                String::new(),  // 20: Multilib
                String::new(),  // 21: Additional pacman packages
                String::new(),  // 22: GPU drivers
                
                // Hostname (23) - moved between GPU drivers and username
                String::new(),  // 23: Hostname
                
                // User Setup (24-26)
                String::new(),  // 24: Username
                String::new(),  // 25: User password
                String::new(),  // 26: Root password
                
                // Package Management (27-29)
                String::new(),  // 27: AUR helper
                String::new(),  // 28: Additional AUR packages
                String::new(),  // 29: Flatpak
                
                // Boot Configuration (30-32)
                String::new(),  // 30: Bootloader
                String::new(),  // 31: OS prober
                String::new(),  // 32: GRUB theme
                
                // Desktop Environment (33-34)
                String::new(),  // 33: Desktop environment
                String::new(),  // 34: Display manager
                
                // Boot Splash and Final Setup (35-38)
                String::new(),  // 35: Plymouth
                String::new(),  // 36: Plymouth theme
                String::new(),  // 37: Numlock on boot
                String::new(),  // 38: Git repository
            ],
            current_input: String::new(),
            input_mode: false,
            editing_field: None,
            popup: PopupState {
                popup_type: PopupType::None,
                is_active: false,
                selected_index: 0,
                options: Vec::new(),
                title: String::new(),
                bash_output: Vec::new(),
                bash_prompt: String::new(),
            },
            focus: Focus::Configuration,
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Setup signal handling for graceful shutdown
    setup_signal_handlers();
    
    // Setup terminal with proper error handling
    let result = run_app();
    
    // Always restore terminal, even if there was an error
    let _ = restore_terminal();
    
    result
}

fn setup_signal_handlers() {
    // Set up signal handlers for graceful shutdown
    let interrupted = &INTERRUPTED;
    
    // Handle SIGINT (Ctrl+C)
    ctrlc::set_handler(move || {
        interrupted.store(true, Ordering::SeqCst);
        eprintln!("\nReceived interrupt signal. Shutting down gracefully...");
    }).expect("Error setting Ctrl+C handler");
}

fn run_app() -> Result<(), Box<dyn std::error::Error>> {
    // Setup terminal
    crossterm::terminal::enable_raw_mode()?;
    let mut stdout = stdout();
    crossterm::execute!(stdout, crossterm::terminal::EnterAlternateScreen)?;

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create shared app state
    let app_state = Arc::new(Mutex::new(InstallerState::default()));

    // Initial draw
    terminal.draw(|f| {
        let mut state = app_state.lock().unwrap();
        ui(f, &mut state)
    })?;

    // Main event loop with proper error handling
    loop {
        // Check for interrupt signal
        if INTERRUPTED.load(Ordering::SeqCst) {
            break;
        }
        
        // Handle input with timeout to prevent blocking
        if crossterm::event::poll(Duration::from_millis(50))? {
            match crossterm::event::read()? {
                Event::Key(KeyEvent { code, modifiers, .. }) => {
                    match code {
                        KeyCode::Char('q') => {
                            // 'q' quits the installer from main screen
                            return Ok(());
                        }
                        KeyCode::Esc => {
                            let mut state = app_state.lock().unwrap();
                            
                            // 'Esc' returns to main menu from a popup
                            if state.popup.is_active {
                                            state.popup.is_active = false;
                                            state.popup.popup_type = PopupType::None;
                                state.popup.options.clear();
                                state.popup.title.clear();
                                state.popup.selected_index = 0;
                            } else if matches!(state.focus, Focus::FloatingWindow(_)) {
                                // Return to main focus from floating windows
                                            state.focus = Focus::Configuration;
                            }
                            // If already on main screen, do nothing (don't quit)
                        }
                        KeyCode::Char('c') if modifiers.contains(crossterm::event::KeyModifiers::CONTROL) => {
                            // Handle Ctrl+C - only quit app when NOT in floating window
                            let mut state = app_state.lock().unwrap();
                            match &mut state.focus {
                                Focus::FloatingWindow(float) => {
                                    // Pass Ctrl+C to floating window
                                    let key_event = KeyEvent { 
                                        code: KeyCode::Char('c'), 
                                        modifiers, 
                                        kind: crossterm::event::KeyEventKind::Press, 
                                        state: crossterm::event::KeyEventState::NONE 
                                    };
                                    if float.handle_key_event(&key_event) {
                                        // Floating window is finished, save packages if any were selected
                                        let config_step = state.config_step;
                                        if config_step == 20 || config_step == 21 {
                                            // This is a package selection step, set a placeholder
                                            state.config_values[config_step] = "packages selected".to_string();
                                        }
                                        state.focus = Focus::Configuration;
                                    }
                                }
                                Focus::Configuration => {
                                    // Quit the application only when in configuration mode
                                    break;
                                }
                            }
                        }
                        KeyCode::Left | KeyCode::Right => {
                            // Change configuration values (for selection-based options)
                            let mut state = app_state.lock().unwrap();
                            if state.is_configuring && !state.input_mode {
                                change_config_value(&mut state);
                            }
                        }
                        KeyCode::Enter => {
                            // Enter input mode or confirm selection
                            let mut state = app_state.lock().unwrap();
                            if state.is_configuring {
                                // Handle based on focus
                                let popup_active = state.popup.is_active;
                                match &mut state.focus {
                                    Focus::FloatingWindow(float) => {
                                        let float_result = float.handle_key_event(&KeyEvent { 
                                            code: KeyCode::Enter, 
                                            modifiers, 
                                            kind: crossterm::event::KeyEventKind::Press, 
                                            state: crossterm::event::KeyEventState::NONE 
                                        });
                                        
                                        if float_result {
                                            // Floating window is finished, return to configuration
                                            state.focus = Focus::Configuration;
                                            // Clear any popup state
                                            state.popup.is_active = false;
                                            state.popup.popup_type = PopupType::None;
                                        }
                                    }
                                    Focus::Configuration if popup_active => {
                                    if matches!(state.popup.popup_type, PopupType::TextInput(_)) {
                                        // Confirm text input from popup
                                        let current_step = state.config_step;
                                        let input_value = state.current_input.clone();
                                        state.config_values[current_step] = input_value;
                                        state.popup.is_active = false;
                                        state.popup.popup_type = PopupType::None;
                                        state.current_input.clear();
                                    } else if matches!(state.popup.popup_type, PopupType::PackageSelection) {
                                        // Handle bash session command
                                        let command = state.current_input.clone();
                                        let prompt = state.popup.bash_prompt.clone();
                                        state.popup.bash_output.push(format!("{}{}", prompt, command));
                                        
                                        let parts: Vec<&str> = command.split_whitespace().collect();
                                        if parts.is_empty() {
                                            // Empty command, just show prompt again
                                        } else {
                                            match parts[0] {
                                                "search" => {
                                                    if parts.len() > 1 {
                                                        let term = parts[1..].join(" ");
                                                        state.popup.bash_output.push(format!("Searching for '{}'...", term));
                                                        // Simulate search results
                                                        state.popup.bash_output.push(format!("Found packages matching '{}':", term));
                                                        state.popup.bash_output.push(format!("  {}-1.0-1 (Package 1)", term));
                                                        state.popup.bash_output.push(format!("  {}-2.0-1 (Package 2)", term));
                                                        state.popup.bash_output.push(format!("  {}-3.0-1 (Package 3)", term));
                                                    } else {
                                                        state.popup.bash_output.push("Usage: search <term>".to_string());
                                                    }
                                                },
                                                "add" => {
                                                    if parts.len() > 1 {
                                                        let package = parts[1..].join(" ");
                                                        // Add to current packages (stored in bash_output for now)
                                                        state.popup.bash_output.push(format!("Added '{}' to package list", package));
                                                    } else {
                                                        state.popup.bash_output.push("Usage: add <package>".to_string());
                                                    }
                                                },
                                                "remove" => {
                                                    if parts.len() > 1 {
                                                        let package = parts[1..].join(" ");
                                                        state.popup.bash_output.push(format!("Removed '{}' from package list", package));
                                                    } else {
                                                        state.popup.bash_output.push("Usage: remove <package>".to_string());
                                                    }
                                                },
                                                "list" => {
                                                    state.popup.bash_output.push("Current packages:".to_string());
                                                    state.popup.bash_output.push("  (packages will be listed here)".to_string());
                                                },
                                                "done" => {
                                                    // Save package list and close popup
                                                    let current_step = state.config_step;
                                                    state.config_values[current_step] = "packages selected".to_string(); // Placeholder
                                                    state.popup.is_active = false;
                                                    state.popup.popup_type = PopupType::None;
                                                    state.current_input.clear();
                                                    return Ok(());
                                                },
                                                _ => {
                                                    state.popup.bash_output.push(format!("Unknown command: {}", parts[0]));
                                                    state.popup.bash_output.push("Available commands: search, add, remove, list, done".to_string());
                                                }
                                            }
                                        }
                                        state.popup.bash_output.push("".to_string());
                                        state.current_input.clear();
                                        // Keep popup open
                                        return Ok(());
                                    } else {
                                        // Confirm popup selection
                                        if !state.popup.options.is_empty() && state.popup.selected_index < state.popup.options.len() {
                                            let current_step = state.config_step;
                                            let selected_value = state.popup.options[state.popup.selected_index].clone();
                                            
                                            // Special handling for different popup types
                                            if matches!(state.popup.popup_type, PopupType::PartitioningStrategy) {
                                                // Clear any existing RAID level from previous selection
                                                // and store the clean partitioning strategy
                                                state.config_values[current_step] = selected_value.clone();
                                                
                                                // Auto-set encryption based on partitioning strategy
                                                if selected_value.contains("luks") {
                                                    state.config_values[6] = "yes".to_string();
                                                } else if selected_value != "manual" {
                                                    state.config_values[6] = "no".to_string();
                                                }
                                                // For manual, leave encryption choice to user
                                                
                                                // If RAID strategy selected, show RAID level selection
                                                if selected_value.starts_with("auto_raid") {
                                                    state.popup.popup_type = PopupType::RAIDLevel;
                                                    state.popup.selected_index = 0;
                                                    // Keep popup open for RAID level selection
                                                    continue;
                                                } else {
                                                    // Close popup for other strategies
                                                    state.popup.is_active = false;
                                                    state.popup.popup_type = PopupType::None;
                                                    
                                                    // Show appropriate message for manual partitioning
                                                    if selected_value == "manual" {
                                                        state.status_message = "Manual partitioning selected. The installer will pause for you to partition the disk manually when installation begins.".to_string();
                                                    } else {
                                                        let encryption_status = if selected_value.contains("luks") { " (encryption auto-enabled)" } else { " (encryption auto-disabled)" };
                                                        state.status_message = format!("Partitioning strategy set to: {}{}", selected_value, encryption_status);
                                                    }
                                                }
                                            } else if matches!(state.popup.popup_type, PopupType::RAIDLevel) {
                                                // Combine partitioning strategy with RAID level
                                                let strategy = state.config_values[5].clone();
                                                state.config_values[5] = format!("{}_{}", strategy, selected_value);
                                                state.popup.is_active = false;
                                                state.popup.popup_type = PopupType::None;
                                                state.status_message = format!("RAID {} selected for partitioning.", selected_value);
                                            } else if matches!(state.popup.popup_type, PopupType::DesktopEnvironment) {
                                                // Store desktop environment and auto-select display manager
                                                state.config_values[current_step] = selected_value.clone();
                                                
                                                // Auto-select display manager based on DE (only if not "none")
                                                if selected_value != "none" {
                                                    let display_manager = match selected_value.as_str() {
                                                        "gnome" => "gdm",
                                                        "kde" => "sddm", 
                                                        "hyprland" => "sddm",
                                                        _ => "sddm", // Default fallback
                                                    };
                                                    state.config_values[34] = display_manager.to_string();
                                                } else {
                                                    // If "none" is selected, clear display manager to allow manual selection
                                                    state.config_values[34] = String::new();
                                                }
                                            } else if matches!(state.popup.popup_type, PopupType::TimezoneRegion) {
                                                // Store timezone region and move to timezone city selection
                                                state.config_values[current_step] = selected_value;
                                                // Move to next step (timezone city selection)
                                                state.config_step += 1;
                                            } else {
                                                state.config_values[current_step] = selected_value;
                                            }
                                        }
                                        state.popup.is_active = false;
                                        state.popup.popup_type = PopupType::None;
                                    }
                                    }
                                    Focus::Configuration => {
                                        // Handle normal configuration mode
                                        if state.editing_field.is_some() {
                                            // Confirm text input
                                            if let Some(field_index) = state.editing_field {
                                                state.config_values[field_index] = state.current_input.clone();
                                                state.editing_field = None;
                                                state.current_input.clear();
                                                }
                                        } else if state.config_step == 39 {
                                            // Start button pressed - begin installation
                                            state.is_configuring = false;
                                            state.is_running = true;
                                            state.current_phase = "Starting Installation".to_string();
                                            state.status_message = "Launching installer with configuration...".to_string();
                                            state.progress = 10;
                                            
                                            // Start the installer with configuration
                                            let config_values = state.config_values.clone();
                                            drop(state); // Release lock before spawning thread
                                            start_installer_with_config(Arc::clone(&app_state), config_values);
                                        } else {
                                            // Open popup or enter text input mode
                                            if is_text_input_field(state.config_step) {
                                                // Start editing text field directly
                                                state.editing_field = Some(state.config_step);
                                                state.current_input = state.config_values[state.config_step].clone();
                                            } else {
                                                // Open selection popup
                                                let popup_type = match state.config_step {
                                                    0 => PopupType::BootOverride,
                                                    1 => PopupType::SecureBoot,
                                                    2 => PopupType::Locale,
                                                    3 => PopupType::Keymap,
                                                    4 => PopupType::DiskSelection,
                                                    5 => {
                                                        // Always show partitioning strategy options to allow changes
                                                            PopupType::PartitioningStrategy
                                                    },
                                                    6 => {
                                                        // Show encryption popup only for manual partitioning
                                                        // Other strategies have encryption auto-set based on strategy
                                                        if state.config_values[5] == "manual" {
                                                            PopupType::Encryption
                                                        } else {
                                                            // For auto strategies, encryption is auto-set, no popup needed
                                                            PopupType::None
                                                        }
                                                    },
                                                    7 => PopupType::RootFilesystem,
                                                    8 => PopupType::HomePartition,
                                                    9 => PopupType::HomeFilesystem,
                                                    10 => PopupType::Swap,
                                                    11 => PopupType::BtrfsSnapshots,
                                                    12 => PopupType::BtrfsFrequency,
                                                    13 => PopupType::BtrfsKeep,
                                                    14 => PopupType::BtrfsAssistant,
                                                    15 => PopupType::TimezoneRegion,
                                                    16 => {
                                                        // Only show timezone cities if region is selected
                                                        if !state.config_values[15].is_empty() {
                                                            PopupType::Timezone
                                                        } else {
                                                            PopupType::None
                                                        }
                                                    },
                                                    17 => PopupType::TimeSync,
                                                    18 => PopupType::Mirror,
                                                    19 => PopupType::Kernel,
                                                    20 => PopupType::Multilib,
                                                    21 => PopupType::PackageSelection, // Pacman packages
                                                    22 => PopupType::GPUDrivers,
                                                    23 => PopupType::None, // Hostname - handled as text input
                                                    24 => PopupType::None, // Username - handled as text input
                                                    25 => PopupType::None, // User Password - handled as text input
                                                    26 => PopupType::None, // Root Password - handled as text input
                                                    27 => PopupType::AURHelper,
                                                    28 => PopupType::PackageSelection, // AUR packages
                                                    29 => PopupType::Flatpak,
                                                    30 => PopupType::Bootloader,
                                                    31 => PopupType::OSProber,
                                                    32 => PopupType::GRUBTheme,
                                                    33 => PopupType::DesktopEnvironment,
                                                    34 => {
                                                        // Display Manager - only allow popup if desktop environment is "none"
                                                        // When a specific DE is selected (gnome, kde, hyprland), it's a "full package" setup
                                                        let desktop_env = &state.config_values[33];
                                                        if desktop_env == "none" || desktop_env.is_empty() {
                                                            PopupType::DisplayManager  // Allow manual selection
                                                        } else {
                                                            PopupType::None  // No popup for full package DEs
                                                        }
                                                    },
                                                    35 => PopupType::Plymouth,
                                                    36 => PopupType::PlymouthTheme,
                                                    37 => PopupType::Numlock,
                                                    38 => PopupType::GitRepository,
                                                    _ => PopupType::None,
                                                };
                                                
                                                if !matches!(popup_type, PopupType::None) {
                                                    
                                                    let (options, title) = if matches!(popup_type, PopupType::Timezone) {
                                                        // Special handling for timezone - get timezones for selected region
                                                        let region = state.config_values[15].clone();
                                                        (detect_timezones_for_region(&region), "Select Timezone".to_string())
                                                    } else if matches!(popup_type, PopupType::PackageSelection) {
                                                        // Create floating window for package selection
                                                        let is_pacman = state.config_step == 21; // Pacman packages
                                                        let package_selection = PackageSelection::new(is_pacman);
                                                        state.focus = Focus::FloatingWindow(Float::new(Box::new(package_selection), 80, 60));
                                                        (vec![], "Interactive Package Selection".to_string())
                                                    } else {
                                                        get_popup_options(&popup_type)
                                                    };
                                                    state.popup.popup_type = popup_type;
                                                    state.popup.is_active = true;
                                                    state.popup.options = options;
                                                    state.popup.title = title;
                                                    state.popup.selected_index = 0;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        KeyCode::Char(c) => {
                            // Handle text input
                            let mut state = app_state.lock().unwrap();
                            if state.is_configuring {
                                let editing_field = state.editing_field.is_some();
                                match &mut state.focus {
                                    Focus::FloatingWindow(float) => {
                                        let key_event = KeyEvent { 
                                            code: KeyCode::Char(c), 
                                            modifiers, 
                                            kind: crossterm::event::KeyEventKind::Press, 
                                            state: crossterm::event::KeyEventState::NONE 
                                        };
                                        if float.handle_key_event(&key_event) {
                                            // Floating window is finished, return to configuration
                                            state.focus = Focus::Configuration;
                                        }
                                    }
                                    Focus::Configuration if editing_field => {
                                        state.current_input.push(c);
                                    }
                                    _ => {}
                                }
                            }
                        }
                        KeyCode::Backspace => {
                            // Handle backspace
                            let mut state = app_state.lock().unwrap();
                            if state.is_configuring {
                                let editing_field = state.editing_field.is_some();
                                match &mut state.focus {
                                    Focus::FloatingWindow(float) => {
                                        let key_event = KeyEvent { 
                                            code: KeyCode::Backspace, 
                                            modifiers, 
                                            kind: crossterm::event::KeyEventKind::Press, 
                                            state: crossterm::event::KeyEventState::NONE 
                                        };
                                        if float.handle_key_event(&key_event) {
                                            state.focus = Focus::Configuration;
                                        }
                                    }
                                    Focus::Configuration if editing_field => {
                                        state.current_input.pop();
                                    }
                                    _ => {}
                                }
                            }
                        }
                        KeyCode::Up => {
                            // Navigate popup or configuration options
                            let mut state = app_state.lock().unwrap();
                            if state.is_configuring {
                                // Check if we're in a floating window first
                                if let Focus::FloatingWindow(float) = &mut state.focus {
                                    let key_event = KeyEvent { 
                                        code: KeyCode::Up, 
                                        modifiers, 
                                        kind: crossterm::event::KeyEventKind::Press, 
                                        state: crossterm::event::KeyEventState::NONE 
                                    };
                                    if float.handle_key_event(&key_event) {
                                        state.focus = Focus::Configuration;
                                    }
                                } else if state.popup.is_active {
                                    // Navigate popup options
                                    if state.popup.selected_index > 0 {
                                        state.popup.selected_index -= 1;
                                    }
                                } else {
                                    // Navigate configuration options
                                    if state.config_step > 0 {
                                        state.config_step -= 1;
                                    } else if state.config_step == 0 {
                                        // Wrap around to start button
                                        state.config_step = 39;
                                    }
                                }
                            }
                        }
                        KeyCode::Down => {
                            // Navigate popup or configuration options
                            let mut state = app_state.lock().unwrap();
                            if state.is_configuring {
                                // Check if we're in a floating window first
                                if let Focus::FloatingWindow(float) = &mut state.focus {
                                    let key_event = KeyEvent { 
                                        code: KeyCode::Down, 
                                        modifiers, 
                                        kind: crossterm::event::KeyEventKind::Press, 
                                        state: crossterm::event::KeyEventState::NONE 
                                    };
                                    if float.handle_key_event(&key_event) {
                                        state.focus = Focus::Configuration;
                                    }
                                } else if state.popup.is_active {
                                    // Navigate popup options
                                    if state.popup.selected_index < state.popup.options.len().saturating_sub(1) {
                                        state.popup.selected_index += 1;
                                    }
                                } else {
                                    // Navigate configuration options
                                    if state.config_step < 39 {
                                        state.config_step += 1;
                                    } else if state.config_step == 39 {
                                        // Wrap around to first option
                                        state.config_step = 0;
                                    }
                                }
                            }
                        }
                        _ => {}
                    }
                }
                Event::Resize(_, _) => {
                    // Handle terminal resize - redraw immediately
                    terminal.draw(|f| {
                        let mut state = app_state.lock().unwrap();
                        ui(f, &mut state)
                    })?;
                }
                _ => {}
            }
        }

        // Redraw the UI
        terminal.draw(|f| {
            let mut state = app_state.lock().unwrap();
            ui(f, &mut state)
        })?;
        
        // Small delay to prevent excessive CPU usage
        std::thread::sleep(Duration::from_millis(50));
    }

    Ok(())
}

fn is_text_input_field(step: usize) -> bool {
    match step {
        23..=26 => true,  // Hostname, Username, User Password, Root Password
        _ => false,  // Selection-based fields (including boot mode, disk, packages, etc.)
    }
}

// Helper function to read selected packages from config file
fn get_selected_packages(package_type: &str) -> String {
    // Use the config manager script to get the packages
    match call_script("./config_manager.sh", &["get", package_type]) {
        Ok(results) => {
            if results.is_empty() || results[0].trim().is_empty() {
                "[Press Enter]".to_string()
            } else {
                results[0].clone()
            }
        }
        Err(_) => {
            // Fallback to the old behavior if config manager fails
            "[Press Enter]".to_string()
        }
    }
}

// Helper function to call a script directly with arguments
fn call_script(script_path: &str, args: &[&str]) -> Result<Vec<String>, String> {
    let mut cmd = Command::new(script_path);
    cmd.args(args);
    
    match cmd.output() {
        Ok(output) => {
            if output.status.success() {
                let output_str = String::from_utf8_lossy(&output.stdout);
                let lines: Vec<String> = output_str.lines()
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect();
                Ok(lines)
            } else {
                let error_str = String::from_utf8_lossy(&output.stderr);
                Err(format!("Script failed: {}", error_str))
            }
        }
        Err(e) => Err(format!("Failed to execute script: {}", e))
    }
}

// Helper function to call Bash functions and get their output
fn call_bash_function(script_path: &str, function_name: &str, args: &[&str]) -> Result<Vec<String>, String> {
    let mut cmd = Command::new("bash");
    cmd.arg("-c");
    
    // Build the command to source the script and call the function
    let bash_cmd = format!("source '{}' && {} {}", script_path, function_name, args.join(" "));
    cmd.arg(&bash_cmd);
    
    match cmd.output() {
        Ok(output) => {
            if output.status.success() {
                let output_str = String::from_utf8_lossy(&output.stdout);
                let lines: Vec<String> = output_str.lines()
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect();
                Ok(lines)
            } else {
                let error_str = String::from_utf8_lossy(&output.stderr);
                Err(format!("Bash function failed: {}", error_str))
            }
        }
        Err(e) => Err(format!("Failed to execute bash command: {}", e))
    }
}


fn detect_disks() -> Vec<String> {
    // Try to use the Bash function first (more robust filtering)
    if let Ok(disks) = call_bash_function("./dialogs.sh", "get_available_disks", &[]) {
        if !disks.is_empty() {
            // Get disk sizes and format them nicely
            let mut formatted_disks = Vec::new();
            for disk in disks {
                if let Ok(size_output) = Command::new("lsblk")
                    .args(["-d", "-n", "-o", "SIZE", &disk])
                    .output() {
                    let size_str = String::from_utf8_lossy(&size_output.stdout).trim().to_string();
                    formatted_disks.push(format!("{} ({})", disk, size_str));
                } else {
                    formatted_disks.push(disk);
                }
            }
            return formatted_disks;
        }
    }
    
    // Fallback to direct lsblk call
    let mut disks = Vec::new();
    if let Ok(output) = Command::new("lsblk")
        .args(["-d", "-n", "-o", "NAME,SIZE,TYPE"])
        .output() {
        let output_str = String::from_utf8_lossy(&output.stdout);
        for line in output_str.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 3 && parts[2] == "disk" {
                let disk_name = format!("/dev/{}", parts[0]);
                let disk_size = parts[1];
                disks.push(format!("{} ({})", disk_name, disk_size));
            }
        }
    }
    
    // Final fallback to common disk paths if everything fails
    if disks.is_empty() {
        let common_disks = vec![
            "/dev/sda", "/dev/sdb", "/dev/sdc", "/dev/sdd",
            "/dev/nvme0n1", "/dev/nvme1n1", "/dev/nvme2n1",
            "/dev/vda", "/dev/vdb", "/dev/vdc"
        ];
        
        for disk in common_disks {
            if std::path::Path::new(disk).exists() {
                disks.push(disk.to_string());
            }
        }
    }
    
    disks
}


fn detect_timezones_for_region(region: &str) -> Vec<String> {
    // Try to use the Bash function first (more robust)
    if let Ok(timezones) = call_bash_function("./dialogs.sh", "get_timezones_in_region", &[region]) {
        if !timezones.is_empty() {
            return timezones;
        }
    }
    
    // Fallback to direct timedatectl call
    let mut timezones = Vec::new();
    if let Ok(output) = Command::new("timedatectl")
        .args(["list-timezones"])
        .output() {
        let output_str = String::from_utf8_lossy(&output.stdout);
        for line in output_str.lines() {
            let tz = line.trim();
            if !tz.is_empty() && tz.starts_with(&format!("{}/", region)) {
                timezones.push(tz.to_string());
            }
        }
    }
    
    // Final fallback to common timezones for specific regions if everything fails
    if timezones.is_empty() {
        timezones = match region {
            "US" => vec![
                "US/Eastern".to_string(),
                "US/Central".to_string(),
                "US/Mountain".to_string(),
                "US/Pacific".to_string(),
                "US/Alaska".to_string(),
                "US/Hawaii".to_string(),
            ],
            "America" => vec![
                "America/New_York".to_string(),
                "America/Chicago".to_string(),
                "America/Denver".to_string(),
                "America/Los_Angeles".to_string(),
                "America/Toronto".to_string(),
                "America/Vancouver".to_string(),
            ],
            "Europe" => vec![
                "Europe/London".to_string(),
                "Europe/Paris".to_string(),
                "Europe/Berlin".to_string(),
                "Europe/Rome".to_string(),
                "Europe/Madrid".to_string(),
                "Europe/Amsterdam".to_string(),
            ],
            "Asia" => vec![
                "Asia/Tokyo".to_string(),
                "Asia/Shanghai".to_string(),
                "Asia/Seoul".to_string(),
                "Asia/Singapore".to_string(),
                "Asia/Dubai".to_string(),
                "Asia/Kolkata".to_string(),
            ],
            _ => vec![format!("{}/UTC", region)],
        };
    }
    
    timezones
}

// Update app state from parsed JSON progress update
fn update_app_state_from_progress(app_state: &Arc<Mutex<InstallerState>>, progress_update: &ProgressUpdate) {
    let mut state = app_state.lock().unwrap();
    
    // Update progress and phase based on the JSON data
    state.progress = progress_update.progress;
    state.current_phase = format!("{:?}", progress_update.phase);
    state.status_message = progress_update.message.clone();
    
    // Add the progress message to output log
    let log_message = format!("[{}] {:?}: {} ({}%)", 
        progress_update.timestamp.as_ref().unwrap_or(&"".to_string()),
        progress_update.message_type,
        progress_update.message,
        progress_update.progress
    );
    state.installer_output.push(log_message);
    
    // Keep output log manageable
    if state.installer_output.len() > 50 {
        state.installer_output.remove(0);
    }
    
    // Handle completion
    if matches!(progress_update.phase, InstallationPhase::Complete) {
        state.is_complete = true;
        state.progress = 100;
    }
}

fn get_popup_options(popup_type: &PopupType) -> (Vec<String>, String) {
    match popup_type {
        PopupType::DiskSelection => (detect_disks(), "Select Installation Disk".to_string()),
        PopupType::PartitioningStrategy => (
            vec![
                "auto_simple".to_string(),
                "auto_simple_luks".to_string(),
                "auto_lvm".to_string(),
                "auto_luks_lvm".to_string(),
                "auto_raid_simple".to_string(),
                "auto_raid_lvm".to_string(),
                "manual".to_string(),
            ],
            "Select Partitioning Strategy".to_string()
        ),
        PopupType::DesktopEnvironment => (
            vec![
                "none".to_string(),
                "gnome".to_string(),
                "kde".to_string(),
                "hyprland".to_string(),
            ],
            "Select Desktop Environment".to_string()
        ),
        PopupType::DisplayManager => (
            vec![
                "none".to_string(),
                "gdm".to_string(),
                "sddm".to_string(),
            ],
            "Select Display Manager".to_string()
        ),
        PopupType::AURHelper => (
            vec![
                "paru".to_string(),
                "yay".to_string(),
                "none".to_string(),
            ],
            "Select AUR Helper".to_string()
        ),
        PopupType::TimezoneRegion => (
            vec![
                "US".to_string(),
                "Africa".to_string(),
                "America".to_string(),
                "Antarctica".to_string(),
                "Arctic".to_string(),
                "Asia".to_string(),
                "Atlantic".to_string(),
                "Australia".to_string(),
                "Europe".to_string(),
                "Indian".to_string(),
                "Pacific".to_string(),
            ],
            "Select Timezone Region".to_string()
        ),
        PopupType::Timezone => {
            // This will be handled specially in the popup opening logic
            (vec!["UTC".to_string()], "Select Timezone".to_string())
        },
        PopupType::Locale => (
            vec![
                "en_US.UTF-8".to_string(),
                "en_GB.UTF-8".to_string(),
                "de_DE.UTF-8".to_string(),
                "fr_FR.UTF-8".to_string(),
                "es_ES.UTF-8".to_string(),
            ],
            "Select Locale".to_string()
        ),
        PopupType::Keymap => (
            vec![
                "us".to_string(),
                "uk".to_string(),
                "de".to_string(),
                "fr".to_string(),
                "es".to_string(),
            ],
            "Select Keymap".to_string()
        ),
        PopupType::Bootloader => (
            vec![
                "grub".to_string(),
                "systemd-boot".to_string(),
                "refind".to_string(),
            ],
            "Select Bootloader".to_string()
        ),
        PopupType::GRUBTheme => (
            vec![
                "PolyDark".to_string(),
                "CyberEXS".to_string(),
                "CyberPunk".to_string(),
                "HyperFluent".to_string(),
                "none".to_string(),
            ],
            "Select GRUB Theme".to_string()
        ),
        PopupType::GPUDrivers => (
            vec![
                "auto".to_string(),
                "nvidia".to_string(),
                "amd".to_string(),
                "intel".to_string(),
                "none".to_string(),
            ],
            "Select GPU Drivers".to_string()
        ),
        PopupType::Encryption => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Enable Disk Encryption".to_string()
        ),
        PopupType::Multilib => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Enable Multilib (32-bit support)".to_string()
        ),
        PopupType::Plymouth => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Enable Plymouth Boot Splash".to_string()
        ),
        PopupType::PlymouthTheme => (
            vec![
                "arch-glow".to_string(),
                "arch-mac-style".to_string(),
            ],
            "Select Plymouth Theme".to_string()
        ),
        PopupType::RAIDLevel => (
            vec![
                "raid0".to_string(),
                "raid1".to_string(),
                "raid5".to_string(),
                "raid10".to_string(),
            ],
            "Select RAID Level".to_string()
        ),
        PopupType::PackageSelection => (
            vec![],
            "Interactive Package Selection".to_string()
        ),
        PopupType::TextInput(field_name) => (
            vec![],
            format!("Enter {}", field_name)
        ),
        // New popup types for missing configuration options
        PopupType::WiFi => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Configure Wi-Fi Connection?".to_string()
        ),
        PopupType::WiFiSession => (
            vec![],
            "Launch iwctl Wi-Fi Configuration".to_string()
        ),
        PopupType::BootOverride => (
            vec![
                "auto".to_string(),
                "uefi".to_string(),
                "bios".to_string(),
            ],
            "Select Boot Mode Override".to_string()
        ),
        PopupType::SecureBoot => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Enable Secure Boot".to_string()
        ),
        PopupType::RootFilesystem => (
            vec![
                "ext4".to_string(),
                "btrfs".to_string(),
                "xfs".to_string(),
            ],
            "Select Root Filesystem Type".to_string()
        ),
        PopupType::HomePartition => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Create Separate Home Partition?".to_string()
        ),
        PopupType::HomeFilesystem => (
            vec![
                "ext4".to_string(),
                "btrfs".to_string(),
                "xfs".to_string(),
            ],
            "Select Home Filesystem Type".to_string()
        ),
        PopupType::Swap => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Create Swap Partition?".to_string()
        ),
        PopupType::BtrfsSnapshots => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Enable Btrfs Snapshots?".to_string()
        ),
        PopupType::BtrfsFrequency => (
            vec![
                "hourly".to_string(),
                "daily".to_string(),
                "weekly".to_string(),
                "monthly".to_string(),
            ],
            "Select Snapshot Frequency".to_string()
        ),
        PopupType::BtrfsKeep => (
            vec![
                "5".to_string(),
                "10".to_string(),
                "15".to_string(),
                "20".to_string(),
                "30".to_string(),
            ],
            "Number of Snapshots to Keep".to_string()
        ),
        PopupType::BtrfsAssistant => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Install Btrfs Assistant?".to_string()
        ),
        PopupType::TimeSync => (
            vec![
                "ntpd".to_string(),
                "systemd-timesyncd".to_string(),
                "chrony".to_string(),
            ],
            "Select Time Synchronization Service".to_string()
        ),
        PopupType::Mirror => (
            vec![
                "US".to_string(),
                "CA".to_string(),
                "GB".to_string(),
                "DE".to_string(),
                "FR".to_string(),
                "AU".to_string(),
                "JP".to_string(),
            ],
            "Select Mirror Country".to_string()
        ),
        PopupType::Kernel => (
            vec![
                "linux".to_string(),
                "linux-lts".to_string(),
                "linux-zen".to_string(),
                "linux-hardened".to_string(),
            ],
            "Select Kernel Type".to_string()
        ),
        PopupType::Flatpak => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Install Flatpak Support?".to_string()
        ),
        PopupType::OSProber => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Enable OS Prober (Multi-boot detection)".to_string()
        ),
        PopupType::Numlock => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Enable Numlock on Boot?".to_string()
        ),
        PopupType::GitRepository => (
            vec![
                "yes".to_string(),
                "no".to_string(),
            ],
            "Clone Git Repository?".to_string()
        ),
        PopupType::None => (vec![], String::new()),
    }
}

fn change_config_value(_state: &mut InstallerState) {
    // This function is not currently used in the TUI
    // All configuration changes are handled through popups
    // Keeping this function for potential future use
}

fn start_installer_with_config(app_state: Arc<Mutex<InstallerState>>, config_values: Vec<String>) {
    // Start the installer in a separate thread
    thread::spawn(move || {
        run_actual_installer(app_state, config_values);
    });
}

fn run_actual_installer(app_state: Arc<Mutex<InstallerState>>, config_values: Vec<String>) {
    // Set environment variables for the bash installer
    let mut env_vars = std::collections::HashMap::new();
    env_vars.insert("TUI_MODE".to_string(), "true".to_string());
    
    // Map TUI configuration values to environment variables expected by bash installer
    env_vars.insert("BOOT_MODE_OVERRIDE".to_string(), config_values.first().unwrap_or(&String::new()).clone());
    env_vars.insert("WANT_SECURE_BOOT".to_string(), config_values.get(1).unwrap_or(&String::new()).clone());
    env_vars.insert("LOCALE".to_string(), config_values.get(2).unwrap_or(&String::new()).clone());
    env_vars.insert("KEYMAP".to_string(), config_values.get(3).unwrap_or(&String::new()).clone());
    env_vars.insert("INSTALL_DISK".to_string(), config_values.get(4).unwrap_or(&String::new()).clone());
    env_vars.insert("PARTITION_SCHEME".to_string(), config_values.get(5).unwrap_or(&String::new()).clone());
    env_vars.insert("WANT_ENCRYPTION".to_string(), config_values.get(6).unwrap_or(&String::new()).clone());
    env_vars.insert("ROOT_FILESYSTEM_TYPE".to_string(), config_values.get(7).unwrap_or(&String::new()).clone());
    env_vars.insert("WANT_HOME_PARTITION".to_string(), config_values.get(8).unwrap_or(&String::new()).clone());
    env_vars.insert("HOME_FILESYSTEM_TYPE".to_string(), config_values.get(9).unwrap_or(&String::new()).clone());
    env_vars.insert("WANT_SWAP".to_string(), config_values.get(10).unwrap_or(&String::new()).clone());
    env_vars.insert("WANT_BTRFS_SNAPSHOTS".to_string(), config_values.get(11).unwrap_or(&String::new()).clone());
    env_vars.insert("BTRFS_SNAPSHOT_FREQUENCY".to_string(), config_values.get(12).unwrap_or(&String::new()).clone());
    env_vars.insert("BTRFS_KEEP_SNAPSHOTS".to_string(), config_values.get(13).unwrap_or(&String::new()).clone());
    env_vars.insert("WANT_BTRFS_ASSISTANT".to_string(), config_values.get(14).unwrap_or(&String::new()).clone());
    env_vars.insert("TIMEZONE_REGION".to_string(), config_values.get(15).unwrap_or(&String::new()).clone());
    env_vars.insert("TIMEZONE".to_string(), config_values.get(16).unwrap_or(&String::new()).clone());
    env_vars.insert("TIME_SYNC_CHOICE".to_string(), config_values.get(17).unwrap_or(&String::new()).clone());
    env_vars.insert("REFLECTOR_COUNTRY_CODE".to_string(), config_values.get(18).unwrap_or(&String::new()).clone());
    env_vars.insert("KERNEL_TYPE".to_string(), config_values.get(19).unwrap_or(&String::new()).clone());
    env_vars.insert("WANT_MULTILIB".to_string(), config_values.get(20).unwrap_or(&String::new()).clone());
    env_vars.insert("CUSTOM_PACKAGES".to_string(), config_values.get(21).unwrap_or(&String::new()).clone());
    env_vars.insert("GPU_DRIVER_TYPE".to_string(), config_values.get(22).unwrap_or(&String::new()).clone());
    env_vars.insert("SYSTEM_HOSTNAME".to_string(), config_values.get(23).unwrap_or(&String::new()).clone());
    env_vars.insert("MAIN_USERNAME".to_string(), config_values.get(24).unwrap_or(&String::new()).clone());
    env_vars.insert("MAIN_USER_PASSWORD".to_string(), config_values.get(25).unwrap_or(&String::new()).clone());
    env_vars.insert("ROOT_PASSWORD".to_string(), config_values.get(26).unwrap_or(&String::new()).clone());
    env_vars.insert("AUR_HELPER_CHOICE".to_string(), config_values.get(27).unwrap_or(&String::new()).clone());
    env_vars.insert("CUSTOM_AUR_PACKAGES".to_string(), config_values.get(28).unwrap_or(&String::new()).clone());
    env_vars.insert("WANT_FLATPAK".to_string(), config_values.get(29).unwrap_or(&String::new()).clone());
    env_vars.insert("BOOTLOADER_TYPE".to_string(), config_values.get(30).unwrap_or(&String::new()).clone());
    env_vars.insert("ENABLE_OS_PROBER".to_string(), config_values.get(31).unwrap_or(&String::new()).clone());
    env_vars.insert("GRUB_THEME_CHOICE".to_string(), config_values.get(32).unwrap_or(&String::new()).clone());
    env_vars.insert("DESKTOP_ENVIRONMENT".to_string(), config_values.get(33).unwrap_or(&String::new()).clone());
    env_vars.insert("DISPLAY_MANAGER".to_string(), config_values.get(34).unwrap_or(&String::new()).clone());
    env_vars.insert("WANT_PLYMOUTH".to_string(), config_values.get(35).unwrap_or(&String::new()).clone());
    env_vars.insert("PLYMOUTH_THEME_CHOICE".to_string(), config_values.get(36).unwrap_or(&String::new()).clone());
    env_vars.insert("WANT_NUMLOCK_ON_BOOT".to_string(), config_values.get(37).unwrap_or(&String::new()).clone());
    env_vars.insert("DOTFILES_REPO_URL".to_string(), config_values.get(38).unwrap_or(&String::new()).clone());
    
    // Set additional environment variables that bash scripts expect
    env_vars.insert("WANT_AUR_HELPER".to_string(), if config_values.get(27).unwrap_or(&String::new()) != "none" { "yes".to_string() } else { "no".to_string() });
    env_vars.insert("WANT_GRUB_THEME".to_string(), if config_values.get(32).unwrap_or(&String::new()) != "none" { "yes".to_string() } else { "no".to_string() });
    env_vars.insert("WANT_PLYMOUTH_THEME".to_string(), if config_values.get(36).unwrap_or(&String::new()) != "none" { "yes".to_string() } else { "no".to_string() });
    env_vars.insert("WANT_BTRFS".to_string(), if config_values.get(7).unwrap_or(&String::new()) == "btrfs" || config_values.get(9).unwrap_or(&String::new()) == "btrfs" { "yes".to_string() } else { "no".to_string() });
    env_vars.insert("WANT_LVM".to_string(), if config_values.get(5).unwrap_or(&String::new()).contains("lvm") { "yes".to_string() } else { "no".to_string() });
    env_vars.insert("WANT_RAID".to_string(), if config_values.get(5).unwrap_or(&String::new()).contains("raid") { "yes".to_string() } else { "no".to_string() });
    env_vars.insert("INSTALL_CUSTOM_PACKAGES".to_string(), if config_values.get(21).unwrap_or(&String::new()).is_empty() { "no".to_string() } else { "yes".to_string() });
    env_vars.insert("INSTALL_CUSTOM_AUR_PACKAGES".to_string(), if config_values.get(28).unwrap_or(&String::new()).is_empty() { "no".to_string() } else { "yes".to_string() });
    env_vars.insert("WANT_DOTFILES_DEPLOYMENT".to_string(), if config_values.get(38).unwrap_or(&String::new()).is_empty() { "no".to_string() } else { "yes".to_string() });
    env_vars.insert("OVERRIDE_BOOT_MODE".to_string(), if config_values.first().unwrap_or(&String::new()) == "auto" { "no".to_string() } else { "yes".to_string() });
    
    // Run the installer and capture both stdout and stderr
    let mut child = Command::new("bash")
        .arg("./launch_tui_installer.sh")
        .arg("--bash-only")
        .envs(&env_vars)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("Failed to start installer");

    // Clone app_state for stderr thread
    let stderr_app_state = app_state.clone();
    
    // Handle stderr in a separate thread (this contains JSON progress updates)
    let stderr_handle = child.stderr.take().map(|stderr| thread::spawn(move || {
            let reader = BufReader::new(stderr);
        for line in reader.lines().map_while(Result::ok) {
            // Try to parse as JSON progress update first
            if let Ok(progress_update) = serde_json::from_str::<ProgressUpdate>(&line) {
                // Update app state with parsed progress
                update_app_state_from_progress(&stderr_app_state, &progress_update);
            } else {
                // If not JSON, treat as regular output/error
                let mut state = stderr_app_state.lock().unwrap();
                state.installer_output.push(line.clone());
                if state.installer_output.len() > 50 {
                    state.installer_output.remove(0);
                }
                
                // Check if it looks like an error
                if line.to_lowercase().contains("error") || line.to_lowercase().contains("failed") {
                    state.status_message = format!("Error: {}", line);
                }
            }
        }
    }));

    // Handle stdout for general output
    if let Some(stdout) = child.stdout.take() {
        let reader = BufReader::new(stdout);
        for line in reader.lines().map_while(Result::ok) {
            // Add stdout to output log
            let mut state = app_state.lock().unwrap();
            state.installer_output.push(line.clone());
            if state.installer_output.len() > 50 {
                state.installer_output.remove(0);
            }
            
            // Also try to parse for any fallback progress indicators
            parse_installer_output(&app_state, &line);
        }
    }
    
    // Wait for stderr thread to complete
    if let Some(handle) = stderr_handle {
        let _ = handle.join();
    }

    // Wait for the process to complete
    let status = child.wait().expect("Failed to wait for installer");
    
    // Mark as complete based on exit status
    {
        let mut state = app_state.lock().unwrap();
        state.is_complete = true;
        
        if status.success() {
        state.progress = 100;
        state.status_message = "Installation complete!".to_string();
        state.current_phase = "Complete".to_string();
        } else {
            state.status_message = format!("Installation failed with exit code: {}", status.code().unwrap_or(-1));
            state.current_phase = "Failed".to_string();
        }
    }
    
    println!("Installer completed with status: {:?}", status);
}

fn parse_installer_output(app_state: &Arc<Mutex<InstallerState>>, line: &str) {
    let mut state = app_state.lock().unwrap();
    
    // Add line to output buffer
    state.installer_output.push(line.to_string());
    
    // Keep only last 50 lines to prevent memory issues
    if state.installer_output.len() > 50 {
        state.installer_output.remove(0);
    }
    
    // Try to parse as structured JSON first
    if let Ok(progress_update) = serde_json::from_str::<ProgressUpdate>(line) {
        // Handle structured progress update
        state.current_phase = format!("{:?}", progress_update.phase);
        state.progress = progress_update.progress;
        state.status_message = progress_update.message.clone();
        
        // Handle completion
        if matches!(progress_update.phase, InstallationPhase::Complete) {
            state.is_complete = true;
        }
        
        // Handle errors
        if matches!(progress_update.message_type, MessageType::Error) {
            state.status_message = format!("ERROR: {}", progress_update.message);
        }
        
        return;
    }
    
    // Fallback to legacy string parsing for backward compatibility
    // This will be removed once all Bash scripts are updated
    if line.contains("=== PHASE 0: Gathering Installation Details ===") {
        state.current_phase = "Gathering Installation Details".to_string();
        state.progress = 10;
        state.status_message = "Collecting user preferences...".to_string();
    } else if line.contains("=== PHASE 1: Disk Partitioning ===") {
        state.current_phase = "Disk Partitioning".to_string();
        state.progress = 20;
        state.status_message = "Partitioning disk...".to_string();
    } else if line.contains("=== PHASE 2: Base Installation ===") {
        state.current_phase = "Base Installation".to_string();
        state.progress = 40;
        state.status_message = "Installing base system...".to_string();
    } else if line.contains("=== PHASE 4: System Configuration ===") {
        state.current_phase = "System Configuration".to_string();
        state.progress = 60;
        state.status_message = "Configuring system...".to_string();
    } else if line.contains("=== PHASE 5: Finalization ===") {
        state.current_phase = "Finalization".to_string();
        state.progress = 80;
        state.status_message = "Finalizing installation...".to_string();
    } else if line.contains("Installation completed successfully") {
        state.current_phase = "Complete".to_string();
        state.progress = 100;
        state.status_message = "Installation complete!".to_string();
        state.is_complete = true;
    } else if line.contains("Disk partitioning complete") {
        state.progress = 30;
        state.status_message = "Disk partitioning completed".to_string();
    } else if line.contains("Packages installed") {
        state.progress = 50;
        state.status_message = "Base packages installed".to_string();
    } else if line.contains("System configuration complete") {
        state.progress = 70;
        state.status_message = "System configuration completed".to_string();
    } else if line.contains("Installation failed") {
        state.status_message = "Installation failed - check logs".to_string();
        state.is_complete = true;
    } else if line.contains("Installation interrupted") {
        state.status_message = "Installation interrupted by user".to_string();
        state.is_complete = true;
    }
}

fn ui(f: &mut Frame, app_state: &mut InstallerState) {
    let size = f.area();
    
    // Check if terminal is too small - DISABLED to force full UI
    // if size.height < 10 || size.width < 40 {
    //     render_minimal_ui(f, app_state);
    //     return;
    // }
    
    // Render based on focus
    match &mut app_state.focus {
        Focus::FloatingWindow(float) => {
            // When floating window is active, only render header and title, then the floating window
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Length(7),  // Header
                    Constraint::Length(3),  // Title
                    Constraint::Min(10),    // Floating window area
                    Constraint::Length(3),  // Instructions
                    Constraint::Length(3),  // Start button
                ])
                .split(size);
            
            // Render header and title only
            render_header(f, chunks[0]);
            let title = Paragraph::new("Arch Linux Installation Configuration")
                .block(Block::default().borders(Borders::ALL))
                .alignment(Alignment::Center)
                .style(Style::default().fg(Color::Cyan));
            f.render_widget(title, chunks[1]);
            
            // Render instructions and start button
            let instructions = "Use ↑↓ to navigate, Enter to open popup, 'q' to quit installer";
            let instruction_text = Paragraph::new(instructions)
                .block(Block::default().borders(Borders::NONE))
                .alignment(Alignment::Center)
                .style(Style::default().fg(Color::Yellow));
            f.render_widget(instruction_text, chunks[3]);
            
            let start_button = Paragraph::new("  START INSTALLATION  ")
                .block(Block::default().borders(Borders::ALL))
                .alignment(Alignment::Center)
                .style(Style::default().fg(Color::Green));
            f.render_widget(start_button, chunks[4]);
            
            // Draw floating window in the main content area
            let theme = Theme;
            float.draw(f, chunks[2], &theme);
        }
        Focus::Configuration => {
            // Normal configuration mode
            if app_state.is_configuring {
                render_configuration_ui(f, app_state);
                if app_state.popup.is_active {
                    render_popup(f, app_state);
                }
            } else {
                render_installation_ui(f, app_state);
            }
        }
    }
}

fn render_configuration_ui(f: &mut Frame, app_state: &mut InstallerState) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(7),  // Header
            Constraint::Length(3),  // Title
            Constraint::Min(10),    // Configuration options
            Constraint::Length(3),  // Instructions
            Constraint::Length(3),  // Start button
        ])
        .split(f.area());

    // Header with ASCII art
    render_header(f, chunks[0]);

    // Title
    let title = Paragraph::new("Arch Linux Installation Configuration")
        .block(Block::default().borders(Borders::ALL))
        .alignment(Alignment::Center)
        .style(Style::default().fg(Color::Cyan));
    f.render_widget(title, chunks[1]);

    // Configuration options - Correct order with hostname between GPU drivers and username
    let config_items = vec![
        // Boot Setup (0-1)
        ListItem::new(format!("Boot Mode: {}", if app_state.config_values[0].is_empty() { "[Press Enter]" } else { &app_state.config_values[0] }))
            .style(if app_state.config_step == 0 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Secure Boot: {}", if app_state.config_values[1].is_empty() { "[Press Enter]" } else { &app_state.config_values[1] }))
            .style(if app_state.config_step == 1 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        
        // System Locale and Input (2-3)
        ListItem::new(format!("Locale: {}", if app_state.config_values[2].is_empty() { "[Press Enter]" } else { &app_state.config_values[2] }))
            .style(if app_state.config_step == 2 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Keymap: {}", if app_state.config_values[3].is_empty() { "[Press Enter]" } else { &app_state.config_values[3] }))
            .style(if app_state.config_step == 3 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        
        // Disk and Storage (4-14)
        ListItem::new(format!("Disk: {}", if app_state.config_values[4].is_empty() { "[Press Enter]" } else { &app_state.config_values[4] }))
            .style(if app_state.config_step == 4 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        {
            let strategy_text = if app_state.config_values[5].is_empty() {
                "[Press Enter]".to_string()
            } else {
                format!("{} [Press Enter to change]", app_state.config_values[5])
            };
            ListItem::new(format!("Partitioning Strategy: {}", strategy_text))
        }
            .style(if app_state.config_step == 5 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        {
            let encryption_text = if app_state.config_values[6].is_empty() {
                "[Press Enter]".to_string()
            } else {
                let value = &app_state.config_values[6];
                let strategy = &app_state.config_values[5];
                if (strategy.contains("luks") && value == "yes") || (!strategy.contains("luks") && value == "no") {
                    format!("{} (auto-set)", value)
                } else {
                    format!("{} [Press Enter to change]", value)
                }
            };
            ListItem::new(format!("Encryption: {}", encryption_text))
        }
            .style(if app_state.config_step == 6 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Root Filesystem: {}", if app_state.config_values[7].is_empty() { "[Press Enter]" } else { &app_state.config_values[7] }))
            .style(if app_state.config_step == 7 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Separate Home Partition: {}", if app_state.config_values[8].is_empty() { "[Press Enter]" } else { &app_state.config_values[8] }))
            .style(if app_state.config_step == 8 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Home Filesystem: {}", if app_state.config_values[9].is_empty() { "[Press Enter]" } else { &app_state.config_values[9] }))
            .style(if app_state.config_step == 9 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Swap: {}", if app_state.config_values[10].is_empty() { "[Press Enter]" } else { &app_state.config_values[10] }))
            .style(if app_state.config_step == 10 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Btrfs Snapshots: {}", if app_state.config_values[11].is_empty() { "[Press Enter]" } else { &app_state.config_values[11] }))
            .style(if app_state.config_step == 11 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Btrfs Frequency: {}", if app_state.config_values[12].is_empty() { "[Press Enter]" } else { &app_state.config_values[12] }))
            .style(if app_state.config_step == 12 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Btrfs Keep Count: {}", if app_state.config_values[13].is_empty() { "[Press Enter]" } else { &app_state.config_values[13] }))
            .style(if app_state.config_step == 13 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Btrfs Assistant: {}", if app_state.config_values[14].is_empty() { "[Press Enter]" } else { &app_state.config_values[14] }))
            .style(if app_state.config_step == 14 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        
        // Time and Location (15-17)
        ListItem::new(format!("Timezone Region: {}", if app_state.config_values[15].is_empty() { "[Press Enter]" } else { &app_state.config_values[15] }))
            .style(if app_state.config_step == 15 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Timezone: {}", if app_state.config_values[16].is_empty() { "[Press Enter]" } else { &app_state.config_values[16] }))
            .style(if app_state.config_step == 16 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Time Sync (NTP): {}", if app_state.config_values[17].is_empty() { "[Press Enter]" } else { &app_state.config_values[17] }))
            .style(if app_state.config_step == 17 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        
        // System Packages (19-23)
        ListItem::new(format!("Mirror Country: {}", if app_state.config_values[18].is_empty() { "[Press Enter]" } else { &app_state.config_values[18] }))
            .style(if app_state.config_step == 18 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Kernel: {}", if app_state.config_values[19].is_empty() { "[Press Enter]" } else { &app_state.config_values[19] }))
            .style(if app_state.config_step == 19 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Multilib: {}", if app_state.config_values[20].is_empty() { "[Press Enter]" } else { &app_state.config_values[20] }))
            .style(if app_state.config_step == 20 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Additional Pacman Packages: {}", get_selected_packages("pacman")))
            .style(if app_state.config_step == 21 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("GPU Drivers: {}", if app_state.config_values[22].is_empty() { "[Press Enter]" } else { &app_state.config_values[22] }))
            .style(if app_state.config_step == 22 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        
        // Hostname (23) - moved between GPU drivers and username
        ListItem::new(format!("Hostname: {}", if app_state.editing_field == Some(23) { 
                format!("{}_", app_state.current_input) 
        } else if app_state.config_values[23].is_empty() { 
                "[Press Enter]".to_string() 
            } else { 
            app_state.config_values[23].clone() 
        }))
            .style(if app_state.config_step == 23 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        
        // User Setup (24-26)
        ListItem::new(format!("Username: {}", if app_state.editing_field == Some(24) { 
            format!("{}_", app_state.current_input) 
        } else if app_state.config_values[24].is_empty() { 
            "[Press Enter]".to_string() 
        } else { 
            app_state.config_values[24].clone() 
        }))
            .style(if app_state.config_step == 24 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("User Password: {}", if app_state.editing_field == Some(25) { 
            format!("{}_", app_state.current_input) 
        } else if app_state.config_values[25].is_empty() { 
            "[Press Enter]".to_string() 
        } else { 
            "***".to_string() 
        }))
            .style(if app_state.config_step == 25 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Root Password: {}", if app_state.editing_field == Some(26) { 
            format!("{}_", app_state.current_input) 
        } else if app_state.config_values[26].is_empty() { 
            "[Press Enter]".to_string() 
        } else { 
            "***".to_string() 
        }))
            .style(if app_state.config_step == 26 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        
        // Package Management (28-30)
        ListItem::new(format!("AUR Helper: {}", if app_state.config_values[27].is_empty() { "[Press Enter]" } else { &app_state.config_values[27] }))
            .style(if app_state.config_step == 27 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Additional AUR Packages: {}", get_selected_packages("aur")))
            .style(if app_state.config_step == 28 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Flatpak: {}", if app_state.config_values[29].is_empty() { "[Press Enter]" } else { &app_state.config_values[29] }))
            .style(if app_state.config_step == 29 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        
        // Boot Configuration (31-33)
        ListItem::new(format!("Bootloader: {}", if app_state.config_values[30].is_empty() { "[Press Enter]" } else { &app_state.config_values[30] }))
            .style(if app_state.config_step == 30 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("OS Prober: {}", if app_state.config_values[31].is_empty() { "[Press Enter]" } else { &app_state.config_values[31] }))
            .style(if app_state.config_step == 31 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("GRUB Theme: {}", if app_state.config_values[32].is_empty() { "[Press Enter]" } else { &app_state.config_values[32] }))
            .style(if app_state.config_step == 32 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        
        // Desktop Environment (34-35)
        ListItem::new(format!("Desktop Environment: {}", if app_state.config_values[33].is_empty() { "[Press Enter]" } else { &app_state.config_values[33] }))
            .style(if app_state.config_step == 33 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Display Manager: {}", if app_state.config_values[34].is_empty() { 
            let desktop_env = &app_state.config_values[33];
            if desktop_env == "none" || desktop_env.is_empty() { 
                "[Press Enter]".to_string() 
            } else { 
                "[Auto-selected]".to_string() 
            }
        } else { 
            app_state.config_values[34].clone()
        }))
            .style(if app_state.config_step == 34 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        
        // Boot Splash and Final Setup (36-39)
        ListItem::new(format!("Plymouth: {}", if app_state.config_values[35].is_empty() { "[Press Enter]" } else { &app_state.config_values[35] }))
            .style(if app_state.config_step == 35 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Plymouth Theme: {}", if app_state.config_values[36].is_empty() { "[Press Enter]" } else { &app_state.config_values[36] }))
            .style(if app_state.config_step == 36 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Numlock on Boot: {}", if app_state.config_values[37].is_empty() { "[Press Enter]" } else { &app_state.config_values[37] }))
            .style(if app_state.config_step == 37 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Git Repository: {}", if app_state.config_values[38].is_empty() { "[Press Enter]" } else { &app_state.config_values[38] }))
            .style(if app_state.config_step == 38 { Style::default().fg(Color::Yellow) } else { Style::default() }),
    ];

    let config_list = List::new(config_items)
        .block(Block::default().title("Configuration Options").borders(Borders::ALL));
    f.render_widget(config_list, chunks[2]);

    // Instructions
    let instructions = if app_state.popup.is_active {
        "Use ↑↓ to navigate, Enter to select, Esc to return to main menu"
    } else {
        "Use ↑↓ to navigate, Enter to open popup, 'q' to quit installer"
    };
    let instruction_text = Paragraph::new(instructions)
        .block(Block::default().borders(Borders::NONE))
        .alignment(Alignment::Center)
        .style(Style::default().fg(Color::Yellow));
    f.render_widget(instruction_text, chunks[3]);

    // Start button
    let start_button_text = if app_state.config_step == 39 {
        "> START INSTALLATION <"
    } else {
        "  START INSTALLATION  "
    };
    let start_button = Paragraph::new(start_button_text)
        .block(Block::default().borders(Borders::ALL))
        .alignment(Alignment::Center)
        .style(if app_state.config_step == 39 { 
            Style::default().fg(Color::Black).bg(Color::Green) 
        } else { 
            Style::default().fg(Color::Green) 
        });
    f.render_widget(start_button, chunks[4]);
}

fn render_installation_ui(f: &mut Frame, app_state: &mut InstallerState) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(7),  // Header
            Constraint::Length(3),  // Progress bar
            Constraint::Length(3),  // Status message
            Constraint::Length(8),  // Configuration panel
            Constraint::Min(5),     // Installer output (minimum 5 lines)
            Constraint::Length(3),  // Instructions
        ])
        .split(f.area());

    // Header with ASCII art
    render_header(f, chunks[0]);

    // Progress bar
    render_progress(f, chunks[1], app_state);

    // Status message
    render_status(f, chunks[2], app_state);

    // Configuration panel
    render_config(f, chunks[3], app_state);

    // Installer output
    render_output(f, chunks[4], app_state);

    // Instructions
    render_instructions(f, chunks[5], app_state);
}


fn render_header(f: &mut Frame, area: Rect) {
    // Ensure we have a valid area
    if area.width == 0 || area.height == 0 {
        return;
    }
    
    let header_text = vec![
        Line::from(vec![
            Span::styled("  █████╗ ██████╗  ██████╗██╗  ██╗██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ", Style::default().fg(Color::Cyan)),
        ]),
        Line::from(vec![
            Span::styled(" ██╔══██╗██╔══██╗██╔════╝██║  ██║██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ", Style::default().fg(Color::Cyan)),
        ]),
        Line::from(vec![
            Span::styled(" ███████║██████╔╝██║     ███████║██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     ", Style::default().fg(Color::Cyan)),
        ]),
        Line::from(vec![
            Span::styled(" ██╔══██║██╔══██╗██║     ██╔══██║██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ", Style::default().fg(Color::Cyan)),
        ]),
        Line::from(vec![
            Span::styled(" ██║  ██║██║  ██║╚██████╗██║  ██║██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗", Style::default().fg(Color::Cyan)),
        ]),
        Line::from(vec![
            Span::styled(" ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝", Style::default().fg(Color::Cyan)),
        ]),
    ];

    let header = Paragraph::new(header_text)
        .block(Block::default().borders(Borders::NONE))
        .alignment(Alignment::Center);

    f.render_widget(header, area);
}

fn render_progress(f: &mut Frame, area: Rect, app_state: &mut InstallerState) {
    // Ensure we have a valid area
    if area.width == 0 || area.height == 0 {
        return;
    }
    
    let title = format!("{} - {}%", app_state.current_phase, app_state.progress);
    let progress = Gauge::default()
        .block(Block::default().title(title).borders(Borders::ALL))
        .gauge_style(Style::default().fg(Color::Cyan))
        .percent(app_state.progress.into());

    f.render_widget(progress, area);
}

fn render_status(f: &mut Frame, area: Rect, app_state: &mut InstallerState) {
    // Ensure we have a valid area
    if area.width == 0 || area.height == 0 {
        return;
    }
    
    // Calculate available width for text (accounting for borders and padding)
    let available_width = if area.width > 4 { area.width - 4 } else { 1 };
    
    let status_text = if app_state.status_message.len() > available_width as usize {
        format!("{}...", &app_state.status_message[..(available_width as usize - 3)])
    } else {
        app_state.status_message.clone()
    };

    let status = Paragraph::new(status_text)
        .block(Block::default().title("Status").borders(Borders::ALL))
        .style(Style::default().fg(Color::White))
        .wrap(Wrap { trim: true });

    f.render_widget(status, area);
}

fn render_config(f: &mut Frame, area: Rect, app_state: &mut InstallerState) {
    // Ensure we have a valid area
    if area.width == 0 || area.height == 0 {
        return;
    }
    
    let config_items = vec![
        // Network and Boot Setup
        ListItem::new(format!("Wi-Fi Connection: {}", app_state.config_values[0])),
        ListItem::new(format!("Boot Mode: {}", app_state.config_values[1])),
        ListItem::new(format!("Secure Boot: {}", app_state.config_values[2])),
        
        // System Locale and Input
        ListItem::new(format!("Locale: {}", app_state.config_values[3])),
        ListItem::new(format!("Keymap: {}", app_state.config_values[4])),
        
        // Disk and Storage
        ListItem::new(format!("Disk: {}", app_state.config_values[5])),
        ListItem::new(format!("Partitioning: {}", app_state.config_values[6])),
        ListItem::new(format!("Encryption: {}", app_state.config_values[7])),
        ListItem::new(format!("Root Filesystem: {}", app_state.config_values[8])),
        ListItem::new(format!("Separate Home Partition: {}", app_state.config_values[9])),
        ListItem::new(format!("Home Filesystem: {}", app_state.config_values[10])),
        ListItem::new(format!("Swap: {}", app_state.config_values[11])),
        ListItem::new(format!("Btrfs Snapshots: {}", app_state.config_values[12])),
        ListItem::new(format!("Btrfs Frequency: {}", app_state.config_values[13])),
        ListItem::new(format!("Btrfs Keep Count: {}", app_state.config_values[14])),
        ListItem::new(format!("Btrfs Assistant: {}", app_state.config_values[15])),
        
        // Time and Location
        ListItem::new(format!("Timezone: {}", app_state.config_values[16])),
        ListItem::new(format!("Region: {}", app_state.config_values[17])),
        ListItem::new(format!("Time Sync (NTP): {}", app_state.config_values[18])),
        
        // System Packages
        ListItem::new(format!("Mirror Country: {}", app_state.config_values[19])),
        ListItem::new(format!("Kernel: {}", app_state.config_values[20])),
        ListItem::new(format!("Multilib: {}", app_state.config_values[21])),
        ListItem::new(format!("Additional Pacman Packages: {}", if app_state.config_values[22].is_empty() { "[Press Enter]" } else { &app_state.config_values[22] })),
        ListItem::new(format!("GPU Drivers: {}", app_state.config_values[22])),
        ListItem::new(format!("Hostname: {}", app_state.config_values[23])),
        
        // User Setup
        ListItem::new(format!("Username: {}", app_state.config_values[24])),
        ListItem::new(format!("User Password: {}", if app_state.config_values[25].is_empty() { "Not set" } else { "***" })),
        ListItem::new(format!("Root Password: {}", if app_state.config_values[26].is_empty() { "Not set" } else { "***" })),
        
        // Package Management
        ListItem::new(format!("AUR Helper: {}", app_state.config_values[27])),
        ListItem::new(format!("Additional AUR Packages: {}", if app_state.config_values[28].is_empty() { "[Press Enter]" } else { &app_state.config_values[28] })),
        ListItem::new(format!("Flatpak: {}", app_state.config_values[29])),
        
        // Boot Configuration
        ListItem::new(format!("Bootloader: {}", app_state.config_values[30])),
        ListItem::new(format!("OS Prober: {}", app_state.config_values[31])),
        ListItem::new(format!("GRUB Theme: {}", app_state.config_values[32])),
        
        // Desktop Environment
        ListItem::new(format!("Desktop Environment: {}", app_state.config_values[33])),
        ListItem::new(format!("Display Manager: {}", app_state.config_values[34])),
        
        // Boot Splash and Final Setup
        ListItem::new(format!("Plymouth: {}", app_state.config_values[35])),
        ListItem::new(format!("Plymouth Theme: {}", app_state.config_values[36])),
        ListItem::new(format!("Numlock on Boot: {}", app_state.config_values[37])),
        ListItem::new(format!("Git Repository: {}", app_state.config_values[38])),
    ];

    let config_list = List::new(config_items)
        .block(Block::default().title("Configuration").borders(Borders::ALL));

    f.render_widget(config_list, area);
}

fn render_output(f: &mut Frame, area: Rect, app_state: &mut InstallerState) {
    // Ensure we have a valid area
    if area.width == 0 || area.height == 0 {
        return;
    }
    
    let output_items: Vec<ListItem> = app_state.installer_output
        .iter()
        .map(|line| ListItem::new(line.clone()))
        .collect();

    // Calculate how many items can fit in the area
    let available_height = if area.height > 2 { area.height - 2 } else { 1 };
    let total_items = output_items.len();
    
    // Auto-scroll to bottom (show latest output)
    let start_index = total_items.saturating_sub(available_height as usize);

    let visible_items: Vec<ListItem> = output_items
        .into_iter()
        .skip(start_index)
        .collect();

    let output_list = List::new(visible_items)
        .block(Block::default().title("Installer Output").borders(Borders::ALL));

    f.render_widget(output_list, area);
}

fn render_instructions(f: &mut Frame, area: Rect, app_state: &mut InstallerState) {
    // Ensure we have a valid area
    if area.width == 0 || area.height == 0 {
        return;
    }
    
    let instructions = if app_state.is_running && !app_state.is_complete {
        "Installation in progress... Press 'q' to quit"
    } else if app_state.is_complete {
        if app_state.current_phase == "Failed" {
            "Installation failed! Press 'q' to quit and check logs"
        } else {
        "Installation complete! Press 'q' to quit"
        }
    } else {
        "Press 's' to start installation, 'q' to quit"
    };

    let color = if app_state.current_phase == "Failed" {
        Color::Red
    } else if app_state.is_complete {
        Color::Green
    } else {
        Color::Yellow
    };

    let instruction_text = Paragraph::new(instructions)
        .block(Block::default().borders(Borders::NONE))
        .alignment(Alignment::Center)
        .style(Style::default().fg(color));

    f.render_widget(instruction_text, area);
}

fn render_popup(f: &mut Frame, app_state: &mut InstallerState) {
    let size = f.area();
    
    // Calculate popup size and position (centered)
    let popup_width = (size.width * 3 / 4).min(60);
    let popup_height = if matches!(app_state.popup.popup_type, PopupType::SecureBoot) {
        (size.height * 4 / 5).min(25) // Larger popup for secure boot warnings
    } else {
        (size.height * 3 / 4).min(20)
    };
    let popup_x = (size.width - popup_width) / 2;
    let popup_y = (size.height - popup_height) / 2;
    
    let popup_area = Rect::new(popup_x, popup_y, popup_width, popup_height);
    
    // Clear the popup area
    f.render_widget(Clear, popup_area);
    
    // Create popup content based on type
    match &app_state.popup.popup_type {
        PopupType::TextInput(_) => {
            // Text input popup
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .margin(1)
                .constraints([
                    Constraint::Length(3), // Title
                    Constraint::Length(3), // Input field
                    Constraint::Length(3), // Instructions
                ])
                .split(popup_area);
            
            // Title
            let title = Paragraph::new(app_state.popup.title.as_str())
                .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
                .alignment(Alignment::Center)
                .block(Block::default().borders(Borders::ALL));
            f.render_widget(title, chunks[0]);
            
            // Input field
            let input_text = if matches!(&app_state.popup.popup_type, PopupType::TextInput(field_name) if field_name.contains("Password")) {
                format!("{}_", "*".repeat(app_state.current_input.len()))
            } else {
                format!("{}_", app_state.current_input)
            };
            let input = Paragraph::new(input_text)
                .style(Style::default().fg(Color::Yellow))
                .block(Block::default().borders(Borders::ALL).title("Input"));
            f.render_widget(input, chunks[1]);
            
            // Instructions
            let instructions = Paragraph::new("Type your input and press Enter to confirm, Esc to return to main menu")
                .style(Style::default().fg(Color::Green))
                .alignment(Alignment::Center);
            f.render_widget(instructions, chunks[2]);
        }
        PopupType::PackageSelection => {
            // Simple bash session emulation for package selection
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .margin(1)
                .constraints([
                    Constraint::Length(3), // Title
                    Constraint::Min(15), // Bash output
                    Constraint::Length(3), // Input line
                ])
                .split(popup_area);
            
            // Title
            let title = Paragraph::new(app_state.popup.title.as_str())
                .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
                .alignment(Alignment::Center)
                .block(Block::default().borders(Borders::ALL));
            f.render_widget(title, chunks[0]);
            
            // Bash output (scrollable)
            let output_text = app_state.popup.bash_output.join("\n");
            let output = Paragraph::new(output_text)
                .style(Style::default().fg(Color::White))
                .alignment(Alignment::Left)
                .block(Block::default().borders(Borders::ALL).title("Output"));
            f.render_widget(output, chunks[1]);
            
            // Input line
            let input_text = format!("{}{}_", app_state.popup.bash_prompt, app_state.current_input);
            let input = Paragraph::new(input_text)
                .style(Style::default().fg(Color::Yellow))
                .alignment(Alignment::Left)
                .block(Block::default().borders(Borders::ALL).title("Command"));
            f.render_widget(input, chunks[2]);
        }
        PopupType::SecureBoot => {
            // Special secure boot popup with warnings
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .margin(1)
                .constraints([
                    Constraint::Length(3), // Title
                    Constraint::Length(15), // Warning text
                    Constraint::Length(3), // Options list
                    Constraint::Length(3), // Instructions
                ])
                .split(popup_area);
            
            // Title
            let title = Paragraph::new("⚠️ SECURE BOOT WARNING ⚠️")
                .style(Style::default().fg(Color::Red).add_modifier(Modifier::BOLD))
                .alignment(Alignment::Center)
                .block(Block::default().borders(Borders::ALL));
            f.render_widget(title, chunks[0]);
            
            // Warning text
            let warning_text = "Secure Boot is ONLY needed if:\n\
• You dual-boot with Windows 11\n\
• You play games requiring TPM/Secure Boot\n\
• You have enterprise security requirements\n\n\
IMPORTANT: Before enabling Secure Boot:\n\
1. Disable Secure Boot in your UEFI firmware\n\
2. Clear all existing Secure Boot keys\n\
3. Ensure your motherboard supports custom key enrollment\n\n\
WARNING: If not configured properly, your system may not boot!\n\
Most users should answer 'no' to this question.";
            
            let warning = Paragraph::new(warning_text)
                .style(Style::default().fg(Color::Yellow))
                .alignment(Alignment::Left)
                .block(Block::default().borders(Borders::ALL).title("Requirements & Risks"));
            f.render_widget(warning, chunks[1]);
            
            // Options list with scrolling for long lists
            let total_options = app_state.popup.options.len();
            let max_visible = (chunks[2].height as usize).saturating_sub(2); // Account for borders
            
            let start_index = if total_options > max_visible {
                let selected = app_state.popup.selected_index;
                if selected < max_visible / 2 {
                    0
                } else if selected >= total_options - max_visible / 2 {
                    total_options.saturating_sub(max_visible)
                } else {
                    selected - max_visible / 2
                }
            } else {
                0
            };
            
            let end_index = (start_index + max_visible).min(total_options);
            
            let options: Vec<ListItem> = app_state.popup.options
                .iter()
                .enumerate()
                .skip(start_index)
                .take(end_index - start_index)
                .map(|(i, option)| {
                    let style = if i == app_state.popup.selected_index {
                        Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
                    } else {
                        Style::default()
                    };
                    ListItem::new(option.clone()).style(style)
                })
                .collect();
            
            let options_list = List::new(options)
                .block(Block::default().borders(Borders::ALL).title("Your Choice"));
            f.render_widget(options_list, chunks[2]);
            
            // Instructions
            let instructions = Paragraph::new("Use ↑↓ to navigate, Enter to select, Esc to return to main menu")
                .style(Style::default().fg(Color::Green))
                .alignment(Alignment::Center);
            f.render_widget(instructions, chunks[3]);
        }
        _ => {
            // Selection popup
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .margin(1)
                .constraints([
                    Constraint::Length(3), // Title
                    Constraint::Min(0),    // Options list
                    Constraint::Length(3), // Instructions
                ])
                .split(popup_area);
            
            // Title
            let title = Paragraph::new(app_state.popup.title.as_str())
                .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
                .alignment(Alignment::Center)
                .block(Block::default().borders(Borders::ALL));
            f.render_widget(title, chunks[0]);
            
            // Options list with scrolling for long lists
            let total_options = app_state.popup.options.len();
            let max_visible = (chunks[1].height as usize).saturating_sub(2); // Account for borders
            
            let start_index = if total_options > max_visible {
                let selected = app_state.popup.selected_index;
                if selected < max_visible / 2 {
                    0
                } else if selected >= total_options - max_visible / 2 {
                    total_options.saturating_sub(max_visible)
                } else {
                    selected - max_visible / 2
                }
            } else {
                0
            };
            
            let end_index = (start_index + max_visible).min(total_options);
            
            let options: Vec<ListItem> = app_state.popup.options
                .iter()
                .enumerate()
                .skip(start_index)
                .take(end_index - start_index)
                .map(|(i, option)| {
                    let style = if i == app_state.popup.selected_index {
                        Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
                    } else {
                        Style::default()
                    };
                    ListItem::new(option.clone()).style(style)
                })
                .collect();
            
            let options_list = List::new(options)
                .block(Block::default().borders(Borders::ALL));
            f.render_widget(options_list, chunks[1]);
            
            // Instructions
            let instructions = Paragraph::new("Use ↑↓ to navigate, Enter to select, Esc to return to main menu")
                .style(Style::default().fg(Color::Green))
                .alignment(Alignment::Center);
            f.render_widget(instructions, chunks[2]);
        }
    }
}

fn restore_terminal() -> Result<(), Box<dyn std::error::Error>> {
    // Restore terminal state
    crossterm::terminal::disable_raw_mode()?;
    crossterm::execute!(stdout(), crossterm::terminal::LeaveAlternateScreen)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::sync::Mutex;

    // Test data structures
    fn create_test_package() -> Package {
        Package {
            repo: "core".to_string(),
            name: "linux".to_string(),
            version: "6.6.1.arch1-1".to_string(),
            installed: false,
            description: "The Linux kernel and modules".to_string(),
        }
    }

    fn create_test_installer_state() -> InstallerState {
        InstallerState {
            current_phase: "Configuration".to_string(),
            progress: 0,
            status_message: "Test status".to_string(),
            installer_output: vec!["Test output".to_string()],
            is_running: false,
            is_complete: false,
            is_configuring: true,
            config_step: 0,
            config_values: vec!["test".to_string(); 39],
            current_input: "".to_string(),
            input_mode: false,
            popup: PopupState {
                popup_type: PopupType::DiskSelection,
                is_active: false,
                selected_index: 0,
                options: vec!["/dev/sda".to_string()],
                title: "Test Popup".to_string(),
                bash_output: vec![],
                bash_prompt: "$ ".to_string(),
            },
            editing_field: None,
            focus: Focus::Configuration,
        }
    }

    #[test]
    fn test_package_creation() {
        let package = create_test_package();
        assert_eq!(package.repo, "core");
        assert_eq!(package.name, "linux");
        assert!(!package.installed);
    }

    #[test]
    fn test_installer_state_creation() {
        let state = create_test_installer_state();
        assert_eq!(state.current_phase, "Configuration");
        assert_eq!(state.progress, 0);
        assert!(!state.is_running);
        assert_eq!(state.config_values.len(), 39);
    }

    #[test]
    fn test_is_text_input_field() {
        // Test hostname field (step 23)
        assert!(is_text_input_field(23));
        
        // Test username field (step 24)
        assert!(is_text_input_field(24));
        
        // Test password fields (steps 25, 26)
        assert!(is_text_input_field(25));
        assert!(is_text_input_field(26));
        
        // Test non-text fields
        assert!(!is_text_input_field(0)); // Boot mode
        assert!(!is_text_input_field(4)); // Disk selection
        assert!(!is_text_input_field(5)); // Partition strategy
    }

    #[test]
    fn test_get_selected_packages() {
        // Test with empty package list - should return default prompt
        let result = get_selected_packages("core");
        assert_eq!(result, "[Press Enter]");
        
        // Test with package list - should return default prompt when no packages selected
        let result = get_selected_packages("linux");
        assert_eq!(result, "[Press Enter]");
    }

    #[test]
    fn test_popup_type_options() {
        // Test disk popup
        let (options, title) = get_popup_options(&PopupType::DiskSelection);
        assert!(!options.is_empty());
        assert_eq!(title, "Select Installation Disk");
        
        // Test partition strategy popup
        let (options, title) = get_popup_options(&PopupType::PartitioningStrategy);
        assert!(!options.is_empty());
        assert_eq!(title, "Select Partitioning Strategy");
        
        // Test RAID level popup
        let (options, title) = get_popup_options(&PopupType::RAIDLevel);
        assert!(!options.is_empty());
        assert_eq!(title, "Select RAID Level");
    }

    #[test]
    fn test_progress_update_parsing() {
        let json_str = r#"{"message_type":"Progress","phase":"DiskPartitioning","progress":30,"message":"Starting disk partitioning...","timestamp":"2024-01-01T12:00:00Z"}"#;
        
        let result: Result<ProgressUpdate, serde_json::Error> = serde_json::from_str(json_str);
        assert!(result.is_ok());
        
        let progress = result.unwrap();
        assert_eq!(progress.message_type, MessageType::Progress);
        assert_eq!(progress.phase, InstallationPhase::DiskPartitioning);
        assert_eq!(progress.progress, 30);
        assert_eq!(progress.message, "Starting disk partitioning...");
    }

    #[test]
    fn test_installer_state_default() {
        let state = InstallerState::default();
        assert_eq!(state.current_phase, "Configuration");
        assert_eq!(state.progress, 0);
        assert!(!state.is_running);
        assert_eq!(state.config_values.len(), 39);
        assert_eq!(state.config_step, 0);
    }

    #[test]
    fn test_popup_state_creation() {
        let popup = PopupState {
            popup_type: PopupType::DiskSelection,
            is_active: true,
            selected_index: 0,
            options: vec!["/dev/sda".to_string(), "/dev/sdb".to_string()],
            title: "Select Disk".to_string(),
            bash_output: vec![],
            bash_prompt: "$ ".to_string(),
        };
        
        assert_eq!(popup.popup_type, PopupType::DiskSelection);
        assert!(popup.is_active);
        assert_eq!(popup.selected_index, 0);
        assert_eq!(popup.options.len(), 2);
        assert_eq!(popup.title, "Select Disk");
    }

    #[test]
    fn test_installation_phase_enum() {
        let phase = InstallationPhase::DiskPartitioning;
        match phase {
            InstallationPhase::DiskPartitioning => {},
            _ => unreachable!(),
        }
    }

    #[test]
    fn test_message_type_enum() {
        let msg_type = MessageType::Progress;
        match msg_type {
            MessageType::Progress => {},
            _ => unreachable!(),
        }
    }

    #[test]
    fn test_popup_type_enum() {
        let popup_type = PopupType::DiskSelection;
        match popup_type {
            PopupType::DiskSelection => {},
            _ => unreachable!(),
        }
    }

    #[test]
    fn test_config_values_initialization() {
        let state = create_test_installer_state();
        
        // Test that all config values are initialized
        assert_eq!(state.config_values.len(), 39);
        
        // Test specific config values
        assert_eq!(state.config_values[0], "test"); // Boot mode
        assert_eq!(state.config_values[23], "test"); // Hostname
        assert_eq!(state.config_values[24], "test"); // Username
        assert_eq!(state.config_values[25], "test"); // User password
        assert_eq!(state.config_values[26], "test"); // Root password
    }

    #[test]
    fn test_installer_state_fields() {
        let mut state = create_test_installer_state();
        
        // Test initial state
        assert_eq!(state.current_input, "");
        assert!(!state.input_mode);
        assert_eq!(state.editing_field, None);
        assert!(!state.is_complete);
        assert!(state.is_configuring);
        
        // Test state changes
        state.current_input = "test input".to_string();
        state.input_mode = true;
        state.editing_field = Some(0);
        
        assert_eq!(state.current_input, "test input");
        assert!(state.input_mode);
        assert_eq!(state.editing_field, Some(0));
    }

    #[test]
    fn test_installer_output() {
        let mut state = create_test_installer_state();
        
        // Test initial output
        assert_eq!(state.installer_output.len(), 1);
        assert_eq!(state.installer_output[0], "Test output");
        
        // Test adding output
        state.installer_output.push("New output line".to_string());
        assert_eq!(state.installer_output.len(), 2);
        assert_eq!(state.installer_output[1], "New output line");
    }

    #[test]
    fn test_config_step_navigation() {
        let mut state = create_test_installer_state();
        
        // Test initial step
        assert_eq!(state.config_step, 0);
        
        // Test step increment
        state.config_step = 5;
        assert_eq!(state.config_step, 5);
        
        // Test step bounds (should wrap around)
        state.config_step = 39; // Last config step
        assert_eq!(state.config_step, 39);
        
        // Test start button step
        state.config_step = 39; // Start button
        assert_eq!(state.config_step, 39);
    }

    #[test]
    fn test_popup_navigation() {
        let mut popup = PopupState {
            popup_type: PopupType::DiskSelection,
            is_active: true,
            selected_index: 0,
            options: vec!["/dev/sda".to_string(), "/dev/sdb".to_string(), "/dev/sdc".to_string()],
            title: "Select Disk".to_string(),
            bash_output: vec![],
            bash_prompt: "$ ".to_string(),
        };
        
        // Test initial selection
        assert_eq!(popup.selected_index, 0);
        
        // Test moving down
        popup.selected_index = 1;
        assert_eq!(popup.selected_index, 1);
        
        // Test wrapping around
        popup.selected_index = 2; // Last option
        assert_eq!(popup.selected_index, 2);
        
        // Test wrapping back to beginning
        popup.selected_index = 0;
        assert_eq!(popup.selected_index, 0);
    }

    #[test]
    fn test_progress_update_serialization() {
        let progress = ProgressUpdate {
            message_type: MessageType::Progress,
            phase: InstallationPhase::DiskPartitioning,
            progress: 30,
            message: "Starting disk partitioning...".to_string(),
            timestamp: Some("2024-01-01T12:00:00Z".to_string()),
        };
        
        let json = serde_json::to_string(&progress).unwrap();
        assert!(json.contains("Progress"));
        assert!(json.contains("DiskPartitioning"));
        assert!(json.contains("30"));
        assert!(json.contains("Starting disk partitioning"));
    }

    #[test]
    fn test_installer_state_mutex() {
        let state = Arc::new(Mutex::new(create_test_installer_state()));
        
        // Test that we can lock and modify the state
        {
            let mut state_guard = state.lock().unwrap();
            state_guard.progress = 50;
            state_guard.current_phase = "Installing".to_string();
        }
        
        // Test that changes persist
        {
            let state_guard = state.lock().unwrap();
            assert_eq!(state_guard.progress, 50);
            assert_eq!(state_guard.current_phase, "Installing");
        }
    }

    #[test]
    fn test_package_serialization() {
        let package = create_test_package();
        
        let json = serde_json::to_string(&package).unwrap();
        assert!(json.contains("core"));
        assert!(json.contains("linux"));
        assert!(json.contains("6.6.1.arch1-1"));
        assert!(json.contains("false")); // installed field
        assert!(json.contains("The Linux kernel"));
    }

    #[test]
    fn test_enum_serialization() {
        let phase = InstallationPhase::PackageInstallation;
        let json = serde_json::to_string(&phase).unwrap();
        assert!(json.contains("PackageInstallation"));
        
        let msg_type = MessageType::Error;
        let json = serde_json::to_string(&msg_type).unwrap();
        assert!(json.contains("Error"));
    }
}