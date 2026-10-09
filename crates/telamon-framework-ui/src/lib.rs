//! Starts a Telamon app, so its own code is only what makes it different.
//!
//! The app's Rust library names the app once:
//!
//! ```ignore
//! telamon_framework_ui::app! {
//!     name: "Telamon Notepad",
//!     id: "net.eterneon.telamon.notepad",
//!     repo: "atlasos-notepad",
//! }
//! ```
//!
//! An app that needs a newer Telamon.Ui than the first release names it with a
//! trailing `ui:`; the installed Telamon.Ui is then checked at startup, before
//! any of the app's QML (see `include/telamon/app.h`):
//!
//! ```ignore
//! telamon_framework_ui::app! {
//!     name: "Telamon Notepad",
//!     id: "net.eterneon.telamon.notepad",
//!     repo: "atlasos-notepad",
//!     ui: "2.0.0",
//! }
//! ```
//!
//! and its `main.cpp` calls `telamon_app_run` (or `telamon_app_init` and
//! `telamon_app_ready`, for an app with its own shell); see `include/telamon/app.h`.
//! That gives every Telamon app the same start: the app ID as the desktop file
//! name and single-instance D-Bus name, the version, the org.kde.desktop
//! style, logs in the journal ([`telamon_framework_core::log`]), opt-in crash
//! reports for Rust panics and fatal Qt messages
//! ([`telamon_framework_system::crash`]), and what Telamon.Ui's `TelamonApp` and
//! `TelamonAboutPage` show. The look itself is the installed Telamon.Ui module.

use std::cell::Cell;
use std::ffi::{CStr, CString, c_char, c_int};
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{Once, OnceLock};

pub use telamon_framework_core;
pub use telamon_framework_core::AppInfo;
pub use telamon_framework_system;

/// Names the app for the framework: defines the one function it calls to
/// learn who the app is. Use it once, in the app's library.
///
/// An optional `ui: "2.0.0"` names the oldest Telamon.Ui the app works
/// with (`major.minor.patch`, checked when the app is built). At startup the
/// installed Telamon.Ui is checked against it, and an app that is too new for
/// it says so in a window and exits.
///
/// An optional trailing `crash: false` keeps the app out of Telamon crash
/// reporting altogether (for an app that is not part of Telamon OS and must
/// never feed its crash relay): no panic hook, no report for a fatal Qt
/// message, whatever the user chose for Telamon apps. Logging, settings and
/// the rest of the start are unchanged. `crash: true` is the default.
#[macro_export]
macro_rules! app {
    (name: $name:expr, id: $id:expr, repo: $repo:expr, ui: $ui:expr, crash: $crash:expr $(,)?) => {
        const _: () = ::core::assert!(
            $crate::ui_version_ok($ui),
            "ui: must be a version like \"2.0.0\""
        );
        $crate::app!(@define $name, $id, $repo, $ui, $crash);
    };
    (name: $name:expr, id: $id:expr, repo: $repo:expr, ui: $ui:expr $(,)?) => {
        $crate::app!(name: $name, id: $id, repo: $repo, ui: $ui, crash: true);
    };
    (name: $name:expr, id: $id:expr, repo: $repo:expr, crash: $crash:expr $(,)?) => {
        $crate::app!(@define $name, $id, $repo, "", $crash);
    };
    (name: $name:expr, id: $id:expr, repo: $repo:expr $(,)?) => {
        $crate::app!(@define $name, $id, $repo, "", true);
    };
    (@define $name:expr, $id:expr, $repo:expr, $ui:expr, $crash:expr) => {
        #[doc(hidden)]
        #[unsafe(no_mangle)]
        pub fn telamon_framework_ui_app_info() -> $crate::AppInfo {
            $crate::telamon_framework_core::app_info! { name: $name, id: $id, repo: $repo }
        }

        #[doc(hidden)]
        #[unsafe(no_mangle)]
        pub fn telamon_framework_ui_required_ui() -> &'static str {
            $ui
        }

        #[doc(hidden)]
        #[unsafe(no_mangle)]
        pub fn telamon_framework_ui_crash_reporting() -> bool {
            $crash
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
    safe fn telamon_framework_ui_app_info() -> AppInfo;
    /// Defined by the app's `app!`: "" when it names no Telamon.Ui version.
    safe fn telamon_framework_ui_required_ui() -> &'static str;
    /// Defined by the app's `app!`: whether the app takes part in crash reporting.
    safe fn telamon_framework_ui_crash_reporting() -> bool;
}

/// 0: not set by `telamon_app_set_crash_reporting`, 1: on, 2: off.
static CRASH_OVERRIDE: AtomicU8 = AtomicU8::new(0);

/// Whether this app takes part in crash reporting: the C++ call
/// `telamon_app_set_crash_reporting` if there was one, else the `crash:` of its
/// `app!` (on by default). Off means no panic hook and no report for a fatal Qt
/// message; the user's own switch ([`telamon_framework_system::crash::Settings`])
/// is a second, separate condition.
pub fn crash_reporting() -> bool {
    crash_reporting_choice(
        CRASH_OVERRIDE.load(Ordering::SeqCst),
        telamon_framework_ui_crash_reporting(),
    )
}

fn crash_reporting_choice(call: u8, app: bool) -> bool {
    match call {
        1 => true,
        2 => false,
        _ => app,
    }
}

static START: Once = Once::new();

/// C++: opts the app in (`true`) or out (`false`) of crash reporting, over the
/// `crash:` of its `app!`. Call it before `telamon_app_init`; after that it is
/// logged and ignored, because the panic hook is already in place.
#[unsafe(no_mangle)]
extern "C" fn telamon_app_set_crash_reporting(enabled: bool) {
    if START.is_completed() {
        log::warn!(
            "telamon_app_set_crash_reporting({enabled}) came after telamon_app_init: ignored"
        );
        return;
    }
    CRASH_OVERRIDE.store(if enabled { 1 } else { 2 }, Ordering::SeqCst);
}

/// The Telamon.Ui version the app's `app!` asks for (`ui:`), if any.
pub fn required_ui() -> Option<&'static str> {
    Some(telamon_framework_ui_required_ui()).filter(|v| !v.is_empty())
}

