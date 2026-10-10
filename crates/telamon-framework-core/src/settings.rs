//! An app's own settings: `$XDG_CONFIG_HOME/telamon-<app>rc` (default
//! `~/.config`), in KConfig's INI format, so KDE tools and the app's C++ side
//! can read the same file.
//!
//! ```no_run
//! # let app = telamon_framework_core::app_info! { name: "N", id: "net.eterneon.telamon.n", repo: "r" };
//! use telamon_framework_core::settings::Settings;
//! let s = Settings::for_app(&app);
//! s.set("Restart", "ScheduledAt", Some("1700000000"))?;
//! assert_eq!(s.get("Restart", "ScheduledAt").as_deref(), Some("1700000000"));
//! # Ok::<(), std::io::Error>(())
//! ```
//!
//! Each [`Settings::set`] reads the file, changes one key and replaces the
//! file atomically, keeping every other line, its mode and its owner. Writers
//! take a lock (a thread lock, and `flock` on `.<name>.lock` beside the file,
//! which stays: removing it would race the next writer),
//! so concurrent `set`s in Telamon code never lose a change; another program
//! writing the file without the lock can still race, but never corrupts it.
//! Keys and groups KConfig marks immutable (`[$i]`) are refused.
//!
//! [`Settings::migrate`] upgrades an older file in place, keeping a `.bak`;
//! [`Settings::watch`] reports changes, also from editors that replace the file.

use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

use crate::AppInfo;

mod legacy;
mod migrate;
mod watch;

pub use migrate::{MigrateError, Migrated, Migration, SCHEMA_GROUP, SCHEMA_KEY};
pub use watch::{DEBOUNCE, SettingsWatcher, Snapshot};

/// One settings file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Settings {
    path: PathBuf,
}

impl Settings {
    /// `telamon-updaterrc` for `net.eterneon.telamon.updater`, in [`config_dir`].
    ///
    /// The first time, when that file does not exist yet but the one an app
    /// of the framework's 1.x releases kept (`atlas-updaterrc`, see
    /// [`AppInfo::legacy_short_name`]) does, the old file is copied to the new
    /// name with its `[Atlas]` group renamed to `[Telamon]`, so the app keeps
    /// its settings. The old file is left as it is.
    pub fn for_app(app: &AppInfo) -> Settings {
        Settings::for_app_in(&config_dir(), app)
    }

    fn for_app_in(dir: &Path, app: &AppInfo) -> Settings {
        let new = dir.join(format!("{}rc", app.short_name()));
        let old = dir.join(format!("{}rc", app.legacy_short_name()));
        if !new.starts_with(NO_HOME) {
            match legacy::adopt(&new, &old) {
                Ok(true) => log::info!("settings: copied {} to {}", old.display(), new.display()),
                Ok(false) => {}
                Err(e) => log::warn!(
                    "settings: could not copy {} to {}: {e}",
                    old.display(),
                    new.display()
                ),
            }
        }
        Settings::at(new)
    }

    pub fn at(path: impl Into<PathBuf>) -> Settings {
        Settings { path: path.into() }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// The value, unescaped; `None` if the file, group or key is missing.
    /// The last of duplicate keys wins, as in KConfig.
    pub fn get(&self, group: &str, key: &str) -> Option<String> {
        get_in(&read_text(&self.path).ok()?, group, key)
    }

    pub fn get_bool(&self, group: &str, key: &str) -> Option<bool> {
        parse_bool(&self.get(group, key)?)
    }

    /// Sets `group`/`key`; `None` removes it. Writes nothing when the file
    /// would not change, and never overwrites a file it couldn't read.
    /// Fails with `InvalidInput` for a group or key that can't be written as
    /// one (control characters, brackets, `=`, a group starting with `$`), and `PermissionDenied` for an
    /// immutable one. `TimedOut` after 2 s without the file lock, and
    /// `InvalidData` for a file that is not UTF-8 or over 4 MB: show the error.
    pub fn set(&self, group: &str, key: &str, value: Option<&str>) -> io::Result<()> {
        if migrate::migrating() {
            return Err(migrate::reentry());
        }
        check_group(group)?;
        check_name(key, &['[', ']', '='])?;
        if self.path.starts_with(NO_HOME) {
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                "no home directory to keep settings in",
            ));
        }
        let target = resolve_link(&self.path)?;
        // Nothing to change: no lock, no directory, so this works where the
        // app can read but not write.
        if !change(&target, group, key, value)?.1 {
            return Ok(());
        }
        if let Some(dir) = target.parent() {
            crate::fsutil::create_private_dir_all(dir)?;
        }
        // The file lock first, with its deadline: a stuck holder of one file
        // must not make writers of other files wait on the thread lock.
        let _file = lock(&target)?;
        let _thread = WRITERS.lock().unwrap_or_else(|e| e.into_inner());
        sweep_temps(&target);
        // Again under the lock: another writer may have changed it.
        let (out, changed, meta) = change(&target, group, key, value)?;
        if !changed {
            return Ok(());
        }
        replace(&target, out.as_bytes(), meta.as_ref())
    }
}

