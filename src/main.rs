use ratatui::{
    backend::CrosstermBackend,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Style, Modifier},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, List, ListItem, Paragraph, Wrap, Clear},
    Frame, Terminal,
};
use std::io::{stdout, BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};
use std::thread;
use std::time::Duration;
use crossterm::event::{Event, KeyCode, KeyEvent, KeyModifiers, MouseEvent};

// Global interrupt flag
static INTERRUPTED: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Clone)]
pub enum PopupType {
    None,
    DiskSelection,
    PartitioningStrategy,
    DesktopEnvironment,
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
    ManualPartitioning,
    PackageSelection, // Simple bash session for package selection
    TextInput(String), // Field name
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

// PackageSelection using simple text input
pub struct PackageSelection {
    current_input: String,
    output_lines: Vec<String>,
    scroll_offset: usize,
    package_list: String,
    is_pacman: bool,
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
            "search fastfetch".to_string(),
            "add fastfetch neofetch htop".to_string(),
            "".to_string(),
        ];
        
        if is_pacman {
            output_lines.push("Package selection> ".to_string());
        } else {
            output_lines.push("AUR package selection> ".to_string());
        }
        
        Self {
            current_input: String::new(),
            output_lines,
            scroll_offset: 0,
            package_list: String::new(),
            is_pacman,
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
            .title_bottom("Type commands, Enter to execute, Ctrl-C to exit")
            .style(Style::default().bg(Color::Black).fg(Color::White));

        let inner_area = Rect {
            x: area.x + 1,
            y: area.y + 1,
            width: area.width.saturating_sub(2),
            height: area.height.saturating_sub(2),
        };

        // Create list items from output lines
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

    fn handle_key_event(&mut self, key: &KeyEvent) -> bool {
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
                                self.output_lines.push(format!("Found packages matching '{}':", term));
                                self.output_lines.push(format!("  {}-1.0-1 (Package 1)", term));
                                self.output_lines.push(format!("  {}-2.0-1 (Package 2)", term));
                                self.output_lines.push(format!("  {}-3.0-1 (Package 3)", term));
                            } else {
                                self.output_lines.push("Usage: search <term>".to_string());
                            }
                        }
                        "add" => {
                            if parts.len() > 1 {
                                let packages = parts[1..].join(" ");
                                self.package_list.push_str(&packages);
                                self.package_list.push(' ');
                                self.output_lines.push(format!("Added packages: {}", packages));
                            } else {
                                self.output_lines.push("Usage: add <package1> [package2] ...".to_string());
                            }
                        }
                        "remove" => {
                            if parts.len() > 1 {
                                let package = parts[1];
                                self.package_list = self.package_list.replace(&format!("{} ", package), "");
                                self.output_lines.push(format!("Removed package: {}", package));
                            } else {
                                self.output_lines.push("Usage: remove <package>".to_string());
                            }
                        }
                        "list" => {
                            if self.package_list.trim().is_empty() {
                                self.output_lines.push("No packages selected".to_string());
                            } else {
                                self.output_lines.push(format!("Selected packages: {}", self.package_list.trim()));
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
                Shortcut { keys: vec!["Ctrl-C".to_string()], description: "Exit selection".to_string() },
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
    pub progress: u16,
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
                String::new(),  // Username
                String::new(),  // User password
                String::new(),  // Root password
                String::new(),  // Hostname
                String::new(),  // Disk
                String::new(),  // Partitioning strategy
                String::new(),  // Desktop environment
                String::new(),  // Encryption
                String::new(),  // Multilib
                String::new(),  // AUR helper
                String::new(),  // Timezone region
                String::new(),  // Timezone
                String::new(),  // Locale
                String::new(),  // Keymap
                String::new(),  // Bootloader
                String::new(),  // GRUB theme
                String::new(),  // GPU drivers
                String::new(),  // Plymouth
                String::new(),  // Pacman packages
                String::new(),  // AUR packages
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
        ui(f, &mut *state)
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
                        KeyCode::Char('q') | KeyCode::Esc => {
                            // Always allow quit
                            break;
                        }
                        KeyCode::Char('s') => {
                            let mut state = app_state.lock().unwrap();
                            if state.is_configuring {
                                match &mut state.focus {
                                    Focus::FloatingWindow(float) => {
                                        // Pass 's' to floating window
                                        let key_event = KeyEvent { 
                                            code: KeyCode::Char('s'), 
                                            modifiers, 
                                            kind: crossterm::event::KeyEventKind::Press, 
                                            state: crossterm::event::KeyEventState::NONE 
                                        };
                                        if float.handle_key_event(&key_event) {
                                            state.focus = Focus::Configuration;
                                        }
                                    }
                                    Focus::Configuration => {
                                        if state.editing_field.is_none() && !state.popup.is_active {
                                            // Start configuration process
                                            state.is_configuring = false;
                                            state.is_running = true;
                                            state.current_phase = "Starting Installation".to_string();
                                            state.status_message = "Launching installer with configuration...".to_string();
                                            state.progress = 10;
                                            
                                            // Start the installer with configuration
                                            let config_values = state.config_values.clone();
                                            drop(state); // Release lock before spawning thread
                                            start_installer_with_config(Arc::clone(&app_state), config_values);
                                        } else if state.editing_field.is_some() {
                                            // Handle 's' as text input when editing a field
                                            state.current_input.push('s');
                                        }
                                    }
                                }
                            }
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
                                            // Floating window is finished, save packages if any were selected
                                            let config_step = state.config_step;
                                            if config_step == 18 || config_step == 19 {
                                                // This is a package selection step, set a placeholder
                                                state.config_values[config_step] = "packages selected".to_string();
                                            }
                                            
                                            // Return to configuration
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
                                        
                                        let parts: Vec<&str> = command.trim().split_whitespace().collect();
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
                                                    state.config_values[current_step] = "fastfetch neofetch htop".to_string(); // Placeholder
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
                                            if matches!(state.popup.popup_type, PopupType::ManualPartitioning) {
                                                // Launch the selected partitioning tool
                                                let tool = &selected_value;
                                                state.config_values[current_step] = format!("manual_{}", tool);
                                                
                                                // Note: In a real implementation, you would spawn the CLI tool here
                                                // For now, we'll just set the value and continue
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
                                        } else if state.config_step == 20 {
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
                                                    4 => PopupType::DiskSelection,
                                                    5 => {
                                                        if state.config_values[4] == "manual" {
                                                            PopupType::ManualPartitioning
                                                        } else {
                                                            PopupType::PartitioningStrategy
                                                        }
                                                    },
                                                    6 => PopupType::DesktopEnvironment,
                                                    7 => {
                                                        // Only show encryption if not auto_luks_lvm (which includes encryption)
                                                        if state.config_values[5] == "auto_luks_lvm" {
                                                            // Auto-set encryption to yes for auto_luks_lvm
                                                            state.config_values[7] = "yes".to_string();
                                                            // Move to next step automatically
                                                            state.config_step += 1;
                                                            PopupType::None
                                                        } else {
                                                            PopupType::Encryption
                                                        }
                                                    },
                                                    8 => PopupType::Multilib,
                                                    9 => PopupType::AURHelper,
                                                    10 => PopupType::TimezoneRegion,
                                                    11 => {
                                                        // Only show timezone cities if region is selected
                                                        if !state.config_values[10].is_empty() {
                                                            PopupType::Timezone
                                                        } else {
                                                            PopupType::None
                                                        }
                                                    },
                                                    12 => PopupType::Locale,
                                                    13 => PopupType::Keymap,
                                                    14 => PopupType::Bootloader,
                                                    15 => PopupType::GRUBTheme,
                                                    16 => PopupType::GPUDrivers,
                                                    17 => PopupType::Plymouth,
                                                    18 => PopupType::PackageSelection, // Pacman packages
                                                    19 => PopupType::PackageSelection, // AUR packages
                                                    _ => PopupType::None,
                                                };
                                                
                                                if !matches!(popup_type, PopupType::None) {
                                                    let (options, title) = if matches!(popup_type, PopupType::Timezone) {
                                                        // Special handling for timezone - get timezones for selected region
                                                        let region = state.config_values[10].clone();
                                                        (detect_timezones_for_region(&region), "Select Timezone".to_string())
                                                    } else if matches!(popup_type, PopupType::PackageSelection) {
                                                        // Create floating window for package selection
                                                        let is_pacman = state.config_step == 18;
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
                                if state.popup.is_active {
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
                                        state.config_step = 20;
                                    }
                                }
                            }
                        }
                        KeyCode::Down => {
                            // Navigate popup or configuration options
                            let mut state = app_state.lock().unwrap();
                            if state.is_configuring {
                                if state.popup.is_active {
                                    // Navigate popup options
                                    if state.popup.selected_index < state.popup.options.len().saturating_sub(1) {
                                        state.popup.selected_index += 1;
                                    }
                                } else {
                                    // Navigate configuration options
                                    if state.config_step < 20 {
                                        state.config_step += 1;
                                    } else if state.config_step == 20 {
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
                        ui(f, &mut *state)
                    })?;
                }
                _ => {}
            }
        }

        // Redraw the UI
        terminal.draw(|f| {
            let mut state = app_state.lock().unwrap();
            ui(f, &mut *state)
        })?;
        
        // Small delay to prevent excessive CPU usage
        std::thread::sleep(Duration::from_millis(50));
    }

