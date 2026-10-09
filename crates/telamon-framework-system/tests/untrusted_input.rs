//! The files and documents other programs write, and the text an image
//! supplies: bounded, no panics, nothing planted at a path is followed.

use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::time::{Duration, Instant};

use proptest::prelude::*;
use telamon_framework_system::bootc::{self, ImageReference, Status};
use telamon_framework_system::events::{self, Event};
use telamon_framework_system::history::{self, Entry};

fn fifo(path: &Path) {
    let c = std::ffi::CString::new(path.to_str().unwrap()).unwrap();
    // SAFETY: a NUL-terminated path.
    assert_eq!(unsafe { libc::mkfifo(c.as_ptr(), 0o600) }, 0);
}

fn entry(digest: &str) -> Entry {
    Entry {
        version: Some("44.1".into()),
        digest: digest.into(),
        image: "x:stable".into(),
        timestamp: None,
        first_booted: "2026-10-01T00:00:00Z".into(),
    }
}

#[test]
fn a_fifo_at_a_lock_file_name_fails_at_once() {
    let d = tempfile::tempdir().unwrap();
    let t = Instant::now();
    let h = d.path().join("h.jsonl");
    fifo(&h.with_extension("jsonl.lock"));
    assert!(history::append_if_new(&h, &entry("sha256:a")).is_err());
    let e = d.path().join("e.jsonl");
    fifo(&e.with_extension("jsonl.lock"));
    assert!(events::append(&e, &Event::new("update-staged", None, None)).is_err());
    assert!(t.elapsed() < Duration::from_secs(1));
    assert!(!h.exists() && !e.exists());
}

#[test]
fn a_symlink_at_a_lock_or_log_name_is_not_followed() {
    let d = tempfile::tempdir().unwrap();
    let victim = d.path().join("victim");
    std::fs::write(&victim, "keep").unwrap();
    for (name, lock) in [("a.jsonl", false), ("b.jsonl", true)] {
        let p = d.path().join(name);
        let link = if lock {
            p.with_extension("jsonl.lock")
        } else {
            p.clone()
        };
        std::os::unix::fs::symlink(&victim, &link).unwrap();
        assert!(history::append_if_new(&p, &entry("sha256:a")).is_err());
        assert!(events::append(&p, &Event::new("update-staged", None, None)).is_err());
    }
    assert_eq!(std::fs::read_to_string(&victim).unwrap(), "keep");
}

#[test]
fn a_fifo_as_the_log_is_never_written_to() {
    let d = tempfile::tempdir().unwrap();
    let p = d.path().join("h.jsonl");
    fifo(&p);
    assert!(history::append_if_new(&p, &entry("sha256:a")).is_err());
    assert!(events::append(&p, &Event::new("update-staged", None, None)).is_err());
    assert!(history::read(&p).is_err());
    assert!(events::read(&p).is_empty());
}

#[test]
fn record_boot_cuts_and_cleans_what_an_image_supplies() {
    let d = tempfile::tempdir().unwrap();
    let p = d.path().join("h.jsonl");
    let big = "v".repeat(500_000);
    let json = format!(
        r#"{{"status":{{"booted":{{"image":{{"image":{{"image":"{big}:stable"}},
        "version":"44\n\u001b[2J{big}","timestamp":"{big}","imageDigest":"sha256:{big}"}}}}}}}}"#
    );
    let s = Status::from_json(&json).unwrap();
    assert!(history::record_boot(&p, &s, "2026-10-02T10:00:00Z").unwrap());
    let text = std::fs::read_to_string(&p).unwrap();
    assert!(text.len() < 2048, "{}", text.len());
    assert_eq!(text.lines().count(), 1);
    let e = &history::read(&p).unwrap()[0];
    assert!(e.version.as_deref().unwrap().starts_with("44  [2J"));
    assert!(!e.version.as_deref().unwrap().contains(['\n', '\u{1b}']));
    assert_eq!(e.version.as_deref().unwrap().chars().count(), 128);
    assert_eq!(e.image.chars().count(), 512);
    assert_eq!(
        std::fs::metadata(&p).unwrap().permissions().mode() & 0o777,
        0o644
    );
}

#[test]
fn append_if_new_refuses_a_line_over_8_kb() {
    let d = tempfile::tempdir().unwrap();
    let p = d.path().join("h.jsonl");
    let mut e = entry("sha256:a");
    e.image = "i".repeat(9000);
    let err = history::append_if_new(&p, &e).unwrap_err();
    assert_eq!(err.kind(), std::io::ErrorKind::InvalidInput);
    assert!(!p.exists());
}

#[test]
fn lines_far_over_the_size_of_any_entry_are_skipped_by_both_readers() {
    let d = tempfile::tempdir().unwrap();
    let junk = "z".repeat(200_000);
    let h = d.path().join("h.jsonl");
    std::fs::write(
        &h,
        format!(
            "{{\"digest\":\"sha256:a\",\"first_booted\":\"t\",\"image\":\"{junk}\"}}\n\
             {{\"digest\":\"sha256:b\",\"first_booted\":\"t\"}}\n"
        ),
    )
    .unwrap();
    let got = history::read(&h).unwrap();
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].digest, "sha256:b");
    let e = d.path().join("e.jsonl");
    std::fs::write(
        &e,
        format!("{{\"event\":\"{junk}\",\"time\":\"t\"}}\n{{\"event\":\"ok\",\"time\":\"t\"}}\n"),
    )
    .unwrap();
    let got = events::read(&e);
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].event, "ok");
}

