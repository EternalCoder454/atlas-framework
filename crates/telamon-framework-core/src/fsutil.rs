//! Small file helpers shared by the system history and event logs.

use std::fs::{File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{DirBuilderExt, FileExt, OpenOptionsExt};
use std::path::Path;
use std::time::{Duration, Instant};

/// How long [`lock_with_deadline`] callers wait for a lock file.
pub const LOCK_WAIT: Duration = Duration::from_secs(2);

/// Take an exclusive `flock` on `f`, polling with `LOCK_NB` until `wait` has
/// passed. Fails with `TimedOut` instead of blocking for good behind a
/// stopped holder or a hung network home. Released when `f` is dropped.
pub fn lock_with_deadline(f: &File, wait: Duration) -> io::Result<()> {
    let end = Instant::now() + wait;
    loop {
        match f.try_lock() {
            Ok(()) => return Ok(()),
            Err(std::fs::TryLockError::WouldBlock) => {
                if Instant::now() >= end {
                    return Err(io::Error::new(
                        io::ErrorKind::TimedOut,
                        "timed out waiting for a lock file",
                    ));
                }
                std::thread::sleep(Duration::from_millis(10));
            }
            Err(std::fs::TryLockError::Error(e)) => return Err(e),
        }
    }
}

/// Read a regular file of at most `max` bytes. Never blocks on a FIFO or
/// device (`O_NONBLOCK`), requires a regular file (checked on the opened
/// file, so there is no race), and fails with `InvalidData` when the file is
/// larger than `max`. A symlink is followed (`/etc/os-release` is one).
pub fn read_capped(path: &Path, max: u64) -> io::Result<Vec<u8>> {
    let f = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK | libc::O_NOCTTY | libc::O_CLOEXEC)
        .open(path)?;
    if !f.metadata()?.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "not a regular file",
        ));
    }
    let mut buf = Vec::new();
    f.take(max.saturating_add(1)).read_to_end(&mut buf)?;
    if buf.len() as u64 > max {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "file is too large",
        ));
    }
    Ok(buf)
}

/// Append `line` (a newline is added) to `path`: refuses to follow a symlink
/// at the final component, refuses anything but a regular file (a FIFO or
/// device planted at the path is never written to and never blocks),
/// starts with a newline if the file does not end in one (a torn earlier
/// write), creates it with `mode`, and syncs.
pub fn append_line(path: &Path, line: &str, mode: u32) -> io::Result<()> {
    let f = OpenOptions::new()
        .read(true)
        .append(true)
        .create(true)
        .mode(mode)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK | libc::O_NOCTTY | libc::O_CLOEXEC)
        .open(path)?;
    let meta = f.metadata()?;
    if !meta.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "not a regular file",
        ));
    }
    let len = meta.len();
    let mut data = String::with_capacity(line.len() + 2);
    if len > 0 {
        let mut last = [0u8; 1];
        f.read_exact_at(&mut last, len - 1)?;
        if last[0] != b'\n' {
            data.push('\n');
        }
    }
    data.push_str(line);
    data.push('\n');
    (&f).write_all(data.as_bytes())?;
    f.sync_all()
}

/// The longest line [`lossy_lines`] keeps (the writers' lines are under
/// 8 KB).
pub const MAX_LINE_BYTES: usize = 64 * 1024;

/// The lines of `bytes`, split on `\n`, each decoded lossily, so one torn
/// multibyte character spoils only its own line. Empty lines are dropped, and
/// so are lines over [`MAX_LINE_BYTES`], which are never decoded or copied.
pub fn lossy_lines(bytes: &[u8]) -> Vec<String> {
    bytes
        .split(|b| *b == b'\n')
        .filter(|l| !l.is_empty() && l.len() <= MAX_LINE_BYTES)
        .map(|l| String::from_utf8_lossy(l).into_owned())
        .collect()
}

/// Open (creating it, mode 0600) the lock file of a shared log, for
/// [`lock_with_deadline`]. Refuses a symlink at the final component and
/// anything but a regular file; opens without blocking, so a FIFO planted at
/// the lock's name fails at once instead of hanging the caller for good.
pub fn open_lock_file(path: &Path) -> io::Result<File> {
    let f = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK | libc::O_NOCTTY | libc::O_CLOEXEC)
        .open(path)?;
    if !f.metadata()?.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "not a regular file",
        ));
    }
    Ok(f)
}

