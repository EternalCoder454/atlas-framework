//! The settings files framework 1.x wrote (fixtures/atlas-*-rc) are copied to
//! the `telamon-` name the first time an app asks for its settings, with the
//! `[Atlas]` group renamed, and read as they were. One test, because it sets
//! XDG_CONFIG_HOME for the whole process.

use std::fs;
use std::path::PathBuf;

use telamon_framework_core::AppInfo;
use telamon_framework_core::settings::Settings;

fn fixture(name: &str) -> String {
    fs::read_to_string(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name),
    )
    .unwrap()
}

fn app(last: &str) -> AppInfo {
    AppInfo {
        name: "X".into(),
        id: format!("net.eterneon.atlas.{last}"),
        version: "1".into(),
        repo: String::new(),
    }
}

#[test]
fn files_of_1_x_are_adopted_under_the_new_name() {
    let dir = tempfile::tempdir().unwrap();
    // SAFETY: the only test in this process, so no other thread reads the environment.
    unsafe { std::env::set_var("XDG_CONFIG_HOME", dir.path()) };
    for (last, fixture_name) in [
        ("legacy", "atlas-legacy-rc"),
        ("v1", "atlas-v1-rc"),
        ("future", "atlas-future-rc"),
    ] {
        fs::write(
            dir.path().join(format!("atlas-{last}rc")),
            fixture(fixture_name),
        )
        .unwrap();
    }

    let s = Settings::for_app(&app("legacy"));
    assert_eq!(s.path(), dir.path().join("telamon-legacyrc"));
    assert_eq!(s.get("Telamon", "Format"), None);
    assert_eq!(s.get_bool("General", "CrashReports"), Some(true));
    assert_eq!(s.get("General", "Language").as_deref(), Some("nl_NL"));
    assert_eq!(s.get("Restart", "Note").as_deref(), Some("a b\nc"));

    let s = Settings::for_app(&app("v1"));
    assert_eq!(s.get("Telamon", "Format").as_deref(), Some("1"));
    assert_eq!(s.get("Atlas", "Format"), None);
    assert_eq!(s.get("General", "Language").as_deref(), Some("en_US"));
    assert_eq!(s.get("Restart", "Note").as_deref(), Some("a b\nc"));

    let s = Settings::for_app(&app("future"));
    assert_eq!(s.get("Telamon", "Format").as_deref(), Some("2"));
    assert_eq!(s.get("General", "NewKey").as_deref(), Some("whatever"));
    assert_eq!(s.get("LaterGroup", "Anything").as_deref(), Some("1"));
    // A change keeps the newer app's format number.
    s.set("General", "Language", Some("fr_FR")).unwrap();
    assert_eq!(s.get("Telamon", "Format").as_deref(), Some("2"));

    // The 1.x files are untouched.
    for (last, fixture_name) in [
        ("legacy", "atlas-legacy-rc"),
        ("v1", "atlas-v1-rc"),
        ("future", "atlas-future-rc"),
    ] {
        assert_eq!(
            fs::read_to_string(dir.path().join(format!("atlas-{last}rc"))).unwrap(),
            fixture(fixture_name)
        );
    }
}