    Ok(())
}

fn is_text_input_field(step: usize) -> bool {
    match step {
        0 | 1 | 2 | 3 => true,  // Username, passwords, hostname
        _ => false,  // Selection-based fields (including disk and packages)
    }
}

fn detect_disks() -> Vec<String> {
    let mut disks = Vec::new();
    
    // Try to get disk list from lsblk
    if let Ok(output) = Command::new("lsblk")
        .args(&["-d", "-n", "-o", "NAME,SIZE,TYPE"])
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
    
    // Fallback to common disk paths if lsblk fails
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
    let mut timezones = Vec::new();
    
    // Try to get timezone list from timedatectl for specific region
    if let Ok(output) = Command::new("timedatectl")
        .args(&["list-timezones"])
        .output() {
        let output_str = String::from_utf8_lossy(&output.stdout);
        for line in output_str.lines() {
            let tz = line.trim();
            if !tz.is_empty() && tz.starts_with(&format!("{}/", region)) {
                timezones.push(tz.to_string());
            }
        }
    }
    
    // Fallback to common timezones for specific regions if timedatectl fails
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

fn get_popup_options(popup_type: &PopupType) -> (Vec<String>, String) {
    match popup_type {
        PopupType::DiskSelection => (detect_disks(), "Select Installation Disk".to_string()),
        PopupType::PartitioningStrategy => (
            vec![
                "auto_simple".to_string(),
                "auto_luks_lvm".to_string(),
                "manual".to_string(),
                "raid".to_string(),
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
        PopupType::ManualPartitioning => (
            vec![
                "fdisk".to_string(),
                "gdisk".to_string(),
                "cfdisk".to_string(),
                "cgdisk".to_string(),
                "parted".to_string(),
            ],
            "Select Partitioning Tool".to_string()
        ),
        PopupType::PackageSelection => (
            vec![],
            "Interactive Package Selection".to_string()
        ),
        PopupType::TextInput(field_name) => (
            vec![],
            format!("Enter {}", field_name)
        ),
        PopupType::None => (vec![], String::new()),
    }
}

fn change_config_value(state: &mut InstallerState) {
    match state.config_step {
        5 => { // Partitioning strategy
            state.config_values[5] = match state.config_values[5].as_str() {
                "auto_simple" => "auto_luks_lvm".to_string(),
                "auto_luks_lvm" => "auto_simple".to_string(),
                _ => "auto_simple".to_string(),
            };
        }
        6 => { // Desktop environment
            state.config_values[6] = match state.config_values[6].as_str() {
                "gnome" => "kde".to_string(),
                "kde" => "xfce".to_string(),
                "xfce" => "lxqt".to_string(),
                "lxqt" => "none".to_string(),
                "none" => "gnome".to_string(),
                _ => "gnome".to_string(),
            };
        }
        7 => { // Encryption
            state.config_values[7] = match state.config_values[7].as_str() {
                "yes" => "no".to_string(),
                "no" => "yes".to_string(),
                _ => "yes".to_string(),
            };
        }
        8 => { // Multilib
            state.config_values[8] = match state.config_values[8].as_str() {
                "yes" => "no".to_string(),
                "no" => "yes".to_string(),
                _ => "yes".to_string(),
            };
        }
        9 => { // AUR helper
            state.config_values[9] = match state.config_values[9].as_str() {
                "paru" => "yay".to_string(),
                "yay" => "aura".to_string(),
                "aura" => "none".to_string(),
                "none" => "paru".to_string(),
                _ => "paru".to_string(),
            };
        }
        10 => { // Timezone
            state.config_values[10] = match state.config_values[10].as_str() {
                "America/New_York" => "America/Chicago".to_string(),
                "America/Chicago" => "America/Denver".to_string(),
                "America/Denver" => "America/Los_Angeles".to_string(),
                "America/Los_Angeles" => "Europe/London".to_string(),
                "Europe/London" => "Europe/Paris".to_string(),
                "Europe/Paris" => "Asia/Tokyo".to_string(),
                "Asia/Tokyo" => "America/New_York".to_string(),
                _ => "America/New_York".to_string(),
            };
        }
        11 => { // Locale
            state.config_values[11] = match state.config_values[11].as_str() {
                "en_US.UTF-8" => "en_GB.UTF-8".to_string(),
                "en_GB.UTF-8" => "de_DE.UTF-8".to_string(),
                "de_DE.UTF-8" => "fr_FR.UTF-8".to_string(),
                "fr_FR.UTF-8" => "es_ES.UTF-8".to_string(),
                "es_ES.UTF-8" => "en_US.UTF-8".to_string(),
                _ => "en_US.UTF-8".to_string(),
            };
        }
        12 => { // Keymap
            state.config_values[12] = match state.config_values[12].as_str() {
                "us" => "uk".to_string(),
                "uk" => "de".to_string(),
                "de" => "fr".to_string(),
                "fr" => "es".to_string(),
                "es" => "us".to_string(),
                _ => "us".to_string(),
            };
        }
        13 => { // Bootloader
            state.config_values[13] = match state.config_values[13].as_str() {
                "grub" => "systemd-boot".to_string(),
                "systemd-boot" => "refind".to_string(),
                "refind" => "grub".to_string(),
                _ => "grub".to_string(),
            };
        }
        14 => { // GRUB theme
            state.config_values[14] = match state.config_values[14].as_str() {
                "arch-glow" => "arch-silence".to_string(),
                "arch-silence" => "arch-matrix".to_string(),
                "arch-matrix" => "none".to_string(),
                "none" => "arch-glow".to_string(),
                _ => "arch-glow".to_string(),
            };
        }
        15 => { // GPU drivers
            state.config_values[15] = match state.config_values[15].as_str() {
                "auto" => "nvidia".to_string(),
                "nvidia" => "amd".to_string(),
                "amd" => "intel".to_string(),
                "intel" => "none".to_string(),
                "none" => "auto".to_string(),
                _ => "auto".to_string(),
            };
        }
        _ => {}
    }
}

fn start_installer_with_config(app_state: Arc<Mutex<InstallerState>>, config_values: Vec<String>) {
    // Start the installer in a separate thread
    thread::spawn(move || {
        run_actual_installer(app_state, config_values);
    });
}

fn run_actual_installer(app_state: Arc<Mutex<InstallerState>>, _config_values: Vec<String>) {
    // For now, let's run the installer in bash-only mode to avoid the interactive issues
    // The TUI will show progress but the actual installation will be handled by the bash script
    let mut child = Command::new("bash")
        .arg("./launch_tui_installer.sh")
        .arg("--bash-only")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("Failed to start installer");

    // Read stdout and parse for progress updates
    if let Some(stdout) = child.stdout.take() {
        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            if let Ok(line) = line {
                // Parse the line for progress information
                parse_installer_output(&app_state, &line);
            }
        }
    }

    // Read stderr for error messages
    if let Some(stderr) = child.stderr.take() {
        let reader = BufReader::new(stderr);
        for line in reader.lines() {
            if let Ok(line) = line {
                // Add error messages to output and update status
                let mut state = app_state.lock().unwrap();
                state.installer_output.push(format!("ERROR: {}", line));
                if state.installer_output.len() > 50 {
                    state.installer_output.remove(0);
                }
                state.status_message = format!("Error: {}", line);
            }
        }
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
    
    // Parse specific patterns from installer output
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
    
    // Check if terminal is too small
    if size.height < 20 || size.width < 80 {
        render_minimal_ui(f, app_state);
        return;
    }
    
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
            let instructions = "Use ↑↓ to navigate, Enter to open popup, 'q' to quit";
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

    // Configuration options
    let config_items = vec![
        ListItem::new(format!("Username: {}", 
            if app_state.editing_field == Some(0) { 
                format!("{}_", app_state.current_input) 
            } else if app_state.config_values[0].is_empty() { 
                "[Press Enter]".to_string() 
            } else { 
                app_state.config_values[0].clone() 
            }))
            .style(if app_state.config_step == 0 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("User Password: {}", 
            if app_state.editing_field == Some(1) { 
                format!("{}_", "*".repeat(app_state.current_input.len())) 
            } else if app_state.config_values[1].is_empty() { 
                "[Press Enter]".to_string() 
            } else { 
                "***".to_string() 
            }))
            .style(if app_state.config_step == 1 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Root Password: {}", 
            if app_state.editing_field == Some(2) { 
                format!("{}_", "*".repeat(app_state.current_input.len())) 
            } else if app_state.config_values[2].is_empty() { 
                "[Press Enter]".to_string() 
            } else { 
                "***".to_string() 
            }))
            .style(if app_state.config_step == 2 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Hostname: {}", 
            if app_state.editing_field == Some(3) { 
                format!("{}_", app_state.current_input) 
            } else if app_state.config_values[3].is_empty() { 
                "[Press Enter]".to_string() 
            } else { 
                app_state.config_values[3].clone() 
            }))
            .style(if app_state.config_step == 3 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Disk: {}", if app_state.config_values[4].is_empty() { "[Press Enter]" } else { &app_state.config_values[4] }))
            .style(if app_state.config_step == 4 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Partitioning Strategy: {}", if app_state.config_values[5].is_empty() { "[Press Enter]" } else { &app_state.config_values[5] }))
            .style(if app_state.config_step == 5 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Desktop Environment: {}", if app_state.config_values[6].is_empty() { "[Press Enter]" } else { &app_state.config_values[6] }))
            .style(if app_state.config_step == 6 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Encryption: {}", if app_state.config_values[7].is_empty() { "[Press Enter]" } else { &app_state.config_values[7] }))
            .style(if app_state.config_step == 7 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Multilib (32-bit): {}", if app_state.config_values[8].is_empty() { "[Press Enter]" } else { &app_state.config_values[8] }))
            .style(if app_state.config_step == 8 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("AUR Helper: {}", if app_state.config_values[9].is_empty() { "[Press Enter]" } else { &app_state.config_values[9] }))
            .style(if app_state.config_step == 9 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Timezone Region: {}", if app_state.config_values[10].is_empty() { "[Press Enter]" } else { &app_state.config_values[10] }))
            .style(if app_state.config_step == 10 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Timezone: {}", if app_state.config_values[11].is_empty() { "[Press Enter]" } else { &app_state.config_values[11] }))
            .style(if app_state.config_step == 11 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Locale: {}", if app_state.config_values[12].is_empty() { "[Press Enter]" } else { &app_state.config_values[12] }))
            .style(if app_state.config_step == 12 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Keymap: {}", if app_state.config_values[13].is_empty() { "[Press Enter]" } else { &app_state.config_values[13] }))
            .style(if app_state.config_step == 13 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Bootloader: {}", if app_state.config_values[14].is_empty() { "[Press Enter]" } else { &app_state.config_values[14] }))
            .style(if app_state.config_step == 14 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("GRUB Theme: {}", if app_state.config_values[15].is_empty() { "[Press Enter]" } else { &app_state.config_values[15] }))
            .style(if app_state.config_step == 15 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("GPU Drivers: {}", if app_state.config_values[16].is_empty() { "[Press Enter]" } else { &app_state.config_values[16] }))
            .style(if app_state.config_step == 16 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Plymouth: {}", if app_state.config_values[17].is_empty() { "[Press Enter]" } else { &app_state.config_values[17] }))
            .style(if app_state.config_step == 17 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Pacman Packages: {}", 
            if app_state.config_values[18].is_empty() { 
                "[Press Enter]".to_string() 
            } else { 
                app_state.config_values[18].clone() 
            }))
            .style(if app_state.config_step == 18 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("AUR Packages: {}", 
            if app_state.config_values[19].is_empty() { 
                "[Press Enter]".to_string() 
            } else { 
                app_state.config_values[19].clone() 
            }))
            .style(if app_state.config_step == 19 { Style::default().fg(Color::Yellow) } else { Style::default() }),
    ];

    let config_list = List::new(config_items)
        .block(Block::default().title("Configuration Options").borders(Borders::ALL));
    f.render_widget(config_list, chunks[2]);

    // Instructions
    let instructions = if app_state.popup.is_active {
        "Use ↑↓ to navigate, Enter to select, Esc to cancel"
    } else {
        "Use ↑↓ to navigate, Enter to open popup, 'q' to quit"
    };
    let instruction_text = Paragraph::new(instructions)
        .block(Block::default().borders(Borders::NONE))
        .alignment(Alignment::Center)
        .style(Style::default().fg(Color::Yellow));
    f.render_widget(instruction_text, chunks[3]);

    // Start button
    let start_button_text = if app_state.config_step == 20 {
        "> START INSTALLATION <"
    } else {
        "  START INSTALLATION  "
    };
    let start_button = Paragraph::new(start_button_text)
        .block(Block::default().borders(Borders::ALL))
        .alignment(Alignment::Center)
        .style(if app_state.config_step == 20 { 
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

fn render_minimal_ui(f: &mut Frame, app_state: &mut InstallerState) {
    let size = f.area();
    
    // Simple layout for small terminals
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),  // Title
            Constraint::Length(3),  // Progress
            Constraint::Length(3),  // Status
            Constraint::Min(0),     // Output
            Constraint::Length(3),  // Instructions
        ])
        .split(size);

    // Simple title
    let title = Paragraph::new("Arch Linux Installer")
        .block(Block::default().borders(Borders::ALL))
        .alignment(Alignment::Center)
        .style(Style::default().fg(Color::Cyan));
    f.render_widget(title, chunks[0]);

    // Progress bar
    let progress = Gauge::default()
        .block(Block::default().title(format!("{} - {}%", app_state.current_phase, app_state.progress)))
        .gauge_style(Style::default().fg(Color::Cyan))
        .percent(app_state.progress);
    f.render_widget(progress, chunks[1]);

    // Status
    let status = Paragraph::new(app_state.status_message.as_str())
        .block(Block::default().title("Status").borders(Borders::ALL))
        .style(Style::default().fg(Color::White))
        .wrap(Wrap { trim: true });
    f.render_widget(status, chunks[2]);

    // Output (simplified)
    let output_items: Vec<ListItem> = app_state.installer_output
        .iter()
        .rev()
        .take(10) // Show only last 10 lines
        .map(|line| ListItem::new(line.clone()))
        .collect();
    let output_list = List::new(output_items)
        .block(Block::default().title("Output").borders(Borders::ALL));
    f.render_widget(output_list, chunks[3]);

    // Instructions
    let instructions = if app_state.is_running && !app_state.is_complete {
        "Installing... Press 'q' to quit"
    } else if app_state.is_complete {
        if app_state.current_phase == "Failed" {
            "Failed! Press 'q' to quit"
        } else {
            "Complete! Press 'q' to quit"
        }
    } else {
        "Press 's' to start, 'q' to quit"
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
    f.render_widget(instruction_text, chunks[4]);
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
        .percent(app_state.progress);

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
        ListItem::new(format!("Username: {}", app_state.config_values[0])),
        ListItem::new(format!("User Password: {}", if app_state.config_values[1].is_empty() { "Not set" } else { "***" })),
        ListItem::new(format!("Root Password: {}", if app_state.config_values[2].is_empty() { "Not set" } else { "***" })),
        ListItem::new(format!("Hostname: {}", app_state.config_values[3])),
        ListItem::new(format!("Disk: {}", app_state.config_values[4])),
        ListItem::new(format!("Partitioning: {}", app_state.config_values[5])),
        ListItem::new(format!("Desktop: {}", app_state.config_values[6])),
        ListItem::new(format!("Encryption: {}", app_state.config_values[7])),
        ListItem::new(format!("Multilib: {}", app_state.config_values[8])),
        ListItem::new(format!("AUR Helper: {}", app_state.config_values[9])),
        ListItem::new(format!("Timezone Region: {}", app_state.config_values[10])),
        ListItem::new(format!("Timezone: {}", app_state.config_values[11])),
        ListItem::new(format!("Locale: {}", app_state.config_values[12])),
        ListItem::new(format!("Keymap: {}", app_state.config_values[13])),
        ListItem::new(format!("Bootloader: {}", app_state.config_values[14])),
        ListItem::new(format!("GRUB Theme: {}", app_state.config_values[15])),
        ListItem::new(format!("GPU Drivers: {}", app_state.config_values[16])),
        ListItem::new(format!("Plymouth: {}", app_state.config_values[17])),
        ListItem::new(format!("Plymouth Theme: {}", app_state.config_values[18])),
        ListItem::new(format!("Pacman Packages: {}", app_state.config_values[19])),
        ListItem::new(format!("AUR Packages: {}", app_state.config_values[20])),
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
    let start_index = if total_items > available_height as usize {
        total_items - available_height as usize
    } else {
        0
    };

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
    let popup_height = (size.height * 3 / 4).min(20);
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
            let instructions = Paragraph::new("Type your input and press Enter to confirm, Esc to cancel")
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
            let instructions = Paragraph::new("Use ↑↓ to navigate, Enter to select, Esc to cancel")
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