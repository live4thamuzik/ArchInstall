use ratatui::{
    backend::CrosstermBackend,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, List, ListItem, Paragraph, Wrap, Clear},
    Frame, Terminal,
};
use std::io::{stdout, BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};
use std::thread;
use std::time::Duration;
use crossterm::event::{Event, KeyCode, KeyEvent};

// Global interrupt flag
static INTERRUPTED: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Clone)]
pub struct InstallerState {
    pub current_phase: String,
    pub progress: u16,
    pub status_message: String,
    pub disk: String,
    pub strategy: String,
    pub boot_mode: String,
    pub desktop: String,
    pub username: String,
    pub installer_output: Vec<String>,
    pub is_running: bool,
    pub is_complete: bool,
    pub is_configuring: bool,
    pub config_step: usize,
    pub config_values: Vec<String>,
}

impl Default for InstallerState {
    fn default() -> Self {
        Self {
            current_phase: "Configuration".to_string(),
            progress: 0,
            status_message: "Press 's' to start configuration...".to_string(),
            disk: "Not selected".to_string(),
            strategy: "Not selected".to_string(),
            boot_mode: "Not selected".to_string(),
            desktop: "Not selected".to_string(),
            username: "Not selected".to_string(),
            installer_output: Vec::new(),
            is_running: false,
            is_complete: false,
            is_configuring: true,
            config_step: 0,
            config_values: vec![
                "auto_luks_lvm".to_string(),  // Partitioning strategy
                "gnome".to_string(),          // Desktop environment
                "l4tm".to_string(),           // Username
                "ArchBTW".to_string(),        // Hostname
                "yes".to_string(),            // Encryption
                "yes".to_string(),            // Multilib
                "paru".to_string(),           // AUR helper
            ],
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
    let initial_state = app_state.lock().unwrap().clone();
    terminal.draw(|f| ui(f, &initial_state))?;

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
                            }
                        }
                        KeyCode::Char('c') if modifiers.contains(crossterm::event::KeyModifiers::CONTROL) => {
                            // Handle Ctrl+C
                            break;
                        }
                        KeyCode::Up => {
                            // Navigate configuration options
                            let mut state = app_state.lock().unwrap();
                            if state.is_configuring && state.config_step > 0 {
                                state.config_step -= 1;
                            }
                        }
                        KeyCode::Down => {
                            // Navigate configuration options
                            let mut state = app_state.lock().unwrap();
                            if state.is_configuring && state.config_step < 6 {
                                state.config_step += 1;
                            }
                        }
                        KeyCode::Left | KeyCode::Right => {
                            // Change configuration values
                            let mut state = app_state.lock().unwrap();
                            if state.is_configuring {
                                change_config_value(&mut state);
                            }
                        }
                        _ => {}
                    }
                }
                Event::Resize(_, _) => {
                    // Handle terminal resize - redraw immediately
                    let current_state = app_state.lock().unwrap().clone();
                    terminal.draw(|f| ui(f, &current_state))?;
                }
                _ => {}
            }
        }

        // Redraw the UI
        let current_state = app_state.lock().unwrap().clone();
        terminal.draw(|f| ui(f, &current_state))?;
        
        // Small delay to prevent excessive CPU usage
        std::thread::sleep(Duration::from_millis(50));
    }

    Ok(())
}

