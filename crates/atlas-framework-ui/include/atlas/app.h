// Starting an Atlas app. The app's Rust library names the app once, with
// atlas_framework_ui::app!, and its main.cpp calls one of these.
//
// A window and nothing else (most apps):
//
//     int main(int argc, char *argv[])
//     {
//         return atlas_app_run(argc, argv, "net.eterneon.atlas.notepad", "Main", atlas_backend_new);
//     }
//
// An app with its own shell (a tray icon, its own single-instance rules):
//
//     atlas_app_init();
//     QApplication app(argc, argv);
//     atlas_app_ready();
//     ... its own KDBusService and windows ...
//
// AtlasApp (Atlas.Ui) reads the app's names once, when QML first uses it:
// call atlas_app_ready before loading any QML.
//
// The Atlas.Ui version the app needs: name it in the Rust `app!` (a trailing
// `ui: "1.3.0"`), or call atlas_app_require_ui before atlas_app_ready. Then
// atlas_app_ready checks the installed Atlas.Ui before any QML loads. With no
// version named it checks nothing, at no cost.
//
// The check reads Atlas.Ui through the default QML import paths of a fresh
// engine (the installed module, plus QML_IMPORT_PATH and QML2_IMPORT_PATH),
// the same ones the app's own QML uses. `app!` is the only supported way to
// define the app's info: the C++ side reads it from the Rust library.
//
// A CMake app that doesn't get this header from the crate can declare the
// functions itself: they have C linkage and only plain types.
#pragma once

extern "C" {

// Before QApplication: the journal logger, the Rust crash hook and the fatal
// Qt message hook (a crash report when the user turned reports on), the
// app's names (the app ID becomes the single-instance D-Bus name and the
// desktop file name), and the org.kde.desktop style.
void atlas_app_init();

// After QApplication: the display name, the window icon, and what Atlas.Ui's
// AtlasApp shows.
void atlas_app_ready();

// Optional, before atlas_app_ready (or atlas_app_run, which calls it first):
// the oldest Atlas.Ui the app works with, as "major.minor.patch" ("1.3.0").
// It overrides the `ui:` of the app's `app!`; null or "" removes the
// requirement. atlas_app_ready then loads a tiny QML component that reads
// AtlasApp.uiVersion. (atlas_app_run does this after the single-instance
// registration, so a second launch that only raises the window skips it.)
// If Atlas.Ui cannot be loaded (the window says "could not be loaded" and
// gives the first line of the error), is older than asked, or
// is older than 1.3.0 (which has no uiVersion to answer with), it logs why,
// shows a plain window (no Atlas.Ui in it) saying which version is needed,
// which is installed and how to fix it, and exits with code 1 once the
// window is closed. On the offscreen and minimal Qt platforms there is no
// one to read it: it logs and exits at once. A string that isn't a version
// is logged and ignored.
void atlas_app_require_ui(const char *minVersion);

// Everything: atlas_app_init, QApplication, atlas_app_ready, one instance per
// session (a second launch raises the first window and exits, dropping its
// arguments: an app that opens files uses init/ready and its own
// KDBusService; with no session bus each launch runs), and the QML type
// `qmlType` of module `qmlModule` as the window. `makeBackend` (may be null)
// is called once QApplication exists; the QObject it returns is the window's
// `backend` property, and is deleted after the event loop ends. Returns the
// exit code.
int atlas_app_run(int argc, char *argv[], const char *qmlModule, const char *qmlType, void *(*makeBackend)());
}
