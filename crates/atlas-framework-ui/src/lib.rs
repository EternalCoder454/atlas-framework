//! Starts an Atlas app, so its own code is only what makes it different.
//!
//! The app's Rust library names the app once:
//!
//! ```ignore
//! atlas_framework_ui::app! {
//!     name: "Atlas Notepad",
//!     id: "net.eterneon.atlas.notepad",
//!     repo: "atlasos-notepad",
//! }
//! ```
//!
//! and its `main.cpp` calls `atlas_app_run` (or `atlas_app_init` and
//! `atlas_app_ready`, for an app with its own shell); see `include/atlas/app.h`.
//! That gives every Atlas app the same start: the app ID as the desktop file
//! name and single-instance D-Bus name, the version, the org.kde.desktop
//! style, logs in the journal ([`atlas_framework_core::log`]), opt-in crash
//! reports for Rust panics and fatal Qt messages
//! ([`atlas_framework_system::crash`]), and what Atlas.Ui's `AtlasApp` and
//! `AtlasAboutPage` show. The look itself is the installed Atlas.Ui module.

use std::cell::Cell;
use std::ffi::{CStr, CString, c_char, c_int};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Once, OnceLock};

pub use atlas_framework_core;
pub use atlas_framework_core::AppInfo;
pub use atlas_framework_system;

/// Names the app for the framework: defines the one function it calls to
/// learn who the app is. Use it once, in the app's library.
#[macro_export]
macro_rules! app {
    (name: $name:expr, id: $id:expr, repo: $repo:expr $(,)?) => {
        #[doc(hidden)]
        #[unsafe(no_mangle)]
        pub fn atlas_framework_ui_app_info() -> $crate::AppInfo {
            $crate::atlas_framework_core::app_info! { name: $name, id: $id, repo: $repo }
        }
    };
}

unsafe extern "Rust" {
    /// Defined by the app's `app!`.
    safe fn atlas_framework_ui_app_info() -> AppInfo;
}

/// The app, as its `app!` named it.
pub fn app_info() -> &'static AppInfo {
    static APP: OnceLock<AppInfo> = OnceLock::new();
    APP.get_or_init(atlas_framework_ui_app_info)
}

/// The logger and the crash hook. `atlas_app_init` calls it; a Rust test or
/// tool may call it directly. Only the first call does anything.
pub fn start() {
    static START: Once = Once::new();
    START.call_once(|| {
        let app = app_info();
        atlas_framework_core::log::init(app);
        atlas_framework_system::crash::install(app.clone());
    });
}

#[unsafe(no_mangle)]
extern "C" fn atlas_framework_ui_start() {
    start();
}

/// A fatal Qt message: logged, and saved as a crash report when the user
/// turned reports on. Only the first call saves one (Qt may raise fatals
/// on several threads, or again from inside this one). A fatal on another
/// thread waits here until that report is saved, so its abort can't cut
/// it off; a watchdog ends the process if saving hangs.
///
/// # Safety
/// `msg` must be null or a valid NUL-terminated string.
#[unsafe(no_mangle)]
unsafe extern "C" fn atlas_framework_ui_fatal(msg: *const c_char) {
    static STARTED: AtomicBool = AtomicBool::new(false);
    static DONE: AtomicBool = AtomicBool::new(false);
    thread_local!(static IN_FATAL: Cell<bool> = const { Cell::new(false) });
    // During thread exit the flag may be gone: treat that as re-entry.
    if IN_FATAL.try_with(|f| f.replace(true)).unwrap_or(true) {
        return; // a fatal while saving this thread's report
    }
    if STARTED.swap(true, Ordering::SeqCst) {
        // The alarm the first thread set bounds this wait.
        while !DONE.load(Ordering::SeqCst) {
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        return;
    }
    // SIGALRM's default action ends the process: Qt's abort comes next
    // anyway, this only stops a lock taken by the crashing code from
    // hanging it. SAFETY: alarm has no preconditions.
    unsafe { libc::alarm(10) };
    let _done = SetOnDrop(&DONE);
    let text = if msg.is_null() {
        String::from("Qt fatal message")
    } else {
        unsafe { CStr::from_ptr(msg) }
            .to_string_lossy()
            .into_owned()
    };
    log::error!("{text}");
    atlas_framework_system::crash::record_fatal(&text);
}

struct SetOnDrop(&'static AtomicBool);

impl Drop for SetOnDrop {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
    }
}

/// 0 name, 1 ID, 2 version, 3 repository; anything else is empty. The
/// strings live as long as the process.
#[unsafe(no_mangle)]
extern "C" fn atlas_framework_ui_field(field: c_int) -> *const c_char {
    static FIELDS: OnceLock<[CString; 4]> = OnceLock::new();
    let fields = FIELDS.get_or_init(|| {
        let app = app_info();
        // A NUL inside a value can't cross to C++: leave that one empty.
        let c = |s: &str| CString::new(s).unwrap_or_default();
        [c(&app.name), c(&app.id), c(&app.version), c(&app.repo)]
    });
    usize::try_from(field)
        .ok()
        .and_then(|i| fields.get(i))
        .map_or(c"".as_ptr(), |s| s.as_ptr())
}

#[cfg(test)]
mod tests {
    use super::*;

    crate::app! {
        name: "Atlas Test",
        id: "net.eterneon.atlas.test",
        repo: "atlas-framework",
    }

    fn field(i: c_int) -> String {
        unsafe { CStr::from_ptr(atlas_framework_ui_field(i)) }
            .to_string_lossy()
            .into_owned()
    }

    #[test]
    fn fields_for_cpp() {
        assert_eq!(field(0), "Atlas Test");
        assert_eq!(field(1), "net.eterneon.atlas.test");
        assert_eq!(field(2), env!("CARGO_PKG_VERSION"));
        assert_eq!(field(3), "atlas-framework");
        assert_eq!(field(4), "");
        assert_eq!(field(-1), "");
    }
}