fn parse_bool(v: &str) -> Option<bool> {
    match v.to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => Some(true),
        "false" | "0" | "no" | "off" => Some(false),
        _ => None,
    }
}

/// The file's new text, whether that differs from what's there, and the
/// file's metadata (`None` if it doesn't exist yet).
fn change(
    target: &Path,
    group: &str,
    key: &str,
    value: Option<&str>,
) -> io::Result<(String, bool, Option<fs::Metadata>)> {
    let (text, meta) = match read_text_strict(target) {
        Ok(t) => (t, Some(fs::metadata(target)?)),
        Err(e) if e.kind() == io::ErrorKind::NotFound => (String::new(), None),
        Err(e) => return Err(e),
    };
    let out = set_in(&text, group, key, value);
    if out == text {
        return Ok((out, false, meta));
    }
    if immutable(&text, group, key) {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!("{group}/{key} is immutable"),
        ));
    }
    Ok((with_format(&text, out), true, meta))
}

/// The settings file's format version, in `[Telamon] Format=` (`[Atlas]` in
/// files from before 2.0.0, which also count). Written when a
/// file is first created or changed; never required when reading, so files
/// from before it, and files a newer app wrote (a higher number), read the
/// same. Only a change to how existing keys are read would raise it.
pub const FORMAT: u32 = 1;

/// `out` (the new text, derived from `old`) with `[Telamon] Format=` added
/// unless the file already has one (any number: a newer app's stays) or
/// KConfig would ignore the write. A new file gets it first.
fn with_format(old: &str, out: String) -> String {
    if out.is_empty()
        || get_in(&out, "Telamon", "Format").is_some()
        || get_in(&out, legacy::LEGACY_GROUP, "Format").is_some()
        || immutable(old, "Telamon", "Format")
    {
        return out;
    }
    if old.trim().is_empty() {
        return format!("[Telamon]\nFormat={FORMAT}\n\n{out}");
    }
    set_in(&out, "Telamon", "Format", Some(&FORMAT.to_string()))
}

/// Where [`config_dir`] points when there is no home: `set` refuses it.
const NO_HOME: &str = "/nonexistent";

/// `$XDG_CONFIG_HOME`, else `~/.config`. Relative values are ignored, as the
/// XDG spec says. With neither, `/nonexistent`, where nothing is written.
pub fn config_dir() -> PathBuf {
    let abs = |k: &str| {
        std::env::var_os(k)
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
    };
    abs("XDG_CONFIG_HOME")
        .or_else(|| abs("HOME").map(|h| h.join(".config")))
        .unwrap_or_else(|| PathBuf::from(NO_HOME))
}

/// A name that reads back as itself: no line breaks or brackets (or `=` in
/// a key), no edge spaces (trimmed on read), and not a comment (`#`, `;`).
fn check_name(name: &str, banned: &[char]) -> io::Result<()> {
    if name.is_empty()
        || name.trim() != name
        || name.starts_with(['#', ';'])
        || name.chars().any(|c| c.is_control() || banned.contains(&c))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("not a settings group or key: {name:?}"),
        ));
    }
    Ok(())
}

/// [`check_name`] for a group, which also cannot start with `$`: `[$i]` is
/// KConfig's mark for an immutable file, not a group.
fn check_group(group: &str) -> io::Result<()> {
    check_name(group, &['[', ']'])?;
    if group.starts_with('$') {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("not a settings group or key: {group:?}"),
        ));
    }
    Ok(())
}

/// A symlinked rc file (dotfiles) keeps its link: write its target, even one
/// that doesn't exist yet.
fn resolve_link(path: &Path) -> io::Result<PathBuf> {
    let mut path = path.to_path_buf();
    for _ in 0..40 {
        match fs::symlink_metadata(&path) {
            Ok(m) if m.file_type().is_symlink() => {
                let to = fs::read_link(&path)?;
                path = match path.parent() {
                    Some(dir) => dir.join(to),
                    None => to,
                };
            }
            _ => return Ok(path),
        }
    }
    Err(io::Error::other("too many levels of symbolic links"))
}

/// One writer at a time in this process (flock is per open file, so threads
/// sharing it need their own lock).
static WRITERS: Mutex<()> = Mutex::new(());

/// The biggest settings file read (4 MB; a real one is a few KB).
const MAX_BYTES: u64 = 4 * 1024 * 1024;

