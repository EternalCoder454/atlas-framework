//! Change notification: inotify on the file's directory, so an editor that
//! writes a temp file and renames it over the settings file is seen too.

use std::ffi::{CString, OsString};
use std::fs;
use std::io;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::ffi::OsStrExt;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use super::{Settings, get_in, parse_bool, read_text, resolve_link};

/// How long the file must be quiet before the callback runs: a save is often
/// several events (create, write, rename, chmod).
pub const DEBOUNCE: Duration = Duration::from_millis(200);

/// The longest the callback is held back by a steady stream of events.
const MAX_WAIT: Duration = Duration::from_secs(2);

/// The file's contents at one moment, read once, so every `get` of one
/// callback agrees. A snapshot is only made of a file that is missing
/// (`exists()` is false) or that was read as text: a file that cannot be read
/// (over 4 MB, not a regular file, no permission) is never reported as
/// missing; the watch logs it and keeps the last snapshot.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Snapshot {
    text: Option<String>,
}

impl Snapshot {
    /// Whether the file existed (`false` only for a missing file).
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

/// How long a drop waits for the watch thread (a callback still running).
const JOIN_WAIT: Duration = Duration::from_secs(1);

/// Keeps a watch alive. Dropping it stops the watch: no callback starts after
/// the drop. It waits up to one second for a callback that is running, then
/// gives up (logged) and leaves that thread to end by itself, so a drop can
/// never hang the UI; dropping the watcher from inside its own callback does
/// not wait.
#[derive(Debug)]
pub struct SettingsWatcher {
    stop: Arc<AtomicBool>,
    wake: OwnedFd,
    thread: Option<JoinHandle<()>>,
}

impl Drop for SettingsWatcher {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        let one = 1u64.to_ne_bytes();
        // SAFETY: a valid eventfd and an 8-byte buffer.
        unsafe { libc::write(self.wake.as_raw_fd(), one.as_ptr().cast(), 8) };
        if let Some(h) = self.thread.take()
            && h.thread().id() != std::thread::current().id()
        {
            let end = Instant::now() + JOIN_WAIT;
            while !h.is_finished() && Instant::now() < end {
                std::thread::sleep(Duration::from_millis(2));
            }
            if h.is_finished() {
                let _ = h.join();
            } else {
                log::warn!(
                    "settings watch: a callback is still running; not waiting for it. \
                     Callbacks must hand work off without blocking"
                );
            }
        }
    }
}

fn cvt(r: libc::c_int) -> io::Result<libc::c_int> {
    if r < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(r)
    }
}

/// `Ok(Missing)` for a file that is not there, an error for one that is but
/// cannot be read.
fn snapshot(path: &Path) -> io::Result<Snapshot> {
    match read_text(path) {
        Ok(t) => Ok(Snapshot { text: Some(t) }),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(Snapshot { text: None }),
        Err(e) => Err(e),
    }
}

/// One watched directory and the file name in it that counts. `pending`:
/// the directory does not exist (yet), so this is its nearest existing
/// ancestor and `name` is the next component down.
struct Watched {
    wd: libc::c_int,
    name: OsString,
    pending: bool,
}

fn dir_of(p: &Path) -> io::Result<&Path> {
    let Some(dir) = p.parent() else {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "not a file path",
        ));
    };
    Ok(if dir.as_os_str().is_empty() {
        Path::new(".")
    } else {
        dir
    })
}

fn add_watch(ino: &OwnedFd, dir: &Path, mask: u32) -> io::Result<libc::c_int> {
    let c = CString::new(dir.as_os_str().as_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "NUL in a path"))?;
    // SAFETY: a valid inotify fd and a NUL-terminated path.
    let wd = unsafe { libc::inotify_add_watch(ino.as_raw_fd(), c.as_ptr(), mask) };
    if wd < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(wd)
    }
}

