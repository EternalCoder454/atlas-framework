---
title: The C API
summary: The C functions in include/telamon/app.h that an app's main.cpp calls to start, with telamon_app_run for most apps and telamon_app_init and telamon_app_ready for apps with their own shell.
order: 20
---

`include/telamon/app.h` in the crate declares the functions an app's `main.cpp` calls. They have C linkage and use only plain types, so a CMake app that does not get the header from the crate can declare them itself. They read the app's names from the library that used [`app!`](app-macro.md).

## Most apps: a window and nothing else

```cpp
#include <telamon/app.h>

extern "C" void *telamon_backend_new(); // the app's backend factory, may be omitted

int main(int argc, char *argv[])
{
    return telamon_app_run(argc, argv, "net.eterneon.telamon.notepad", "Main", telamon_backend_new);
}
```

## An app with its own shell

For a tray icon or its own single-instance rules, call init and ready around `QApplication`:

```cpp
telamon_app_init();
QApplication app(argc, argv);
telamon_app_ready();
// ... its own KDBusService and windows ...
```

`TelamonApp` (Telamon.Ui) reads the app's names once, when QML first uses it, so call `telamon_app_ready` before loading any QML.

## Functions

| Function | When | What it does |
|---|---|---|
| `void telamon_app_init()` | Before `QApplication` | Starts the journal logger, the Rust crash hook and the fatal Qt message hook (a crash report when the user turned reports on). Sets the app's names: the organization domain and application name are derived from the app ID so that KDBusService registers the app ID itself as the single-instance D-Bus name, the version, and the desktop file name. Sets the `org.kde.desktop` Qt Quick Controls style unless `QT_QUICK_CONTROLS_STYLE` is set. Calling it again does nothing, so `telamon_app_run` after your own call is safe |
| `void telamon_app_ready()` | After `QApplication` | Sets the display name and the window icon (the icon named by the app ID from the icon theme), and stores the repository where Telamon.Ui's `TelamonApp` reads it. Then runs the Telamon.Ui version check, last, before any QML |
| `void telamon_app_require_ui(const char *minVersion)` | Optional, before `telamon_app_ready` (or `telamon_app_run`) | The oldest Telamon.Ui the app works with, as `"major.minor.patch"`. Overrides `ui:` of `app!` when it is a version. Null or `""` clears an earlier call, so the `ui:` of `app!` applies again (no check only when `app!` has no `ui:`). A string that is not a version is logged and ignored |
| `int telamon_app_run(int argc, char *argv[], const char *qmlModule, const char *qmlType, void *(*makeBackend)())` | `main` | Does everything: init, `QApplication`, ready, one instance per session, the Telamon.Ui check, the backend, the QML window, and the event loop. Returns the exit code |

## telamon_app_require_ui

When a version is set (here or by `ui:`), `telamon_app_ready` loads a tiny QML component that reads `TelamonApp.uiVersion`, through the default QML import paths of a fresh engine: the installed module plus `QML_IMPORT_PATH` and `QML2_IMPORT_PATH`, the same paths the app's own QML uses. If Telamon.Ui cannot be loaded (the window says "could not be loaded" and gives the first line of the error), is older than asked, or is older than 1.3.0, it logs why, shows a plain window saying which version is needed, which is installed and how to fix it, and exits with code 1 once the window is closed. See [app!](app-macro.md#the-ui-version-check).

`telamon_app_run` calls the check after the single-instance registration, so a second launch that only raises the window skips it.

## telamon_app_run in detail

- `qmlModule` and `qmlType` name the QML type used as the window: it is loaded with `QQmlApplicationEngine::loadFromModule(qmlModule, qmlType)`.
- `makeBackend` may be null. It is called once, after `QApplication` exists and after the version check. The `QObject` it returns is set as the window's `backend` initial property (declare `required property var backend` or a `backend` property on the root), is never owned by the QML engine, and is deleted after the event loop ends.
- If the QML fails to load, the app exits with code 1.
- One instance per session: see [Startup behaviour](startup.md#single-instance). A second launch drops its arguments, so an app that opens files uses `telamon_app_init` and `telamon_app_ready` with its own `KDBusService`.

## Linking

The crate exports its Qt init (`cxx_qt_init_crate_telamon_framework_ui`) through CXX-Qt. Corrosion does not pass the crate's native libraries to the executable, so the app's CMake links `KF6::DBusAddons` and `KF6::WindowSystem` itself; the app template shows it.
