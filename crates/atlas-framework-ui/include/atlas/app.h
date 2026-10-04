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
// A CMake app that doesn't get this header from the crate can declare the
// three functions itself: they have C linkage and only plain types.
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
