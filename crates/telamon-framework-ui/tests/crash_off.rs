//! An app with `crash: false` in its `app!` never takes part in crash
//! reporting, even when the user turned reports on for Telamon apps: `start()`
//! installs no panic hook and a fatal Qt message writes no report. (A test
//! binary of its own: `start()` and the app's `app!` are once per process. The
//! same flow with the default is in crash_on.rs.)

use std::ffi::{c_char, c_int};

telamon_framework_ui::app! {
    name: "Telamon Off",
    id: "net.eterneon.telamon.crashoff",
    repo: "telamon-framework",
    crash: false,
}

unsafe extern "C" {
    fn telamon_framework_ui_fatal(msg: *const c_char);
    fn telamon_framework_ui_field(field: c_int) -> *const c_char;
}

#[test]
fn an_app_with_crash_false_writes_no_report_and_installs_no_hook() {
    let home = tempfile::tempdir().unwrap();
    // SAFETY: the only test of this process, so nothing reads the environment
    // while it is changed.
    unsafe {
        std::env::set_var("HOME", home.path());
        std::env::set_var("XDG_CONFIG_HOME", home.path().join("config"));
        std::env::set_var("XDG_STATE_HOME", home.path().join("state"));
    }
    // The user has turned reports on.
    telamon_framework_system::crash::Settings { enabled: true }
        .save()
        .unwrap();
    assert!(telamon_framework_system::crash::Settings::load().enabled);

    assert!(!telamon_framework_ui::crash_reporting());
    telamon_framework_ui::start();

    // A hook that is ours would queue this panic.
    let _ =
        std::panic::catch_unwind(|| panic!("a panic of an app that keeps out of crash reports"));
    assert!(telamon_framework_system::crash::pending().is_empty());

    // A fatal Qt message is only logged.
    unsafe { telamon_framework_ui_fatal(c"Qt fatal: nothing may be written".as_ptr()) };
    assert!(telamon_framework_system::crash::pending().is_empty());

    // Nothing at all under the state directory (no marker, no report folder).
    let reports = home.path().join("state/telamon/crash-reports");
    let files = |d: &std::path::Path| -> usize {
        std::fs::read_dir(d)
            .map(|r| r.flatten().count())
            .unwrap_or(0)
    };
    assert_eq!(files(&reports.join("pending")), 0);

    // The rest of the app is as it was: its names are served.
    let id = unsafe { std::ffi::CStr::from_ptr(telamon_framework_ui_field(1)) };
    assert_eq!(id.to_str().unwrap(), "net.eterneon.telamon.crashoff");
}
