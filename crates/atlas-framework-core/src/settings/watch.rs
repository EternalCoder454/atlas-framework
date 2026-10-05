//! Change notification: inotify on the file's directory, so an editor that
//! writes a temp file and renames it over the settings file is seen too.

use std::ffi::{CString, OsString};
use std::fs;
use std::io;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::ffi::OsStrExt;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use super::{Settings, get_in, parse_bool, read_text, resolve_link};

/// How long the file must be quiet before the callback runs: a save is often
/// several events (create, write, rename, chmod).
pub const DEBOUNCE: Duration = Duration::from_millis(200);

/// The file's contents at one moment, read once, so every `get` of one
/// callback agrees. A missing, unreadable or non-regular file reads as empty.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Snapshot {
    text: Option<String>,
}

impl Snapshot {
    /// Whether the file existed and could be read.
    pub fn exists(&self) -> bool {
        self.text.is_some()
    }

    /// As [`Settings::get`].
    pub fn get(&self, group: &str, key: &str) -> Option<String> {
        get_in(self.text.as_deref()?, group, key)
    }

    /// As [`Settings::get_bool`].
    pub fn get_bool(&self, group: &str, key: &str) -> Option<bool> {
        parse_bool(&self.get(group, key)?)
    }
}

/// Keeps a watch alive. Dropping it stops the watch; a callback already
/// running finishes, none starts after the drop.
#[derive(Debug)]
pub struct SettingsWatcher {
    stop: Arc<AtomicBool>,
    wake: OwnedFd,
}

impl Drop for SettingsWatcher {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        let one = 1u64.to_ne_bytes();
        // SAFETY: a valid eventfd and an 8-byte buffer.
        unsafe { libc::write(self.wake.as_raw_fd(), one.as_ptr().cast(), 8) };
    }
}

fn cvt(r: libc::c_int) -> io::Result<libc::c_int> {
    if r < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(r)
    }
}

fn snapshot(path: &Path) -> Snapshot {
    Snapshot {
        text: read_text(path).ok(),
    }
}

impl Settings {
    /// Calls `on_change` with the new values whenever the file's contents
    /// change, on a thread named `atlas-settings-watch`.
    ///
    /// - The directory is watched, not the file: a write in place, a rename
    ///   over the file, a delete and a re-create are all seen. A symlinked
    ///   file is followed to its target's directory too.
    /// - Events are debounced by [`DEBOUNCE`], and the callback runs only if
    ///   the text differs from the last one reported (the text at the call to
    ///   `watch` is the first), so the app's own no-op `set`s and a
    ///   delete-then-same-content never call it. A deleted file is reported
    ///   as a snapshot where [`Snapshot::exists`] is false.
    /// - The directory is created if missing. If it is removed while watched,
    ///   the watch logs a warning and ends.
    /// - A panic in the callback is logged; the watch goes on.
    /// - Errors: no home directory (`NotFound`), no inotify instance or watch
    ///   slots left, the directory not readable.
    pub fn watch<F>(&self, on_change: F) -> io::Result<SettingsWatcher>
    where
        F: FnMut(&Snapshot) + Send + 'static,
    {
        if self.path.starts_with(super::NO_HOME) {
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                "no home directory to keep settings in",
            ));
        }
        let target = resolve_link(&self.path)?;
        // (directory, file name) pairs: the path itself, and its link target.
        let mut spots: Vec<(std::path::PathBuf, OsString)> = Vec::new();
        for p in [self.path.as_path(), target.as_path()] {
            let (Some(dir), Some(name)) = (p.parent(), p.file_name()) else {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "not a file path",
                ));
            };
            let dir = if dir.as_os_str().is_empty() {
                Path::new(".")
            } else {
                dir
            };
            let spot = (dir.to_path_buf(), name.to_os_string());
            if !spots.contains(&spot) {
                spots.push(spot);
            }
        }
        fs::create_dir_all(&spots[0].0)?;

        // SAFETY: plain syscalls; the fds are wrapped at once.
        let ino = unsafe {
            OwnedFd::from_raw_fd(cvt(libc::inotify_init1(
                libc::IN_CLOEXEC | libc::IN_NONBLOCK,
            ))?)
        };
        let wake = unsafe {
            OwnedFd::from_raw_fd(cvt(libc::eventfd(
                0,
                libc::EFD_CLOEXEC | libc::EFD_NONBLOCK,
            ))?)
        };
        let mask = libc::IN_CLOSE_WRITE
            | libc::IN_MOVED_TO
            | libc::IN_MOVED_FROM
            | libc::IN_CREATE
            | libc::IN_DELETE
            | libc::IN_MODIFY
            | libc::IN_DELETE_SELF
            | libc::IN_MOVE_SELF;
        let mut dirs: Vec<(libc::c_int, OsString)> = Vec::new();
        for (dir, name) in &spots {
            let c = CString::new(dir.as_os_str().as_bytes())
                .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "NUL in a path"))?;
            let wd = cvt(unsafe { libc::inotify_add_watch(ino.as_raw_fd(), c.as_ptr(), mask) })?;
            dirs.push((wd, name.clone()));
        }
        let names: Vec<OsString> = spots.iter().map(|(_, n)| n.clone()).collect();
        let wds: Vec<libc::c_int> = dirs.iter().map(|d| d.0).collect();
        let stop = Arc::new(AtomicBool::new(false));
        let wake_fd = wake.as_raw_fd();
        let path = self.path.clone();
        let first = snapshot(&path);
        let stop2 = stop.clone();
        let eventfd = unsafe { OwnedFd::from_raw_fd(cvt(libc::dup(wake_fd))?) };
        std::thread::Builder::new()
            .name("atlas-settings-watch".into())
            .spawn(move || run(ino, eventfd, stop2, wds, names, path, first, on_change))?;
        Ok(SettingsWatcher { stop, wake })
    }
}

