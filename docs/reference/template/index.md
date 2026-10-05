---
title: App template
summary: A minimal Atlas app to copy: a Kirigami window on Atlas.Ui, one Rust QObject exposed through CXX-Qt, built with CMake and Corrosion on the framework's crates.
order: 7
---

The app template (`template/` in the atlas-framework repository) is a minimal Atlas app: a QML interface compiled ahead of time by `qt_add_qml_module`, one Rust QObject exposed through CXX-Qt, built with CMake and Corrosion, on atlas-framework's Rust crates and the installed [Atlas.Ui](../atlas-ui/index.md). The framework starts the app (app ID, one instance per session, journal logging, crash hooks) and Atlas.Ui gives it the look and an About page. It builds on its own: the template is not part of the framework's Cargo workspace.

## What is in it

| File | What it is |
|---|---|
| `CMakeLists.txt` | Finds Qt 6.11, Corrosion and KF6, checks that Atlas.Ui is installed, builds the Rust crate and the executable, installs it. |
| `Cargo.toml`, `build.rs` | The Rust crate (a static library) and the CXX-Qt build step. |
| `main.cpp` | The only C++: one call to `atlas_app_run`. |
| `src/lib.rs` | Names the app with `atlas_framework_ui::app!` and exports `atlas_backend_new()`. |
| `src/backend.rs` | The `Backend` QObject: properties, invokables, a worker thread, a notification. |
| `qml/Main.qml`, `qml/MainPage.qml` | The window, and a page that shows many Atlas.Ui controls. |
| `data/` | The desktop file and `atlas-apptemplate.notifyrc`, the notification events. |

## Pages

- [Start a new app](start-a-new-app.md): copy it and rename it.
- [Build and run](build.md): packages, CMake, running headless.
- [How it fits together](how-it-fits-together.md): startup, the backend, QML, notifications, settings.
