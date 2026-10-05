---
title: settings
summary: An app's own settings file in ~/.config, in KConfig INI format, written atomically under a lock shared with Atlas.Ui's AtlasSettings.
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
- Writers take an `flock` on `.<name>.lock` beside the file and a thread lock. The wait for the file lock is bounded: `LOCK_NB` polling for 2 seconds, then `set` fails with `ErrorKind::TimedOut` (a stopped holder or a hung network home never freezes the caller for good). A caller must handle that error and show it, as it must any `set` error. The lock file stays on purpose: removing it would race the next writer. Concurrent `set` calls in Atlas code never lose a change. Another program writing the file without the lock can still race, but cannot corrupt it.
- `set` writes nothing, and takes no lock, when the file would not change. This works where the app can read but not write.
- A file that cannot be read is never overwritten. Reading is bounded: only a regular file of at most 4 MB is read (a FIFO is not opened for blocking, a larger file is an error), and bytes that are not UTF-8 read as U+FFFD, but such a file is never rewritten (`set` fails with `InvalidData`), so no other line or comment is changed.
- Under the lock, `set` removes the temp files (`.<name>.tmp<pid>-<n>`, exactly) left by a crashed writer when they are older than a day, once per process and file.
- A symlinked file (dotfiles) keeps its link: the target is written.
- Keys and groups that KConfig marks immutable (`[$i]`) are refused.
- Values are escaped as KConfig does: a value stays on one line (`\n`, `\t`, `\r`, `\\`, `\xNN` for other control characters), and leading or trailing spaces are written as `\s`.
- The last of duplicate keys wins when reading, as in KConfig.

## Format version

A file carries `[Atlas]` `Format=1` (`settings::FORMAT`), written when a file is first created or changed. Reading never requires it: files from before it, and files a newer app wrote with a higher number, read the same. Only a change to how existing keys are read would raise it.

## Migrations

`Settings::migrate(&[Migration])` brings an older file up to the app's schema version. The version is `[Atlas]` `SchemaVersion=N` (`SCHEMA_GROUP`, `SCHEMA_KEY`), separate from `Format`. `migrations[n]` upgrades version `n` to `n + 1`, so the app's version is `migrations.len()`. A file without `SchemaVersion` is version 0. Call `migrate` once at start, before reading.

```rust
use atlas_framework_core::settings::{Migration, Settings, get_in, set_in};

fn rename_lang(text: &str) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let v = get_in(text, "General", "Lang");
    let text = set_in(text, "General", "Lang", None);
    Ok(match v {
        Some(v) => set_in(&text, "General", "Language", Some(&v)),
        None => text,
    })
}
const MIGRATIONS: &[Migration] = &[rename_lang]; // version 0 to 1

let s = Settings::at("/tmp/atlas-examplerc");
match s.migrate(MIGRATIONS) {
    Ok(done) => log::info!("settings: {done:?}"),
    Err(e) => eprintln!("{e}"), // show it; the file is untouched
}
```

