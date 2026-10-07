---
title: fsutil
summary: Helpers for appending to shared log files without following symlinks, and for reading lines that may be torn.
order: 50
---

The `fsutil` module holds the two small helpers behind the Telamon OS history and event logs (`history.jsonl`, `events.jsonl`; see [telamon-framework-system](../telamon-framework-system/formats.md)). Use them for any append-only line file that several programs share.

## Example

```rust
use telamon_framework_core::fsutil::{append_line, lossy_lines};
use std::path::Path;

let path = Path::new("/tmp/example.log");
append_line(path, r#"{"event":"x"}"#, 0o644)?;
let lines = lossy_lines(&std::fs::read(path)?);
```

## Items

| Name | Signature | Description |
|---|---|---|
| `append_line` | `pub fn append_line(path: &Path, line: &str, mode: u32) -> io::Result<()>` | Appends `line` and a newline. Refuses to follow a symlink at the final path component (`O_NOFOLLOW`). Starts with a newline if the file does not end in one (a torn earlier write). Creates the file with `mode` and syncs before returning |
| `read_capped` | `pub fn read_capped(path: &Path, max: u64) -> io::Result<Vec<u8>>` | Reads a regular file of at most `max` bytes. Opens with `O_NONBLOCK` (a FIFO never blocks), requires a regular file, follows a symlink, and fails with `InvalidData` for a non-file or a larger file |
| `lock_with_deadline` | `pub fn lock_with_deadline(f: &File, wait: Duration) -> io::Result<()>` | An exclusive `flock` polled with `LOCK_NB` for up to `wait`; `ErrorKind::TimedOut` after that. Released when `f` is dropped |
| `LOCK_WAIT` | `pub const LOCK_WAIT: Duration` | 2 seconds: what the settings, events and history locks wait |
| `lossy_lines` | `pub fn lossy_lines(bytes: &[u8]) -> Vec<String>` | Splits on `\n` and decodes each line lossily, so one torn multibyte character spoils only its own line. Empty lines are dropped |
