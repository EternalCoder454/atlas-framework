---
title: osrelease
summary: The OS name, version and logo from os-release(5), for About pages and reports.
order: 40
---

The `osrelease` module reads the OS name, version and logo from `/etc/os-release`, else `/usr/lib/os-release`. Only the system's own files are read. Use it for About pages and reports.

## Example

```rust
use atlas_framework_core::osrelease::OsRelease;

let os = OsRelease::load();
println!("{}", os.display_name()); // for example "AtlasOS 44.20261003"
```

## OsRelease

`#[derive(Debug, Clone, Default, PartialEq, Eq)]`. Missing fields are empty strings.

| Field | os-release key |
|---|---|
| `id` | `ID` |
| `name` | `NAME` |
| `version` | `VERSION` |
| `version_id` | `VERSION_ID` |
| `pretty_name` | `PRETTY_NAME` |
| `logo` | `LOGO`, an icon name such as `atlasos-logo` |
| `home_url` | `HOME_URL` |
| `bug_report_url` | `BUG_REPORT_URL` |

Values may be unquoted, single-quoted, or double-quoted (inside double quotes `\` escapes `"`, `\`, `$` and the backtick). Comments, blank lines and lines without `=` are skipped. The last of duplicate keys wins.

## Methods and functions

| Name | Signature | Description |
|---|---|---|
| `OsRelease::load` | `fn load() -> OsRelease` | `/etc/os-release`, else `/usr/lib/os-release`, else all empty |
| `OsRelease::load_from` | `fn load_from(path: &Path) -> Option<OsRelease>` | One file; `None` if it cannot be read |
| `OsRelease::parse` | `fn parse(text: &str) -> OsRelease` | Parses os-release text |
| `OsRelease::display_name` | `fn display_name(&self) -> String` | `PRETTY_NAME`, else `NAME VERSION` (or `VERSION_ID`), else `Linux` |
| `OsRelease::logo_icon` | `fn logo_icon(&self) -> Option<String>` | `LOGO` when it is a plain icon name (ASCII letters, digits, `-`, `_`, `.`, `+`); a path or an empty value is `None` |
| `logo_icon` | `pub fn logo_icon() -> Option<String>` | `OsRelease::load().logo_icon()` |
