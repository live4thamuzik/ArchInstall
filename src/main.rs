use ratatui::{
    backend::CrosstermBackend,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, List, ListItem, Paragraph},
    Frame, Terminal,
};
use std::io::{stdout, BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

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
}

impl Default for InstallerState {
    fn default() -> Self {
        Self {
            current_phase: "Ready".to_string(),
            progress: 0,
            status_message: "Press 's' to start installation...".to_string(),
            disk: "Not selected".to_string(),
            strategy: "Not selected".to_string(),
            boot_mode: "Not selected".to_string(),
            desktop: "Not selected".to_string(),
            username: "Not selected".to_string(),
            installer_output: Vec::new(),
            is_running: false,
            is_complete: false,
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Setup terminal
    crossterm::terminal::enable_raw_mode()?;
    let mut stdout = stdout();
    crossterm::execute!(stdout, crossterm::terminal::EnterAlternateScreen)?;

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create shared app state
    let app_state = Arc::new(Mutex::new(InstallerState::default()));

    // Main event loop
    loop {
        // Get current state
        let current_state = app_state.lock().unwrap().clone();
        
        // Clear the terminal and redraw the TUI
        terminal.clear()?;
        terminal.draw(|f| ui(f, &current_state))?;

        // Handle input
        if crossterm::event::poll(Duration::from_millis(100))? {
            if let crossterm::event::Event::Key(key_event) = crossterm::event::read()? {
                match key_event.code {
                    crossterm::event::KeyCode::Char('q') => break,
                    crossterm::event::KeyCode::Char('s') if !current_state.is_running => {
                        // Start the installer
                        start_installer(Arc::clone(&app_state));
                    }
                    _ => {}
                }
            }
        }
    }

    // Restore terminal
    crossterm::terminal::disable_raw_mode()?;
    crossterm::execute!(terminal.backend_mut(), crossterm::terminal::LeaveAlternateScreen)?;

    Ok(())
}

fn start_installer(app_state: Arc<Mutex<InstallerState>>) {
    // Update initial state
    {
        let mut state = app_state.lock().unwrap();
        state.is_running = true;
        state.current_phase = "Starting Installation".to_string();
        state.status_message = "Launching installer...".to_string();
        state.progress = 5;
    }

    // Start installer in a separate thread
    thread::spawn(move || {
        let mut child = Command::new("bash")
            .arg("./install_arch.sh")
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

        // Wait for the process to complete
        let status = child.wait().expect("Failed to wait for installer");
        
        // Mark as complete
        {
            let mut state = app_state.lock().unwrap();
            state.is_complete = true;
            state.progress = 100;
            state.status_message = "Installation complete!".to_string();
            state.current_phase = "Complete".to_string();
        }
        
        println!("Installer completed with status: {:?}", status);
    });
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
    if line.contains("=== PHASE 1: Disk Partitioning ===") {
        state.current_phase = "Disk Partitioning".to_string();
        state.progress = 20;
        state.status_message = "Partitioning disk...".to_string();
    } else if line.contains("=== PHASE 2: Base Installation ===") {
        state.current_phase = "Base Installation".to_string();
        state.progress = 40;
        state.status_message = "Installing base system...".to_string();
    } else if line.contains("=== PHASE 3: Bootloader Installation ===") {
        state.current_phase = "Bootloader Installation".to_string();
        state.progress = 80;
        state.status_message = "Installing bootloader...".to_string();
    } else if line.contains("=== PHASE 4: System Configuration ===") {
        state.current_phase = "System Configuration".to_string();
        state.progress = 60;
        state.status_message = "Configuring system...".to_string();
    } else if line.contains("Collecting installation preferences") {
        state.current_phase = "Collecting Preferences".to_string();
        state.progress = 10;
        state.status_message = "Collecting user preferences...".to_string();
    } else if line.contains("Installation completed successfully") {
        state.current_phase = "Complete".to_string();
        state.progress = 100;
        state.status_message = "Installation complete!".to_string();
        state.is_complete = true;
    }
    
    // Parse configuration updates
    if line.contains("Selected disk:") {
        if let Some(disk) = line.split("Selected disk:").nth(1) {
            state.disk = disk.trim().to_string();
        }
    } else if line.contains("Selected strategy:") {
        if let Some(strategy) = line.split("Selected strategy:").nth(1) {
            state.strategy = strategy.trim().to_string();
        }
    } else if line.contains("Selected desktop:") {
        if let Some(desktop) = line.split("Selected desktop:").nth(1) {
            state.desktop = desktop.trim().to_string();
        }
    } else if line.contains("Username:") {
        if let Some(username) = line.split("Username:").nth(1) {
            state.username = username.trim().to_string();
        }
    }
}

fn ui(f: &mut Frame, app_state: &InstallerState) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),  // Header
            Constraint::Length(3),  // Progress bar
            Constraint::Length(3),  // Status message
            Constraint::Length(8),  // Configuration panel
            Constraint::Min(0),     // Installer output
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

fn render_header(f: &mut Frame, area: Rect) {
    let header_text = vec![
        Line::from(vec![
            Span::styled("    _    ____  _   _ _     _ _       _     _ _   ", Style::default().fg(Color::Cyan)),
        ]),
        Line::from(vec![
            Span::styled("   / \\  / ___|| | | | |   (_) | __ _| |__ | | |  ", Style::default().fg(Color::Cyan)),
        ]),
        Line::from(vec![
            Span::styled("  / _ \\ \\___ \\| |_| | |   | | |/ _` | '_ \\| | |  ", Style::default().fg(Color::Cyan)),
        ]),
        Line::from(vec![
            Span::styled(" / ___ \\ ___) |  _  | |___| | | (_| | | | | | |  ", Style::default().fg(Color::Cyan)),
        ]),
        Line::from(vec![
            Span::styled("/_/   \\_\\____/|_| |_|_____|_|_|\\__,_|_| |_|_|_|  ", Style::default().fg(Color::Cyan)),
        ]),
    ];

    let header = Paragraph::new(header_text)
        .block(Block::default().borders(Borders::NONE))
        .alignment(Alignment::Center);

    f.render_widget(header, area);
}

fn render_progress(f: &mut Frame, area: Rect, app_state: &InstallerState) {
    let title = format!("{} - {}%", app_state.current_phase, app_state.progress);
    let progress = Gauge::default()
        .block(Block::default().title(title).borders(Borders::ALL))
        .gauge_style(Style::default().fg(Color::Cyan))
        .percent(app_state.progress);

    f.render_widget(progress, area);
}

fn render_status(f: &mut Frame, area: Rect, app_state: &InstallerState) {
    let status_text = if app_state.status_message.len() > 50 {
        format!("{}...", &app_state.status_message[..47])
    } else {
        app_state.status_message.clone()
    };

    let status = Paragraph::new(status_text)
        .block(Block::default().title("Status").borders(Borders::ALL))
        .style(Style::default().fg(Color::White));

    f.render_widget(status, area);
}

fn render_config(f: &mut Frame, area: Rect, app_state: &InstallerState) {
    let config_items = vec![
        ListItem::new(format!("Disk: {}", app_state.disk)),
        ListItem::new(format!("Strategy: {}", app_state.strategy)),
        ListItem::new(format!("Boot Mode: {}", app_state.boot_mode)),
        ListItem::new(format!("Desktop: {}", app_state.desktop)),
        ListItem::new(format!("Username: {}", app_state.username)),
    ];

    let config_list = List::new(config_items)
        .block(Block::default().title("Configuration").borders(Borders::ALL));

    f.render_widget(config_list, area);
}

fn render_output(f: &mut Frame, area: Rect, app_state: &InstallerState) {
    let output_items: Vec<ListItem> = app_state.installer_output
        .iter()
        .map(|line| ListItem::new(line.clone()))
        .collect();

    let output_list = List::new(output_items)
        .block(Block::default().title("Installer Output").borders(Borders::ALL));

    f.render_widget(output_list, area);
}

fn render_instructions(f: &mut Frame, area: Rect, app_state: &InstallerState) {
    let instructions = if app_state.is_running {
        "Installation in progress... Press 'q' to quit"
    } else if app_state.is_complete {
        "Installation complete! Press 'q' to quit"
    } else {
        "Press 's' to start installation, 'q' to quit"
    };

    let instruction_text = Paragraph::new(instructions)
        .block(Block::default().borders(Borders::NONE))
        .alignment(Alignment::Center)
        .style(Style::default().fg(Color::Yellow));

    f.render_widget(instruction_text, area);
}