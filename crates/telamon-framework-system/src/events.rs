//! `/var/lib/atlas-core/events.jsonl`: update and rollback events the helper
//! records, one JSON object per line, world-readable. Apps turn new lines into
//! crash reports (see `crash::collect_events`) when the user opted in.
//! The path keeps the old atlas-core name: existing systems hold data there.

use std::fs;
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;

use serde::{Deserialize, Serialize};

const MAX_ERROR_CHARS: usize = 300;
/// `Event::new` cuts `event` and `version` to these many characters.
const MAX_EVENT_CHARS: usize = 64;
const MAX_VERSION_CHARS: usize = 128;
/// `append` refuses a line longer than this (a line is about 2.5 KB at most
/// when built by [`Event::new`]); a truncation drops such lines.
const MAX_LINE_BYTES: usize = 8 * 1024;
/// The biggest events file `read` takes (it is cut to 512 KB; this is for a
/// file something else grew).
const MAX_READ_BYTES: u64 = 16 * 1024 * 1024;
/// `read` leaves out an event whose `time` is longer than this.
const MAX_TIME_CHARS: usize = 40;
pub const DEFAULT_PATH: &str = "/var/lib/atlas-core/events.jsonl";

/// The line format the writers produce (`"format": 1`, before the event's
/// own fields). Lines from before it have no `format`; lines with a higher
/// number read by the fields this build knows. Old readers ignore the field.
/// (`version` in a line is the OS version, so the format has its own name.)
pub const FORMAT: u32 = 1;

/// What goes on a line: the format, then the event's own fields. Kept apart
/// from [`Event`] so that struct, which callers build with a literal, keeps
/// its fields.
#[derive(Serialize)]
struct Line<'a> {
    format: u32,
    #[serde(flatten)]
    event: &'a Event,
}

/// Events that `record-event` accepts from greenboot scripts.
pub const CLI_EVENTS: &[&str] = &["health-check-failed", "health-check-passed"];

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Event {
    /// `update-staged`, `update-failed`, `rollback-requested`,
    /// `rollback-failed`, `channel-switched`, `channel-switch-failed`,
    /// `update-applied`, `rollback-applied`, `automatic-rollback`,
    /// `health-check-failed`, `health-check-passed`.
    pub event: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    /// Scrubbed error text.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    /// RFC 3339 UTC.
    pub time: String,
}

impl Event {
    pub fn new(event: &str, version: Option<String>, error: Option<&str>) -> Event {
        // paths and addresses included: the file is world-readable
        let scrubber = crate::crash::Scrubber::for_system();
        Event {
            event: event.chars().take(MAX_EVENT_CHARS).collect(),
            version: version.map(|v| v.chars().take(MAX_VERSION_CHARS).collect()),
            error: error.map(|e| {
                scrubber
                    .scrub_message(e)
                    .chars()
                    .take(MAX_ERROR_CHARS)
                    .collect()
            }),
            time: crate::history::now_rfc3339(),
        }
    }
}

/// The file is cut when it grows past `MAX_BYTES`, down to at most
/// `KEEP_BYTES` and `KEEP_LINES` (a line is at most about 2.5 KB even with a
/// 300 char error full of escapes, so one cut always lands far below the
/// limit).
const MAX_BYTES: u64 = 512 * 1024;
const KEEP_BYTES: usize = 256 * 1024;
const KEEP_LINES: usize = 1000;
/// A cut reads this much of the end of the file.
const TAIL_BYTES: u64 = 1024 * 1024;

/// Append one event (file created 0644). Fails with `InvalidInput` when the
/// line is over 8 KB, and with `TimedOut` when the lock file is still held
/// after 2 s. A lock file serializes the helper
/// and `record-event` (greenboot), so no line is lost to a concurrent cut.
/// A failed cut is logged and does not fail the append.
pub fn append(path: &Path, event: &Event) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    let line = serde_json::to_string(&Line {
        format: FORMAT,
        event,
    })
    .map_err(io::Error::other)?;
    if line.len() > MAX_LINE_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "event line is {} bytes, the limit is {MAX_LINE_BYTES}",
                line.len()
            ),
        ));
    }
    let lock = crate::fsutil::open_lock_file(&path.with_extension("jsonl.lock"))?;
    // released when `lock` is dropped; waits 2 s at most
    crate::fsutil::lock_with_deadline(&lock, crate::fsutil::LOCK_WAIT)?;
    crate::fsutil::append_line(path, &line, 0o644)?;
    if fs::symlink_metadata(path)?.len() > MAX_BYTES
        && let Err(e) = truncate(path)
    {
        log::warn!("cannot shrink {}: {e}", path.display());
    }
    Ok(())
}

