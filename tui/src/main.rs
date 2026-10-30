use anyhow::{Context, Result};
use chrono::{Local, TimeZone};
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::Line,
    widgets::{Block, Borders, Cell, Paragraph, Row, Table, TableState},
    Frame, Terminal,
};
use rusqlite::Connection;
use std::{
    collections::HashSet,
    env,
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    path::PathBuf,
};
use unicode_width::UnicodeWidthStr;

#[derive(Clone, Debug)]
struct Session {
    id: String,
    title: String,
    parent: Option<String>,
    time_created: i64,
}

#[derive(Clone)]
enum Mode {
    Menu,
    List,
    Select,
    EditKeep,
    Auto,
    Confirm,
    Done,
}

struct App {
    mode: Mode,
    menu_idx: usize,
    sessions: Vec<Session>,
    table_state: TableState,
    selected: Vec<bool>,
    keep_set: HashSet<String>,
    keep_file: PathBuf,
    db_path: PathBuf,
    msg: String,
}

fn get_db_path() -> Result<PathBuf> {
    if let Ok(out) = std::process::Command::new("opencode").args(["debug", "paths"]).output() {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout);
            for line in s.lines() {
                let t = line.trim();
                if t.starts_with("db") {
                    for p in t.split_whitespace() {
                        if p.ends_with(".db") {
                            return Ok(PathBuf::from(p));
                        }
                    }
                }
            }
        }
    }
    let mut p = dirs::home_dir().context("no home")?;
    p.push(".local/share/opencode/opencode.db");
    Ok(p)
}

