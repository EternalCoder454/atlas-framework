---
title: app!
summary: The macro that names a Telamon app once, with its name, ID, repository and optionally the oldest Telamon.Ui it works with.
order: 10
---

`telamon_framework_ui::app!` names the app for the framework. It defines the functions the C++ start-up calls to learn who the app is. Use it once, in the app's Rust library. It is the only supported way to define the app info: the C++ side reads it from the Rust library.

## Example

```rust
telamon_framework_ui::app! {
    name: "Telamon Notepad",
    id: "net.eterneon.telamon.notepad",
    repo: "atlasos-notepad",
}
```

An app that needs a newer Telamon.Ui than the first release names it with a trailing `ui:`:

```rust
telamon_framework_ui::app! {
    name: "Telamon Notepad",
    id: "net.eterneon.telamon.notepad",
    repo: "atlasos-notepad",
    ui: "2.0.0",
}
```

## Fields

The fields are in this order, and a trailing comma is allowed. `ui:` and `crash:` are optional.

| Field | Type | Description |
|---|---|---|
| `name` | expression convertible to `String` | The name people see, such as `Telamon Notepad`. Becomes the application display name and `AppInfo.name` |
| `id` | expression | The reverse-DNS app ID. It is the desktop file name, the window icon name, the single-instance D-Bus name and the base of the settings file and journal names. See [AppInfo](../telamon-framework-core/app-info.md) |
| `repo` | expression | The repository under `github.com/EternalCoder454/`. Telamon.Ui's About page builds its links from it |
| `ui` | string literal or constant expression | The oldest Telamon.Ui the app works with, as `major.minor.patch` (fewer parts are allowed). Optional |
| `crash` | `bool` expression | `false` keeps the app out of Telamon crash reporting altogether; `true` (the default) lets the user's own switch decide. Optional, after `ui:`. See [Keeping an app out of crash reports](#keeping-an-app-out-of-crash-reports) |

The version in `AppInfo.version` is not a field: it is the `CARGO_PKG_VERSION` of the crate that uses the macro.

## The `ui:` version check

`ui:` is the oldest Telamon.Ui the app works with.

- At build time, a `ui:` that is not plain numbers separated by dots (at most three parts, each at most six digits) fails to compile with "ui: must be a version like \"1.3.0\"". Examples that pass: `"1"`, `"1.3"`, `"1.3.0"`. Examples that fail: `""`, `"1.3.0-dev"`, `"v1"`, `"1.2.3.4"`.
- At startup, before any of the app's QML loads, the installed Telamon.Ui is asked for `TelamonApp.uiVersion` (the time it takes is logged with `QT_LOGGING_RULES=telamon.ui.debug=true`) and compared with the numbers, missing parts counting as 0 (`1.3` equals `1.3.0`, and `1.10` is above `1.9`).
- When the installed Telamon.Ui is older, does not report a version (no `uiVersion`), or cannot be loaded, the app logs why, shows a plain window with no Telamon.Ui in it (which version is needed, which is installed, how to fix it) and exits with code 1 once the window is closed. On the offscreen and minimal Qt platforms it logs and exits at once.
- Without `ui:` nothing is checked and nothing is paid.
- Keep `ui:` equal to the RPM's `Requires: telamon-ui >=`.
- `telamon_app_run` runs the check after the single-instance registration, so a second launch that only raises the window skips it. A C++ call to [`telamon_app_require_ui`](c-api.md#telamon_app_require_ui) with a version overrides `ui:`.

## Keeping an app out of crash reports

```rust
telamon_framework_ui::app! {
    name: "Pong",
    id: "net.example.pong",
    repo: "pong",
    crash: false,
}
```

An app that is not part of Telamon OS must never feed the Telamon crash relay, even when the user enabled crash reporting for Telamon apps. With `crash: false` the start installs no panic hook ([`crash::install`](../telamon-framework-system/crash.md) is not called) and a fatal Qt message is logged but never saved ([`record_fatal`](../telamon-framework-system/crash.md) is not called). Logging, the settings file and everything else in the start are unchanged. Without the field, or with `crash: true`, nothing changes for the app: it reports only when the user turned reports on.

A C++ app can decide at run time with [`telamon_app_set_crash_reporting`](c-api.md#functions) before `telamon_app_init`; that call overrides `crash:`. `telamon_framework_ui::crash_reporting()` tells which applies (see [Startup behaviour](startup.md)).

## Generated items

The macro defines three `#[no_mangle]` functions, `telamon_framework_ui_app_info`, `telamon_framework_ui_required_ui` and `telamon_framework_ui_crash_reporting`, which the crate calls. They are not part of the API: do not call or define them yourself. The macro also uses the hidden `ui_version_ok` function for the compile-time check.
