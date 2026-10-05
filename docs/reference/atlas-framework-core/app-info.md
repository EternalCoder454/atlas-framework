---
title: AppInfo and app_info!
summary: The value that names the running app, from which its settings file, journal identifier, crash reports and links are derived.
order: 10
---

`AppInfo` says who the running app is. One value names the settings file, the journal entries, the crash reports and the About links. Build it with `app_info!`, which takes the version from the calling crate's own `Cargo.toml`.

A GUI app does not usually build one itself: the [`app!`](../atlas-framework-ui/app-macro.md) macro of atlas-framework-ui does, and `atlas_framework_ui::app_info()` returns it.

## Example

```rust
use atlas_framework_core::app_info;

let app = app_info! {
    name: "Atlas Notepad",
    id: "net.eterneon.atlas.notepad",
    repo: "atlasos-notepad",
};
assert_eq!(app.short_name(), "atlas-notepad");
assert_eq!(
    app.issues_url().as_deref(),
    Some("https://github.com/EternalCoder454/atlasos-notepad/issues")
);
```

## AppInfo

`#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]`

| Field | Type | Description |
|---|---|---|
| `name` | `String` | The name people see, such as `Atlas Updater` |
| `id` | `String` | Reverse-DNS app ID, such as `net.eterneon.atlas.updater`. It is also the desktop file name, the icon name and the single-instance D-Bus name |
| `version` | `String` | The app's version |
| `repo` | `String` | Repository under `github.com/EternalCoder454/`, such as `atlasos-updater` |

## Methods

| Method | Description |
|---|---|
| `fn short_name(&self) -> String` | `atlas-` plus the last part of the ID (without an `atlas-` of its own), for example `atlas-updater` for `net.eterneon.atlas.updater`. Names the settings file (`atlas-updaterrc`) and the journal identifier. Characters outside `[a-z0-9_-]` become `_` (capitals are lowercased), and the result is at most 64 characters, so it is always a safe file name. An empty ID gives `atlas-app` |
| `fn source_url(&self) -> Option<String>` | `https://github.com/EternalCoder454/<repo>`, or `None` when `repo` is not a plain repository name (empty, `.`, `..`, or characters other than letters, digits, `.`, `_`, `-`), so a bad value cannot point a link elsewhere |
| `fn issues_url(&self) -> Option<String>` | `source_url()` plus `/issues`, where people report problems |

## app_info!

```rust
use atlas_framework_core::app_info;

let app = app_info! { name: "Atlas Notepad", id: "net.eterneon.atlas.notepad", repo: "atlasos-notepad" }; // a trailing comma is allowed
```

Expands to an `AppInfo` whose `name`, `id` and `repo` come from the expressions and whose `version` is `env!("CARGO_PKG_VERSION")` of the crate that calls the macro. The three fields are required and must be in that order.
