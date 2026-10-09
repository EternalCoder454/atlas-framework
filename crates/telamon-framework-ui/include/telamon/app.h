// Starting a Telamon app. The app's Rust library names the app once, with
// telamon_framework_ui::app!, and its main.cpp calls one of these.
//
// A window and nothing else (most apps):
//
//     int main(int argc, char *argv[])
//     {
//         return telamon_app_run(argc, argv, "net.eterneon.telamon.notepad", "Main", telamon_backend_new);
//     }
//
// An app with its own shell (a tray icon, its own single-instance rules):
//
//     telamon_app_init();
//     QApplication app(argc, argv);
//     telamon_app_ready();
//     ... its own KDBusService and windows ...
//
// TelamonApp (Telamon.Ui) reads the app's names once, when QML first uses it:
// call telamon_app_ready before loading any QML.
//
// The Telamon.Ui version the app needs: name it in the Rust `app!` (a trailing
// `ui: "2.0.0"`), or call telamon_app_require_ui before telamon_app_ready. Then
// telamon_app_ready checks the installed Telamon.Ui before any QML loads. With no
// version named it checks nothing, at no cost.
//
// The check reads Telamon.Ui through the default QML import paths of a fresh
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
// Calling it again does nothing, so telamon_app_run after your own call is safe.
void telamon_app_init();

// Optional, before telamon_app_init (or telamon_app_run, which calls it): keep
// the app out of Telamon crash reporting (false), or into it (true), over the
// `crash:` of the app's `app!` (on by default). Off means no panic hook and no
// report for a fatal Qt message, whatever the user chose for Telamon apps;
// logging, settings and the rest of the start are unchanged. For an app that is
// not part of Telamon OS and must never feed its crash relay. After
// telamon_app_init the call is logged and ignored (the hook is in place).
void telamon_app_set_crash_reporting(bool enabled);

// After QApplication: the display name, the window icon, and what Telamon.Ui's
// TelamonApp shows.
void telamon_app_ready();

// Optional, before telamon_app_ready (or telamon_app_run, which calls it first):
// the oldest Telamon.Ui the app works with, as "major.minor.patch" ("2.0.0").
// A version overrides the `ui:` of the app's `app!`; null or "" clears an
// earlier call, so the `ui:` of `app!` applies again. telamon_app_ready then
// loads a tiny QML component that reads TelamonApp.uiVersion. (telamon_app_run
// does this after the single-instance registration, so a second launch that
// only raises the window skips it.)
// If Telamon.Ui cannot be loaded (the window says "could not be loaded" and
// gives the first line of the error), is older than asked, or
// does not report a version (no uiVersion to answer with), it logs why,
// shows a plain window (no Telamon.Ui in it) saying which version is needed,
// which is installed and how to fix it, and exits with code 1 once the
// window is closed (or after five minutes, or when it cannot be drawn). On the offscreen and minimal Qt platforms there is no
// one to read it: it logs and exits at once. A string that isn't a version
// is logged and ignored.
void telamon_app_require_ui(const char *minVersion);

// Everything: telamon_app_init, QApplication, telamon_app_ready, one instance per
// session (a second launch raises the first window and exits, dropping its
// arguments: an app that opens files uses init/ready and its own
// KDBusService; with no session bus each launch runs), and the QML type
// `qmlType` of module `qmlModule` as the window. `makeBackend` (may be null)
// is called once QApplication exists; the QObject it returns is the window's
// `backend` property, and is deleted after the event loop ends. Returns the
// exit code.
int telamon_app_run(int argc, char *argv[], const char *qmlModule, const char *qmlType, void *(*makeBackend)());
}