- All steps run in memory under the writer lock. Only when every step has succeeded is the old file copied to `<name>.bak` (a temp file and a rename, with the old file's mode) and also to `<name>.bak.v<N>`, `N` being the version it was. `<name>.bak` is the latest call's copy and is replaced by a later call; the `.bak.v<N>` files are not, so an older schema's backup survives a later migration. The `.bak.v<N>` just made and the 2 highest other versions are kept, and then the new text replaces the file atomically. A failing step, a step whose text is over 4 MB, or a panic in one (caught only with `panic = "unwind"`), returns `MigrateError::Failed { from, source }` and writes nothing, not even the `.bak`. Its message names the version: "settings migration from version 1 to 2 failed: ...".
- A step runs under the file lock and the writer lock. It must work only on the text it is given: `Settings::set` or `migrate` called from inside a step (on any file) returns an error at once instead of hanging.
- A file newer than the app (`SchemaVersion` above `migrations.len()`) is never written: `migrate` returns `MigrateError::Newer { found, known }` and logs a warning. The file still reads. The app chooses: read it and avoid `set`, or quit with a message. Nothing stops a later `set`, so the app must not call it.
- A missing or empty file is created at the current version (`Migrated::Created`), so a later start does not run the migrations on new data.
- `SchemaVersion` that is not a number is `MigrateError::BadVersion` (the value cut to 64 characters); an immutable one is `Io` with `PermissionDenied`; a file that is not UTF-8 is `Io` with `InvalidData`.

| Item | Description |
|---|---|
| `type Migration = fn(&str) -> Result<String, Box<dyn Error + Send + Sync>>` | One step: the whole text in, the new text out |
| `fn migrate(&self, migrations: &[Migration]) -> Result<Migrated, MigrateError>` | As above |
| `enum Migrated` | `UpToDate`, `Created { to }`, `Upgraded { from, to }` (`Debug, Clone, Copy, PartialEq, Eq`) |
| `enum MigrateError` (`#[non_exhaustive]`) | `Failed { from, source }`, `Newer { found, known }`, `BadVersion(String)`, `Io(io::Error)`; implements `Error` and `Display` |
| `SCHEMA_GROUP`, `SCHEMA_KEY` | `pub const &str`: `"Atlas"`, `"SchemaVersion"` |

## Watching for changes

`Settings::watch(on_change)` calls `on_change(&Snapshot)` on a thread named `atlas-settings-watch` whenever the file's contents change, and returns a `SettingsWatcher`. Dropping the watcher stops the watch; a callback already running finishes and none starts afterwards.

```rust
let s = Settings::at("/tmp/atlas-examplerc");
let _watch = s.watch(|new| {
    let dark = new.get_bool("General", "Dark");
    // hand `dark` to the UI thread
})?;
```

- The directory is watched with inotify (through `libc`; no new dependency), not the file, so a write in place, an editor's rename over the file, a delete and a re-create are all seen. Other files in the directory are ignored.
- A symlinked file is followed: its target's directory is watched as well, and the link is resolved again when the link itself changes (checked only on events for the link's name), so a retargeted link is followed. A target in a directory that does not exist yet is watched through its nearest existing ancestor until it appears. Only the last component of the path is resolved as a link: a symlinked directory higher up is watched by what it points to (its inode), so replacing that link by another is not noticed.
- Events are debounced: the callback runs once the file has been quiet for `DEBOUNCE` (200 ms), but a steady stream of events holds it back at most 2 seconds. It runs only when the text differs from the last one reported; the text when `watch` was called is the first. The app's own `set` that changes nothing, or a delete and re-create with the same text, call nothing.
- A deleted file gives a `Snapshot` where `exists()` is false and every `get` is `None`. `exists()` is false only for a missing file. A file that is there but cannot be read (over 4 MB, not a regular file such as a FIFO, no permission) is logged and no callback runs: the last values stand until it reads again, so an app that writes defaults when `!exists()` never overwrites it.
- `watch` creates the file's own directory if it is missing, as `set` would. After that the watch creates nothing: if the directory is removed or renamed away (an uninstall, `rm -rf`), the file is reported as missing and the watch follows the nearest existing ancestor until the directory comes back, then watches it again. If it cannot watch again it logs a warning and ends.
- A panic in the callback is logged and the watch goes on (only with `panic = "unwind"`, the default).
- The callback runs on the watch thread, not the UI thread, and **must hand work off without blocking**: post with a non-blocking `queue` (see [task](task.md)), never a call that waits for the UI thread.
- Dropping the `SettingsWatcher` stops the watch. It waits up to 1 second for the watch thread. If a callback is still running then, the drop gives up with a logged warning and leaves the thread to end by itself, so a drop cannot hang the UI. A callback that has not started is not started, but one already past the stop check when the drop began can still start. Everything the callback captures must therefore stay valid until it returns (no raw pointers, no unprotected references to what the dropper frees), and a `queue` to a QObject must cope with a target that is gone. Dropping it from inside its own callback does not wait.
- A file that is unreadable when `watch` starts counts as unknown: the first successful read is reported.
- Errors: `NotFound` with no home directory; the OS error when inotify has no instances or watches left, or the directory cannot be read.

| Item | Description |
|---|---|
| `fn watch<F: FnMut(&Snapshot) + Send + 'static>(&self, on_change: F) -> io::Result<SettingsWatcher>` | Starts the watch |
| `struct SettingsWatcher` | Keeps the watch alive; stops it on drop |
| `struct Snapshot` | The file read once: `exists() -> bool`, `get(group, key) -> Option<String>`, `get_bool(group, key) -> Option<bool>` (`Debug, Clone, PartialEq, Eq`) |
| `DEBOUNCE` | `pub const Duration`, 200 ms |

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