/// The file's text, read without blocking on a FIFO, only if it is a regular
/// file of at most [`MAX_BYTES`]. Bytes that are not UTF-8 become U+FFFD (for
/// reading only: see [`read_text_strict`]).
fn read_text(path: &Path) -> io::Result<String> {
    let bytes = crate::fsutil::read_capped(path, MAX_BYTES)?;
    Ok(String::from_utf8(bytes)
        .unwrap_or_else(|e| String::from_utf8_lossy(e.as_bytes()).into_owned()))
}

/// [`read_text`], but a file that is not valid UTF-8 is an `InvalidData`
/// error: a rewrite would replace the bad bytes of other lines (comments
/// included) with U+FFFD, so such a file is never rewritten.
fn read_text_strict(path: &Path) -> io::Result<String> {
    String::from_utf8(crate::fsutil::read_capped(path, MAX_BYTES)?).map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            "the settings file is not valid UTF-8; not rewriting it",
        )
    })
}

/// Whether `file` is a temp name [`replace`] makes for `name`:
/// `.<name>.tmp<digits>-<digits>`. Nothing else (a sibling's `.lock` file, a
/// user's `.foo.tmp.bak`) is ever a candidate.
fn is_temp_name(file: &str, name: &str) -> bool {
    let Some(rest) = file
        .strip_prefix('.')
        .and_then(|f| f.strip_prefix(name))
        .and_then(|f| f.strip_prefix(".tmp"))
    else {
        return false;
    };
    let digits = |t: &str| !t.is_empty() && t.bytes().all(|b| b.is_ascii_digit());
    rest.split_once('-')
        .is_some_and(|(a, b)| digits(a) && digits(b))
}

/// Remove temp files a crashed writer left, older than a day. Under the
/// lock, so no live writer's temp file is a candidate; best effort, and at
/// most once per process for each directory and name.
fn sweep_temps(path: &Path) {
    static DONE: Mutex<Vec<PathBuf>> = Mutex::new(Vec::new());
    let (Some(dir), Some(name)) = (path.parent(), path.file_name()) else {
        return;
    };
    {
        let mut done = DONE.lock().unwrap_or_else(|e| e.into_inner());
        if done.iter().any(|p| p == path) {
            return;
        }
        done.push(path.to_path_buf());
    }
    let dir = if dir.as_os_str().is_empty() {
        Path::new(".")
    } else {
        dir
    };
    let name = name.to_string_lossy();
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let day = std::time::Duration::from_secs(24 * 3600);
    for e in entries.flatten() {
        if !is_temp_name(&e.file_name().to_string_lossy(), &name) {
            continue;
        }
        let old = e
            .metadata()
            .ok()
            .filter(|m| m.is_file())
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.elapsed().ok())
            .is_some_and(|age| age > day);
        if old {
            let _ = fs::remove_file(e.path());
        }
    }
}

/// An exclusive `flock` on `.<name>.lock` beside `path`, held until dropped,
/// waited for at most 2 s (`TimedOut` after that).
/// Opened read-only (flock doesn't need more). Root gives a lock file it
/// creates to the directory's owner, so the user can still take it.
fn lock(path: &Path) -> io::Result<fs::File> {
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    let f = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(path.with_file_name(format!(".{name}.lock")))
        .or_else(|e| match e.kind() {
            // Someone else's lock file this user may only read.
            io::ErrorKind::PermissionDenied => fs::OpenOptions::new()
                .read(true)
                .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
                .open(path.with_file_name(format!(".{name}.lock"))),
            _ => Err(e),
        })?;
    // SAFETY: geteuid has no preconditions.
    if unsafe { libc::geteuid() } == 0
        && let Some(dir) = path.parent()
        && let Ok(d) = fs::metadata(if dir.as_os_str().is_empty() {
            Path::new(".")
        } else {
            dir
        })
        && f.metadata()?.uid() != d.uid()
    {
        std::os::unix::fs::fchown(&f, Some(d.uid()), Some(d.gid()))?;
    }
    crate::fsutil::lock_with_deadline(&f, crate::fsutil::LOCK_WAIT)?;
    Ok(f)
}

/// Write a temp file beside `path`, sync it and rename it over `path`, then
/// sync the directory: a crash leaves the old file or the new one, whole.
/// The new file gets the old one's mode and, when running as root, its owner.
fn replace(path: &Path, bytes: &[u8], old: Option<&fs::Metadata>) -> io::Result<()> {
    static COUNT: AtomicU64 = AtomicU64::new(0);
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    let tmp = path.with_file_name(format!(
        ".{name}.tmp{}-{}",
        std::process::id(),
        COUNT.fetch_add(1, Ordering::Relaxed)
    ));
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(&tmp)?;
    // Only this call's own temp file is ever removed.
    let written = (|| {
        if let Some(old) = old {
            // SAFETY: geteuid has no preconditions.
            if unsafe { libc::geteuid() } == 0 {
                std::os::unix::fs::fchown(&f, Some(old.uid()), Some(old.gid()))?;
            }
            // After any chown, which clears set-id bits; not through the umask.
            f.set_permissions(fs::Permissions::from_mode(old.mode() & 0o7777))?;
        }
        f.write_all(bytes)?;
        f.sync_all()?;
        fs::rename(&tmp, path)
    })();
    if written.is_err() {
        let _ = fs::remove_file(&tmp);
        return written;
    }
    if let Some(dir) = path.parent() {
        let dir = if dir.as_os_str().is_empty() {
            Path::new(".")
        } else {
            dir
        };
        // The new file is in place: a failed directory sync only makes it
        // less durable, which is no reason to report the write as failed.
        let _ = fs::File::open(dir).and_then(|d| d.sync_all());
    }
    Ok(())
}

