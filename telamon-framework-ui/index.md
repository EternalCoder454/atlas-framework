---
title: telamon-framework-ui
summary: The Rust crate that starts every Telamon GUI app, with the app! macro, the C functions main.cpp calls, one instance per session, journal logging, crash hooks and the Telamon.Ui version check.
order: 4
---

`telamon-framework-ui` starts a Telamon app so the app's own code is only what makes it different. The app's Rust library names the app once with [`app!`](app-macro.md), and its `main.cpp` makes one call into the [C API](c-api.md). Every Telamon app then starts the same way: the app ID as the desktop file name and single-instance D-Bus name, the org.kde.desktop style, [logs in the journal, crash hooks and one instance per session](startup.md), and the names that [TelamonApp](../telamon-ui/telamon-app.md) and [TelamonAboutPage](../telamon-ui/telamon-about-page.md) show.

Every GUI app needs it. The look itself is not here: it is the installed [Telamon.Ui](../telamon-ui/index.md) QML module.

## Add it

```toml
telamon-framework-ui = { git = "https://github.com/EternalCoder454/atlas-framework", tag = "v2.0.0" }
```

The commit is the one tagged `v1.4.0`. Pin apps to a commit or a release tag and build with `cargo build --locked`. Add [telamon-framework-system](../telamon-framework-system/index.md) or [telamon-framework-flatpak](../telamon-framework-flatpak/index.md) separately only if the app needs them.

The crate builds C++ through CXX-Qt (`cxx-qt-build`, Qt modules Gui, Widgets, Qml, Quick, QuickControls2 and DBus) and links `KF6DBusAddons` and `KF6WindowSystem`. KF6 ships no pkg-config files, so its headers are taken from `/usr/include/KF6`, or from the directory in the `TELAMON_KF6_INCLUDEDIR` environment variable. Corrosion does not pass a crate's native libraries on to the executable, so a CMake app also links `KF6::DBusAddons` and `KF6::WindowSystem` itself (the app template shows it).

## Features

None. The crate depends on telamon-framework-core and telamon-framework-system (without its `polkit` and `notify` features), `log` and `libc`.

## Pages

| Page | What it covers |
|---|---|
| [app!](app-macro.md) | The macro that names the app, every field, and the `ui:` version check |
| [The C API](c-api.md) | `telamon_app_run`, `telamon_app_init`, `telamon_app_ready`, `telamon_app_require_ui` |
| [Startup behaviour](startup.md) | Single instance, activation token, logging, panic and Qt message hooks |

## Crate root

| Name | Kind | Description |
|---|---|---|
| `app!` | macro | Names the app. Use it once in the app's library |
| `AppInfo` | re-export | `telamon_framework_core::AppInfo` |
| `telamon_framework_core` | re-export | The whole core crate |
| `telamon_framework_system` | re-export | The whole system crate (without the optional features) |
| `fn app_info() -> &'static AppInfo` | function | The app, as its `app!` named it |
| `fn required_ui() -> Option<&'static str>` | function | The Telamon.Ui version the app's `app!` asks for (`ui:`), if any |
| `fn start()` | function | Installs the logger and the crash hook. Only the first call does anything |