fn load_sessions(db_path: &PathBuf) -> Result<Vec<Session>> {
    if !db_path.exists() {
        return Ok(vec![]);
    }
    let conn = Connection::open_with_flags(db_path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    let mut stmt = conn.prepare(
        "SELECT id, COALESCE(REPLACE(REPLACE(REPLACE(title,char(9),' '),char(10),' '),char(13),' '),''), COALESCE(parent_id,''), time_created FROM session_v2 ORDER BY time_created ASC, id ASC",
    )?;
    let rows = stmt.query_map([], |r| {
        let id: String = r.get(0)?;
        let title: String = r.get(1)?;
        let parent: String = r.get(2)?;
        let tc: i64 = r.get(3)?;
        Ok(Session {
            id,
            title,
            parent: if parent.is_empty() { None } else { Some(parent) },
            time_created: tc,
        })
    })?;
    let mut v = Vec::new();
    for rr in rows {
        if let Ok(x) = rr {
            v.push(x);
        }
    }
    Ok(v)
}

fn fmt_ts(ts: i64) -> String {
    if let Some(dt) = Local.timestamp_millis_opt(ts).single() {
        dt.format("%Y-%m-%d %H:%M").to_string()
    } else {
        ts.to_string()
    }
}

fn truncate(s: &str, max: usize) -> String {
    let w = UnicodeWidthStr::width(s);
    if w <= max {
        return s.to_string();
    }
    let mut out = String::new();
    let mut cur = 0;
    for c in s.chars() {
        let cw = UnicodeWidthStr::width(c.to_string().as_str());
        if cur + cw > max - 3 {
            break;
        }
        out.push(c);
        cur += cw;
    }
    out.push_str("...");
    out
}

fn load_keep(keep_file: &PathBuf) -> HashSet<String> {
    let mut set = HashSet::new();
    if let Ok(mut f) = File::open(keep_file) {
        let mut s = String::new();
        if f.read_to_string(&mut s).is_ok() {
            for line in s.lines() {
                let t = line.trim();
                if t.is_empty() || t.starts_with('#') {
                    continue;
                }
                for token in t.split_whitespace() {
                    if token.starts_with("ses_") {
                        set.insert(token.to_string());
                        break;
                    }
                }
            }
        }
    }
    set
}

fn save_keep_from_set(sessions: &[Session], keep_file: &PathBuf, keep_set: &HashSet<String>) -> Result<()> {
    let mut out = OpenOptions::new().create(true).write(true).truncate(true).open(keep_file)?;
    writeln!(out, "# Lista blanca de sesiones a CONSERVAR").unwrap();
    writeln!(out, "# Solo las listadas se conservan en modo AUTO").unwrap();
    writeln!(out, "# Todo lo demás se BORRARÁ").unwrap();
    writeln!(out, "#").unwrap();
    for s in sessions {
        if keep_set.contains(&s.id) {
            writeln!(out, "{}\t# {} | {}", s.id, fmt_ts(s.time_created), s.title).unwrap();
        }
    }
    Ok(())
}

fn do_cleanup(db_path: &PathBuf, keep_file: &PathBuf) -> Result<String> {
    if !db_path.exists() {
        return Ok("Sin base de datos".to_string());
    }
    let sessions = load_sessions(db_path)?;
    let keep_set = load_keep(keep_file);
    if keep_set.is_empty() {
        return Ok("keep-sessions.txt vacío o sin IDs válidos".to_string());
    }
    let mut to_del: Vec<String> = Vec::new();
    for sess in &sessions {
        if !keep_set.contains(&sess.id) {
            to_del.push(sess.id.clone());
        }
    }
    if to_del.is_empty() {
        return Ok("Nada que borrar".to_string());
    }
    let cwd = env::current_dir()?;
    let backup_dir = cwd.join("backups");
    fs::create_dir_all(&backup_dir)?;
    let ts = Local::now().format("%Y%m%d_%H%M%S").to_string();
    let bkp = backup_dir.join(format!("opencode.db.{}", ts));
    let _ = fs::copy(db_path, &bkp);
    let conn = Connection::open(db_path)?;
    let mut cnt = 0;
    for id in &to_del {
        let _ = conn.execute("DELETE FROM message WHERE session_id = ?1", [id]);
        let _ = conn.execute("DELETE FROM part WHERE message_id IN (SELECT id FROM message WHERE session_id = ?1)", [id]);
        let _ = conn.execute("DELETE FROM todo WHERE session_id = ?1", [id]);
        let _ = conn.execute("DELETE FROM session_message WHERE session_id = ?1", [id]);
        let _ = conn.execute("DELETE FROM session_v2 WHERE id = ?1", [id]);
        let _ = conn.execute("DELETE FROM session WHERE id = ?1", [id]);
        cnt += 1;
    }
    let _ = conn.execute_batch("VACUUM;");
    Ok(format!("Eliminadas: {} | Backup: {}", cnt, bkp.display()))
}

fn main() -> Result<()> {
    let args: Vec<String> = env::args().collect();
    let auto = args.iter().any(|a| a == "--auto" || a == "--apply");

    let db_path = get_db_path()?;
    let sessions = load_sessions(&db_path)?;
    let mut keep_file = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    keep_file.push("keep-sessions.txt");
    let keep_set = load_keep(&keep_file);

    if auto {
        match do_cleanup(&db_path, &keep_file) {
            Ok(m) => println!("{}", m),
            Err(e) => {
                eprintln!("Error: {}", e);
                std::process::exit(1);
            }
        }
        return Ok(());
    }

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut app = App {
        mode: Mode::Menu,
        menu_idx: 0,
        sessions: sessions.clone(),
        table_state: TableState::default(),
        selected: vec![false; sessions.len()],
        keep_set: keep_set.clone(),
        keep_file,
        db_path: db_path.clone(),
        msg: if !db_path.exists() { "Sin base de datos".to_string() } else { "↑↓ navegar • ENTER seleccionar".to_string() },
    };
    for (i, s) in app.sessions.iter().enumerate() {
        app.selected[i] = app.keep_set.contains(&s.id);
    }
    if !app.sessions.is_empty() {
        app.table_state.select(Some(0));
    }

    let res = run_app(&mut terminal, &mut app);
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), DisableMouseCapture)?;
    terminal.show_cursor()?;
    let _ = res;
    Ok(())
}

