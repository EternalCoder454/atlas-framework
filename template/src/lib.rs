//! Rust side of the app. C++ (`main.cpp`) only hands over to the framework;
//! everything else lives here as QObjects exposed to QML.

mod backend;

// Who this app is: its name, app ID (also the desktop file and icon name) and
// repository. The framework uses it for the window, the single-instance name,
// the journal, crash reports and the About page.
atlas_framework_ui::app! {
    name: "Atlas App",
    id: "net.eterneon.atlas.apptemplate",
    // The app's own repository under github.com/EternalCoder454: the About
    // page links to it. Change it in a copied app.
    repo: "atlas-framework",
}

use std::ffi::c_void;

/// Called once from `main.cpp`. Returns the `Backend` QObject, which C++ hands
/// to the QML engine. Ownership passes to the caller (a QObject with no parent).
#[unsafe(no_mangle)]
pub extern "C" fn atlas_backend_new() -> *mut c_void {
    backend::qobject::backend_make_unique().into_raw().cast()
}
