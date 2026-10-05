//! Small file helpers shared by the system history and event logs.

use std::fs::{File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{FileExt, OpenOptionsExt};
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
        .custom_flags(libc::O_NONBLOCK | libc::O_CLOEXEC)
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
/// at the final component, starts with a newline if the file does not end in
/// one (a torn earlier write), creates it with `mode`, and syncs.
pub fn append_line(path: &Path, line: &str, mode: u32) -> io::Result<()> {
    let f = OpenOptions::new()
        .read(true)
        .append(true)
        .create(true)
        .mode(mode)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)?;
    let len = f.metadata()?.len();
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

/// The lines of `bytes`, split on `\n`, each decoded lossily, so one torn
/// multibyte character spoils only its own line. Empty lines are dropped.
pub fn lossy_lines(bytes: &[u8]) -> Vec<String> {
    bytes
        .split(|b| *b == b'\n')
        .filter(|l| !l.is_empty())
        .map(|l| String::from_utf8_lossy(l).into_owned())
        .collect()
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
        assert_eq!(unsafe { libc::mkfifo(c.as_ptr(), 0o600) }, 0);
        assert!(read_capped(&fifo, 10).is_err()); // returns, does not block
        assert_eq!(
            read_capped(&d.path().join("none"), 10).unwrap_err().kind(),
            io::ErrorKind::NotFound
        );
    }
}
