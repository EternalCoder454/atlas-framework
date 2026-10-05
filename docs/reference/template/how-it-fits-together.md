---
title: How it fits together
summary: How the template starts: app! in lib.rs, main.cpp, the Rust Backend QObject, Main.qml, the Atlas.Ui version check, notifications, settings and threads.
order: 30
---

## Startup

`src/lib.rs` names the app once with `atlas_framework_ui::app!` (name, app ID, repository and the oldest Atlas.Ui) and exports `atlas_backend_new()`, which hands the Rust `Backend` QObject to the QML engine.

```rust
atlas_framework_ui::app! {
    name: "Atlas App",
    id: "net.eterneon.atlas.apptemplate",
    repo: "atlas-framework",
    ui: "1.3.0",
}
```

`main.cpp` is the only C++, one call to `atlas_app_run` (declared in atlas-framework-ui's `include/atlas/app.h`):

```cpp
extern "C" int atlas_app_run(int argc, char *argv[], const char *qmlModule, const char *qmlType, void *(*makeBackend)());
extern "C" void *atlas_backend_new();

int main(int argc, char *argv[])
{
    return atlas_app_run(argc, argv, "net.eterneon.atlas.apptemplate", "Main", atlas_backend_new);
}
```

`atlas_app_run` sets up Qt and the app ID, keeps one instance per session (a second launch raises the window), starts logging and crash hooks, and loads `Main` from the QML module. CMake links `KF6::DBusAddons` and `KF6::WindowSystem` for that startup code, because Corrosion does not pass a crate's native libraries on. See [atlas-framework-ui](../atlas-framework-ui/index.md).

## The Atlas.Ui version check

`ui: "1.3.0"` is the oldest Atlas.Ui the app works with. At startup, before any of the app's QML, the framework asks the installed Atlas.Ui (`AtlasApp.uiVersion`). If it is older, or missing, the app shows a plain window saying which version it needs and exits with code 1. Raise it when the app starts using something newer, and keep it equal to the RPM's `Requires: atlas-ui >=`. Leave `ui:` out and nothing is checked. C++ apps without `app!` call `atlas_app_require_ui("1.3.0")`.

## The Backend QObject

`src/backend.rs` defines `Backend` with CXX-Qt: a `#[qobject]` with the properties `status` and `busy`, and the invokables `refresh` and `sendNotification`. `impl cxx_qt::Threading for Backend` lets worker threads post closures back to the Qt thread. Slow work runs on a thread and posts back with `qt_thread().queue(..)`; never block the GUI thread.

In QML the backend is `required property var backend` in `qml/Main.qml`, which `atlas_app_run` sets.

## The QML

`qml/Main.qml` is an [AtlasWindow](../atlas-ui/atlas-window.md), blurred or opaque by the shared transparency switch, with a `StackView` that shows `MainPage` and pushes an [AtlasAboutPage](../atlas-ui/atlas-about-page.md) from the About button. `AtlasApp` (name, version, OS, links) feeds the About page and the window title. `qml/MainPage.qml` is an [AtlasPage](../atlas-ui/atlas-page.md) of [StatusHero](../atlas-ui/status-hero.md), [Section](../atlas-ui/section.md)s, charts, a [DataTable](../atlas-ui/data-table.md), a [TabBar](../atlas-ui/tab-bar.md), banners and a status bar. Its timers run only while the window is shown.

## Notifications

`atlas_framework_system::notify` (feature `notify`) sends notifications the way KNotification does, so Plasma groups them under the app and its notification settings apply. The "Send a Notification" button calls `sendNotification` in `src/backend.rs`, which sends the `demoAction` event from a worker thread. The events are declared in `data/atlas-apptemplate.notifyrc`, installed to `share/knotifications6/`, and every event ID you send needs an `[Event/<id>]` there (camelCase, letters and digits).

Notify only when the user can act on it: popups only, no sounds, persistent only when ignoring it has consequences, actions that are short verbs which open the right page, and no notifications from a root service. See [atlas-framework-system](../atlas-framework-system/index.md).

## Settings and logging

`atlas_framework_ui::atlas_framework_core::settings::Settings::for_app` reads and writes `~/.config/atlas-<app>rc`. The `log` crate's macros (add `log = "0.4"`) go to the journal: `journalctl -t atlas-<app>`. See [atlas-framework-core](../atlas-framework-core/index.md).

## Rules the template follows

The system Plasma theme and no hard-coded colours, Atlas.Ui's controls rather than Qt Quick Controls' or Kirigami's buttons, and `AtlasWindow` for the window. See [Design rules](../atlas-ui/design-rules.md).