#[allow(clippy::too_many_arguments)]
fn run<F: FnMut(&Snapshot)>(
    ino: OwnedFd,
    wake: OwnedFd,
    stop: Arc<AtomicBool>,
    wds: Vec<libc::c_int>,
    names: Vec<OsString>,
    path: std::path::PathBuf,
    mut last: Snapshot,
    mut on_change: F,
) {
    let mut buf = vec![0u8; 16 * 1024];
    let mut due: Option<Instant> = None;
    loop {
        let timeout = match due {
            None => -1,
            Some(t) => t
                .saturating_duration_since(Instant::now())
                .as_millis()
                .min(i32::MAX as u128) as libc::c_int,
        };
        let mut fds = [
            libc::pollfd {
                fd: ino.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            },
            libc::pollfd {
                fd: wake.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            },
        ];
        // SAFETY: two valid pollfds.
        let n = unsafe { libc::poll(fds.as_mut_ptr(), 2, timeout) };
        if n < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
            log::warn!(
                "settings watch: poll failed: {}",
                io::Error::last_os_error()
            );
            return;
        }
        if stop.load(Ordering::SeqCst) {
            return;
        }
        if fds[0].revents & libc::POLLIN != 0 {
            loop {
                // SAFETY: buf is valid for its length.
                let r = unsafe { libc::read(ino.as_raw_fd(), buf.as_mut_ptr().cast(), buf.len()) };
                if r <= 0 {
                    break; // EAGAIN: drained
                }
                let mut off = 0usize;
                let end = r as usize;
                while off + 16 <= end {
                    // inotify_event: wd i32, mask u32, cookie u32, len u32, name
                    let rd = |o: usize| u32::from_ne_bytes(buf[o..o + 4].try_into().unwrap());
                    let wd = rd(off) as i32;
                    let mask = rd(off + 4);
                    let len = rd(off + 12) as usize;
                    let nend = (off + 16 + len).min(end);
                    let raw = &buf[off + 16..nend];
                    let nm = raw.split(|b| *b == 0).next().unwrap_or(&[]);
                    off = nend;
                    if mask & libc::IN_Q_OVERFLOW != 0 {
                        due = Some(Instant::now() + DEBOUNCE);
                    } else if mask & (libc::IN_DELETE_SELF | libc::IN_IGNORED) != 0 {
                        if wds.contains(&wd) {
                            log::warn!("settings watch: the directory is gone; watch ends");
                            // Report the loss of the file once, then stop.
                            let now = snapshot(&path);
                            if now != last && !stop.load(Ordering::SeqCst) {
                                call(&mut on_change, &now);
                            }
                            return;
                        }
                    } else if wds.contains(&wd) && names.iter().any(|n| n.as_bytes() == nm) {
                        due = Some(Instant::now() + DEBOUNCE);
                    }
                }
            }
        }
        if let Some(t) = due
            && Instant::now() >= t
        {
            due = None;
            let now = snapshot(&path);
            if now != last {
                last = now.clone();
                if !stop.load(Ordering::SeqCst) {
                    call(&mut on_change, &now);
                }
            }
        }
    }
}

