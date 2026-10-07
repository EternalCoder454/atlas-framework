---
title: How it fits together
summary: How the template starts: app! in lib.rs, main.cpp, the Rust Backend QObject, Main.qml, the Telamon.Ui version check, notifications, settings and threads.
order: 30
---

## Startup

`src/lib.rs` names the app once with `telamon_framework_ui::app!` (name, app ID, repository and the oldest Telamon.Ui) and exports `telamon_backend_new()`, which hands the Rust `Backend` QObject to the QML engine.

```rust
telamon_framework_ui::app! {
    name: "Telamon App",
    id: "net.eterneon.telamon.apptemplate",
    repo: "telamon-framework",
    ui: "2.0.0",
}
```

`main.cpp` is the only C++, one call to `telamon_app_run` (declared in telamon-framework-ui's `include/telamon/app.h`):

```cpp
extern "C" int telamon_app_run(int argc, char *argv[], const char *qmlModule, const char *qmlType, void *(*makeBackend)());
extern "C" void *telamon_backend_new();

int main(int argc, char *argv[])
{
    return telamon_app_run(argc, argv, "net.eterneon.telamon.apptemplate", "Main", telamon_backend_new);
}
```

`telamon_app_run` sets up Qt and the app ID, keeps one instance per session (a second launch raises the window), starts logging and crash hooks, and loads `Main` from the QML module. CMake links `KF6::DBusAddons` and `KF6::WindowSystem` for that startup code, because Corrosion does not pass a crate's native libraries on. See [telamon-framework-ui](../telamon-framework-ui/index.md).

## The Telamon.Ui version check

`ui: "2.0.0"` is the oldest Telamon.Ui the app works with. At startup, before any of the app's QML, the framework asks the installed Telamon.Ui (`TelamonApp.uiVersion`). If it is older, or missing, the app shows a plain window saying which version it needs and exits with code 1. Raise it when the app starts using something newer, and keep it equal to the RPM's `Requires: telamon-ui >=`. Leave `ui:` out and nothing is checked. C++ apps without `app!` call `telamon_app_require_ui("1.3.0")`.

## The Backend QObject

`src/backend.rs` defines `Backend` with CXX-Qt: a `#[qobject]` with the properties `status` and `busy`, and the invokables `refresh` and `sendNotification`. `impl cxx_qt::Threading for Backend` lets worker threads post closures back to the Qt thread. Slow work runs on a thread and posts back with `qt_thread().queue(..)`; never block the GUI thread.

In QML the backend is `required property var backend` in `qml/Main.qml`, which `telamon_app_run` sets.

## The QML

`qml/Main.qml` is a [TelamonWindow](../telamon-ui/telamon-window.md), blurred or opaque by the shared transparency switch, with a `StackView` that shows `MainPage` and pushes a [TelamonAboutPage](../telamon-ui/telamon-about-page.md) from the About button. `TelamonApp` (name, version, OS, links) feeds the About page and the window title. `qml/MainPage.qml` is a [TelamonPage](../telamon-ui/telamon-page.md) of [StatusHero](../telamon-ui/status-hero.md), [Section](../telamon-ui/section.md)s, charts, a [DataTable](../telamon-ui/data-table.md), a [TabBar](../telamon-ui/tab-bar.md), banners and a status bar. Its timers run only while the window is shown.

## Notifications

`telamon_framework_system::notify` (feature `notify`) sends notifications the way KNotification does, so Plasma groups them under the app and its notification settings apply. The "Send a Notification" button calls `sendNotification` in `src/backend.rs`, which sends the `demoAction` event from a worker thread. The events are declared in `data/telamon-apptemplate.notifyrc`, installed to `share/knotifications6/`, and every event ID you send needs an `[Event/<id>]` there (camelCase, letters and digits).

Notify only when the user can act on it: popups only, no sounds, persistent only when ignoring it has consequences, actions that are short verbs which open the right page, and no notifications from a root service. See [telamon-framework-system](../telamon-framework-system/index.md).

## Settings and logging

`telamon_framework_ui::telamon_framework_core::settings::Settings::for_app` reads and writes `~/.config/telamon-<app>rc`. The `log` crate's macros (add `log = "0.4"`) go to the journal: `journalctl -t telamon-<app>`. See [telamon-framework-core](../telamon-framework-core/index.md).

## Rules the template follows

The system Plasma theme and no hard-coded colours, Telamon.Ui's controls rather than Qt Quick Controls' or Kirigami's buttons, and `TelamonWindow` for the window. See [Design rules](../telamon-ui/design-rules.md).