/// A group header's name, without KConfig's trailing `[$i]`-style options.
fn header(line: &str) -> Option<&str> {
    header_and_options(line).map(|(g, _)| g)
}

/// `[Group][$i]` is `("Group", "i")`; a line `[$i]` alone (the whole file
/// is immutable) is `("", "i")`.
fn header_and_options(line: &str) -> Option<(&str, &str)> {
    let inner = line.trim().strip_prefix('[')?.strip_suffix(']')?;
    if let Some(opts) = inner.strip_prefix('$') {
        return Some(("", opts));
    }
    Some(match inner.rfind("][$") {
        Some(i) => (&inner[..i], &inner[i + 3..]),
        None => (inner, ""),
    })
}

/// Whether KConfig would ignore a change to `group`/`key`: the file, the
/// group or the key is marked `$i`.
fn immutable(text: &str, group: &str, key: &str) -> bool {
    let mut in_group = false;
    let mut seen_group = false;
    for line in text.lines() {
        if let Some((g, opts)) = header_and_options(line) {
            if g.is_empty() && !seen_group && opts.contains('i') {
                return true;
            }
            seen_group = true;
            in_group = g == group;
            if in_group && opts.contains('i') {
                return true;
            }
        } else if in_group
            && line_key(line) == Some(key)
            && let Some((k, _)) = line.split_once('=')
            && let Some(i) = k.find("[$")
            && k[i + 2..]
                .split(']')
                .next()
                .is_some_and(|o| o.contains('i'))
        {
            return true;
        }
    }
    false
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

/// The value of `group`/`key` in KConfig text, unescaped. The last of
/// duplicate keys wins, as in KConfig.
pub fn get_in(text: &str, group: &str, key: &str) -> Option<String> {
    let mut in_group = false;
    let mut found = None;
    for line in text.lines() {
        if let Some(g) = header(line) {
            in_group = g == group;
        } else if in_group
            && line_key(line) == Some(key)
            && let Some((_, v)) = line.split_once('=')
        {
            found = Some(unescape(trim_value(v)));
        }
    }
    found
}

/// A raw value without the blanks around it. Only ASCII ones: [`escape`] writes
/// an edge space as `\s`, so any other character (a no-break space, say) at
/// the edge is part of the value and must survive the round trip.
fn trim_value(v: &str) -> &str {
    v.trim_matches([' ', '\t', '\r', '\n'])
}

/// `text` with `group`/`key` set to `value` (escaped), or removed for `None`.
/// A `group` or `key` that [`Settings::set`] would refuse (line breaks or
/// other control characters, brackets, `=` in a key, edge spaces, a leading
/// `#` or `;`) cannot be written as itself and would forge other lines or
/// groups, so then `text` comes back unchanged.
pub fn set_in(text: &str, group: &str, key: &str, value: Option<&str>) -> String {
    if check_group(group).is_err() || check_name(key, &['[', ']', '=']).is_err() {
        return text.to_string();
    }
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
        let s = Settings::at(dir.path().join("sub/telamon-xrc"));
        assert_eq!(s.get("G", "K"), None);
        s.set("G", "K", Some("v")).unwrap();
        s.set("G", "On", Some("true")).unwrap();
        assert_eq!(s.get("G", "K").as_deref(), Some("v"));
        assert_eq!(s.get_bool("G", "On"), Some(true));
        let mode = fs::metadata(s.path()).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
        // the file and its lock file are left: no temp files
        let mut names: Vec<_> = fs::read_dir(dir.path().join("sub"))
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        names.sort();
        assert_eq!(names, [".telamon-xrc.lock", "telamon-xrc"]);
    }

    #[test]
    fn writes_through_a_symlink() {
        let dir = tempfile::tempdir().unwrap();
        let real = dir.path().join("real");
        fs::write(&real, "[G]\nA=1\n").unwrap();
        fs::set_permissions(&real, fs::Permissions::from_mode(0o640)).unwrap();
        let link = dir.path().join("telamon-xrc");
        std::os::unix::fs::symlink(&real, &link).unwrap();
        Settings::at(&link).set("G", "B", Some("2")).unwrap();
        assert!(
            fs::symlink_metadata(&link)
                .unwrap()
                .file_type()
                .is_symlink()
        );
        assert_eq!(
            fs::read_to_string(&real).unwrap(),
            "[G]\nA=1\nB=2\n\n[Telamon]\nFormat=1\n"
        );
        assert_eq!(
            fs::metadata(&real).unwrap().permissions().mode() & 0o777,
            0o640
        );
    }

    #[test]
    fn keeps_a_wide_mode_and_last_duplicate_wins() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("telamon-xrc");
        fs::write(&path, "[G]\nK=1\nK=2\n").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o666)).unwrap();
        let s = Settings::at(&path);
        assert_eq!(s.get("G", "K").as_deref(), Some("2"));
        s.set("G", "K", Some("3")).unwrap();
        assert_eq!(
            fs::read_to_string(&path).unwrap(),
            "[G]\nK=3\n\n[Telamon]\nFormat=1\n"
        );
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o666
        );
    }

    #[test]
    fn refuses_bad_names_and_immutable_entries() {
        let dir = tempfile::tempdir().unwrap();
        let s = Settings::at(dir.path().join("telamon-xrc"));
        for (g, k) in [
            ("G\n[H]", "K"),
            ("G]", "K"),
            ("G", "K=1"),
            ("G", "[K"),
            ("G", " K"),
            ("G ", "K"),
            ("G", "#K"),
            ("G", ";K"),
            ("", "K"),
            ("G", ""),
        ] {
            let e = s.set(g, k, Some("v")).unwrap_err();
            assert_eq!(e.kind(), io::ErrorKind::InvalidInput, "{g:?} {k:?}");
        }
        for text in ["[G]\nK[$i]=locked\n", "[G][$i]\nK=1\n", "[$i]\n[G]\nK=1\n"] {
            fs::write(s.path(), text).unwrap();
            let e = s.set("G", "K", Some("v")).unwrap_err();
            assert_eq!(e.kind(), io::ErrorKind::PermissionDenied, "{text:?}");
            assert_eq!(fs::read_to_string(s.path()).unwrap(), text);
        }
        // an immutable group doesn't lock the others; [G][$i] is still group G
        fs::write(s.path(), "[G][$i]\nK=1\n").unwrap();
        assert_eq!(s.get("G", "K").as_deref(), Some("1"));
        s.set("H", "K", Some("v")).unwrap();
        assert_eq!(s.get("H", "K").as_deref(), Some("v"));
    }

    #[test]
    fn options_other_than_i_are_not_immutable() {
        let t = "[G]\nK[$e][it]=x\n";
        assert!(!immutable(t, "G", "K"));
        assert!(immutable("[G]\nK[$ie]=x\n", "G", "K"));
    }

    #[test]
    fn unchanged_set_needs_no_write_access() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("telamon-xrc");
        fs::write(&path, "[G]\nK=v\n").unwrap();
        fs::set_permissions(dir.path(), fs::Permissions::from_mode(0o500)).unwrap();
        let r = Settings::at(&path).set("G", "K", Some("v"));
        fs::set_permissions(dir.path(), fs::Permissions::from_mode(0o700)).unwrap();
        r.unwrap();
        assert!(!dir.path().join(".telamon-xrc.lock").exists());
    }

    #[test]
    fn no_home_is_refused() {
        let s = Settings::at(Path::new(NO_HOME).join("telamon-xrc"));
        assert_eq!(
            s.set("G", "K", Some("v")).unwrap_err().kind(),
            io::ErrorKind::NotFound
        );
    }

    #[test]
    fn dangling_symlink_creates_its_target() {
        let dir = tempfile::tempdir().unwrap();
        let link = dir.path().join("telamon-xrc");
        std::os::unix::fs::symlink("real", &link).unwrap();
        Settings::at(&link).set("G", "K", Some("v")).unwrap();
        assert_eq!(
            fs::read_to_string(dir.path().join("real")).unwrap(),
            "[Telamon]\nFormat=1\n\n[G]\nK=v\n"
        );
    }

    /// Eight writers queue 80 sets behind one file lock, and every set syncs
    /// the file and its directory while it holds that lock. The lock's 2 s
    /// wait (`LOCK_WAIT`) is how long one set may wait, not how long a queue
    /// of 80 syncs may take: on a disk where a sync costs 15 ms or more
    /// (a loaded CI runner) the last writer legitimately gets `TimedOut`,
    /// which `set` documents. So a timed-out set is tried again, as an app
    /// would show the error and the user retry; what the test proves (no
    /// update is lost or torn, whatever the interleaving) is unchanged, and
    /// any other error still fails it.
    #[test]
    fn concurrent_sets_all_land() {
        let dir = tempfile::tempdir().unwrap();
        let s = Settings::at(dir.path().join("telamon-xrc"));
        let give_up = std::time::Instant::now() + std::time::Duration::from_secs(120);
        std::thread::scope(|scope| {
            for t in 0..8 {
                let s = &s;
                scope.spawn(move || {
                    for i in 0..10 {
                        loop {
                            match s.set("G", &format!("K{t}_{i}"), Some("v")) {
                                Ok(()) => break,
                                Err(e)
                                    if e.kind() == io::ErrorKind::TimedOut
                                        && std::time::Instant::now() < give_up => {}
                                Err(e) => panic!("set K{t}_{i}: {e}"),
                            }
                        }
                    }
                });
            }
        });
        for t in 0..8 {
            for i in 0..10 {
                assert_eq!(s.get("G", &format!("K{t}_{i}")).as_deref(), Some("v"));
            }
        }
    }

    #[test]
    fn non_utf8_content_reads_but_is_not_rewritten() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("telamon-xrc");
        fs::write(&path, b"[G]\nBad=\xff\xfe\nK=1\n").unwrap();
        let s = Settings::at(&path);
        assert_eq!(s.get("G", "K").as_deref(), Some("1"));
        let e = s.set("G", "K", Some("2")).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::InvalidData);
        assert_eq!(fs::read(&path).unwrap(), b"[G]\nBad=\xff\xfe\nK=1\n");
    }

    #[test]
    fn only_replace_temp_names_are_swept() {
        assert!(is_temp_name(".telamon-xrc.tmp12-3", "telamon-xrc"));
        for no in [
            ".telamon-xrc.tmp12-3.lock",
            ".telamon-xrc.tmp.bak",
            ".telamon-xrc.tmp12",
            ".telamon-xrc.tmpa-1",
            ".telamon-xrc.lock",
            "telamon-xrc.tmp1-1",
        ] {
            assert!(!is_temp_name(no, "telamon-xrc"), "{no}");
        }
    }

    #[test]
    fn a_fifo_or_huge_file_is_not_read() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("telamon-xrc");
        let c = std::ffi::CString::new(path.to_str().unwrap()).unwrap();
        assert_eq!(unsafe { libc::mkfifo(c.as_ptr(), 0o600) }, 0);
        let s = Settings::at(&path);
        assert_eq!(s.get("G", "K"), None);
        assert!(s.set("G", "K", Some("v")).is_err());
        fs::remove_file(&path).unwrap();
        fs::write(&path, vec![b'#'; MAX_BYTES as usize + 1]).unwrap();
        assert!(s.set("G", "K", Some("v")).is_err());
    }

    #[test]
    fn a_held_lock_times_out_instead_of_hanging() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("telamon-xrc");
        let s = Settings::at(&path);
        s.set("G", "K", Some("1")).unwrap();
        let held = lock(&path).unwrap();
        let t = std::time::Instant::now();
        let e = s.set("G", "K", Some("2")).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::TimedOut);
        assert!(t.elapsed() < std::time::Duration::from_secs(10));
        drop(held);
        s.set("G", "K", Some("2")).unwrap();
    }

    #[test]
    fn old_temp_leftovers_are_swept_and_fresh_ones_kept() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("telamon-xrc");
        let (old, fresh, other) = (
            dir.path().join(".telamon-xrc.tmp1-0"),
            dir.path().join(".telamon-xrc.tmp2-0"),
            dir.path().join(".telamon-yrc.tmp1-0"),
        );
        for p in [&old, &fresh, &other] {
            fs::write(p, "x").unwrap();
        }
        let two_days = std::time::SystemTime::now() - std::time::Duration::from_secs(2 * 86400);
        for p in [&old, &other] {
            fs::File::options()
                .write(true)
                .open(p)
                .unwrap()
                .set_modified(two_days)
                .unwrap();
        }
        Settings::at(&path).set("G", "K", Some("1")).unwrap();
        assert!(!old.exists() && fresh.exists() && other.exists());
    }

    #[test]
    fn unreadable_file_is_not_replaced() {
        let dir = tempfile::tempdir().unwrap();
        // a directory where the file should be: reading fails, not NotFound
        fs::create_dir(dir.path().join("telamon-xrc")).unwrap();
        assert!(
            Settings::at(dir.path().join("telamon-xrc"))
                .set("G", "K", Some("v"))
                .is_err()
        );
    }

    #[test]
    fn writes_the_format_once_and_never_requires_it() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("telamon-xrc");
        let s = Settings::at(&path);
        s.set("G", "K", Some("1")).unwrap();
        assert_eq!(s.get("Telamon", "Format").as_deref(), Some("1"));
        s.set("G", "K", Some("2")).unwrap();
        assert_eq!(
            fs::read_to_string(&path).unwrap(),
            "[Telamon]\nFormat=1\n\n[G]\nK=2\n"
        );
        // a file without it reads, and gets it on its next change
        fs::write(&path, "[G]\nK=old\n").unwrap();
        assert_eq!(s.get("G", "K").as_deref(), Some("old"));
        assert_eq!(s.get("Telamon", "Format"), None);
        s.set("G", "K", Some("new")).unwrap();
        assert_eq!(s.get("Telamon", "Format").as_deref(), Some("1"));
        // a newer app's number stays
        fs::write(&path, "[Telamon]\nFormat=7\n[G]\nK=1\n").unwrap();
        s.set("G", "K", Some("2")).unwrap();
        assert_eq!(s.get("Telamon", "Format").as_deref(), Some("7"));
        // removing a key that isn't there changes nothing, so no Format either
        fs::write(&path, "[G]\nK=1\n").unwrap();
        s.set("G", "Nope", None).unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "[G]\nK=1\n");
    }

    #[test]
    fn an_immutable_telamon_group_is_left_alone() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("telamon-xrc");
        fs::write(&path, "[Telamon][$i]\nOther=1\n").unwrap();
        let s = Settings::at(&path);
        s.set("G", "K", Some("v")).unwrap();
        assert_eq!(s.get("Telamon", "Format"), None);
    }

    fn app(id: &str) -> AppInfo {
        AppInfo {
            name: "X".into(),
            id: id.into(),
            version: "1".into(),
            repo: String::new(),
        }
    }

    #[test]
    fn for_app_adopts_the_file_of_1_x_once() {
        let dir = tempfile::tempdir().unwrap();
        let old = dir.path().join("atlas-updaterrc");
        fs::write(
            &old,
            "[Atlas]\nFormat=1\nSchemaVersion=3\n\n[General]\nLang=nl\n",
        )
        .unwrap();
        // The app ID may still say atlas, or already say telamon: same file.
        for id in ["net.eterneon.atlas.updater", "net.eterneon.telamon.updater"] {
            let new = dir.path().join("telamon-updaterrc");
            let _ = fs::remove_file(&new);
            let s = Settings::for_app_in(dir.path(), &app(id));
            assert_eq!(s.path(), new);
            assert_eq!(s.get("General", "Lang").as_deref(), Some("nl"));
            assert_eq!(s.get("Telamon", "Format").as_deref(), Some("1"));
            assert_eq!(s.get("Telamon", "SchemaVersion").as_deref(), Some("3"));
            assert_eq!(s.get("Atlas", "Format"), None);
            assert!(old.exists());
        }
        // From then on the new file is the app's: a change in it stays, and
        // an old app writing the old file does not reach it.
        let s = Settings::for_app_in(dir.path(), &app("net.eterneon.telamon.updater"));
        s.set("General", "Lang", Some("de")).unwrap();
        fs::write(&old, "[General]\nLang=fr\n").unwrap();
        let again = Settings::for_app_in(dir.path(), &app("net.eterneon.telamon.updater"));
        assert_eq!(again.get("General", "Lang").as_deref(), Some("de"));
    }

    #[test]
    fn for_app_without_an_old_file_creates_nothing() {
        let dir = tempfile::tempdir().unwrap();
        let s = Settings::for_app_in(dir.path(), &app("net.eterneon.telamon.fresh"));
        assert_eq!(s.get("General", "Lang"), None);
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 0);
    }

    #[test]
    fn a_legacy_format_group_counts_as_the_format() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("telamon-xrc");
        fs::write(&path, "[Atlas]\nFormat=7\n[G]\nK=1\n").unwrap();
        let s = Settings::at(&path);
        s.set("G", "K", Some("2")).unwrap();
        assert_eq!(s.get("Telamon", "Format"), None);
        assert_eq!(s.get("Atlas", "Format").as_deref(), Some("7"));
    }

    #[test]
    fn a_value_cannot_forge_another_group_or_key() {
        let evil = "x\n[Other]\nkey=1\r\n[$i]\n\u{85}[Z]\u{2028}k=v";
        let t = set_in("[Other]\nA=1\n", "G", "K", Some(evil));
        assert_eq!(get_in(&t, "G", "K").as_deref(), Some(evil));
        assert_eq!(get_in(&t, "Other", "key"), None);
        assert_eq!(get_in(&t, "Other", "A").as_deref(), Some("1"));
        assert_eq!(get_in(&t, "Z", "k"), None);
        assert!(!immutable(&t, "Other", "A"));
        // one header per group, one line per key (and the blank between groups)
        assert_eq!(t.lines().count(), 5, "{t:?}");
        assert!(!t.contains('\r'));
    }

    #[test]
    fn set_in_refuses_names_that_would_forge_lines() {
        let base = "[G]\nA=1\n";
        for (g, k) in [
            ("G\n[H]", "K"),
            ("G", "K\nZ=1"),
            ("G", "K=1\nZ"),
            ("G]\n[H", "K"),
            ("G", "K[$i]"),
            ("$i", "K"),
            ("$x", "K"),
            ("G", "#c"),
            (" G", "K"),
            ("G", "K\u{85}Z"),
            ("", "K"),
            ("G", ""),
        ] {
            assert_eq!(set_in(base, g, k, Some("v")), base, "{g:?} {k:?}");
        }
    }

    #[test]
    fn edge_whitespace_other_than_ascii_survives_a_round_trip() {
        for v in ["\u{a0}x", "x\u{3000}", "\u{a0}", "\u{2003}\u{a0}"] {
            let t = set_in("", "G", "K", Some(v));
            assert_eq!(get_in(&t, "G", "K").as_deref(), Some(v), "{v:?}");
        }
    }

    #[test]
    fn a_new_settings_directory_is_private() {
        use std::os::unix::fs::PermissionsExt;
        let d = tempfile::tempdir().unwrap();
        let s = Settings::at(d.path().join("a/b/telamon-xrc"));
        s.set("G", "K", Some("1")).unwrap();
        for p in [d.path().join("a"), d.path().join("a/b")] {
            assert_eq!(
                p.metadata().unwrap().permissions().mode() & 0o077,
                0,
                "{p:?}"
            );
        }
        let file = d.path().join("a/b/telamon-xrc");
        assert_eq!(file.metadata().unwrap().permissions().mode() & 0o077, 0);
    }

    mod props {
        use super::*;
        use proptest::prelude::*;

        fn name() -> impl Strategy<Value = String> {
            // mostly plain names, but any text: the invalid ones are refused
            prop_oneof![
                3 => "[A-Za-z0-9_/. -]{1,10}",
                1 => any::<String>(),
            ]
        }

        fn value() -> impl Strategy<Value = String> {
            prop_oneof![
                3 => any::<String>(),
                2 => "[ a-z=\\\\\\[\\]#;\n\r\t\u{a0}\u{85}\u{2028}$]{0,16}",
            ]
        }

        proptest! {
            #[test]
            fn prop_escape_unescape_round_trips(v in value()) {
                prop_assert_eq!(unescape(&escape(&v)), v.clone());
                let e = escape(&v);
                prop_assert!(!e.contains(['\n', '\r']));
                let raw_control = e.chars().any(|c| (c as u32) < 0x20 && c != '\t' || c == '\u{7f}');
                prop_assert!(!raw_control);
            }

            #[test]
            fn prop_unescape_never_panics(v in any::<String>()) {
                let _ = unescape(&v);
            }

            #[test]
            fn prop_a_written_value_reads_back_and_forges_nothing(
                g in name(), k in name(), v in value(), v2 in value(),
            ) {
                let base = "# c\n[Other]\nA=1\n\n[Z]\nB=2\n";
                let valid = check_group(&g).is_ok() && check_name(&k, &['[', ']', '=']).is_ok();
                let t = set_in(base, &g, &k, Some(&v));
                if !valid {
                    prop_assert_eq!(&t, base);
                    return Ok(());
                }
                prop_assert_eq!(get_in(&t, &g, &k), Some(v.clone()));
                if g != "Other" && g != "Z" {
                    prop_assert_eq!(get_in(&t, "Other", "A"), Some("1".to_string()));
                    prop_assert_eq!(get_in(&t, "Z", "B"), Some("2".to_string()));
                }
                // every line is a comment, a blank, a header or key=value
                let headers = t.lines().filter(|l| header(l).is_some()).count();
                let groups_expected = 2 + usize::from(g != "Other" && g != "Z");
                prop_assert_eq!(headers, groups_expected, "{:?}", t);
                prop_assert!(!immutable(&t, &g, &k) || immutable(base, &g, &k));
                // changing it again changes only that key; removing it removes it
                let t2 = set_in(&t, &g, &k, Some(&v2));
                prop_assert_eq!(get_in(&t2, &g, &k), Some(v2.clone()));
                prop_assert_eq!(t2.lines().count(), t.lines().count());
                let t3 = set_in(&t2, &g, &k, None);
                prop_assert_eq!(get_in(&t3, &g, &k), None);
                // a second identical write is a no-op
                prop_assert_eq!(set_in(&t, &g, &k, Some(&v)), t);
            }

            #[test]
            fn prop_set_and_get_never_panic_on_any_file(
                text in any::<String>(), g in name(), k in name(), v in any::<String>(),
            ) {
                let t = set_in(&text, &g, &k, Some(&v));
                let _ = get_in(&t, &g, &k);
                let _ = set_in(&text, &g, &k, None);
                let _ = immutable(&text, &g, &k);
                let _ = legacy::rename_group(&text);
            }
        }
    }
}