fn run_app<B: ratatui::backend::Backend>(terminal: &mut Terminal<B>, app: &mut App) -> Result<()> {
    loop {
        terminal.draw(|f| ui(f, app))?;
        if let Event::Key(key) = event::read()? {
            if key.kind != KeyEventKind::Press {
                continue;
            }
            match app.mode {
                Mode::Menu => match key.code {
                    KeyCode::Up => {
                        if app.menu_idx > 0 {
                            app.menu_idx -= 1;
                        }
                    }
                    KeyCode::Down => {
                        if app.menu_idx < 5 {
                            app.menu_idx += 1;
                        }
                    }
                    KeyCode::Char('0') | KeyCode::Char('q') | KeyCode::Char('Q') => {
                        return Ok(());
                    }
                    KeyCode::Enter => {
                        if app.menu_idx == 5 {
                            return Ok(());
                        }
                        match app.menu_idx {
                            0 => {
                                if app.sessions.is_empty() {
                                    app.msg = "Sin sesiones".to_string();
                                } else {
                                    app.mode = Mode::List;
                                    if app.table_state.selected().is_none() {
                                        app.table_state.select(Some(0));
                                    }
                                    app.msg = "↑↓ mover • ESC/q volver".to_string();
                                }
                            }
                            1 => {
                                if app.sessions.is_empty() {
                                    app.msg = "Sin sesiones".to_string();
                                } else {
                                    for (i, s) in app.sessions.iter().enumerate() {
                                        app.selected[i] = app.keep_set.contains(&s.id);
                                    }
                                    app.mode = Mode::Select;
                                    if app.table_state.selected().is_none() {
                                        app.table_state.select(Some(0));
                                    }
                                    app.msg = "ESPACIO alternar • A/N/I • ENTER guardar • ESC/q volver".to_string();
                                }
                            }
                            2 => {
                                if app.sessions.is_empty() {
                                    app.msg = "Sin sesiones".to_string();
                                } else {
                                    app.mode = Mode::EditKeep;
                                    let ks = load_keep(&app.keep_file);
                                    app.keep_set = ks;
                                    for (i, s) in app.sessions.iter().enumerate() {
                                        app.selected[i] = app.keep_set.contains(&s.id);
                                    }
                                    if app.table_state.selected().is_none() {
                                        app.table_state.select(Some(0));
                                    }
                                    app.msg = "[x]=en keep-sessions.txt • ESPACIO añadir/quitar • ENTER guardar • ESC/q volver".to_string();
                                }
                            }
                            3 => {
                                if !app.keep_file.exists() {
                                    let _ = save_keep_from_set(&app.sessions, &app.keep_file, &HashSet::new());
                                }
                                app.mode = Mode::Auto;
                                app.msg = "ENTER confirmar • ESC/q volver".to_string();
                            }
                            4 => {
                                for (i, s) in app.sessions.iter().enumerate() {
                                    app.selected[i] = true;
                                    app.keep_set.insert(s.id.clone());
                                }
                                let _ = save_keep_from_set(&app.sessions, &app.keep_file, &app.keep_set);
                                app.msg = format!("Guardado {}", app.keep_file.display());
                            }
                            5 => {
                                return Ok(());
                            }
                            _ => {}
                        }
                    },
                    _ => {}
                },
                Mode::List => match key.code {
                    KeyCode::Up => {
                        let i = app.table_state.selected().unwrap_or(0);
                        if i > 0 {
                            app.table_state.select(Some(i - 1));
                        }
                    }
                    KeyCode::Down => {
                        let i = app.table_state.selected().unwrap_or(0);
                        if i + 1 < app.sessions.len() {
                            app.table_state.select(Some(i + 1));
                        }
                    }
                    KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('Q') => app.mode = Mode::Menu,
                    _ => {}
                },
                Mode::Select => match key.code {
                    KeyCode::Up => {
                        let i = app.table_state.selected().unwrap_or(0);
                        if i > 0 {
                            app.table_state.select(Some(i - 1));
                        }
                    }
                    KeyCode::Down => {
                        let i = app.table_state.selected().unwrap_or(0);
                        if i + 1 < app.sessions.len() {
                            app.table_state.select(Some(i + 1));
                        }
                    }
                    KeyCode::Char(' ') => {
                        if let Some(i) = app.table_state.selected() {
                            app.selected[i] = !app.selected[i];
                        }
                    }
                    KeyCode::Char('a') | KeyCode::Char('A') => {
                        for v in app.selected.iter_mut() {
                            *v = true;
                        }
                    }
                    KeyCode::Char('n') | KeyCode::Char('N') => {
                        for v in app.selected.iter_mut() {
                            *v = false;
                        }
                    }
                    KeyCode::Char('i') | KeyCode::Char('I') => {
                        for v in app.selected.iter_mut() {
                            *v = !*v;
                        }
                    }
                    KeyCode::Enter => {
                        app.keep_set.clear();
                        for (i, s) in app.sessions.iter().enumerate() {
                            if app.selected[i] {
                                app.keep_set.insert(s.id.clone());
                            }
                        }
                        let _ = save_keep_from_set(&app.sessions, &app.keep_file, &app.keep_set);
                        app.msg = format!("Guardado {}", app.keep_file.display());
                        app.mode = Mode::Menu;
                    }
                    KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('Q') => app.mode = Mode::Menu,
                    _ => {}
                },
                Mode::EditKeep => match key.code {
                    KeyCode::Up => {
                        let i = app.table_state.selected().unwrap_or(0);
                        if i > 0 {
                            app.table_state.select(Some(i - 1));
                        }
                    }
                    KeyCode::Down => {
                        let i = app.table_state.selected().unwrap_or(0);
                        if i + 1 < app.sessions.len() {
                            app.table_state.select(Some(i + 1));
                        }
                    }
                    KeyCode::Char(' ') => {
                        if let Some(i) = app.table_state.selected() {
                            app.selected[i] = !app.selected[i];
                            let id = app.sessions[i].id.clone();
                            if app.selected[i] {
                                app.keep_set.insert(id);
                            } else {
                                app.keep_set.remove(&id);
                            }
                        }
                    }
                    KeyCode::Enter => {
                        let _ = save_keep_from_set(&app.sessions, &app.keep_file, &app.keep_set);
                        app.msg = format!("Actualizado {}", app.keep_file.display());
                        app.mode = Mode::Menu;
                    }
                    KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('Q') => app.mode = Mode::Menu,
                    _ => {}
                },
                Mode::Auto => match key.code {
                    KeyCode::Enter => {
                        app.mode = Mode::Confirm;
                        app.msg = "Confirmar borrado".to_string();
                    }
                    KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('Q') => app.mode = Mode::Menu,
                    _ => {}
                },
                Mode::Confirm => match key.code {
                    KeyCode::Enter => {
                        match do_cleanup(&app.db_path, &app.keep_file) {
                            Ok(m) => {
                                app.msg = m;
                                app.mode = Mode::Done;
                            }
                            Err(e) => {
                                app.msg = format!("Error: {}", e);
                                app.mode = Mode::Done;
                            }
                        }
                    }
                    KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('Q') => app.mode = Mode::Menu,
                    _ => {}
                },
                Mode::Done => match key.code {
                    KeyCode::Enter | KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('Q') => return Ok(()),
                    _ => {}
                },
            }
        }
    }
}

