//! An app's own settings: `$XDG_CONFIG_HOME/atlas-<app>rc` (default
//! `~/.config`), in KConfig's INI format, so KDE tools and the app's C++ side
//! can read the same file.
//!
//! ```no_run
//! # let app = atlas_framework_core::app_info! { name: "N", id: "net.eterneon.atlas.n", repo: "r" };
//! use atlas_framework_core::settings::Settings;
//! let s = Settings::for_app(&app);
//! s.set("Restart", "ScheduledAt", Some("1700000000"))?;
//! assert_eq!(s.get("Restart", "ScheduledAt").as_deref(), Some("1700000000"));
//! # Ok::<(), std::io::Error>(())
//! ```
//!
//! Each [`Settings::set`] reads the file, changes one key and replaces the
//! file atomically, keeping every other line as it was. Two processes setting
//! keys at the same moment can lose one of the two changes, never the file.

use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

use crate::AppInfo;

/// One settings file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Settings {
    path: PathBuf,
}

impl Settings {
    /// `atlas-updaterrc` for `net.eterneon.atlas.updater`, in [`config_dir`].
    pub fn for_app(app: &AppInfo) -> Settings {
        Settings::at(config_dir().join(format!("{}rc", app.short_name())))
    }

    pub fn at(path: impl Into<PathBuf>) -> Settings {
        Settings { path: path.into() }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// The value, unescaped; `None` if the file, group or key is missing.
    pub fn get(&self, group: &str, key: &str) -> Option<String> {
        get_in(&fs::read_to_string(&self.path).ok()?, group, key)
    }

    pub fn get_bool(&self, group: &str, key: &str) -> Option<bool> {
        match self.get(group, key)?.to_ascii_lowercase().as_str() {
            "true" | "1" | "yes" | "on" => Some(true),
            "false" | "0" | "no" | "off" => Some(false),
            _ => None,
        }
    }

    /// Sets `group`/`key`; `None` removes it. Writes nothing when the file
    /// would not change, and never overwrites a file it couldn't read.
    pub fn set(&self, group: &str, key: &str, value: Option<&str>) -> io::Result<()> {
        // A symlinked rc file (dotfiles) keeps its link: write the target.
        let target = match fs::symlink_metadata(&self.path) {
            Ok(m) if m.file_type().is_symlink() => fs::canonicalize(&self.path)?,
            _ => self.path.clone(),
        };
        let (text, mode) = match fs::read_to_string(&target) {
            Ok(t) => {
                let mode = fs::metadata(&target)?.permissions().mode() & 0o7777;
                (t, mode)
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => (String::new(), 0o600),
            Err(e) => return Err(e),
        };
        let out = set_in(&text, group, key, value);
        if out == text {
            return Ok(());
        }
        if let Some(dir) = target.parent() {
            fs::create_dir_all(dir)?;
        }
        replace(&target, out.as_bytes(), mode)
    }
}

/// `$XDG_CONFIG_HOME`, else `~/.config`. Relative values are ignored, as the
/// XDG spec says.
pub fn config_dir() -> PathBuf {
    let abs = |k: &str| {
        std::env::var_os(k)
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
    };
    abs("XDG_CONFIG_HOME")
        .or_else(|| abs("HOME").map(|h| h.join(".config")))
        .unwrap_or_else(|| PathBuf::from("/nonexistent"))
}

/// Write a temp file beside `path`, sync it and rename it over `path`: a
/// crash never leaves a half-written file.
fn replace(path: &Path, bytes: &[u8], mode: u32) -> io::Result<()> {
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    let tmp = path.with_file_name(format!(".{name}.tmp{}", std::process::id()));
    let written = (|| {
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(mode)
            .custom_flags(libc::O_NOFOLLOW)
            .open(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
        fs::rename(&tmp, path)
    })();
    if written.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    written
}

fn header(line: &str) -> Option<&str> {
    line.trim().strip_prefix('[')?.strip_suffix(']')
}

/// The key of a `key=value` line, without KConfig's `[$i]`-style options.
fn line_key(line: &str) -> Option<&str> {
    let (k, _) = line.split_once('=')?;
    let k = k.trim();
    Some(match k.find("[$") {
        Some(i) if k.ends_with(']') => &k[..i],
        _ => k,
    })
}

/// The value of `group`/`key` in KConfig text, unescaped.
pub fn get_in(text: &str, group: &str, key: &str) -> Option<String> {
    let mut in_group = false;
    for line in text.lines() {
        if let Some(g) = header(line) {
            in_group = g == group;
        } else if in_group && line_key(line) == Some(key) {
            let (_, v) = line.split_once('=')?;
            return Some(unescape(v.trim()));
        }
    }
    None
}

/// `text` with `group`/`key` set to `value` (escaped), or removed for `None`.
pub fn set_in(text: &str, group: &str, key: &str, value: Option<&str>) -> String {
    let mut out: Vec<String> = Vec::new();
    let mut in_group = false;
    let mut group_seen = false;
    let mut done = false;
    let new_line = value.map(|v| format!("{key}={}", escape(v)));
    let flush = |out: &mut Vec<String>, done: &mut bool| {
        if !*done {
            if let Some(l) = &new_line {
                // Insert before trailing blank lines of the group.
                let mut at = out.len();
                while at > 0 && out[at - 1].trim().is_empty() {
                    at -= 1;
                }
                out.insert(at, l.clone());
            }
            *done = true;
        }
    };
    for line in text.lines() {
        if let Some(g) = header(line) {
            if in_group {
                flush(&mut out, &mut done);
            }
            in_group = g == group;
            group_seen |= in_group;
            out.push(line.to_string());
            continue;
        }
        if in_group && line_key(line) == Some(key) {
            if !done {
                if let Some(l) = &new_line {
                    out.push(l.clone());
                }
                done = true;
            }
            continue;
        }
        out.push(line.to_string());
    }
    if in_group {
        flush(&mut out, &mut done);
    }
    if !group_seen
        && !done
        && let Some(l) = &new_line
    {
        if !out.is_empty() && !out.last().is_some_and(|l| l.trim().is_empty()) {
            out.push(String::new());
        }
        out.push(format!("[{group}]"));
        out.push(l.clone());
    }
    let mut s = out.join("\n");
    if !s.is_empty() {
        s.push('\n');
    }
    s
}

/// KConfig's escaping: a value stays on one line and keeps its edge spaces.
fn escape(v: &str) -> String {
    let mut out = String::with_capacity(v.len());
    let last = v.chars().count().saturating_sub(1);
    for (i, c) in v.chars().enumerate() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            ' ' if i == 0 || i == last => out.push_str("\\s"),
            c if (c as u32) < 0x20 || c == '\u{7f}' => {
                out.push_str(&format!("\\x{:02x}", c as u32))
            }
            c => out.push(c),
        }
    }
    out
}

fn unescape(v: &str) -> String {
    let mut out = String::with_capacity(v.len());
    let mut chars = v.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('s') => out.push(' '),
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some('r') => out.push('\r'),
            Some('x') => {
                let hex: String = chars.clone().take(2).collect();
                match u8::from_str_radix(&hex, 16) {
                    Ok(b) if hex.len() == 2 => {
                        out.push(char::from(b));
                        chars.nth(1);
                    }
                    _ => out.push_str("\\x"),
                }
            }
            Some(n) => out.push(n),
            None => out.push('\\'),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn set_get_remove() {
        let t = set_in("", "Restart", "ScheduledAt", Some("100"));
        assert_eq!(t, "[Restart]\nScheduledAt=100\n");
        assert_eq!(get_in(&t, "Restart", "ScheduledAt").as_deref(), Some("100"));
        let t = set_in(&t, "Restart", "ScheduledAt", Some("200"));
        assert_eq!(get_in(&t, "Restart", "ScheduledAt").as_deref(), Some("200"));
        let t = set_in(&t, "Notified", "Digest", Some("sha256:x"));
        let t = set_in(&t, "Restart", "ScheduledAt", None);
        assert_eq!(get_in(&t, "Restart", "ScheduledAt"), None);
        assert_eq!(
            get_in(&t, "Notified", "Digest").as_deref(),
            Some("sha256:x")
        );
    }

    #[test]
    fn keeps_other_groups() {
        let t = "[General]\nA=1\n\n[Restart]\nB=2\n";
        let t = set_in(t, "Restart", "ScheduledAt", Some("5"));
        assert_eq!(t, "[General]\nA=1\n\n[Restart]\nB=2\nScheduledAt=5\n");
    }

    #[test]
    fn escapes_like_kconfig() {
        let v = " two\nlines\\ \u{1}";
        let t = set_in("", "G", "K", Some(v));
        assert_eq!(t, "[G]\nK=\\stwo\\nlines\\\\ \\x01\n");
        assert_eq!(get_in(&t, "G", "K").as_deref(), Some(v));
        assert_eq!(
            get_in("[G]\nK=a\\;b\\xzz\n", "G", "K").as_deref(),
            Some("a;b\\xzz")
        );
    }

    #[test]
    fn options_on_keys() {
        let t = "[G]\nK[$i]=locked\n";
        assert_eq!(get_in(t, "G", "K").as_deref(), Some("locked"));
        assert_eq!(get_in(t, "G", "K[$i]"), None);
    }

    #[test]
    fn file_round_trip_and_mode() {
        let dir = tempfile::tempdir().unwrap();
        let s = Settings::at(dir.path().join("sub/atlas-xrc"));
        assert_eq!(s.get("G", "K"), None);
        s.set("G", "K", Some("v")).unwrap();
        s.set("G", "On", Some("true")).unwrap();
        assert_eq!(s.get("G", "K").as_deref(), Some("v"));
        assert_eq!(s.get_bool("G", "On"), Some(true));
        let mode = fs::metadata(s.path()).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
        // only the file itself is left: no temp files
        assert_eq!(fs::read_dir(dir.path().join("sub")).unwrap().count(), 1);
    }

    #[test]
    fn writes_through_a_symlink() {
        let dir = tempfile::tempdir().unwrap();
        let real = dir.path().join("real");
        fs::write(&real, "[G]\nA=1\n").unwrap();
        fs::set_permissions(&real, fs::Permissions::from_mode(0o640)).unwrap();
        let link = dir.path().join("atlas-xrc");
        std::os::unix::fs::symlink(&real, &link).unwrap();
        Settings::at(&link).set("G", "B", Some("2")).unwrap();
        assert!(
            fs::symlink_metadata(&link)
                .unwrap()
                .file_type()
                .is_symlink()
        );
        assert_eq!(fs::read_to_string(&real).unwrap(), "[G]\nA=1\nB=2\n");
        assert_eq!(
            fs::metadata(&real).unwrap().permissions().mode() & 0o777,
            0o640
        );
    }

    #[test]
    fn unreadable_file_is_not_replaced() {
        let dir = tempfile::tempdir().unwrap();
        // a directory where the file should be: reading fails, not NotFound
        fs::create_dir(dir.path().join("atlas-xrc")).unwrap();
        assert!(
            Settings::at(dir.path().join("atlas-xrc"))
                .set("G", "K", Some("v"))
                .is_err()
        );
    }
}
