//! Reads every fixture of the settings file (see fixtures/README.md).

use std::path::PathBuf;
use telamon_framework_core::settings::Settings;

fn fixture(name: &str) -> Settings {
    Settings::at(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name),
    )
}

#[test]
fn legacy_without_format() {
    let s = fixture("telamon-legacy-rc");
    assert_eq!(s.get("Telamon", "Format"), None);
    assert_eq!(s.get_bool("General", "CrashReports"), Some(true));
    assert_eq!(s.get("General", "Language").as_deref(), Some("nl_NL"));
    assert_eq!(
        s.get("Restart", "ScheduledAt").as_deref(),
        Some("1700000000")
    );
    assert_eq!(s.get("Restart", "Note").as_deref(), Some("a b\nc"));
}

#[test]
fn format_1() {
    let s = fixture("telamon-v1-rc");
    assert_eq!(s.get("Telamon", "Format").as_deref(), Some("1"));
    assert_eq!(s.get_bool("General", "CrashReports"), Some(false));
    assert_eq!(s.get("General", "Language").as_deref(), Some("en_US"));
    assert_eq!(
        s.get("Restart", "ScheduledAt").as_deref(),
        Some("1800000000")
    );
    assert_eq!(s.get("Restart", "Note").as_deref(), Some("a b\nc"));
}

#[test]
fn a_newer_format_still_reads_what_it_knows() {
    let s = fixture("telamon-future-rc");
    assert_eq!(s.get("Telamon", "Format").as_deref(), Some("2"));
    assert_eq!(s.get_bool("General", "CrashReports"), Some(true));
    assert_eq!(s.get("General", "Language").as_deref(), Some("de_DE"));
    assert_eq!(s.get("General", "NewKey").as_deref(), Some("whatever"));
    assert_eq!(s.get("LaterGroup", "Anything").as_deref(), Some("1"));
}
