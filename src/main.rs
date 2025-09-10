use ratatui::{
    backend::CrosstermBackend,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, List, ListItem, Paragraph},
    Frame, Terminal,
};
use std::io::stdout;
use std::fs;
use std::path::Path;

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
}

impl Default for InstallerState {
    fn default() -> Self {
        Self {
            current_phase: "Initializing...".to_string(),
            progress: 0,
            status_message: "Starting Arch Linux installation...".to_string(),
            disk: "/dev/nvme0n1 (500GB)".to_string(),
            strategy: "LUKS+LVM".to_string(),
            boot_mode: "UEFI".to_string(),
            desktop: "KDE Plasma".to_string(),
            username: "l4tm".to_string(),
        }
    }
}

// Progress file paths
const PROGRESS_FILE: &str = "/tmp/archinstall_progress";
const STATUS_FILE: &str = "/tmp/archinstall_status";
const PHASE_FILE: &str = "/tmp/archinstall_phase";

// Read progress from files
fn read_progress() -> u16 {
    if let Ok(content) = fs::read_to_string(PROGRESS_FILE) {
        content.trim().parse().unwrap_or(0)
    } else {
        0
    }
}

fn read_status() -> String {
    if let Ok(content) = fs::read_to_string(STATUS_FILE) {
        content.trim().to_string()
    } else {
        "Waiting for installation to start...".to_string()
    }
}

fn read_phase() -> String {
    if let Ok(content) = fs::read_to_string(PHASE_FILE) {
        content.trim().to_string()
    } else {
        "Initializing...".to_string()
    }
}

// Check if installation is running
fn is_installation_running() -> bool {
    Path::new(PROGRESS_FILE).exists()
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Setup terminal
    crossterm::terminal::enable_raw_mode()?;
    let mut stdout = stdout();
    crossterm::execute!(stdout, crossterm::terminal::EnterAlternateScreen)?;

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app state
    let mut app_state = InstallerState::default();

    // Main event loop
    loop {
        // Update state from progress files
        if is_installation_running() {
            app_state.progress = read_progress();
            app_state.status_message = read_status();
            app_state.current_phase = read_phase();
        } else {
            // Installation not running, show waiting message
            app_state.status_message = "Waiting for installation to start...".to_string();
            app_state.current_phase = "Ready".to_string();
        }

        // Clear the terminal and redraw the TUI
        terminal.clear()?;
        terminal.draw(|f| ui(f, &app_state))?;

        // Handle input
        if crossterm::event::poll(std::time::Duration::from_millis(100))? {
            if let crossterm::event::Event::Key(key) = crossterm::event::read()? {
                match key.code {
                    crossterm::event::KeyCode::Esc => break,
                    crossterm::event::KeyCode::Char('h') => {
                        // Show help
                        app_state.status_message = "Help: ESC to exit, h for help, l for logs".to_string();
                    }
                    crossterm::event::KeyCode::Char('l') => {
                        // Show logs
                        app_state.status_message = "Logs: Check terminal output for detailed logs".to_string();
                    }
                    _ => {}
                }
            }
        }

        // Exit if installation is complete
        if app_state.progress >= 100 {
            app_state.status_message = "Installation complete! Press ESC to exit.".to_string();
        }
    }

    // Restore terminal
    crossterm::terminal::disable_raw_mode()?;
    crossterm::execute!(terminal.backend_mut(), crossterm::terminal::LeaveAlternateScreen)?;

    Ok(())
}

fn ui(f: &mut Frame, app_state: &InstallerState) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(12), // Header with logo
            Constraint::Length(8),  // Configuration summary
            Constraint::Length(4),  // Progress bar
            Constraint::Length(6),  // Status area (fixed size)
            Constraint::Min(0),     // Footer with controls
        ])
        .split(f.size());

    // Header with Arch logo
    render_header(f, chunks[0]);

    // Configuration summary
    render_config_summary(f, chunks[1], app_state);

    // Progress bar
    render_progress(f, chunks[2], app_state);

    // Status message
    render_status(f, chunks[3], app_state);

    // Footer with controls
    render_footer(f, chunks[4]);
}

fn render_header(f: &mut Frame, area: Rect) {
    let header_block = Block::default()
        .borders(Borders::ALL)
        .style(Style::default().fg(Color::White));

    let logo_text = vec![
        Line::from(""),
        Line::from("    █████╗ ██████╗  ██████╗██╗  ██╗"),
        Line::from("   ██╔══██╗██╔══██╗██╔════╝██║  ██║"),
        Line::from("   ███████║██████╔╝██║     ███████║"),
        Line::from("   ██╔══██║██╔══██╗██║     ██╔══██║"),
        Line::from("   ██║  ██║██║  ██║╚██████╗██║  ██║"),
        Line::from("   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝"),
        Line::from(""),
        Line::from("        Linux Installer v2.0        "),
    ];

    let logo_paragraph = Paragraph::new(logo_text)
        .block(header_block)
        .alignment(Alignment::Center);

    f.render_widget(logo_paragraph, area);
}

fn render_config_summary(f: &mut Frame, area: Rect, app_state: &InstallerState) {
    let config_items = vec![
        ListItem::new(format!("[✓] Disk: {}", app_state.disk)),
        ListItem::new(format!("[✓] Strategy: {}", app_state.strategy)),
        ListItem::new(format!("[✓] Boot: {}", app_state.boot_mode)),
        ListItem::new(format!("[✓] Desktop: {}", app_state.desktop)),
        ListItem::new(format!("[✓] User: {}", app_state.username)),
    ];

    let config_list = List::new(config_items)
        .block(Block::default().borders(Borders::ALL).title("Configuration"));

    f.render_widget(config_list, area);
}

fn render_progress(f: &mut Frame, area: Rect, app_state: &InstallerState) {
    let title = format!("Progress - {}", app_state.current_phase);
    let progress_gauge = Gauge::default()
        .block(Block::default().borders(Borders::ALL).title(title))
        .gauge_style(Style::default().fg(Color::Blue))
        .percent(app_state.progress);

    f.render_widget(progress_gauge, area);
}

fn render_status(f: &mut Frame, area: Rect, app_state: &InstallerState) {
    // Calculate available width inside the box (accounting for borders and padding)
    let available_width = if area.width > 6 { area.width - 6 } else { 1 };
    
    // Truncate status message to fit within the available width
    let truncated_message = if app_state.status_message.len() > available_width as usize {
        format!("{}...", &app_state.status_message[..(available_width as usize - 3)])
    } else {
        app_state.status_message.clone()
    };

    let status_text = vec![
        Line::from(""),
        Line::from(Span::styled(
            &truncated_message,
            Style::default().fg(Color::Blue),
        )),
        Line::from(""),
    ];

    let status_paragraph = Paragraph::new(status_text)
        .block(Block::default().borders(Borders::ALL).title("Status"))
        .alignment(Alignment::Center)
        .wrap(ratatui::widgets::Wrap { trim: true });

    f.render_widget(status_paragraph, area);
}

fn render_footer(f: &mut Frame, area: Rect) {
    let footer_text = vec![
        Line::from(""),
        Line::from(Span::styled(
            "[ESC] Exit  [H] Help  [L] Logs",
            Style::default().fg(Color::Yellow),
        )),
    ];

    let footer_paragraph = Paragraph::new(footer_text)
        .block(Block::default().borders(Borders::ALL))
        .alignment(Alignment::Center);

    f.render_widget(footer_paragraph, area);
}
