---
title: app!
summary: The macro that names an Atlas app once, with its name, ID, repository and optionally the oldest Atlas.Ui it works with.
order: 10
---

`atlas_framework_ui::app!` names the app for the framework. It defines the two functions the C++ start-up calls to learn who the app is. Use it once, in the app's Rust library. It is the only supported way to define the app info: the C++ side reads it from the Rust library.

## Example

```rust
atlas_framework_ui::app! {
    name: "Atlas Notepad",
    id: "net.eterneon.atlas.notepad",
    repo: "atlasos-notepad",
}
```

An app that needs a newer Atlas.Ui than the first release names it with a trailing `ui:`:

```rust
atlas_framework_ui::app! {
    name: "Atlas Notepad",
    id: "net.eterneon.atlas.notepad",
    repo: "atlasos-notepad",
    ui: "1.3.0",
}
```

## Fields

The fields are in this order, and a trailing comma is allowed. `ui:` is the only optional one.

| Field | Type | Description |
|---|---|---|
| `name` | expression convertible to `String` | The name people see, such as `Atlas Notepad`. Becomes the application display name and `AppInfo.name` |
| `id` | expression | The reverse-DNS app ID. It is the desktop file name, the window icon name, the single-instance D-Bus name and the base of the settings file and journal names. See [AppInfo](../atlas-framework-core/app-info.md) |
| `repo` | expression | The repository under `github.com/EternalCoder454/`. Atlas.Ui's About page builds its links from it |
| `ui` | string literal or constant expression | The oldest Atlas.Ui the app works with, as `major.minor.patch` (fewer parts are allowed). Optional |

The version in `AppInfo.version` is not a field: it is the `CARGO_PKG_VERSION` of the crate that uses the macro.

## The `ui:` version check

`ui:` is the oldest Atlas.Ui the app works with.

- At build time, a `ui:` that is not plain numbers separated by dots (at most three parts, each at most six digits) fails to compile with "ui: must be a version like \"1.3.0\"". Examples that pass: `"1"`, `"1.3"`, `"1.3.0"`. Examples that fail: `""`, `"1.3.0-dev"`, `"v1"`, `"1.2.3.4"`.
- At startup, before any of the app's QML loads, the installed Atlas.Ui is asked for `AtlasApp.uiVersion` (the time it takes is logged with `QT_LOGGING_RULES=atlas.ui.debug=true`) and compared with the numbers, missing parts counting as 0 (`1.3` equals `1.3.0`, and `1.10` is above `1.9`).
- When the installed Atlas.Ui is older, is older than 1.3.0 (which has no `uiVersion`), or cannot be loaded, the app logs why, shows a plain window with no Atlas.Ui in it (which version is needed, which is installed, how to fix it) and exits with code 1 once the window is closed. On the offscreen and minimal Qt platforms it logs and exits at once.
- Without `ui:` nothing is checked and nothing is paid.
- Keep `ui:` equal to the RPM's `Requires: atlas-ui >=`.
- `atlas_app_run` runs the check after the single-instance registration, so a second launch that only raises the window skips it. A C++ call to [`atlas_app_require_ui`](c-api.md#atlas_app_require_ui) with a version overrides `ui:`.

## Generated items

The macro defines two `#[no_mangle]` functions, `atlas_framework_ui_app_info` and `atlas_framework_ui_required_ui`, which the crate calls. They are not part of the API: do not call or define them yourself. The macro also uses the hidden `ui_version_ok` function for the compile-time check.
