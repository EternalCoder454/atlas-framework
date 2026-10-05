---
title: fsutil
summary: Helpers for appending to shared log files without following symlinks, and for reading lines that may be torn.
order: 50
---

The `fsutil` module holds the two small helpers behind the AtlasOS history and event logs (`history.jsonl`, `events.jsonl`; see [atlas-framework-system](../atlas-framework-system/formats.md)). Use them for any append-only line file that several programs share.

## Example

```rust
use atlas_framework_core::fsutil::{append_line, lossy_lines};
use std::path::Path;

let path = Path::new("/tmp/example.log");
append_line(path, r#"{"event":"x"}"#, 0o644)?;
let lines = lossy_lines(&std::fs::read(path)?);
```

## Items

| Name | Signature | Description |
|---|---|---|
| `append_line` | `pub fn append_line(path: &Path, line: &str, mode: u32) -> io::Result<()>` | Appends `line` and a newline. Refuses to follow a symlink at the final path component (`O_NOFOLLOW`). Starts with a newline if the file does not end in one (a torn earlier write). Creates the file with `mode` and syncs before returning |
| `lossy_lines` | `pub fn lossy_lines(bytes: &[u8]) -> Vec<String>` | Splits on `\n` and decodes each line lossily, so one torn multibyte character spoils only its own line. Empty lines are dropped |
