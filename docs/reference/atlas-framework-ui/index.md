---
title: atlas-framework-ui
summary: The Rust crate that starts every Atlas GUI app, with the app! macro, the C functions main.cpp calls, one instance per session, journal logging, crash hooks and the Atlas.Ui version check.
order: 4
---

`atlas-framework-ui` starts an Atlas app so the app's own code is only what makes it different. The app's Rust library names the app once with [`app!`](app-macro.md), and its `main.cpp` makes one call into the [C API](c-api.md). Every Atlas app then starts the same way: the app ID as the desktop file name and single-instance D-Bus name, the org.kde.desktop style, [logs in the journal, crash hooks and one instance per session](startup.md), and the names that [AtlasApp](../atlas-ui/atlas-app.md) and [AtlasAboutPage](../atlas-ui/atlas-about-page.md) show.

Every GUI app needs it. The look itself is not here: it is the installed [Atlas.Ui](../atlas-ui/index.md) QML module.

## Add it

```toml
atlas-framework-ui = { git = "https://github.com/EternalCoder454/atlas-framework", rev = "7a114a112bd1fff4fe3d6facc81b0a81e5d2db30" }
```

The commit is the one tagged `v1.4.0`. Pin apps to a commit or a release tag and build with `cargo build --locked`. Add [atlas-framework-system](../atlas-framework-system/index.md) or [atlas-framework-flatpak](../atlas-framework-flatpak/index.md) separately only if the app needs them.

The crate builds C++ through CXX-Qt (`cxx-qt-build`, Qt modules Gui, Widgets, Qml, Quick, QuickControls2 and DBus) and links `KF6DBusAddons` and `KF6WindowSystem`. KF6 ships no pkg-config files, so its headers are taken from `/usr/include/KF6`, or from the directory in the `ATLAS_KF6_INCLUDEDIR` environment variable. Corrosion does not pass a crate's native libraries on to the executable, so a CMake app also links `KF6::DBusAddons` and `KF6::WindowSystem` itself (the app template shows it).

## Features

None. The crate depends on atlas-framework-core and atlas-framework-system (without its `polkit` and `notify` features), `log` and `libc`.

## Pages

| Page | What it covers |
|---|---|
| [app!](app-macro.md) | The macro that names the app, every field, and the `ui:` version check |
| [The C API](c-api.md) | `atlas_app_run`, `atlas_app_init`, `atlas_app_ready`, `atlas_app_require_ui` |
| [Startup behaviour](startup.md) | Single instance, activation token, logging, panic and Qt message hooks |

## Crate root

| Name | Kind | Description |
|---|---|---|
| `app!` | macro | Names the app. Use it once in the app's library |
| `AppInfo` | re-export | `atlas_framework_core::AppInfo` |
| `atlas_framework_core` | re-export | The whole core crate |
| `atlas_framework_system` | re-export | The whole system crate (without the optional features) |
| `fn app_info() -> &'static AppInfo` | function | The app, as its `app!` named it |
| `fn required_ui() -> Option<&'static str>` | function | The Atlas.Ui version the app's `app!` asks for (`ui:`), if any |
| `fn start()` | function | Installs the logger and the crash hook. Only the first call does anything |