/// `create_dir_all` for a directory that belongs to the user (settings,
/// state): every directory it has to make gets mode 0700 (less the umask),
/// as the XDG Base Directory spec asks, not 0777 less the umask. A directory
/// that exists is left as it is.
pub fn create_private_dir_all(path: &Path) -> io::Result<()> {
    std::fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repairs_missing_newline_and_refuses_symlinks() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("f");
        std::fs::write(&p, "torn").unwrap();
        append_line(&p, "{}", 0o644).unwrap();
        assert_eq!(std::fs::read_to_string(&p).unwrap(), "torn\n{}\n");
        let l = d.path().join("link");
        std::os::unix::fs::symlink(&p, &l).unwrap();
        assert!(append_line(&l, "x", 0o644).is_err());
    }

    #[test]
    fn lock_times_out_behind_a_holder() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("l");
        let a = std::fs::File::create(&p).unwrap();
        let b = std::fs::File::open(&p).unwrap();
        lock_with_deadline(&a, LOCK_WAIT).unwrap();
        let e = lock_with_deadline(&b, Duration::from_millis(100)).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::TimedOut);
        drop(a);
        lock_with_deadline(&b, Duration::from_millis(100)).unwrap();
    }

    #[test]
    fn read_capped_refuses_fifos_and_big_files_and_follows_links() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("f");
        std::fs::write(&p, "abcd").unwrap();
        assert_eq!(read_capped(&p, 4).unwrap(), b"abcd");
        assert_eq!(
            read_capped(&p, 3).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
        let l = d.path().join("l");
        std::os::unix::fs::symlink(&p, &l).unwrap();
        assert_eq!(read_capped(&l, 10).unwrap(), b"abcd");
        let fifo = d.path().join("fifo");
        let c = std::ffi::CString::new(fifo.to_str().unwrap()).unwrap();
        // SAFETY: a NUL-terminated path.
        assert_eq!(unsafe { libc::mkfifo(c.as_ptr(), 0o600) }, 0);
        assert!(read_capped(&fifo, 10).is_err()); // returns, does not block
        assert_eq!(
            read_capped(&d.path().join("none"), 10).unwrap_err().kind(),
            io::ErrorKind::NotFound
        );
    }

    fn fifo(path: &Path) {
        let c = std::ffi::CString::new(path.to_str().unwrap()).unwrap();
        // SAFETY: a NUL-terminated path.
        assert_eq!(unsafe { libc::mkfifo(c.as_ptr(), 0o600) }, 0);
    }

    #[test]
    fn append_line_never_writes_to_a_fifo() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("log");
        fifo(&p);
        // A reader on the other end: whatever the writer sent would arrive.
        let reader = OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NONBLOCK)
            .open(&p)
            .unwrap();
        let e = append_line(&p, "secret", 0o644).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::InvalidData);
        let mut got = Vec::new();
        let _ = (&reader).read_to_end(&mut got);
        assert!(got.is_empty(), "{got:?}");
    }

    #[test]
    fn a_fifo_for_a_lock_file_fails_at_once() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("log.lock");
        fifo(&p);
        let t = Instant::now();
        assert!(open_lock_file(&p).is_err()); // ENXIO: no reader, no hang
        assert!(t.elapsed() < Duration::from_secs(1));
        let l = d.path().join("link.lock");
        std::os::unix::fs::symlink(d.path().join("target"), &l).unwrap();
        assert!(open_lock_file(&l).is_err());
        assert!(!d.path().join("target").exists());
        let ok = d.path().join("ok.lock");
        open_lock_file(&ok).unwrap();
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(ok.metadata().unwrap().permissions().mode() & 0o777, 0o600);
    }

    #[test]
    fn lines_over_the_limit_are_dropped_unread() {
        let mut bytes = b"ok1\n".to_vec();
        bytes.extend(std::iter::repeat_n(b'x', MAX_LINE_BYTES + 1));
        bytes.extend_from_slice(b"\nok2\n");
        let mut edge = vec![b'y'; MAX_LINE_BYTES];
        edge.push(b'\n');
        bytes.extend(edge);
        let lines = lossy_lines(&bytes);
        assert_eq!(lines.len(), 3);
        assert_eq!((lines[0].as_str(), lines[1].as_str()), ("ok1", "ok2"));
        assert_eq!(lines[2].len(), MAX_LINE_BYTES);
    }

    #[test]
    fn private_dirs_are_0700_all_the_way_down() {
        use std::os::unix::fs::PermissionsExt;
        let d = tempfile::tempdir().unwrap();
        let deep = d.path().join("a/b/c");
        create_private_dir_all(&deep).unwrap();
        for p in [d.path().join("a"), d.path().join("a/b"), deep.clone()] {
            let mode = p.metadata().unwrap().permissions().mode() & 0o777;
            assert_eq!(mode & 0o077, 0, "{p:?} is {mode:o}");
        }
        // An existing directory keeps its mode, and calling again is fine.
        std::fs::set_permissions(&deep, std::fs::Permissions::from_mode(0o755)).unwrap();
        create_private_dir_all(&deep).unwrap();
        assert_eq!(deep.metadata().unwrap().permissions().mode() & 0o777, 0o755);
    }

    mod props {
        use super::*;
        use proptest::prelude::*;

        proptest! {
            #[test]
            fn prop_lossy_lines_never_panics_and_stays_bounded(
                bytes in proptest::collection::vec(any::<u8>(), 0..2048)
            ) {
                for l in lossy_lines(&bytes) {
                    prop_assert!(!l.is_empty());
                    prop_assert!(!l.contains('\n'));
                    // lossy decoding turns one bad byte into at most 3
                    prop_assert!(l.len() <= MAX_LINE_BYTES * 3);
                }
            }

            #[test]
            fn prop_read_capped_never_returns_more_than_max(
                bytes in proptest::collection::vec(any::<u8>(), 0..256),
                max in 0u64..300,
            ) {
                let d = tempfile::tempdir().unwrap();
                let p = d.path().join("f");
                std::fs::write(&p, &bytes).unwrap();
                match read_capped(&p, max) {
                    Ok(got) => {
                        prop_assert!(got.len() as u64 <= max);
                        prop_assert_eq!(got, bytes);
                    }
                    Err(e) => {
                        prop_assert_eq!(e.kind(), io::ErrorKind::InvalidData);
                        prop_assert!(bytes.len() as u64 > max);
                    }
                }
            }
        }
    }
}