fn call<F: FnMut(&Snapshot)>(f: &mut F, s: &Snapshot) {
    if catch_unwind(AssertUnwindSafe(|| f(s))).is_err() {
        log::error!("settings watch: the callback panicked");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc::{Receiver, channel};

    const WAIT: Duration = Duration::from_secs(5);

    fn watch(s: &Settings) -> (SettingsWatcher, Receiver<Snapshot>) {
        let (tx, rx) = channel();
        let w = s
            .watch(move |snap| {
                let _ = tx.send(snap.clone());
            })
            .unwrap();
        (w, rx)
    }

    #[test]
    fn sees_a_write_once_after_the_debounce() {
        let d = tempfile::tempdir().unwrap();
        let s = Settings::at(d.path().join("atlas-xrc"));
        let (_w, rx) = watch(&s);
        let t = Instant::now();
        s.set("G", "A", Some("1")).unwrap();
        s.set("G", "B", Some("2")).unwrap();
        let snap = rx.recv_timeout(WAIT).unwrap();
        assert!(t.elapsed() >= DEBOUNCE);
        assert_eq!(snap.get("G", "A").as_deref(), Some("1"));
        assert_eq!(snap.get("G", "B").as_deref(), Some("2"));
        // one call for the burst, none for a no-op set
        s.set("G", "B", Some("2")).unwrap();
        assert!(rx.recv_timeout(Duration::from_millis(600)).is_err());
    }

    #[test]
    fn sees_a_rename_replace() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("atlas-xrc");
        fs::write(&p, "[G]\nA=1\n").unwrap();
        let s = Settings::at(&p);
        let (_w, rx) = watch(&s);
        let tmp = d.path().join(".atlas-xrc.swp");
        fs::write(&tmp, "[G]\nA=2\n").unwrap();
        fs::rename(&tmp, &p).unwrap();
        assert_eq!(
            rx.recv_timeout(WAIT).unwrap().get("G", "A").as_deref(),
            Some("2")
        );
        // an unrelated file in the directory is not an event
        fs::write(d.path().join("other"), "x").unwrap();
        assert!(rx.recv_timeout(Duration::from_millis(600)).is_err());
    }

    #[test]
    fn sees_delete_then_recreate() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("atlas-xrc");
        fs::write(&p, "[G]\nA=1\n").unwrap();
        let s = Settings::at(&p);
        let (_w, rx) = watch(&s);
        fs::remove_file(&p).unwrap();
        let gone = rx.recv_timeout(WAIT).unwrap();
        assert!(!gone.exists());
        assert_eq!(gone.get("G", "A"), None);
        fs::write(&p, "[G]\nA=3\n").unwrap();
        let back = rx.recv_timeout(WAIT).unwrap();
        assert!(back.exists());
        assert_eq!(back.get("G", "A").as_deref(), Some("3"));
    }

    #[test]
    fn dropping_the_watcher_stops_it() {
        let d = tempfile::tempdir().unwrap();
        let s = Settings::at(d.path().join("atlas-xrc"));
        let (w, rx) = watch(&s);
        drop(w);
        s.set("G", "A", Some("1")).unwrap();
        // the thread ends and drops its sender: disconnected, never a value
        assert!(matches!(
            rx.recv_timeout(WAIT),
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected)
        ));
    }
}
