//! The default: an app that names no `crash:` takes part in crash reporting,
//! so with the user's opt-in a panic and a fatal Qt message are queued. The
//! counterpart of crash_off.rs, which proves the opt-out does something.

use std::ffi::c_char;

telamon_framework_ui::app! {
    name: "Telamon On",
    id: "net.eterneon.telamon.crashon",
    repo: "telamon-framework",
}

unsafe extern "C" {
    fn telamon_framework_ui_fatal(msg: *const c_char);
}

#[test]
fn the_default_app_queues_a_panic_and_a_fatal_message() {
    let home = tempfile::tempdir().unwrap();
    // SAFETY: the only test of this process.
    unsafe {
        std::env::set_var("HOME", home.path());
        std::env::set_var("XDG_CONFIG_HOME", home.path().join("config"));
        std::env::set_var("XDG_STATE_HOME", home.path().join("state"));
    }
    telamon_framework_system::crash::Settings { enabled: true }
        .save()
        .unwrap();
    assert!(telamon_framework_ui::crash_reporting());
    telamon_framework_ui::start();

    let _ = std::panic::catch_unwind(|| panic!("a panic of an app that reports"));
    assert!(
        !telamon_framework_system::crash::pending().is_empty(),
        "the panic hook queued nothing"
    );
    unsafe { telamon_framework_ui_fatal(c"Qt fatal: a different message".as_ptr()) };
    assert!(telamon_framework_system::crash::pending().len() >= 2);
}