/// Watches the directory of `path` and, when `path` is a symlink, of its
/// target. Creates nothing: a directory that does not exist is watched
/// through its nearest existing ancestor until it appears. Returns the watches
/// and the link's resolved target.
fn establish(ino: &OwnedFd, path: &Path) -> io::Result<(Vec<Watched>, PathBuf)> {
    let target = resolve_link(path)?;
    let mask = libc::IN_CLOSE_WRITE
        | libc::IN_MOVED_TO
        | libc::IN_MOVED_FROM
        | libc::IN_CREATE
        | libc::IN_DELETE
        | libc::IN_MODIFY
        | libc::IN_DELETE_SELF
        | libc::IN_MOVE_SELF;
    let mut out: Vec<Watched> = Vec::new();
    for (i, p) in [path, target.as_path()].into_iter().enumerate() {
        let Some(name) = p.file_name() else {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "not a file path",
            ));
        };
        let dir = dir_of(p)?;
        let found = if fs::metadata(dir).is_ok_and(|m| m.is_dir()) {
            add_watch(ino, dir, mask).map(|wd| Watched {
                wd,
                name: name.to_os_string(),
                pending: false,
            })
        } else {
            // The nearest existing ancestor, and the component below it.
            let mut below = dir;
            let mut res = Err(io::Error::from(io::ErrorKind::NotFound));
            while let Some(up) = below.parent() {
                let up_dir = if up.as_os_str().is_empty() {
                    Path::new(".")
                } else {
                    up
                };
                if fs::metadata(up_dir).is_ok_and(|m| m.is_dir()) {
                    res = add_watch(ino, up_dir, mask).map(|wd| Watched {
                        wd,
                        name: below.file_name().unwrap_or_default().to_os_string(),
                        pending: true,
                    });
                    break;
                }
                below = up;
            }
            res
        };
        match found {
            Ok(w) => {
                if !out.iter().any(|o| o.wd == w.wd && o.name == w.name) {
                    out.push(w);
                }
            }
            Err(e) if i == 0 => return Err(e),
            Err(e) => log::warn!(
                "settings watch: not watching the link target's directory {}: {e}",
                dir.display()
            ),
        }
    }
    Ok((out, target))
}

fn forget(ino: &OwnedFd, old: &[Watched], keep: &[Watched]) {
    for w in old {
        if !keep.iter().any(|k| k.wd == w.wd) {
            // SAFETY: a valid inotify fd; an already-gone watch just fails.
            unsafe { libc::inotify_rm_watch(ino.as_raw_fd(), w.wd) };
        }
    }
}

impl Settings {
    /// Calls `on_change` with the new values whenever the file's contents
    /// change, on a thread named `atlas-settings-watch`.
    ///
    /// - The directory is watched, not the file: a write in place, a rename
    ///   over the file, a delete and a re-create are all seen.
    /// - A symlinked file is followed: its target's directory is watched too,
    ///   and the link is resolved again when something happens to the link
    ///   itself, so a retargeted link is followed. A target in a directory
    ///   that does not exist yet is watched through its nearest existing
    ///   ancestor until it appears.
    /// - Events are debounced by [`DEBOUNCE`] (but a steady stream of them
    ///   holds the callback back at most 2 s), and the callback runs only if
    ///   the text differs from the last one reported (the text at the call to
    ///   `watch` is the first), so the app's own no-op `set`s and a
    ///   delete-then-same-content never call it. A deleted file is reported
    ///   as a snapshot where [`Snapshot::exists`] is false.
    /// - A file that exists but cannot be read (over 4 MB, not a regular
    ///   file, no permission) is not "deleted": the watch logs it, does not
    ///   call back, and keeps the last snapshot until the file reads again.
    /// - `watch` creates the file's own directory if it is missing, as `set`
    ///   would. After that the watch creates nothing: if the directory is
    ///   removed or renamed away (an uninstall, `rm -rf`), the watch reports
    ///   the file as missing and watches the nearest existing ancestor until
    ///   the directory comes back. If it cannot watch again it logs a warning
    ///   and ends.
    /// - The callback runs on the watch thread. It must hand work off without
    ///   blocking (a `queue`, not a blocking call into the UI thread): see
    ///   [`SettingsWatcher`] for what a drop does while it runs.
    /// - A panic in the callback is logged and the watch goes on (with
    ///   `panic = "unwind"`; under `panic = "abort"` the process ends).
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
        // The one place a watch creates anything: the file's own directory,
        // as `set` would, so a first start has something to watch.
        fs::create_dir_all(dir_of(&self.path)?)?;
        let (watched, target) = establish(&ino, &self.path)?;
        let path = self.path.clone();
        // None: unknown (unreadable now), so the first read that works is
        // reported.
        let first = snapshot(&path)
            .map_err(|e| log::warn!("settings watch: {} cannot be read: {e}", path.display()))
            .ok();
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        // SAFETY: a valid fd.
        let wake2 = unsafe { OwnedFd::from_raw_fd(cvt(libc::dup(wake.as_raw_fd()))?) };
        let thread = std::thread::Builder::new()
            .name("atlas-settings-watch".into())
            .spawn(move || run(ino, wake2, stop2, watched, target, path, first, on_change))?;
        Ok(SettingsWatcher {
            stop,
            wake,
            thread: Some(thread),
        })
    }
}

