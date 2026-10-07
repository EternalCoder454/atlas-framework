//! Reads every fixture of the history and events files (fixtures/README.md).

use std::path::PathBuf;
use telamon_framework_system::{events, history};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name)
}

#[test]
fn history_legacy() {
    let h = history::read(&fixture("history-legacy.jsonl")).unwrap();
    // newest first; the bad line is skipped
    let digests: Vec<_> = h.iter().map(|e| e.digest.as_str()).collect();
    assert_eq!(
        digests,
        ["sha256:aaa4", "sha256:aaa3", "sha256:aaa2", "sha256:aaa1"]
    );
    let first = &h[3];
    assert_eq!(first.version.as_deref(), Some("44.20260901"));
    assert_eq!(first.image, "ghcr.io/eternalcoder454/atlasos:stable");
    assert_eq!(first.timestamp.as_deref(), Some("2026-09-01T04:00:00Z"));
    assert_eq!(first.first_booted, "2026-09-02T08:00:00Z");
    // missing version, image and timestamp
    assert_eq!(
        (
            h[2].version.clone(),
            h[2].image.as_str(),
            h[2].timestamp.clone()
        ),
        (None, "", None)
    );
    // missing timestamp only
    assert_eq!(h[1].version.as_deref(), Some("44.20260915"));
    assert_eq!(h[1].timestamp, None);
    // explicit nulls
    assert_eq!(
        (h[0].version.clone(), h[0].image.as_str()),
        (None, "x:beta")
    );
}

#[test]
fn history_v1() {
    let h = history::read(&fixture("history-v1.jsonl")).unwrap();
    assert_eq!(h.len(), 2);
    assert_eq!(h[1].digest, "sha256:bbb1");
    assert_eq!(h[1].version.as_deref(), Some("44.20261001"));
    assert_eq!(h[1].timestamp.as_deref(), Some("2026-10-01T04:12:09Z"));
    assert_eq!(
        (h[0].digest.as_str(), h[0].image.as_str()),
        ("sha256:bbb2", "")
    );
}

#[test]
fn history_future() {
    let h = history::read(&fixture("history-future.jsonl")).unwrap();
    assert_eq!(h.len(), 2);
    assert_eq!(h[0].digest, "sha256:ccc2");
    assert_eq!(h[0].version.as_deref(), Some("45.1"));
    assert_eq!(h[0].image, "x:stable");
    assert_eq!(h[1].digest, "sha256:ccc1");
}

#[test]
fn events_legacy() {
    let e = events::read(&fixture("events-legacy.jsonl"));
    let names: Vec<_> = e.iter().map(|e| e.event.as_str()).collect();
    assert_eq!(
        names,
        ["update-staged", "update-failed", "health-check-passed"]
    );
    assert_eq!(e[0].version.as_deref(), Some("44.20260901"));
    assert_eq!(e[0].time, "2026-09-01T10:00:00Z");
    assert_eq!(e[1].error.as_deref(), Some("cannot read <path>"));
    assert_eq!((e[2].version.clone(), e[2].error.clone()), (None, None));
}

#[test]
fn events_v1() {
    let e = events::read(&fixture("events-v1.jsonl"));
    assert_eq!(e.len(), 2);
    assert_eq!(e[0].event, "rollback-requested");
    assert_eq!(e[0].version.as_deref(), Some("44.20261001"));
    assert_eq!(e[1].event, "channel-switch-failed");
    assert_eq!(e[1].error.as_deref(), Some("timeout"));
    assert_eq!(e[1].time, "2026-10-02T10:00:00Z");
}

#[test]
fn events_future() {
    let e = events::read(&fixture("events-future.jsonl"));
    assert_eq!(e.len(), 2);
    assert_eq!(e[0].event, "update-applied");
    assert_eq!(e[1].event, "rollback-applied");
    assert_eq!(e[1].version.as_deref(), Some("45.1"));
    assert_eq!(e[1].time, "2027-02-01T00:00:00Z");
}
