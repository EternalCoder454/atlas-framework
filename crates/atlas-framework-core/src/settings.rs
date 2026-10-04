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
//! file atomically, keeping every other line, its mode and its owner. Writers
//! take a lock (a thread lock, and `flock` on `.<name>.lock` beside the file,
//! which stays: removing it would race the next writer),
//! so concurrent `set`s in Atlas code never lose a change; another program
//! writing the file without the lock can still race, but never corrupts it.
//! Keys and groups KConfig marks immutable (`[$i]`) are refused.

use std::fs;
use std::io::{self, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

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
    /// The last of duplicate keys wins, as in KConfig.
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
    /// Fails with `InvalidInput` for a group or key that can't be written as
    /// one (control characters, brackets, `=`), and `PermissionDenied` for an
    /// immutable one.
    pub fn set(&self, group: &str, key: &str, value: Option<&str>) -> io::Result<()> {
        check_name(group, &['[', ']'])?;
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
            fs::create_dir_all(dir)?;
        }
        let _thread = WRITERS.lock().unwrap_or_else(|e| e.into_inner());
        let _file = lock(&target)?;
        // Again under the lock: another writer may have changed it.
        let (out, changed, meta) = change(&target, group, key, value)?;
        if !changed {
            return Ok(());
        }
        replace(&target, out.as_bytes(), meta.as_ref())
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
    let (text, meta) = match fs::read_to_string(target) {
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

/// The settings file's format version, in `[Atlas] Format=`. Written when a
/// file is first created or changed; never required when reading, so files
/// from before it, and files a newer app wrote (a higher number), read the
/// same. Only a change to how existing keys are read would raise it.
pub const FORMAT: u32 = 1;

/// `out` (the new text, derived from `old`) with `[Atlas] Format=` added
/// unless the file already has one (any number: a newer app's stays) or
/// KConfig would ignore the write. A new file gets it first.
fn with_format(old: &str, out: String) -> String {
    if out.is_empty()
        || get_in(&out, "Atlas", "Format").is_some()
        || immutable(old, "Atlas", "Format")
    {
        return out;
    }
    if old.trim().is_empty() {
        return format!("[Atlas]\nFormat={FORMAT}\n\n{out}");
    }
    set_in(&out, "Atlas", "Format", Some(&FORMAT.to_string()))
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

/// An exclusive `flock` on `.<name>.lock` beside `path`, held until dropped.
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
    loop {
        // SAFETY: flock on a descriptor this function owns.
        if unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX) } == 0 {
            return Ok(f);
        }
        let e = io::Error::last_os_error();
        if e.kind() != io::ErrorKind::Interrupted {
            return Err(e);
        }
    }
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
            found = Some(unescape(v.trim()));
        }
    }
    found
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
        // the file and its lock file are left: no temp files
        let mut names: Vec<_> = fs::read_dir(dir.path().join("sub"))
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        names.sort();
        assert_eq!(names, [".atlas-xrc.lock", "atlas-xrc"]);
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
        assert_eq!(
            fs::read_to_string(&real).unwrap(),
            "[G]\nA=1\nB=2\n\n[Atlas]\nFormat=1\n"
        );
        assert_eq!(
            fs::metadata(&real).unwrap().permissions().mode() & 0o777,
            0o640
        );
    }

    #[test]
    fn keeps_a_wide_mode_and_last_duplicate_wins() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("atlas-xrc");
        fs::write(&path, "[G]\nK=1\nK=2\n").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o666)).unwrap();
        let s = Settings::at(&path);
        assert_eq!(s.get("G", "K").as_deref(), Some("2"));
        s.set("G", "K", Some("3")).unwrap();
        assert_eq!(
            fs::read_to_string(&path).unwrap(),
            "[G]\nK=3\n\n[Atlas]\nFormat=1\n"
        );
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o666
        );
    }

    #[test]
    fn refuses_bad_names_and_immutable_entries() {
        let dir = tempfile::tempdir().unwrap();
        let s = Settings::at(dir.path().join("atlas-xrc"));
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
        let path = dir.path().join("atlas-xrc");
        fs::write(&path, "[G]\nK=v\n").unwrap();
        fs::set_permissions(dir.path(), fs::Permissions::from_mode(0o500)).unwrap();
        let r = Settings::at(&path).set("G", "K", Some("v"));
        fs::set_permissions(dir.path(), fs::Permissions::from_mode(0o700)).unwrap();
        r.unwrap();
        assert!(!dir.path().join(".atlas-xrc.lock").exists());
    }

    #[test]
    fn no_home_is_refused() {
        let s = Settings::at(Path::new(NO_HOME).join("atlas-xrc"));
        assert_eq!(
            s.set("G", "K", Some("v")).unwrap_err().kind(),
            io::ErrorKind::NotFound
        );
    }

    #[test]
    fn dangling_symlink_creates_its_target() {
        let dir = tempfile::tempdir().unwrap();
        let link = dir.path().join("atlas-xrc");
        std::os::unix::fs::symlink("real", &link).unwrap();
        Settings::at(&link).set("G", "K", Some("v")).unwrap();
        assert_eq!(
            fs::read_to_string(dir.path().join("real")).unwrap(),
            "[Atlas]\nFormat=1\n\n[G]\nK=v\n"
        );
    }

    #[test]
    fn concurrent_sets_all_land() {
        let dir = tempfile::tempdir().unwrap();
        let s = Settings::at(dir.path().join("atlas-xrc"));
        std::thread::scope(|scope| {
            for t in 0..8 {
                let s = &s;
                scope.spawn(move || {
                    for i in 0..10 {
                        s.set("G", &format!("K{t}_{i}"), Some("v")).unwrap();
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

    #[test]
    fn writes_the_format_once_and_never_requires_it() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("atlas-xrc");
        let s = Settings::at(&path);
        s.set("G", "K", Some("1")).unwrap();
        assert_eq!(s.get("Atlas", "Format").as_deref(), Some("1"));
        s.set("G", "K", Some("2")).unwrap();
        assert_eq!(
            fs::read_to_string(&path).unwrap(),
            "[Atlas]\nFormat=1\n\n[G]\nK=2\n"
        );
        // a file without it reads, and gets it on its next change
        fs::write(&path, "[G]\nK=old\n").unwrap();
        assert_eq!(s.get("G", "K").as_deref(), Some("old"));
        assert_eq!(s.get("Atlas", "Format"), None);
        s.set("G", "K", Some("new")).unwrap();
        assert_eq!(s.get("Atlas", "Format").as_deref(), Some("1"));
        // a newer app's number stays
        fs::write(&path, "[Atlas]\nFormat=7\n[G]\nK=1\n").unwrap();
        s.set("G", "K", Some("2")).unwrap();
        assert_eq!(s.get("Atlas", "Format").as_deref(), Some("7"));
        // removing a key that isn't there changes nothing, so no Format either
        fs::write(&path, "[G]\nK=1\n").unwrap();
        s.set("G", "Nope", None).unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "[G]\nK=1\n");
    }

    #[test]
    fn an_immutable_atlas_group_is_left_alone() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("atlas-xrc");
        fs::write(&path, "[Atlas][$i]\nOther=1\n").unwrap();
        let s = Settings::at(&path);
        s.set("G", "K", Some("v")).unwrap();
        assert_eq!(s.get("Atlas", "Format"), None);
    }
}
