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
//! An app that needs a newer Atlas.Ui than the first release names it with a
//! trailing `ui:`; the installed Atlas.Ui is then checked at startup, before
//! any of the app's QML (see `include/atlas/app.h`):
//!
//! ```ignore
//! atlas_framework_ui::app! {
//!     name: "Atlas Notepad",
//!     id: "net.eterneon.atlas.notepad",
//!     repo: "atlasos-notepad",
//!     ui: "1.3.0",
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
///
/// An optional trailing `ui: "1.3.0"` names the oldest Atlas.Ui the app works
/// with (`major.minor.patch`, checked when the app is built). At startup the
/// installed Atlas.Ui is checked against it, and an app that is too new for
/// it says so in a window and exits.
#[macro_export]
macro_rules! app {
    (name: $name:expr, id: $id:expr, repo: $repo:expr, ui: $ui:expr $(,)?) => {
        const _: () = ::core::assert!(
            $crate::ui_version_ok($ui),
            "ui: must be a version like \"1.3.0\""
        );
        $crate::app!(@define $name, $id, $repo, $ui);
    };
    (name: $name:expr, id: $id:expr, repo: $repo:expr $(,)?) => {
        $crate::app!(@define $name, $id, $repo, "");
    };
    (@define $name:expr, $id:expr, $repo:expr, $ui:expr) => {
        #[doc(hidden)]
        #[unsafe(no_mangle)]
        pub fn atlas_framework_ui_app_info() -> $crate::AppInfo {
            $crate::atlas_framework_core::app_info! { name: $name, id: $id, repo: $repo }
        }

        #[doc(hidden)]
        #[unsafe(no_mangle)]
        pub fn atlas_framework_ui_required_ui() -> &'static str {
            $ui
        }
    };
}

/// Whether `v` is `major.minor.patch` (or fewer parts) of plain numbers, as
/// `ui:` takes. Used by [`app!`] at compile time.
#[doc(hidden)]
pub const fn ui_version_ok(v: &str) -> bool {
    let b = v.as_bytes();
    let (mut i, mut parts, mut digits) = (0, 0, 0);
    while i < b.len() {
        match b[i] {
            b'0'..=b'9' => digits += 1,
            b'.' if digits > 0 && parts < 2 => {
                parts += 1;
                digits = 0;
            }
            _ => return false,
        }
        if digits > 6 {
            return false;
        }
        i += 1;
    }
    digits > 0
}

unsafe extern "Rust" {
    /// Defined by the app's `app!`.
    safe fn atlas_framework_ui_app_info() -> AppInfo;
    /// Defined by the app's `app!`: "" when it names no Atlas.Ui version.
    safe fn atlas_framework_ui_required_ui() -> &'static str;
}

/// The Atlas.Ui version the app's `app!` asks for (`ui:`), if any.
pub fn required_ui() -> Option<&'static str> {
    Some(atlas_framework_ui_required_ui()).filter(|v| !v.is_empty())
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

/// 0 name, 1 ID, 2 version, 3 repository, 4 the Atlas.Ui version the app
/// asks for (empty for none); anything else is empty. The
/// strings live as long as the process.
#[unsafe(no_mangle)]
extern "C" fn atlas_framework_ui_field(field: c_int) -> *const c_char {
    static FIELDS: OnceLock<[CString; 5]> = OnceLock::new();
    let fields = FIELDS.get_or_init(|| {
        let app = app_info();
        // A NUL inside a value can't cross to C++: leave that one empty.
        let c = |s: &str| CString::new(s).unwrap_or_default();
        [
            c(&app.name),
            c(&app.id),
            c(&app.version),
            c(&app.repo),
            c(atlas_framework_ui_required_ui()),
        ]
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
        assert_eq!(field(5), "");
        assert_eq!(field(-1), "");
        assert_eq!(required_ui(), None);
    }

    #[test]
    fn ui_versions() {
        for ok in ["1", "1.3", "1.3.0", "99.0.0", "10.20.30"] {
            assert!(ui_version_ok(ok), "{ok}");
        }
        for bad in [
            "",
            ".",
            "1.",
            ".1",
            "1..2",
            "1.2.3.4",
            "1.3.0-dev",
            "v1",
            "1 .3",
            "1234567",
        ] {
            assert!(!ui_version_ok(bad), "{bad:?}");
        }
    }
}
