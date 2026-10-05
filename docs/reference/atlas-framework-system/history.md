---
title: history
summary: The record of AtlasOS versions this machine has booted, one JSON line each, and the helpers that read and append to it.
order: 20
---

The `history` module reads and writes the boot history: `/var/lib/atlas-core/history.jsonl`, one JSON object per line, appended by `atlas-system-helper record-boot` when the booted image digest changes. The path keeps the old atlas-core name because existing systems hold data there. The file format is in [On-disk formats](formats.md#history).

## Example

```rust
use atlas_framework_system::history;

// Newest first. A missing file is an empty history.
for e in history::read_default()? {
    println!("{} first booted {}", e.version.as_deref().unwrap_or("?"), e.first_booted);
}
```

## Entry

`#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)] pub struct Entry`

| Field | Type | Description |
|---|---|---|
| `version` | `Option<String>` | The OS version (the image's version label) |
| `digest` | `String` | The image digest |
| `image` | `String` | The image reference, such as `x:stable`. Defaults to empty |
| `timestamp` | `Option<String>` | The image build time, RFC 3339 |
| `first_booted` | `String` | When this machine first booted it, RFC 3339 UTC |

## Items

| Name | Signature | Description |
|---|---|---|
| `DEFAULT_PATH` | `pub const &str` | `/var/lib/atlas-core/history.jsonl` |
| `FORMAT` | `pub const u32` | `1`, the line format the writers produce |
| `read_default` | `pub fn read_default() -> io::Result<Vec<Entry>>` | Reads the history at the default path, newest first |
| `read` | `pub fn read(path: &Path) -> io::Result<Vec<Entry>>` | Reads a history file, newest first. A missing file is an empty history; lines that do not parse are skipped |
| `append_if_new` | `pub fn append_if_new(path: &Path, entry: &Entry) -> io::Result<bool>` | Appends `entry` unless the newest entry has the same digest. Returns whether a line was written. Creates the directory and the file (mode 0644), and refuses a symlink at the file |
| `record_boot` | `pub fn record_boot(path: &Path, status: &bootc::Status, now: &str) -> io::Result<bool>` | Records the booted deployment of a [`Status`](bootc.md#status). Errors when bootc reports no booted image |
| `now_rfc3339` | `pub fn now_rfc3339() -> String` | The current time as `YYYY-MM-DDTHH:MM:SSZ` |
| `rfc3339_from_unix` | `pub fn rfc3339_from_unix(secs: u64) -> String` | Unix seconds as UTC RFC 3339 |

Writing needs permission to write under `/var/lib/atlas-core`, which only the root helper has. An app reads.
