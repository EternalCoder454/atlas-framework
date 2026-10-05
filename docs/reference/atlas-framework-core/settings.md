---
title: settings
summary: An app's own settings file, ~/.config/atlas-<app>rc, in KConfig INI format, written atomically under a lock shared with Atlas.Ui's AtlasSettings.
order: 20
---

The `settings` module reads and writes the app's own settings file: `$XDG_CONFIG_HOME/atlas-<app>rc`, or `~/.config/atlas-<app>rc`. The format is KConfig's INI, so KDE tools and the app's C++ and QML side read the same file. [AtlasSettings](../atlas-ui/atlas-settings.md) in QML uses the same file and the same lock.

Use it only for Atlas-owned files (`atlas-<app>rc`). It parses and rewrites the whole file, so do not point it at another program's configuration.

## Example

```rust
use atlas_framework_core::settings::Settings;

let app = atlas_framework_core::app_info! {
    name: "Atlas Notepad",
    id: "net.eterneon.atlas.notepad",
    repo: "atlasos-notepad",
};
let s = Settings::for_app(&app);
s.set("Restart", "ScheduledAt", Some("1700000000"))?;
assert_eq!(s.get("Restart", "ScheduledAt").as_deref(), Some("1700000000"));
s.set("Restart", "ScheduledAt", None)?; // removes the key
// (the ? operator needs a function that returns io::Result)
```

## How writes behave

- Each `set` reads the file, changes one key and replaces the file atomically (temp file, sync, rename, then a directory sync). Every other line is kept, and so are the file's mode and, when running as root, its owner.
- Writers take a thread lock and an `flock` on `.<name>.lock` beside the file. The lock file stays on purpose: removing it would race the next writer. Concurrent `set` calls in Atlas code never lose a change. Another program writing the file without the lock can still race, but cannot corrupt it.
- `set` writes nothing, and takes no lock, when the file would not change. This works where the app can read but not write.
- A file that cannot be read is never overwritten.
- A symlinked file (dotfiles) keeps its link: the target is written.
- Keys and groups that KConfig marks immutable (`[$i]`) are refused.
- Values are escaped as KConfig does: a value stays on one line (`\n`, `\t`, `\r`, `\\`, `\xNN` for other control characters), and leading or trailing spaces are written as `\s`.
- The last of duplicate keys wins when reading, as in KConfig.

## Format version

A file carries `[Atlas]` `Format=1` (`settings::FORMAT`), written when a file is first created or changed. Reading never requires it: files from before it, and files a newer app wrote with a higher number, read the same. Only a change to how existing keys are read would raise it.

## Settings

`#[derive(Debug, Clone, PartialEq, Eq)]`

| Method | Description |
|---|---|
| `fn for_app(app: &AppInfo) -> Settings` | The file `<short_name>rc` in `config_dir()`, for example `atlas-updaterrc` |
| `fn at(path: impl Into<PathBuf>) -> Settings` | Any path |
| `fn path(&self) -> &Path` | The file's path |
| `fn get(&self, group: &str, key: &str) -> Option<String>` | The unescaped value, or `None` if the file, group or key is missing |
| `fn get_bool(&self, group: &str, key: &str) -> Option<bool>` | `true`, `1`, `yes`, `on` and `false`, `0`, `no`, `off` (any case); anything else, or a missing key, is `None` |
| `fn set(&self, group: &str, key: &str, value: Option<&str>) -> io::Result<()>` | Sets the key, or removes it for `None`. Errors: `InvalidInput` for a group or key that cannot be written as one (empty, control characters, brackets, `=` in a key, edge spaces, a leading `#` or `;`), `PermissionDenied` for an immutable one, `NotFound` when there is no home directory |

## Functions and constants

| Name | Kind | Description |
|---|---|---|
| `FORMAT` | `pub const u32` | The format version written, `1` |
| `config_dir()` | `pub fn config_dir() -> PathBuf` | `$XDG_CONFIG_HOME`, else `~/.config`. Relative values are ignored, as the XDG spec says. With neither, `/nonexistent`, where nothing is written |
| `get_in` | `pub fn get_in(text: &str, group: &str, key: &str) -> Option<String>` | Reads a value from KConfig text you already hold |
| `set_in` | `pub fn set_in(text: &str, group: &str, key: &str, value: Option<&str>) -> String` | Returns `text` with the key set (escaped) or removed. Does no file work and no name checks |
