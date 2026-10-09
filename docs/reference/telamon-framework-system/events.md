---
title: events
summary: The update and rollback events the Telamon OS system helper records, one JSON line each, and the functions that read and append them.
order: 40
---

The `events` module handles `/var/lib/atlas-core/events.jsonl`: update and rollback events the helper records, one JSON object per line, world-readable. Apps turn new lines into crash reports (see [`crash::collect_events`](crash.md)) when the user opted in. The path keeps the old atlas-core name. The file format is in [On-disk formats](formats.md#events).

## Example

```rust
use telamon_framework_system::events;
use std::path::Path;

// Oldest first. A missing file or bad lines give fewer events.
let all = events::read(Path::new(events::DEFAULT_PATH));
let failures: Vec<_> = all.iter().filter(|e| e.event.ends_with("-failed")).collect();
```

## Event

`#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)] pub struct Event`

| Field | Type | Description |
|---|---|---|
| `event` | `String` | One of `update-staged`, `update-failed`, `rollback-requested`, `rollback-failed`, `channel-switched`, `channel-switch-failed`, `update-applied`, `rollback-applied`, `automatic-rollback`, `health-check-failed`, `health-check-passed` |
| `version` | `Option<String>` | The OS version. Left out of the line when `None` |
| `error` | `Option<String>` | Scrubbed error text. Left out of the line when `None` |
| `time` | `String` | RFC 3339 UTC |

`Event::new(event: &str, version: Option<String>, error: Option<&str>) -> Event` builds one with the current time. The error text is scrubbed (the file is world-readable, so paths and addresses go too) and cut to 300 characters; `event` is cut to 64 characters and `version` to 128.

## Items

| Name | Signature | Description |
|---|---|---|
| `DEFAULT_PATH` | `pub const &str` | `/var/lib/atlas-core/events.jsonl` |
| `FORMAT` | `pub const u32` | `1` |
| `CLI_EVENTS` | `pub const &[&str]` | The events `record-event` accepts from greenboot scripts: `health-check-failed` and `health-check-passed` |
| `append` | `pub fn append(path: &Path, event: &Event) -> io::Result<()>` | Appends one event (file created 0644, no symlink followed). A lock file (`events.jsonl.lock`, 0600; a symlink or FIFO at its name is refused at once) serializes the helper and `record-event`; waiting for it is bounded (polled for 2 seconds, then `ErrorKind::TimedOut`). A line over 8 KB is refused with `InvalidInput`. When the file passes 512 KiB it is cut to the newest lines (at most 1000 lines and 256 KiB); a cut reads only the last 1 MB, drops any line over 8 KB (one huge line never empties the file), and a failed cut is logged (`log::warn!`) and does not fail the append |
| `read` | `pub fn read(path: &Path) -> Vec<Event>` | All events, oldest first. A file that is not a regular file or is over 16 MB reads as no events |

Writing needs permission to write under `/var/lib/atlas-core`, which only the root helper has. An app reads.