fn ui(f: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(0), Constraint::Length(3)])
        .split(f.area());

    match app.mode {
        Mode::Menu => {
            let items = vec![
                "1) Ver sesiones",
                "2) Seleccionar conservar/eliminar",
                "3) Editar keep-sessions.txt",
                "4) Limpieza automática",
                "5) Marcar todas y guardar",
                "0) Salir",
            ];
            let rows: Vec<Row> = items
                .iter()
                .enumerate()
                .map(|(i, it)| {
                    if i == app.menu_idx {
                        Row::new(vec![Cell::from(*it).style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))])
                    } else {
                        Row::new(vec![Cell::from(*it).style(Style::default().fg(Color::White))])
                    }
                })
                .collect();
            let info = format!("SESSION-CLEANUP | Sesiones: {} | En keep: {}", app.sessions.len(), app.keep_set.len());
            let table = Table::new(rows, [Constraint::Percentage(100)])
                .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::DarkGray)).title(info));
            f.render_widget(table, chunks[0]);
        }
        Mode::List => {
            let header_cells = ["Fecha", "ID", "Tipo", "Título"];
            let header = Row::new(header_cells)
                .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
                .height(1);
            let rows: Vec<Row> = app
                .sessions
                .iter()
                .map(|s| {
                    let typ = if s.parent.is_none() { "[RAÍZ]" } else { "[SUB]" };
                    Row::new(vec![
                        Cell::from(fmt_ts(s.time_created)),
                        Cell::from(s.id.clone()),
                        Cell::from(typ),
                        Cell::from(truncate(&s.title, 72)),
                    ])
                })
                .collect();
            let table = Table::new(rows, [Constraint::Length(16), Constraint::Length(25), Constraint::Length(6), Constraint::Min(40)])
                .header(header)
                .block(Block::default().borders(Borders::ALL).title("Sesiones • ESC/q volver"))
                .highlight_style(Style::default().bg(Color::DarkGray));
            f.render_stateful_widget(table, chunks[0], &mut app.table_state.clone());
        }
        Mode::Select => {
            let header_cells = ["", "Fecha", "ID", "Tipo", "Título"];
            let header = Row::new(header_cells)
                .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
                .height(1);
            let rows: Vec<Row> = app
                .sessions
                .iter()
                .enumerate()
                .map(|(i, s)| {
                    let mark = if app.selected[i] { "[x]" } else { "[ ]" };
                    let typ = if s.parent.is_none() { "[RAÍZ]" } else { "[SUB]" };
                    Row::new(vec![
                        Cell::from(mark).style(Style::default().fg(if app.selected[i] { Color::Green } else { Color::Red })),
                        Cell::from(fmt_ts(s.time_created)),
                        Cell::from(s.id.clone()),
                        Cell::from(typ),
                        Cell::from(truncate(&s.title, 58)),
                    ])
                })
                .collect();
            let table = Table::new(rows, [Constraint::Length(3), Constraint::Length(16), Constraint::Length(25), Constraint::Length(6), Constraint::Min(40)])
                .header(header)
                .block(Block::default().borders(Borders::ALL).title("[x]=conservar • ESPACIO/A/N/I • ENTER guardar • ESC/q volver"))
                .highlight_style(Style::default().bg(Color::DarkGray));
            f.render_stateful_widget(table, chunks[0], &mut app.table_state.clone());
        }
        Mode::EditKeep => {
            let header_cells = ["", "Fecha", "ID", "Tipo", "Título"];
            let header = Row::new(header_cells)
                .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
                .height(1);
            let rows: Vec<Row> = app
                .sessions
                .iter()
                .enumerate()
                .map(|(i, s)| {
                    let mark = if app.selected[i] { "[x]" } else { "[ ]" };
                    let typ = if s.parent.is_none() { "[RAÍZ]" } else { "[SUB]" };
                    Row::new(vec![
                        Cell::from(mark).style(Style::default().fg(if app.selected[i] { Color::Green } else { Color::Red })),
                        Cell::from(fmt_ts(s.time_created)),
                        Cell::from(s.id.clone()),
                        Cell::from(typ),
                        Cell::from(truncate(&s.title, 58)),
                    ])
                })
                .collect();
            let table = Table::new(rows, [Constraint::Length(3), Constraint::Length(16), Constraint::Length(25), Constraint::Length(6), Constraint::Min(40)])
                .header(header)
                .block(Block::default().borders(Borders::ALL).title("[x]=EN ARCHIVO • ESPACIO añadir/quitar • ENTER guardar • ESC/q volver"))
                .highlight_style(Style::default().bg(Color::DarkGray));
            f.render_stateful_widget(table, chunks[0], &mut app.table_state.clone());
        }
        Mode::Auto => {
            let p = Paragraph::new(vec![
                Line::from(""),
                Line::from("LIMPIEZA AUTOMÁTICA"),
                Line::from(""),
                Line::from("Solo se conservan las sesiones en keep-sessions.txt"),
                Line::from("El resto se elimina"),
                Line::from(""),
                Line::from("ENTER confirmar • ESC/q volver"),
            ])
            .alignment(ratatui::layout::Alignment::Center)
            .block(Block::default().borders(Borders::ALL));
            f.render_widget(p, chunks[0]);
        }
        Mode::Confirm => {
            let p = Paragraph::new(vec![
                Line::from(""),
                Line::from("CONFIRMAR BORRADO"),
                Line::from(""),
                Line::from("Se creará backup"),
                Line::from(""),
                Line::from("ENTER ejecutar • ESC/q cancelar"),
            ])
            .alignment(ratatui::layout::Alignment::Center)
            .block(Block::default().borders(Borders::ALL));
            f.render_widget(p, chunks[0]);
        }
        Mode::Done => {
            let p = Paragraph::new(vec![
                Line::from(""),
                Line::from("COMPLETADO"),
                Line::from(""),
                Line::from(app.msg.clone()),
                Line::from(""),
                Line::from("ENTER/ESC/q salir"),
            ])
            .alignment(ratatui::layout::Alignment::Center)
            .block(Block::default().borders(Borders::ALL));
            f.render_widget(p, chunks[0]);
        }
    }

    let status = Paragraph::new(app.msg.clone())
        .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::DarkGray)))
        .style(Style::default().fg(Color::DarkGray));
    f.render_widget(status, chunks[1]);
}
