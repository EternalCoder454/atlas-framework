---
title: The C API
summary: The C functions in include/atlas/app.h that an app's main.cpp calls to start, with atlas_app_run for most apps and atlas_app_init and atlas_app_ready for apps with their own shell.
order: 20
---

`include/atlas/app.h` in the crate declares the functions an app's `main.cpp` calls. They have C linkage and use only plain types, so a CMake app that does not get the header from the crate can declare them itself. They read the app's names from the library that used [`app!`](app-macro.md).

## Most apps: a window and nothing else

```cpp
#include <atlas/app.h>

extern "C" void *atlas_backend_new(); // the app's backend factory, may be omitted

int main(int argc, char *argv[])
{
    return atlas_app_run(argc, argv, "net.eterneon.atlas.notepad", "Main", atlas_backend_new);
}
```

## An app with its own shell

For a tray icon or its own single-instance rules, call init and ready around `QApplication`:

```cpp
atlas_app_init();
QApplication app(argc, argv);
atlas_app_ready();
// ... its own KDBusService and windows ...
```

`AtlasApp` (Atlas.Ui) reads the app's names once, when QML first uses it, so call `atlas_app_ready` before loading any QML.

## Functions

| Function | When | What it does |
|---|---|---|
| `void atlas_app_init()` | Before `QApplication` | Starts the journal logger, the Rust crash hook and the fatal Qt message hook (a crash report when the user turned reports on). Sets the app's names: the organization domain and application name are derived from the app ID so that KDBusService registers the app ID itself as the single-instance D-Bus name, the version, and the desktop file name. Sets the `org.kde.desktop` Qt Quick Controls style unless `QT_QUICK_CONTROLS_STYLE` is set |
| `void atlas_app_ready()` | After `QApplication` | Sets the display name and the window icon (the icon named by the app ID from the icon theme), and stores the repository where Atlas.Ui's `AtlasApp` reads it. Then runs the Atlas.Ui version check, last, before any QML |
| `void atlas_app_require_ui(const char *minVersion)` | Optional, before `atlas_app_ready` (or `atlas_app_run`) | The oldest Atlas.Ui the app works with, as `"major.minor.patch"`. Overrides `ui:` of `app!`. Null or `""` removes the requirement. A string that is not a version is logged and ignored |
| `int atlas_app_run(int argc, char *argv[], const char *qmlModule, const char *qmlType, void *(*makeBackend)())` | `main` | Does everything: init, `QApplication`, ready, one instance per session, the Atlas.Ui check, the backend, the QML window, and the event loop. Returns the exit code |

## atlas_app_require_ui

When a version is set (here or by `ui:`), `atlas_app_ready` loads a tiny QML component that reads `AtlasApp.uiVersion`, through the default QML import paths of a fresh engine: the installed module plus `QML_IMPORT_PATH` and `QML2_IMPORT_PATH`, the same paths the app's own QML uses. If Atlas.Ui cannot be loaded (the window says "could not be loaded" and gives the first line of the error), is older than asked, or is older than 1.3.0, it logs why, shows a plain window saying which version is needed, which is installed and how to fix it, and exits with code 1 once the window is closed. See [app!](app-macro.md#the-ui-version-check).

`atlas_app_run` calls the check after the single-instance registration, so a second launch that only raises the window skips it.

## atlas_app_run in detail

- `qmlModule` and `qmlType` name the QML type used as the window: it is loaded with `QQmlApplicationEngine::loadFromModule(qmlModule, qmlType)`.
- `makeBackend` may be null. It is called once, after `QApplication` exists and after the version check. The `QObject` it returns is set as the window's `backend` initial property (declare `required property var backend` or a `backend` property on the root), is never owned by the QML engine, and is deleted after the event loop ends.
- If the QML fails to load, the app exits with code 1.
- One instance per session: see [Startup behaviour](startup.md#single-instance). A second launch drops its arguments, so an app that opens files uses `atlas_app_init` and `atlas_app_ready` with its own `KDBusService`.

## Linking

The crate exports its Qt init (`cxx_qt_init_crate_atlas_framework_ui`) through CXX-Qt. Corrosion does not pass the crate's native libraries to the executable, so the app's CMake links `KF6::DBusAddons` and `KF6::WindowSystem` itself; the app template shows it.
