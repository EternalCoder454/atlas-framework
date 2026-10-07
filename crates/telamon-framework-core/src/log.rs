//! Logging for Telamon apps: the `log` crate's macros (`log::info!` and the
//! rest), sent straight to the systemd journal with a priority, the app's
//! identifier and the source line, so `journalctl -t telamon-updater` finds an
//! app's messages. Without a journal (a container, a test) they go to stderr.
//!
//! [`init`] once, first thing. `TELAMON_LOG=debug` (or `error`, `warn`, `info`,
//! `trace`, `off`) changes the level; the default is `info`. `ATLAS_LOG`, the
//! name before 2.0.0, is read when `TELAMON_LOG` is not set.

use std::io::Write;
use std::os::unix::net::UnixDatagram;
use std::path::{Path, PathBuf};

use ::log::{Level, LevelFilter, Log, Metadata, Record};

use crate::AppInfo;

const JOURNAL_SOCKET: &str = "/run/systemd/journal/socket";
/// Longer messages are cut: one datagram must hold the whole entry.
const MAX_MESSAGE: usize = 32 * 1024;

/// Install the logger for `app`. Later calls do nothing, so a library may
/// call it too.
pub fn init(app: &AppInfo) {
    let level = level_from(level_env(|k| std::env::var(k).ok()).as_deref());
    let logger = Journal::new(app.short_name(), Path::new(JOURNAL_SOCKET));
    if ::log::set_boxed_logger(Box::new(logger)).is_ok() {
        ::log::set_max_level(level);
    }
}

/// `TELAMON_LOG`, else the 1.x name `ATLAS_LOG`.
fn level_env(get: impl Fn(&str) -> Option<String>) -> Option<String> {
    get("TELAMON_LOG").or_else(|| get("ATLAS_LOG"))
}

fn level_from(v: Option<&str>) -> LevelFilter {
    v.and_then(|v| v.trim().parse().ok())
        .unwrap_or(LevelFilter::Info)
}

struct Journal {
    ident: String,
    /// `None` when there's no journal: write to stderr.
    socket: Option<(UnixDatagram, PathBuf)>,
}

impl Journal {
    fn new(ident: String, path: &Path) -> Journal {
        // Non-blocking: a stalled journal must not stall the app (its GUI
        // thread logs too). A message it can't take goes to stderr.
        let socket = path
            .exists()
            .then(UnixDatagram::unbound)
            .and_then(Result::ok)
            .filter(|s| s.set_nonblocking(true).is_ok())
            .map(|s| (s, path.to_path_buf()));
        Journal { ident, socket }
    }
}

impl Log for Journal {
    fn enabled(&self, metadata: &Metadata) -> bool {
        metadata.level() <= ::log::max_level()
    }

    fn log(&self, record: &Record) {
        if !self.enabled(record.metadata()) {
            return;
        }
        let mut message = record.args().to_string();
        truncate(&mut message, MAX_MESSAGE);
        if let Some((sock, path)) = &self.socket {
            let entry = entry(&self.ident, record, &message);
            if sock.send_to(&entry, path).is_ok() {
                return;
            }
        }
        let _ = writeln!(
            std::io::stderr().lock(),
            "{}: {}: {}",
            self.ident,
            record.level().as_str().to_ascii_lowercase(),
            for_terminal(&message)
        );
    }

    fn flush(&self) {}
}

/// syslog priorities: error 3, warning 4, info 6, debug 7.
fn priority(level: Level) -> u8 {
    match level {
        Level::Error => 3,
        Level::Warn => 4,
        Level::Info => 6,
        Level::Debug | Level::Trace => 7,
    }
}

/// One entry in the journal's native protocol (systemd.journal-fields(7)).
fn entry(ident: &str, record: &Record, message: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(message.len() + 128);
    field(&mut out, "MESSAGE", message);
    field(&mut out, "PRIORITY", &priority(record.level()).to_string());
    field(&mut out, "SYSLOG_IDENTIFIER", ident);
    field(&mut out, "TELAMON_TARGET", record.target());
    if let Some(file) = record.file() {
        field(&mut out, "CODE_FILE", file);
    }
    if let Some(line) = record.line() {
        field(&mut out, "CODE_LINE", &line.to_string());
    }
    out
}