/// The app, as its `app!` named it.
pub fn app_info() -> &'static AppInfo {
    static APP: OnceLock<AppInfo> = OnceLock::new();
    APP.get_or_init(telamon_framework_ui_app_info)
}

/// The logger and the crash hook (not for an app with `crash: false`).
/// `telamon_app_init` calls it; a Rust test or tool may call it directly. Only
/// the first call does anything.
pub fn start() {
    START.call_once(|| {
        let app = app_info();
        telamon_framework_core::log::init(app);
        if crash_reporting() {
            telamon_framework_system::crash::install(app.clone());
        } else {
            // A native crash still goes to systemd-coredump: tell the other
            // Telamon apps that collect those not to report this program's.
            telamon_framework_system::crash::opt_out(app);
        }
    });
}

#[unsafe(no_mangle)]
extern "C" fn telamon_framework_ui_start() {
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
unsafe extern "C" fn telamon_framework_ui_fatal(msg: *const c_char) {
    static STARTED: AtomicBool = AtomicBool::new(false);
    static DONE: AtomicBool = AtomicBool::new(false);
    thread_local!(static IN_FATAL: Cell<bool> = const { Cell::new(false) });
    // An app that keeps out of crash reporting only logs the message.
    if !crash_reporting() {
        if !msg.is_null() {
            log::error!("{}", unsafe { CStr::from_ptr(msg) }.to_string_lossy());
        }
        return;
    }
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
    telamon_framework_system::crash::record_fatal(&text);
}

struct SetOnDrop(&'static AtomicBool);

impl Drop for SetOnDrop {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
    }
}

/// 0 name, 1 ID, 2 version, 3 repository, 4 the Telamon.Ui version the app
/// asks for (empty for none); anything else is empty. The
/// strings live as long as the process.
#[unsafe(no_mangle)]
extern "C" fn telamon_framework_ui_field(field: c_int) -> *const c_char {
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
            c(telamon_framework_ui_required_ui()),
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
        name: "Telamon Test",
        id: "net.eterneon.telamon.test",
        repo: "telamon-framework",
    }

    fn field(i: c_int) -> String {
        unsafe { CStr::from_ptr(telamon_framework_ui_field(i)) }
            .to_string_lossy()
            .into_owned()
    }

    #[test]
    fn fields_for_cpp() {
        assert_eq!(field(0), "Telamon Test");
        assert_eq!(field(1), "net.eterneon.telamon.test");
        assert_eq!(field(2), env!("CARGO_PKG_VERSION"));
        assert_eq!(field(3), "telamon-framework");
        assert_eq!(field(4), "");
        assert_eq!(field(5), "");
        assert_eq!(field(-1), "");
        assert_eq!(required_ui(), None);
    }

    #[test]
    fn crash_reporting_choice_is_the_call_then_the_app() {
        assert!(crash_reporting_choice(0, true));
        assert!(!crash_reporting_choice(0, false));
        assert!(crash_reporting_choice(1, false));
        assert!(!crash_reporting_choice(2, true));
        // This test app names no `crash:`: on.
        assert!(telamon_framework_ui_crash_reporting());
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
