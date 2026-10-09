//! Rust side of the app. C++ (`main.cpp`) only hands over to the framework;
//! everything else lives here as QObjects exposed to QML.

mod backend;

// Who this app is: its name, app ID (also the desktop file and icon name) and
// repository. The framework uses it for the window, the single-instance name,
// the journal, crash reports and the About page.
telamon_framework_ui::app! {
    name: "Telamon App",
    id: "net.eterneon.telamon.apptemplate",
    // The app's own repository under github.com/EternalCoder454: the About
    // page links to it. Change it in a copied app.
    repo: "telamon-framework",
    // The oldest Telamon.Ui this app works with. If the installed one is older
    // (or missing), the app says so in a plain window and exits instead of
    // failing half-drawn. Raise it when the app starts using a newer Telamon.Ui.
    ui: "1.4.0",
    // Crash reports: on by default, so a panic or a fatal Qt message is queued
    // when the user turned reports on for Telamon apps. An app that is not part
    // of Telamon OS must never feed its crash relay: add `crash: false,` here.
}

use std::ffi::c_void;

/// Called once from `main.cpp`. Returns the `Backend` QObject, which C++ hands
/// to the QML engine. Ownership passes to the caller (a QObject with no parent).
#[unsafe(no_mangle)]
pub extern "C" fn telamon_backend_new() -> *mut c_void {
    backend::qobject::backend_make_unique().into_raw().cast()
}