fn truncate(path: &Path) -> io::Result<()> {
    // Only the tail is read: what is kept comes from the end, and a file
    // something else grew must not be read whole.
    let mut f = fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK | libc::O_NOFOLLOW | libc::O_NOCTTY | libc::O_CLOEXEC)
        .open(path)?;
    if !f.metadata()?.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "not a regular file",
        ));
    }
    let start = f.metadata()?.len().saturating_sub(TAIL_BYTES);
    f.seek(SeekFrom::Start(start))?;
    let mut bytes = Vec::new();
    f.take(TAIL_BYTES).read_to_end(&mut bytes)?;
    if start > 0 {
        // the first line is cut; drop it
        let at = bytes
            .iter()
            .position(|b| *b == b'\n')
            .map_or(bytes.len(), |i| i + 1);
        bytes.drain(..at);
    }
    let lines: Vec<&[u8]> = bytes
        .split(|b| *b == b'\n')
        .filter(|l| !l.is_empty())
        .collect();
    // Newest first; a line over the limit is dropped, never the reason to
    // keep nothing.
    let mut kept: Vec<&[u8]> = Vec::new();
    let mut total = 0usize;
    for l in lines.iter().rev() {
        if l.len() > MAX_LINE_BYTES {
            continue;
        }
        if kept.len() >= KEEP_LINES || total + l.len() >= KEEP_BYTES {
            break;
        }
        total += l.len() + 1;
        kept.push(l);
    }
    kept.reverse();
    let tmp = path.with_extension(format!("jsonl.{}.tmp", std::process::id()));
    let _ = fs::remove_file(&tmp);
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o644)
        .open(&tmp)?;
    let res = (|| {
        for l in &kept {
            f.write_all(l)?;
            f.write_all(b"\n")?;
        }
        f.sync_all()?;
        fs::rename(&tmp, path)
    })();
    if res.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    res
}

