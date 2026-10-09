//! The C++ switch `telamon_app_set_crash_reporting(false)`, called before
//! `telamon_app_init`, keeps an app whose `app!` names no `crash:` out of crash
//! reporting; a call after the start is ignored (the panic hook is in place).

telamon_framework_ui::app! {
    name: "Telamon Switch",
    id: "net.eterneon.telamon.crashswitch",
    repo: "telamon-framework",
}

unsafe extern "C" {
    fn telamon_app_set_crash_reporting(enabled: bool);
}

#[test]
fn the_cpp_switch_turns_reporting_off_before_the_start_and_not_after() {
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

    unsafe { telamon_app_set_crash_reporting(false) };
    assert!(!telamon_framework_ui::crash_reporting());
    telamon_framework_ui::start();
    let _ = std::panic::catch_unwind(|| panic!("a panic after the switch was turned off"));
    assert!(telamon_framework_system::crash::pending().is_empty());

    // Too late to change anything.
    unsafe { telamon_app_set_crash_reporting(true) };
    assert!(!telamon_framework_ui::crash_reporting());
}