#[allow(clippy::too_many_arguments)]
fn run<F: FnMut(&Snapshot)>(
    ino: OwnedFd,
    wake: OwnedFd,
    stop: Arc<AtomicBool>,
    mut watched: Vec<Watched>,
    mut target: PathBuf,
    path: PathBuf,
    mut last: Option<Snapshot>,
    mut on_change: F,
) {
    let link_name = path.file_name().map(|n| n.to_os_string());
    let mut buf = vec![0u8; 16 * 1024];
    // (first event of the burst, when to read)
    let mut due: Option<(Instant, Instant)> = None;
    let bump = |due: &mut Option<(Instant, Instant)>| {
        let now = Instant::now();
        let first = due.map_or(now, |d| d.0);
        *due = Some((first, (now + DEBOUNCE).min(first + MAX_WAIT)));
    };
    loop {
        let timeout = match due {
            None => -1,
            Some((_, t)) => t
                .saturating_duration_since(Instant::now())
                .as_millis()
                .saturating_add(1) // round up: never wake just before it is due
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
            let mut reestablish = false;
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
                        bump(&mut due);
                        continue;
                    }
                    let Some(w) = watched.iter().find(|w| w.wd == wd) else {
                        continue; // a watch dropped on purpose
                    };
                    if mask & (libc::IN_DELETE_SELF | libc::IN_MOVE_SELF | libc::IN_IGNORED) != 0 {
                        reestablish = true;
                        bump(&mut due);
                    } else if watched
                        .iter()
                        .any(|w| w.wd == wd && w.name.as_bytes() == nm)
                    {
                        if w.pending {
                            reestablish = true; // the directory is back
                        } else if link_name.as_ref().is_some_and(|l| l.as_bytes() == nm)
                            && resolve_link(&path).ok().as_ref() != Some(&target)
                        {
                            reestablish = true; // the link now points elsewhere
                        }
                        bump(&mut due);
                    }
                }
            }
            if reestablish {
                match establish(&ino, &path) {
                    Ok((new, t)) => {
                        forget(&ino, &watched, &new);
                        watched = new;
                        target = t;
                    }
                    Err(e) => {
                        log::warn!(
                            "settings watch: cannot watch {} again: {e}; watch ends",
                            path.display()
                        );
                        if let Ok(now) = snapshot(&path)
                            && last.as_ref() != Some(&now)
                            && !stop.load(Ordering::SeqCst)
                        {
                            call(&mut on_change, &now);
                        }
                        return;
                    }
                }
            }
        }
        if let Some((_, t)) = due
            && Instant::now() >= t
        {
            due = None;
            match snapshot(&path) {
                Ok(now) if last.as_ref() != Some(&now) => {
                    last = Some(now.clone());
                    if !stop.load(Ordering::SeqCst) {
                        call(&mut on_change, &now);
                    }
                }
                Ok(_) => {}
                Err(e) => log::warn!(
                    "settings watch: {} exists but cannot be read ({e}); keeping the last values",
                    path.display()
                ),
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

    #[test]
    fn an_unreadable_file_is_not_a_deletion() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("atlas-xrc");
        fs::write(&p, "[G]\nA=1\n").unwrap();
        let s = Settings::at(&p);
        let (_w, rx) = watch(&s);
        // over 4 MB
        replace_with(&p, &vec![b'a'; 5 * 1024 * 1024]);
        assert!(rx.recv_timeout(Duration::from_millis(700)).is_err());
        // a FIFO in its place
        let fifo = d.path().join("fifo");
        let c = std::ffi::CString::new(fifo.to_str().unwrap()).unwrap();
        assert_eq!(unsafe { libc::mkfifo(c.as_ptr(), 0o600) }, 0);
        fs::rename(&fifo, &p).unwrap();
        assert!(rx.recv_timeout(Duration::from_millis(700)).is_err());
        // readable again: reported as a normal change
        fs::remove_file(&p).unwrap();
        let gone = rx.recv_timeout(WAIT).unwrap();
        assert!(!gone.exists());
        fs::write(&p, "[G]\nA=9\n").unwrap();
        assert_eq!(
            rx.recv_timeout(WAIT).unwrap().get("G", "A").as_deref(),
            Some("9")
        );
    }

    #[test]
    fn follows_a_retargeted_link() {
        let d = tempfile::tempdir().unwrap();
        let (a, b) = (d.path().join("a"), d.path().join("b"));
        fs::create_dir(&a).unwrap();
        fs::create_dir(&b).unwrap();
        fs::write(a.join("real"), "[G]\nA=a\n").unwrap();
        fs::write(b.join("real"), "[G]\nA=b\n").unwrap();
        let link = d.path().join("atlas-xrc");
        std::os::unix::fs::symlink(a.join("real"), &link).unwrap();
        let s = Settings::at(&link);
        let (_w, rx) = watch(&s);
        let tmp = d.path().join("tmplink");
        std::os::unix::fs::symlink(b.join("real"), &tmp).unwrap();
        fs::rename(&tmp, &link).unwrap();
        assert_eq!(
            rx.recv_timeout(WAIT).unwrap().get("G", "A").as_deref(),
            Some("b")
        );
        // the new target's directory is watched now; the old one is not
        fs::write(b.join("real"), "[G]\nA=b2\n").unwrap();
        assert_eq!(
            rx.recv_timeout(WAIT).unwrap().get("G", "A").as_deref(),
            Some("b2")
        );
        fs::write(a.join("real"), "[G]\nA=a2\n").unwrap();
        assert!(rx.recv_timeout(Duration::from_millis(600)).is_err());
    }

    #[test]
    fn follows_a_renamed_directory() {
        let d = tempfile::tempdir().unwrap();
        let dir = d.path().join("cfg");
        fs::create_dir(&dir).unwrap();
        let p = dir.join("atlas-xrc");
        fs::write(&p, "[G]\nA=1\n").unwrap();
        let s = Settings::at(&p);
        let (_w, rx) = watch(&s);
        fs::rename(&dir, d.path().join("moved")).unwrap();
        let gone = rx.recv_timeout(WAIT).unwrap();
        assert!(!gone.exists());
        // nothing is recreated behind the user's back
        std::thread::sleep(Duration::from_millis(400));
        assert!(!dir.exists());
        // when the directory comes back, the same path is watched again
        fs::create_dir(&dir).unwrap();
        fs::write(&p, "[G]\nA=2\n").unwrap();
        assert_eq!(
            rx.recv_timeout(WAIT).unwrap().get("G", "A").as_deref(),
            Some("2")
        );
        fs::write(&p, "[G]\nA=3\n").unwrap();
        assert_eq!(
            rx.recv_timeout(WAIT).unwrap().get("G", "A").as_deref(),
            Some("3")
        );
    }

    #[test]
    fn a_removed_tree_is_not_recreated_and_a_deep_one_comes_back() {
        let d = tempfile::tempdir().unwrap();
        let dir = d.path().join("a/b");
        fs::create_dir_all(&dir).unwrap();
        let p = dir.join("atlas-xrc");
        fs::write(&p, "x=1\n").unwrap();
        let s = Settings::at(&p);
        let (_w, rx) = watch(&s);
        fs::remove_dir_all(d.path().join("a")).unwrap();
        assert!(!rx.recv_timeout(WAIT).unwrap().exists());
        std::thread::sleep(Duration::from_millis(400));
        assert!(!d.path().join("a").exists());
        fs::create_dir_all(&dir).unwrap();
        fs::write(&p, "[G]\nA=5\n").unwrap();
        assert_eq!(
            rx.recv_timeout(WAIT).unwrap().get("G", "A").as_deref(),
            Some("5")
        );
    }

    #[test]
    fn a_file_unreadable_at_start_is_reported_once_it_reads() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("atlas-xrc");
        fs::write(&p, vec![b'a'; 5 * 1024 * 1024]).unwrap();
        let s = Settings::at(&p);
        let (_w, rx) = watch(&s);
        replace_with(&p, b"[G]\nA=1\n");
        let snap = rx.recv_timeout(WAIT).unwrap();
        assert!(snap.exists());
        assert_eq!(snap.get("G", "A").as_deref(), Some("1"));
    }

    fn replace_with(p: &Path, bytes: &[u8]) {
        let tmp = p.with_file_name(".swap");
        fs::write(&tmp, bytes).unwrap();
        fs::rename(&tmp, p).unwrap();
    }

    #[test]
    fn a_drop_never_hangs_and_no_callback_starts_after_it() {
        use std::sync::atomic::AtomicUsize;
        use std::sync::mpsc::sync_channel;
        struct Ended(std::sync::mpsc::Sender<()>);
        impl Drop for Ended {
            fn drop(&mut self) {
                let _ = self.0.send(());
            }
        }
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("atlas-xrc");
        let s = Settings::at(&p);
        let calls = Arc::new(AtomicUsize::new(0));
        let (started_tx, started) = sync_channel::<()>(8);
        let (release, released) = channel::<()>();
        let (ended_tx, ended) = channel();
        let (calls2, guard) = (calls.clone(), Ended(ended_tx));
        let w = s
            .watch(move |_| {
                let _keep = &guard;
                calls2.fetch_add(1, Ordering::SeqCst);
                let _ = started_tx.send(());
                let _ = released.recv(); // a callback stuck in a blocking post
            })
            .unwrap();
        s.set("G", "A", Some("1")).unwrap();
        started.recv_timeout(WAIT).unwrap();
        s.set("G", "A", Some("2")).unwrap(); // an event pending behind it
        std::thread::sleep(Duration::from_millis(100));
        let t = Instant::now();
        drop(w); // must return although the callback is stuck
        assert!(t.elapsed() < Duration::from_secs(3));
        // now let the stuck callback go: the pending change is not delivered
        release.send(()).unwrap();
        ended.recv_timeout(WAIT).unwrap(); // the watch thread has ended
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }
    #[test]
    fn a_steady_stream_cannot_starve_the_callback() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("atlas-xrc");
        let s = Settings::at(&p);
        let (_w, rx) = watch(&s);
        let t = Instant::now();
        let mut i = 0;
        while t.elapsed() < Duration::from_millis(3500) {
            fs::write(&p, format!("[G]\nA={i}\n")).unwrap();
            i += 1;
            std::thread::sleep(Duration::from_millis(50));
        }
        assert!(rx.try_recv().is_ok(), "no callback during the burst");
    }

    #[test]
    fn drop_waits_and_works_from_inside_the_callback() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("atlas-xrc");
        let s = Settings::at(&p);
        let (tx, rx) = channel();
        let slot: Arc<std::sync::Mutex<Option<SettingsWatcher>>> = Arc::default();
        let slot2 = slot.clone();
        let w = s
            .watch(move |_| {
                // dropping the watcher on the watch thread must not deadlock
                drop(slot2.lock().unwrap().take());
                let _ = tx.send(());
            })
            .unwrap();
        *slot.lock().unwrap() = Some(w);
        s.set("G", "A", Some("1")).unwrap();
        rx.recv_timeout(WAIT).unwrap();
    }
}