/// All events, oldest first. A missing file, a file that is not a regular
/// file or is over 16 MB, bad lines, or a line with a `time` over 40
/// characters give fewer events.
pub fn read(path: &Path) -> Vec<Event> {
    let bytes = match crate::fsutil::read_capped(path, MAX_READ_BYTES) {
        Ok(b) => b,
        Err(e) => {
            if e.kind() != io::ErrorKind::NotFound {
                log::warn!("cannot read {}: {e}", path.display());
            }
            Vec::new()
        }
    };
    crate::fsutil::lossy_lines(&bytes)
        .iter()
        .filter_map(|l| serde_json::from_str::<Event>(l).ok())
        // a time is an RFC 3339 time (at most 35 characters), and a report
        // is saved under it: a longer one can never be queued
        .filter(|e| e.time.len() <= MAX_TIME_CHARS)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn concurrent_appenders_with_cuts_lose_no_structure() {
        let d = tempfile::tempdir().unwrap();
        let p = std::sync::Arc::new(d.path().join("e.jsonl"));
        // escapes make every error 6x bigger in the file: forces many cuts
        let err = "\u{1}\"\\".repeat(100);
        let hs: Vec<_> = (0..8)
            .map(|_| {
                let (p, err) = (p.clone(), err.clone());
                std::thread::spawn(move || {
                    for _ in 0..200 {
                        append(&p, &Event::new("update-failed", None, Some(&err))).unwrap();
                    }
                })
            })
            .collect();
        for h in hs {
            h.join().unwrap();
        }
        let text = fs::read_to_string(&*p).unwrap();
        let lines: Vec<_> = text.lines().collect();
        assert!(!lines.is_empty() && lines.len() <= 1600);
        assert!(
            lines
                .iter()
                .all(|l| serde_json::from_str::<Event>(l).is_ok()),
            "torn line"
        );
        assert!(fs::metadata(&*p).unwrap().len() <= MAX_BYTES + 4096);
        let stray: Vec<_> = fs::read_dir(d.path())
            .unwrap()
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().ends_with(".tmp"))
            .collect();
        assert!(stray.is_empty());
    }

    #[test]
    fn one_cut_goes_well_below_the_limit() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("e.jsonl");
        let e = Event::new("update-failed", None, Some(&"\u{1}".repeat(300)));
        let line = serde_json::to_string(&Line {
            format: FORMAT,
            event: &e,
        })
        .unwrap()
        .len() as u64
            + 1;
        assert!(line > 1500, "escaped error line is {line} bytes");
        let (mut prev, mut cut) = (0, false);
        for _ in 0..2000 {
            append(&p, &e).unwrap();
            let now = fs::metadata(&p).unwrap().len();
            if now < prev {
                cut = true;
                break;
            }
            prev = now;
        }
        assert!(cut, "no cut seen");
        assert!(fs::metadata(&p).unwrap().len() <= KEEP_BYTES as u64 + 4096);
    }

    #[test]
    fn torn_utf8_line_spoils_only_itself() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("e.jsonl");
        append(&p, &Event::new("update-staged", None, None)).unwrap();
        let mut data = fs::read(&p).unwrap();
        data.extend_from_slice(b"{\"event\":\"x\",\"time\":\"\xe2\x82");
        fs::write(&p, data).unwrap();
        append(&p, &Event::new("rollback-requested", None, None)).unwrap();
        let names: Vec<_> = read(&p).into_iter().map(|e| e.event).collect();
        assert_eq!(names, ["update-staged", "rollback-requested"]);
    }

    #[test]
    fn event_and_version_are_capped() {
        let e = Event::new("e".repeat(500).as_str(), Some("v".repeat(500)), None);
        assert_eq!(e.event.chars().count(), 64);
        assert_eq!(e.version.unwrap().chars().count(), 128);
    }

    #[test]
    fn a_line_over_8_kb_is_refused() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("e.jsonl");
        let mut e = Event::new("update-failed", None, None);
        e.error = Some("x".repeat(9000));
        assert_eq!(
            append(&p, &e).unwrap_err().kind(),
            io::ErrorKind::InvalidInput
        );
        assert!(!p.exists());
    }

    #[test]
    fn one_huge_line_does_not_empty_the_file_on_a_cut() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("e.jsonl");
        let e = Event::new("update-staged", None, None);
        append(&p, &e).unwrap();
        // a foreign writer's 600 KB line puts the file over the limit
        let mut f = fs::OpenOptions::new().append(true).open(&p).unwrap();
        f.write_all(&vec![b'x'; 600 * 1024]).unwrap();
        f.write_all(b"\n").unwrap();
        drop(f);
        append(&p, &Event::new("rollback-requested", None, None)).unwrap();
        let names: Vec<_> = read(&p).into_iter().map(|e| e.event).collect();
        assert_eq!(names, ["update-staged", "rollback-requested"]);
        assert!(fs::metadata(&p).unwrap().len() < 1024);
    }

    #[test]
    fn a_held_lock_file_times_out() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("e.jsonl");
        let held = fs::File::create(p.with_extension("jsonl.lock")).unwrap();
        held.lock().unwrap();
        let e = append(&p, &Event::new("update-staged", None, None)).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::TimedOut);
        drop(held);
        append(&p, &Event::new("update-staged", None, None)).unwrap();
    }

    #[test]
    fn long_errors_are_capped_and_file_is_truncated() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("e.jsonl");
        let e = Event::new("update-failed", None, Some(&"x".repeat(5000)));
        assert_eq!(e.error.as_ref().unwrap().chars().count(), 300);
        for _ in 0..2000 {
            append(&p, &e).unwrap();
        }
        assert!(fs::metadata(&p).unwrap().len() <= MAX_BYTES + 1000);
        assert!(read(&p).len() <= 2000 && !read(&p).is_empty());
    }

    #[test]
    fn append_and_read_with_scrubbed_error() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("v/events.jsonl");
        append(
            &p,
            &Event::new(
                "update-failed",
                Some("44.1".into()),
                Some("cannot read /home/zach/x from 10.0.0.2"),
            ),
        )
        .unwrap();
        append(&p, &Event::new("update-staged", None, None)).unwrap();
        let ev = read(&p);
        assert_eq!(ev.len(), 2);
        assert_eq!(ev[0].error.as_deref(), Some("cannot read <path>"));
        assert!(!fs::read_to_string(&p).unwrap().contains("\"error\":null"));
        assert!(read(&d.path().join("none")).is_empty());
    }

    /// The struct as it was before `format` existed: what an older helper or
    /// app (a rollback) reads the file with.
    #[derive(Debug, Deserialize)]
    struct OldEvent {
        event: String,
        #[serde(default)]
        version: Option<String>,
        #[serde(default)]
        error: Option<String>,
        time: String,
    }

    #[test]
    fn lines_carry_format_1_and_old_readers_still_read_them() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("e.jsonl");
        append(&p, &Event::new("update-staged", Some("44.1".into()), None)).unwrap();
        let text = fs::read_to_string(&p).unwrap();
        assert!(
            text.starts_with("{\"format\":1,\"event\":\"update-staged\""),
            "{text}"
        );
        let old: OldEvent = serde_json::from_str(text.trim()).unwrap();
        assert_eq!(
            (old.event.as_str(), old.version.as_deref()),
            ("update-staged", Some("44.1"))
        );
        assert!(old.error.is_none() && !old.time.is_empty());
        assert_eq!(read(&p).len(), 1);
    }

    #[test]
    fn lines_of_any_format_read() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("e.jsonl");
        fs::write(
            &p,
            "{\"event\":\"a\",\"time\":\"t\"}\n{\"format\":5,\"event\":\"b\",\"time\":\"t\",\"more\":[1]}\n",
        )
        .unwrap();
        let names: Vec<_> = read(&p).into_iter().map(|e| e.event).collect();
        assert_eq!(names, ["a", "b"]);
    }

    #[test]
    fn read_leaves_out_an_event_with_a_time_that_is_too_long() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("e.jsonl");
        let long = format!(
            r#"{{"event":"update-failed","time":"2026-10-02T10:00:00Z{}"}}"#,
            "0".repeat(300)
        );
        let edge = format!(
            r#"{{"event":"update-failed","time":"{}"}}"#,
            "2".repeat(MAX_TIME_CHARS)
        );
        let ok = r#"{"format":1,"event":"update-failed","time":"2026-10-02T10:00:01Z"}"#;
        std::fs::write(&p, format!("{long}\n{edge}\n{ok}\n")).unwrap();
        let got = read(&p);
        assert_eq!(got.len(), 2, "{got:?}");
        assert_eq!(got[1].time, "2026-10-02T10:00:01Z");
    }
}