fn change_config_value(state: &mut InstallerState) {
    match state.config_step {
        0 => { // Partitioning strategy
            state.config_values[0] = match state.config_values[0].as_str() {
                "auto_simple" => "auto_luks_lvm".to_string(),
                "auto_luks_lvm" => "auto_simple".to_string(),
                _ => "auto_luks_lvm".to_string(),
            };
        }
        1 => { // Desktop environment
            state.config_values[1] = match state.config_values[1].as_str() {
                "gnome" => "kde".to_string(),
                "kde" => "hyprland".to_string(),
                "hyprland" => "none".to_string(),
                "none" => "gnome".to_string(),
                _ => "gnome".to_string(),
            };
        }
        2 => { // Username
            state.config_values[2] = match state.config_values[2].as_str() {
                "l4tm" => "user".to_string(),
                "user" => "admin".to_string(),
                "admin" => "l4tm".to_string(),
                _ => "l4tm".to_string(),
            };
        }
        3 => { // Hostname
            state.config_values[3] = match state.config_values[3].as_str() {
                "ArchBTW" => "archlinux".to_string(),
                "archlinux" => "mypc".to_string(),
                "mypc" => "ArchBTW".to_string(),
                _ => "ArchBTW".to_string(),
            };
        }
        4 => { // Encryption
            state.config_values[4] = match state.config_values[4].as_str() {
                "yes" => "no".to_string(),
                "no" => "yes".to_string(),
                _ => "yes".to_string(),
            };
        }
        5 => { // Multilib
            state.config_values[5] = match state.config_values[5].as_str() {
                "yes" => "no".to_string(),
                "no" => "yes".to_string(),
                _ => "yes".to_string(),
            };
        }
        6 => { // AUR helper
            state.config_values[6] = match state.config_values[6].as_str() {
                "paru" => "yay".to_string(),
                "yay" => "none".to_string(),
                "none" => "paru".to_string(),
                _ => "paru".to_string(),
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

fn run_actual_installer(app_state: Arc<Mutex<InstallerState>>, config_values: Vec<String>) {
    // Create a temporary config file with the selected options
    let config_content = format!(
        "PARTITION_SCHEME=\"{}\"\n\
         DESKTOP_ENVIRONMENT=\"{}\"\n\
         MAIN_USERNAME=\"{}\"\n\
         SYSTEM_HOSTNAME=\"{}\"\n\
         WANT_ENCRYPTION=\"{}\"\n\
         WANT_MULTILIB=\"{}\"\n\
         AUR_HELPER_CHOICE=\"{}\"\n",
        config_values[0], config_values[1], config_values[2], 
        config_values[3], config_values[4], config_values[5], config_values[6]
    );
    
    // Write config to temporary file
    std::fs::write("/tmp/archinstall_config", config_content)
        .expect("Failed to write config file");

    // Run the actual installer with collected parameters
    let mut child = Command::new("bash")
        .arg("./install_arch.sh")
        .env("ARCHINSTALL_CONFIG", "/tmp/archinstall_config")
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

fn ui(f: &mut Frame, app_state: &InstallerState) {
    let size = f.size();
    
    // Check if terminal is too small
    if size.height < 20 || size.width < 80 {
        render_minimal_ui(f, app_state);
        return;
    }
    
    if app_state.is_configuring {
        render_configuration_ui(f, app_state);
    } else {
        render_installation_ui(f, app_state);
    }
}

fn render_configuration_ui(f: &mut Frame, app_state: &InstallerState) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(7),  // Header
            Constraint::Length(3),  // Title
            Constraint::Min(10),    // Configuration options
            Constraint::Length(3),  // Instructions
        ])
        .split(f.size());

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
        ListItem::new(format!("Partitioning Strategy: {}", app_state.config_values[0]))
            .style(if app_state.config_step == 0 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Desktop Environment: {}", app_state.config_values[1]))
            .style(if app_state.config_step == 1 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Username: {}", app_state.config_values[2]))
            .style(if app_state.config_step == 2 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Hostname: {}", app_state.config_values[3]))
            .style(if app_state.config_step == 3 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Encryption: {}", app_state.config_values[4]))
            .style(if app_state.config_step == 4 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("Multilib (32-bit): {}", app_state.config_values[5]))
            .style(if app_state.config_step == 5 { Style::default().fg(Color::Yellow) } else { Style::default() }),
        ListItem::new(format!("AUR Helper: {}", app_state.config_values[6]))
            .style(if app_state.config_step == 6 { Style::default().fg(Color::Yellow) } else { Style::default() }),
    ];

    let config_list = List::new(config_items)
        .block(Block::default().title("Configuration Options").borders(Borders::ALL));
    f.render_widget(config_list, chunks[2]);

    // Instructions
    let instructions = "Use ↑↓ to navigate, ←→ to change values, 's' to start installation, 'q' to quit";
    let instruction_text = Paragraph::new(instructions)
        .block(Block::default().borders(Borders::NONE))
        .alignment(Alignment::Center)
        .style(Style::default().fg(Color::Yellow));
    f.render_widget(instruction_text, chunks[3]);
}

fn render_installation_ui(f: &mut Frame, app_state: &InstallerState) {
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
        .split(f.size());

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

fn render_minimal_ui(f: &mut Frame, app_state: &InstallerState) {
    let size = f.size();
    
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

fn render_progress(f: &mut Frame, area: Rect, app_state: &InstallerState) {
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

fn render_status(f: &mut Frame, area: Rect, app_state: &InstallerState) {
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

fn render_config(f: &mut Frame, area: Rect, app_state: &InstallerState) {
    // Ensure we have a valid area
    if area.width == 0 || area.height == 0 {
        return;
    }
    
    let config_items = vec![
        ListItem::new(format!("Partitioning: {}", app_state.config_values[0])),
        ListItem::new(format!("Desktop: {}", app_state.config_values[1])),
        ListItem::new(format!("Username: {}", app_state.config_values[2])),
        ListItem::new(format!("Hostname: {}", app_state.config_values[3])),
        ListItem::new(format!("Encryption: {}", app_state.config_values[4])),
        ListItem::new(format!("Multilib: {}", app_state.config_values[5])),
        ListItem::new(format!("AUR Helper: {}", app_state.config_values[6])),
    ];

    let config_list = List::new(config_items)
        .block(Block::default().title("Configuration").borders(Borders::ALL));

    f.render_widget(config_list, area);
}

fn render_output(f: &mut Frame, area: Rect, app_state: &InstallerState) {
    // Ensure we have a valid area
    if area.width == 0 || area.height == 0 {
        return;
    }
    
    let output_items: Vec<ListItem> = app_state.installer_output
        .iter()
        .map(|line| ListItem::new(line.clone()))
        .collect();

    let output_list = List::new(output_items)
        .block(Block::default().title("Installer Output").borders(Borders::ALL));

    f.render_widget(output_list, area);
}

fn render_instructions(f: &mut Frame, area: Rect, app_state: &InstallerState) {
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

fn restore_terminal() -> Result<(), Box<dyn std::error::Error>> {
    // Restore terminal state
    crossterm::terminal::disable_raw_mode()?;
    crossterm::execute!(stdout(), crossterm::terminal::LeaveAlternateScreen)?;
    Ok(())
}