#[test]
fn bootc_status_is_bounded_in_size_and_depth() {
    let big = format!(r#"{{"kind":"{}"}}"#, "k".repeat(bootc::MAX_JSON_BYTES));
    assert!(Status::from_json(&big).is_err());
    let ok = format!(r#"{{"kind":"{}"}}"#, "k".repeat(1000));
    assert_eq!(Status::from_json(&ok).unwrap().kind.len(), 1000);
    // nesting deep enough to overflow a recursive parser's stack
    let deep = format!(
        r#"{{"spec":{{"image":{{"image":"x","signature":{}{}}}}}}}"#,
        "[".repeat(100_000),
        "]".repeat(100_000)
    );
    assert!(Status::from_json(&deep).is_err());
    let deep = "[".repeat(1_000_000);
    assert!(Status::from_json(&deep).is_err());
}

proptest! {
    #[test]
    fn prop_history_and_events_read_any_bytes(
        bytes in proptest::collection::vec(any::<u8>(), 0..1024)
    ) {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("f.jsonl");
        std::fs::write(&p, &bytes).unwrap();
        let h = history::read(&p).unwrap();
        let e = events::read(&p);
        let lines = bytes.split(|b| *b == b'\n').count();
        prop_assert!(h.len() <= lines && e.len() <= lines);
    }

    #[test]
    fn prop_history_and_events_read_json_shaped_lines(
        lines in proptest::collection::vec(
            prop_oneof![
                "\\{\"digest\":\"[a-z:0-9]{0,12}\",\"first_booted\":\"[0-9TZ:-]{0,20}\"(,\"x\":[0-9\\[\\]{}\",:null]{0,12})?\\}",
                "\\{\"event\":\"[a-z-]{0,12}\",\"time\":\"[0-9TZ:-]{0,20}\"(,\"error\":(null|\"[ -~]{0,12}\"))?\\}",
                "[ -~]{0,40}",
            ],
            0..12
        )
    ) {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("f.jsonl");
        std::fs::write(&p, lines.join("\n")).unwrap();
        let h = history::read(&p).unwrap();
        let e = events::read(&p);
        prop_assert!(h.len() <= lines.len() && e.len() <= lines.len());
        // appending after any content keeps every earlier line readable
        let before = e.len();
        events::append(&p, &Event::new("update-staged", None, None)).unwrap();
        prop_assert_eq!(events::read(&p).len(), before + 1);
    }

    #[test]
    fn prop_bootc_status_from_any_text(s in any::<String>()) {
        let _ = Status::from_json(&s);
    }

    #[test]
    fn prop_bootc_status_from_json_shaped_text(
        s in "\\{\"(spec|status)\":\\{\"(image|booted|staged|rollback|cachedUpdate)\":(null|\\{[\"a-zA-Z0-9:,/.{}\\[\\]-]{0,60}\\})\\}\\}"
    ) {
        if let Ok(st) = Status::from_json(&s) {
            let _ = (st.channel(), st.latest_image(), st.available_update(), st.update_available());
            let _ = st.booted_ref().map(|r| (r.tag(), r.channel()));
        }
    }

    #[test]
    fn prop_with_channel_gives_a_safe_reference(
        image in prop_oneof!["[ -~]{0,40}", any::<String>(), "[a-z.]{1,8}(:[0-9]{1,4})?/[a-z/]{1,10}(:[a-z]{1,6})?(@sha256:[0-9a-f]{0,8})?"],
        transport in proptest::option::of(prop_oneof!["registry", "oci", "containers-storage", "[ -~]{0,10}"]),
        channel in prop_oneof!["stable", "testing", "[ -~]{0,8}"],
    ) {
        let r = ImageReference { image, transport, signature: None };
        {
            if let Ok(n) = r.with_channel(&channel) {
                prop_assert!(channel == "stable" || channel == "testing");
                let suffix = format!(":{}", channel);
                prop_assert!(n.image.ends_with(&suffix));
                let name = &n.image[..n.image.len() - channel.len() - 1];
                prop_assert!(!name.is_empty() && !name.starts_with('-'));
                prop_assert!(!name.chars().any(|c| c.is_control() || c.is_whitespace()));
                prop_assert!(!name.contains('@'));
                prop_assert!(bootc::TRANSPORTS.contains(&n.transport_or_default()));
                prop_assert_eq!(n.channel().map(|c| c.to_string()), Some(channel.clone()));
            }
        }
    }

    #[test]
    fn prop_version_and_time_helpers_never_panic(a in any::<String>(), b in any::<String>()) {
        let _ = bootc::version_cmp(&a, &b);
        if let Some(t) = bootc::utc_second(&a) {
            prop_assert_eq!(t.len(), 19);
        }
        let _ = history::rfc3339_from_unix(a.len() as u64 * 1_000_000_007);
    }

    #[test]
    fn prop_policy_check_never_panics(
        image in any::<String>(),
        policy in prop_oneof![
            Just(serde_json::json!({})),
            Just(serde_json::json!([])),
            Just(serde_json::json!({"default": [{"type": "reject"}], "transports": {"docker": {"": [{"type": "sigstoreSigned"}]}}})),
            Just(serde_json::json!({"default": 3, "transports": []})),
        ],
    ) {
        let _ = bootc::policy_requires_signature(&policy, &image);
    }

    #[test]
    fn prop_read_dirs_of_refs_are_bounded(names in proptest::collection::vec("[a-z0-9_]{1,6}", 0..6)) {
        let d = tempfile::tempdir().unwrap();
        for (i, n) in names.iter().enumerate() {
            std::fs::write(d.path().join(n), "x".repeat(i * 3000)).unwrap();
        }
        let heads = bootc::image_ref_heads(d.path());
        prop_assert!(heads.iter().all(|h| h.len() <= 4096));
        let _ = bootc::bad_image_digests(&d.path().join("none"));
    }
}