/// `NAME=value\n`, or for a value with a newline in it
/// `NAME\n<64-bit little-endian length><value>\n`.
fn field(out: &mut Vec<u8>, name: &str, value: &str) {
    out.extend_from_slice(name.as_bytes());
    if value.contains('\n') {
        out.push(b'\n');
        out.extend_from_slice(&(value.len() as u64).to_le_bytes());
    } else {
        out.push(b'=');
    }
    out.extend_from_slice(value.as_bytes());
    out.push(b'\n');
}

/// A message for a terminal: control characters other than newline and tab
/// (escape sequences) are shown, not obeyed.
fn for_terminal(s: &str) -> std::borrow::Cow<'_, str> {
    if !s.chars().any(|c| c.is_control() && c != '\n' && c != '\t') {
        return s.into();
    }
    s.chars()
        .map(|c| match c {
            '\n' | '\t' => c.to_string(),
            c if c.is_control() => c.escape_unicode().to_string(),
            c => c.to_string(),
        })
        .collect::<String>()
        .into()
}

fn truncate(s: &mut String, max: usize) {
    if s.len() > max {
        let mut at = max;
        while !s.is_char_boundary(at) {
            at -= 1;
        }
        s.truncate(at);
        s.push('…');
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(message: &str) -> Vec<u8> {
        let args = format_args!("{message}");
        let r = Record::builder()
            .args(args)
            .level(Level::Warn)
            .target("t")
            .file(Some("src/x.rs"))
            .line(Some(7))
            .build();
        entry("telamon-x", &r, message)
    }

    #[test]
    fn simple_fields() {
        let e = String::from_utf8(record("hello")).unwrap();
        assert_eq!(
            e,
            "MESSAGE=hello\nPRIORITY=4\nSYSLOG_IDENTIFIER=telamon-x\nTELAMON_TARGET=t\n\
             CODE_FILE=src/x.rs\nCODE_LINE=7\n"
        );
    }

    #[test]
    fn multi_line_message_is_length_prefixed() {
        let e = record("a\nb");
        let mut want = b"MESSAGE\n".to_vec();
        want.extend_from_slice(&3u64.to_le_bytes());
        want.extend_from_slice(b"a\nb\n");
        assert!(e.starts_with(&want));
    }

    #[test]
    fn sends_to_the_socket() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("socket");
        let server = UnixDatagram::bind(&path).unwrap();
        let j = Journal::new("telamon-x".into(), &path);
        ::log::set_max_level(LevelFilter::Info);
        j.log(
            &Record::builder()
                .args(format_args!("over the socket"))
                .level(Level::Error)
                .build(),
        );
        let mut buf = [0u8; 512];
        let n = server.recv(&mut buf).unwrap();
        let got = String::from_utf8_lossy(&buf[..n]);
        assert!(
            got.starts_with("MESSAGE=over the socket\nPRIORITY=3\n"),
            "{got}"
        );
    }

    #[test]
    fn the_old_variable_still_sets_the_level() {
        let env = |pairs: &'static [(&'static str, &'static str)]| {
            level_env(move |k| {
                pairs
                    .iter()
                    .find(|(n, _)| *n == k)
                    .map(|(_, v)| v.to_string())
            })
        };
        assert_eq!(env(&[]), None);
        assert_eq!(env(&[("ATLAS_LOG", "debug")]).as_deref(), Some("debug"));
        assert_eq!(env(&[("TELAMON_LOG", "warn")]).as_deref(), Some("warn"));
        // The new name wins.
        assert_eq!(
            env(&[("ATLAS_LOG", "debug"), ("TELAMON_LOG", "warn")]).as_deref(),
            Some("warn")
        );
    }

    #[test]
    fn levels_and_truncation() {
        assert_eq!(level_from(None), LevelFilter::Info);
        assert_eq!(level_from(Some("debug")), LevelFilter::Debug);
        assert_eq!(level_from(Some("nonsense")), LevelFilter::Info);
        let mut s = "ééé".to_string();
        truncate(&mut s, 3);
        assert_eq!(s, "é…");
        assert_eq!(for_terminal("a\nb\tc"), "a\nb\tc");
        assert_eq!(for_terminal("\u{1b}[2J"), "\\u{1b}[2J");
    }
}
