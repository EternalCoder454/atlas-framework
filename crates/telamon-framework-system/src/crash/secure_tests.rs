//! Security tests of the crash reporting: what a hostile journal entry, file,
//! DSN or server can and cannot do. Regression tests first, then property
//! tests (`PROPTEST_CASES` sets the count; the ones that touch the disk or
//! `/proc` cap it, so 20000 runs stay fast).

use super::*;
use proptest::prelude::*;
use std::net::TcpListener;
use std::os::unix::fs::symlink;

fn sc() -> Scrubber {
    Scrubber::new(
        &["zach", "Zachary Smith"],
        &["atlas-box.local"],
        &["/var/home/zach"],
    )
}

/// The default case count, at most `max`.
fn cfg(max: u32) -> ProptestConfig {
    let mut c = ProptestConfig::default();
    c.cases = c.cases.min(max);
    c
}

fn trusted_entry() -> Value {
    json!({
        "_COMM": "systemd-coredum",
        "_UID": "1000",
        "_SYSTEMD_UNIT": "systemd-coredump@48-57347-3760438_7887167-0.service",
        "COREDUMP_UID": "1000",
        "COREDUMP_TIMESTAMP": "1790000000000000",
        "COREDUMP_EXE": "/usr/bin/foo",
        "COREDUMP_COMM": "foo",
        "COREDUMP_SIGNAL_NAME": "SIGSEGV",
        "MESSAGE": "Process 1 (foo) dumped core.\n\n#0  0x1 f (libc.so + 0x1)"
    })
}

fn no_control(s: &str) -> bool {
    !s.chars().any(char::is_control)
}

// ------------------------------------------------------- journal entries

#[test]
fn an_odd_program_path_is_not_the_hosts_crash() {
    // The crashing process names itself (COREDUMP_COMM) and, with a path the
    // kernel cannot have given for an OS program, used to pass as the host's.
    for bad in [
        "/tmp/a\nb",
        "/tmp/a\u{1b}[31mb",
        "/usr/bin/x\u{202e}gnp",
        "/usr/bin/\u{200b}x",
        "relative/path",
        "/usr/../tmp/x",
    ] {
        let mut e = trusted_entry();
        e["COREDUMP_EXE"] = json!(bad);
        e["COREDUMP_COMM"] = json!("telamon-updater");
        assert_eq!(
            Coredump::parse(&e, "1000").unwrap().origin,
            Origin::Foreign,
            "{bad:?}"
        );
        assert!(
            coredump_report(&e, &sc(), "1000", |x| panic!("rpm for {x:?}")).is_none(),
            "{bad:?}"
        );
    }
    let long = format!("/usr/{}", "a".repeat(5000));
    let mut e = trusted_entry();
    e["COREDUMP_EXE"] = json!(long);
    assert_eq!(Coredump::parse(&e, "1000").unwrap().origin, Origin::Foreign);
    // a missing field (an older systemd) is still the host's
    let mut e = trusted_entry();
    e.as_object_mut().unwrap().remove("COREDUMP_EXE");
    assert_eq!(Coredump::parse(&e, "1000").unwrap().origin, Origin::Host);
}

#[test]
fn only_the_users_own_systemd_coredump_entries_count() {
    let ok = |e: &Value| Coredump::parse(e, "1000").is_some();
    assert!(ok(&trusted_entry()));
    // each trusted field, forged or missing, on its own
    for (key, value) in [
        ("_COMM", json!("evil")),
        ("_COMM", json!("systemd-coredum\n")),
        ("_SYSTEMD_UNIT", json!("user@1000.service")),
        ("_SYSTEMD_UNIT", json!("systemd-coredump@x.service.evil")),
        ("_SYSTEMD_UNIT", json!("evil-systemd-coredump@x.service")),
        ("_UID", json!("1001")),
        ("_UID", json!("01000")),
        ("COREDUMP_UID", json!("0")),
        ("COREDUMP_UID", json!(1000)),
    ] {
        let mut e = trusted_entry();
        e[key] = value.clone();
        assert!(!ok(&e), "{key} = {value}");
    }
    for key in [
        "_COMM",
        "_SYSTEMD_UNIT",
        "_UID",
        "COREDUMP_UID",
        "COREDUMP_TIMESTAMP",
    ] {
        let mut e = trusted_entry();
        e.as_object_mut().unwrap().remove(key);
        assert!(!ok(&e), "without {key}");
    }
    // a journal field that appears twice is an array of strings: not a
    // value anyone trusts (it reads as empty)
    let mut e = trusted_entry();
    e["_UID"] = json!(["1000", "0"]);
    assert!(!ok(&e));
    // another user's uid, and no uid, are never trusted
    assert!(Coredump::parse(&trusted_entry(), "1001").is_none());
    assert!(Coredump::parse(&trusted_entry(), "").is_none());
}

#[test]
fn journal_arguments_cannot_be_steered_by_the_uid() {
    // The uid is read from /proc, so it is digits; whatever it were, it is
    // one argument that begins `_UID=`/`COREDUMP_UID=`, never an option.
    for uid in ["1000", "", "--output=export", "1000 --follow", "a\nb"] {
        let a = journal_args(7, Some(9), Some(uid));
        for x in &a {
            let known = x.starts_with("--output-fields=")
                || x.starts_with("--since=@")
                || x.starts_with("--until=@")
                || ["--no-pager", "--all", "-o", "json", "-n", "500"].contains(&x.as_str())
                || x.starts_with("MESSAGE_ID=")
                || x == "_COMM=systemd-coredum"
                || x.starts_with("_UID=")
                || x.starts_with("COREDUMP_UID=");
            assert!(known, "{x:?} for uid {uid:?}");
        }
    }
}

#[test]
fn the_journal_is_read_by_absolute_path_with_a_clean_environment() {
    // No PATH lookup and nothing from the caller's environment reaches it.
    let d = tempfile::tempdir().unwrap();
    let script = d.path().join("probe");
    fs::write(
        &script,
        "#!/bin/sh\nprintf '{\"PATH\":\"%s\",\"HOME\":\"%s\",\"LD\":\"%s\"}\\n' \"$PATH\" \"${HOME-unset}\" \"${LD_PRELOAD-unset}\"\n",
    )
    .unwrap();
    fs::set_permissions(&script, fs::Permissions::from_mode(0o700)).unwrap();
    let out = journal_with(&script, &[], Duration::from_secs(5));
    assert_eq!(
        out,
        vec![json!({"PATH": "/usr/bin", "HOME": "unset", "LD": "unset"})]
    );
    assert!(Path::new("/usr/bin/journalctl").is_absolute());
}

// --------------------------------------------------------- small files

#[test]
fn a_fifo_or_a_huge_file_in_place_of_a_small_file_is_not_read() {
    let d = tempfile::tempdir().unwrap();
    let fifo = d.path().join("settings");
    let c = std::ffi::CString::new(fifo.to_str().unwrap()).unwrap();
    // SAFETY: a valid NUL-terminated path.
    assert_eq!(unsafe { libc::mkfifo(c.as_ptr(), 0o600) }, 0);
    // reading it must neither hang nor count as consent
    let (tx, rx) = std::sync::mpsc::channel();
    let f2 = fifo.clone();
    std::thread::spawn(move || {
        let _ = tx.send((
            Settings::load_from(&f2),
            Endpoint::load_from(&f2),
            read_coredump_marker(&f2),
            read_small(&f2, 10, true).is_err(),
        ));
    });
    let (settings, endpoint, marker, err) = rx
        .recv_timeout(Duration::from_secs(10))
        .expect("reading a FIFO hung");
    assert!(!settings.enabled);
    assert!(endpoint.is_none());
    assert_eq!(marker, marker_mtime(&fifo).map(|m| m.as_micros() as u64));
    assert!(err);

    // a file over the limit is no settings file, even if it ends in "true"
    let big = d.path().join("big.toml");
    fs::write(
        &big,
        format!(
            "# {}\nenabled = true\n",
            "x".repeat(MAX_SMALL_FILE as usize)
        ),
    )
    .unwrap();
    assert!(!Settings::load_from(&big).enabled);
    fs::write(&big, "enabled = true\n").unwrap();
    assert!(Settings::load_from(&big).enabled);
    // a link to settings (a dotfiles manager) still counts; a link as a
    // marker does not
    let link = d.path().join("link.toml");
    symlink(&big, &link).unwrap();
    assert!(Settings::load_from(&link).enabled);
    assert_eq!(
        read_small(&link, 100, true).unwrap_err().raw_os_error(),
        Some(libc::ELOOP)
    );
    assert_eq!(read_small(&link, 100, false).unwrap(), b"enabled = true\n");
    assert_eq!(
        read_small(d.path(), 100, false).unwrap_err().kind(),
        io::ErrorKind::InvalidInput
    );
}

#[test]
fn a_linked_marker_is_not_followed() {
    let d = tempfile::tempdir().unwrap();
    let target = d.path().join("elsewhere");
    fs::write(&target, "123").unwrap();
    let marker = d.path().join("coredump-last");
    symlink(&target, &marker).unwrap();
    // read as damaged: from the link's own time, not from the target's text
    let got = read_coredump_marker(&marker).unwrap();
    assert_ne!(got, 123);
    let m = d.path().join("events-last");
    symlink(&target, &m).unwrap();
    let (time, _) = read_event_marker(&m, &[]).unwrap();
    assert!(looks_like_time(&time));
    // the lock file and the ledger are not written through a link either
    let victim = d.path().join("victim");
    fs::write(&victim, "keep").unwrap();
    symlink(&victim, d.path().join(format!("{RECENT}.lock"))).unwrap();
    assert!(
        lock_file(
            &d.path().join(format!("{RECENT}.lock")),
            Duration::from_millis(50)
        )
        .is_none()
    );
    symlink(&victim, d.path().join(RECENT)).unwrap();
    assert!(ledger_allow(d.path(), SystemTime::now(), 7, true));
    assert_eq!(fs::read_to_string(&victim).unwrap(), "keep");
    assert!(
        fs::read_to_string(d.path().join(RECENT))
            .unwrap()
            .contains(&format!("{:016x}", 7))
    );
}

#[test]
fn private_files_are_0600_in_a_0700_directory_and_never_written_through_a_link() {
    let d = tempfile::tempdir().unwrap();
    let dir = d.path().join("state");
    fs::create_dir(&dir).unwrap();
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o755)).unwrap();
    let victim = d.path().join("victim");
    fs::write(&victim, "keep").unwrap();
    let p = dir.join("coredump-last");
    symlink(&victim, &p).unwrap();
    // create-only refuses to replace anything, a link included
    let e = write_private(&p, b"1", false).unwrap_err();
    assert_eq!(e.kind(), io::ErrorKind::AlreadyExists);
    assert_eq!(fs::read_to_string(&victim).unwrap(), "keep");
    // overwrite replaces the link itself
    write_private(&p, b"2", true).unwrap();
    assert_eq!(fs::read_to_string(&victim).unwrap(), "keep");
    assert_eq!(fs::read_to_string(&p).unwrap(), "2");
    let mode = |q: &Path| fs::symlink_metadata(q).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode(&dir), 0o700);
    assert_eq!(mode(&p), 0o600);
    // no temp file is left behind
    assert_eq!(fs::read_dir(&dir).unwrap().count(), 1);
}

#[test]
fn the_adopted_state_directory_of_1_x_becomes_private() {
    let d = tempfile::tempdir().unwrap();
    let old = d.path().join("atlas");
    let new = d.path().join("telamon");
    fs::create_dir(&old).unwrap();
    fs::set_permissions(&old, fs::Permissions::from_mode(0o755)).unwrap();
    assert!(adopt_state_dir(&new, &old).unwrap());
    assert_eq!(
        fs::metadata(&new).unwrap().permissions().mode() & 0o777,
        0o700
    );
}

// ----------------------------------------------------------- transport

/// One-shot HTTP server on loopback: answers `response` to the first
/// connection and returns the request it got (headers and body).
fn serve_raw(response: Vec<u8>) -> (String, std::thread::JoinHandle<Vec<u8>>) {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    l.set_nonblocking(true).unwrap();
    let port = l.local_addr().unwrap().port();
    let h = std::thread::spawn(move || {
        let end = Instant::now() + Duration::from_secs(10);
        let mut c = loop {
            match l.accept() {
                Ok((c, _)) => break c,
                Err(e) if e.kind() == io::ErrorKind::WouldBlock && Instant::now() < end => {
                    std::thread::sleep(Duration::from_millis(5));
                }
                Err(_) => return Vec::new(),
            }
        };
        c.set_nonblocking(false).unwrap();
        c.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
        c.set_write_timeout(Some(Duration::from_secs(5))).unwrap();
        let mut got = Vec::new();
        let mut buf = [0u8; 65536];
        while let Ok(n) = c.read(&mut buf) {
            if n == 0 {
                break;
            }
            got.extend_from_slice(&buf[..n]);
            let t = String::from_utf8_lossy(&got).to_string();
            if let Some(i) = t.find("\r\n\r\n") {
                let len = t
                    .lines()
                    .find_map(|l| {
                        l.to_ascii_lowercase()
                            .strip_prefix("content-length:")
                            .map(|v| v.trim().parse::<usize>().unwrap_or(0))
                    })
                    .unwrap_or(0);
                if got.len() >= i + 4 + len {
                    break;
                }
            }
        }
        let _ = c.write_all(&response);
        got
    });
    (format!("http://pubkey@127.0.0.1:{port}/7"), h)
}

fn sample() -> Report {
    let c = Crash {
        report_type: "panic",
        app_name: "net.eterneon.telamon.updater",
        app_version: Some("0.1.0"),
        message: "boom",
        stacktrace: "  0: a::b",
    };
    build_report(&c, &sc(), Some("2026-10-02T10:00:00Z")).unwrap()
}

#[test]
fn the_request_is_a_post_to_the_store_url_with_only_the_public_key() {
    let d = tempfile::tempdir().unwrap();
    let ok = b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}".to_vec();
    let (dsn, h) = serve_raw(ok);
    let ep = Endpoint::parse(&dsn).unwrap();
    let r = sample();
    post_in(d.path(), &r, &ep).unwrap();
    let req = String::from_utf8(h.join().unwrap()).unwrap();
    let (head, body) = req.split_once("\r\n\r\n").unwrap();
    let mut lines = head.lines();
    assert_eq!(lines.next().unwrap(), "POST /api/7/store/ HTTP/1.1");
    let heads: Vec<&str> = lines.collect();
    assert!(heads.iter().any(|l| l.starts_with("Host: 127.0.0.1:")));
    assert!(heads.contains(&"Content-Type: application/json"));
    assert!(heads.contains(&format!(
        "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=pubkey, sentry_client=atlas-core/{}",
        env!("CARGO_PKG_VERSION")
    ).as_str()));
    // nothing else identifies the sender: no cookie, no user agent of the
    // system, no credentials
    for l in &heads {
        let l = l.to_ascii_lowercase();
        assert!(
            !l.starts_with("cookie:") && !l.starts_with("authorization:"),
            "{l}"
        );
    }
    // the body is the payload the user was shown, and the body file is gone
    assert_eq!(serde_json::from_str::<Value>(body).unwrap(), r.payload());
    assert_eq!(fs::read_dir(d.path()).unwrap().count(), 0);
}

#[test]
fn a_redirect_is_not_followed() {
    let other = TcpListener::bind("127.0.0.1:0").unwrap();
    other.set_nonblocking(true).unwrap();
    let to = other.local_addr().unwrap().port();
    let resp = format!(
        "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:{to}/stolen\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    );
    let (dsn, h) = serve_raw(resp.into_bytes());
    let d = tempfile::tempdir().unwrap();
    let e = post_in(d.path(), &sample(), &Endpoint::parse(&dsn).unwrap()).unwrap_err();
    h.join().unwrap();
    assert_eq!(send_failure(&e), Some(&SendFailure::BadAnswer), "{e}");
    // nothing connected to the redirect target
    std::thread::sleep(Duration::from_millis(100));
    assert_eq!(
        other.accept().unwrap_err().kind(),
        io::ErrorKind::WouldBlock
    );
}

#[test]
fn an_answer_that_is_too_big_is_not_trusted_or_read_to_the_end() {
    let link = "https://github.com/EternalCoder454/AtlasOS/issues/1";
    let json = format!("{{\"id\":\"abc\",\"url\":\"{link}\"}}");
    // announced length over the limit
    let body = format!("{json}{}", " ".repeat(300_000));
    let resp = format!(
        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let d = tempfile::tempdir().unwrap();
    let (dsn, h) = serve_raw(resp.into_bytes());
    let got = post_in(d.path(), &sample(), &Endpoint::parse(&dsn).unwrap());
    h.join().unwrap();
    match got {
        Ok(s) => assert_eq!(s, Server::default()),
        Err(e) => assert_eq!(send_failure(&e), Some(&SendFailure::BadAnswer), "{e}"),
    }
    // chunked: no length to refuse by, so the reading stops at the limit
    let mut resp =
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n".to_vec();
    let chunk = format!("{json}{}", " ".repeat(8000));
    for _ in 0..40 {
        resp.extend_from_slice(format!("{:x}\r\n{chunk}\r\n", chunk.len()).as_bytes());
    }
    resp.extend_from_slice(b"0\r\n\r\n");
    let (dsn, h) = serve_raw(resp);
    let got = post_in(d.path(), &sample(), &Endpoint::parse(&dsn).unwrap());
    h.join().unwrap();
    match got {
        Ok(s) => assert_eq!(s, Server::default()),
        Err(e) => assert_eq!(send_failure(&e), Some(&SendFailure::BadAnswer), "{e}"),
    }
}

#[test]
fn https_to_a_server_that_does_not_speak_tls_fails_without_sending_the_report() {
    let (dsn, h) = serve_raw(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".to_vec());
    // same server, but asked over https: curl's handshake fails
    let https = dsn.replacen("http://", "https://", 1);
    // (a non-loopback https DSN is the production shape; the parser accepts
    // this one only because the scheme is https)
    let ep = Endpoint::parse(&https).unwrap();
    let d = tempfile::tempdir().unwrap();
    let e = post_in(d.path(), &sample(), &ep).unwrap_err();
    let req = h.join().unwrap();
    assert!(send_failure(&e).is_some(), "{e}");
    let text = String::from_utf8_lossy(&req);
    assert!(
        !text.contains("\"event_id\""),
        "the report went out in clear text"
    );
}

#[test]
fn curl_is_locked_down_whatever_the_dsn() {
    let ep = Endpoint::parse("https://key@glitch.example/1").unwrap();
    let a = curl_args(&ep, Path::new("/x/body.json"));
    assert_eq!(a[0], "-q");
    assert!(a.contains(&"--tlsv1.2".to_string()));
    for bad in [
        "-k",
        "--insecure",
        "--proxy-insecure",
        "--ssl-no-revoke",
        "--cacert",
        "--capath",
        "--location",
        "-L",
        "--proxy",
        "--netrc",
        "--config",
        "--doh-insecure",
    ] {
        assert!(!a.iter().any(|x| x == bad), "{bad}");
    }
    // `--url` is last and the only place the target appears
    assert_eq!(a[a.len() - 2], "--url");
    assert_eq!(a.iter().filter(|x| x.contains("glitch.example")).count(), 1);
}

#[test]
fn curl_text_in_the_log_is_one_clean_line() {
    let t =
        "curl: (60) SSL: certificate subject name '\u{1b}[2J\u{202e}evil' does not match\n\n403\n";
    let l = log_text(t);
    assert!(no_control(&l));
    assert!(!l.contains('\u{202e}') && !l.contains('\n'));
    assert!(l.ends_with("/ 403"), "{l}");
    assert!(log_text(&"x".repeat(100_000)).chars().count() <= 400);
}

#[test]
fn the_endpoint_is_never_read_from_the_users_files() {
    // The DSN files are the system's own: /etc and /usr/share, written by root.
    let all = [
        SYSTEM_CONFIG,
        LEGACY_SYSTEM_CONFIG,
        DEFAULT_CONFIG,
        LEGACY_DEFAULT_CONFIG,
    ];
    for p in all {
        assert!(
            p.starts_with("/etc/") || p.starts_with("/usr/share/"),
            "{p}"
        );
    }
    // and the shipped default is the Telamon relay, over https
    let shipped = include_str!("../../data/telamon/crash-reporting.toml");
    let ep = Endpoint::parse(&toml_value(shipped, "dsn").unwrap()).unwrap();
    assert!(
        ep.store_url.starts_with("https://telamon.eterneon.net/"),
        "{}",
        ep.store_url
    );
}

// ---------------------------------------------------------------- payload

#[test]
fn the_payload_holds_only_the_documented_fields_and_no_machine_identity() {
    let r = sample();
    let p = r.payload();
    let keys = |v: &Value| {
        let mut k: Vec<String> = v.as_object().unwrap().keys().cloned().collect();
        k.sort();
        k
    };
    let top = keys(&p);
    for k in &top {
        assert!(
            [
                "contexts",
                "environment",
                "event_id",
                "exception",
                "level",
                "logger",
                "message",
                "platform",
                "release",
                "tags",
                "timestamp",
            ]
            .contains(&k.as_str()),
            "new top-level field {k}: review it for privacy"
        );
    }
    assert_eq!(
        keys(&p["tags"]),
        [
            "app",
            "app_version",
            "atlasos_version",
            "category",
            "channel",
            "gpu",
            "gpu_driver",
            "kernel",
            "previous_version",
            "report_type"
        ]
    );
    assert_eq!(keys(&p["contexts"]), ["device", "gpu", "os", "runtime"]);
    // none of this machine's or user's names in it
    let text = serde_json::to_string(&p).unwrap();
    let mut secrets = vec![
        read("/etc/machine-id"),
        read("/proc/sys/kernel/hostname"),
        read("/proc/sys/kernel/random/boot_id"),
        std::env::var("USER").unwrap_or_default(),
        std::env::var("LOGNAME").unwrap_or_default(),
        std::env::var("HOME").unwrap_or_default(),
    ];
    for s in &mut secrets {
        *s = s.trim().to_string();
    }
    for s in secrets {
        // short or common values ("root", "/", "/tmp") say nothing
        if s.len() >= 6 && s != "/tmp" {
            assert!(!text.contains(&s), "the payload holds {s:?}");
        }
    }
    // the rotating ID stays on the machine
    assert!(!text.contains(&r.crash_id));
}

// ------------------------------------------------------------- properties

fn json_leaf() -> impl Strategy<Value = Value> {
    prop_oneof![
        any::<String>().prop_map(Value::from),
        any::<u64>().prop_map(Value::from),
        any::<i64>().prop_map(Value::from),
        any::<f64>().prop_map(|f| json!(f)),
        any::<bool>().prop_map(Value::from),
        Just(Value::Null),
        prop::collection::vec(any::<u8>(), 0..40).prop_map(|b| json!(b)),
        prop::collection::vec(any::<u64>(), 0..8).prop_map(|b| json!(b)),
        prop::collection::vec(any::<String>(), 0..4).prop_map(|b| json!(b)),
        prop::collection::vec(any::<String>(), 0..3).prop_map(|b| json!({"a": b})),
    ]
}

const ENTRY_KEYS: &[&str] = &[
    "_COMM",
    "_UID",
    "_SYSTEMD_UNIT",
    "_HOSTNAME",
    "COREDUMP_UID",
    "COREDUMP_TIMESTAMP",
    "COREDUMP_EXE",
    "COREDUMP_COMM",
    "COREDUMP_SIGNAL_NAME",
    "COREDUMP_PACKAGE_NAME",
    "COREDUMP_PACKAGE_VERSION",
    "COREDUMP_CGROUP",
    "COREDUMP_USER_UNIT",
    "COREDUMP_UNIT",
    "COREDUMP_CONTAINER_CMDLINE",
    "COREDUMP_HOSTNAME",
    "MESSAGE",
];

/// A trusted entry with some fields replaced (or removed) by anything.
fn entry() -> impl Strategy<Value = Value> {
    prop::collection::vec((0..ENTRY_KEYS.len(), json_leaf()), 0..8).prop_map(|over| {
        let mut e = trusted_entry();
        for (i, v) in over {
            if v.is_null() {
                e.as_object_mut().unwrap().remove(ENTRY_KEYS[i]);
            } else {
                e[ENTRY_KEYS[i]] = v;
            }
        }
        e
    })
}

/// Text with the awkward characters of journal and path fields in it.
fn nasty() -> impl Strategy<Value = String> {
    prop::collection::vec(
        prop_oneof![
            any::<char>(),
            Just('\n'),
            Just('\r'),
            Just('\0'),
            Just('\u{1b}'),
            Just('\u{202e}'),
            Just('/'),
            Just('.'),
            Just('@'),
            Just(':'),
            Just('['),
            Just(' '),
            Just('%'),
            Just('#'),
            Just('='),
            Just('"'),
        ],
        0..60,
    )
    .prop_map(|c| c.into_iter().collect())
}

proptest! {
    #![proptest_config(cfg(100_000))]

    #[test]
    fn prop_toml_lookup_never_panics_and_yields_one_line(text in nasty(), key in "[a-z]{1,6}") {
        if let Some(v) = toml_value(&text, &key) {
            prop_assert!(!v.contains('\n'));
            prop_assert!(v.len() <= text.len());
        }
    }

    #[test]
    fn prop_consent_needs_a_true_in_the_file(text in nasty()) {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("c.toml");
        fs::write(&p, &text).unwrap();
        if Settings::load_from(&p).enabled {
            prop_assert!(text.contains("enabled") && text.contains("true"));
        }
        // and a missing file is off
        prop_assert!(!Settings::load_from(&d.path().join("none")).enabled);
    }

    #[test]
    fn prop_consent_is_exactly_what_was_saved(on in any::<bool>()) {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("a/b/c.toml");
        Settings { enabled: on }.save_to(&p).unwrap();
        prop_assert_eq!(Settings::load_from(&p).enabled, on);
    }

    #[test]
    fn prop_a_dsn_is_https_or_loopback_and_builds_a_clean_url(s in nasty()) {
        check_dsn(&s)?;
    }

    #[test]
    fn prop_dsn_shaped_text_is_checked_too(
        scheme in prop_oneof![Just("https"), Just("http"), Just("ftp"), Just("")],
        key in "[a-zA-Z0-9:._\\-%]{0,10}",
        host in "[a-zA-Z0-9.:\\[\\]@\\-]{0,30}",
        path in "[a-zA-Z0-9./_\\-%?#]{0,20}",
    ) {
        check_dsn(&format!("{scheme}://{key}@{host}/{path}"))?;
        check_dsn(&format!("{scheme}://{host}/{path}"))?;
    }

    #[test]
    fn prop_curl_gets_no_line_break_from_any_dsn(s in nasty(), file in "[a-z/]{1,20}") {
        if let Some(ep) = Endpoint::parse(&s) {
            for a in curl_args(&ep, Path::new(&file)) {
                prop_assert!(!a.contains(['\r', '\n', '\0']), "{a:?}");
            }
        }
    }

    #[test]
    fn prop_json_fields_read_without_panic(v in json_leaf()) {
        let e = json!({"k": v});
        let _ = field(&e, "k");
        let _ = field(&e, "none");
    }

    #[test]
    fn prop_an_exe_is_absolute_plain_and_bounded(e in nasty()) {
        if valid_exe(&e) {
            prop_assert!(e.starts_with('/') && e.len() <= 4096);
            prop_assert!(no_control(&e));
            prop_assert!(!e.split('/').any(|c| c == ".."));
        }
    }

    #[test]
    fn prop_clean_leaves_a_short_plain_line(s in nasty(), max in 0usize..100) {
        let c = clean(&s, max, false);
        prop_assert!(c.chars().count() <= max);
        prop_assert!(no_control(&c));
        let bad = ['\u{202e}', '\u{200b}', '\u{feff}'];
        prop_assert!(!c.contains(bad));
        prop_assert_eq!(clean(&c, max, false), c);
    }

    #[test]
    fn prop_cgroup_names_never_panic_and_flatpak_ids_are_plain(c in nasty()) {
        let _ = is_container_cgroup(&c);
        if let Some(id) = flatpak_scope_app(&c) {
            prop_assert!((3..=255).contains(&id.len()) && id.contains('.'));
            prop_assert!(id.chars().all(|c| c.is_ascii_alphanumeric() || "._-".contains(c)));
        }
    }

    #[test]
    fn prop_times_parse_without_panic(t in nasty(), secs in any::<u64>()) {
        let _ = unix_from_rfc3339(&t);
        let s = history::rfc3339_from_unix(secs / 1_000_000);
        prop_assert!(s.len() <= 40 && no_control(&s));
        let _ = looks_like_time(&t);
        let _ = parse_event_marker(&t, &[]);
    }

    #[test]
    fn prop_the_servers_answer_yields_only_plain_ids_and_issue_links(b in prop::collection::vec(any::<u8>(), 0..200)) {
        let s = parse_server_answer(&b);
        if let Some(id) = s.id {
            prop_assert!((1..=64).contains(&id.len()));
            prop_assert!(id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-'));
        }
        if let Some(u) = s.url {
            prop_assert!(is_issue_url(&u));
        }
    }

    #[test]
    fn prop_the_servers_json_answer_is_checked_per_field(id in any::<String>(), url in any::<String>(), extra in json_leaf()) {
        let body = serde_json::to_vec(&json!({"id": id, "url": url, "x": extra})).unwrap();
        let s = parse_server_answer(&body);
        prop_assert!(s.url.is_none_or(|u| is_issue_url(&u)));
        prop_assert!(s.id.is_none_or(|i| i.len() <= 64 && i.is_ascii()));
    }

    #[test]
    fn prop_journal_output_of_any_bytes_is_read_without_panic(bytes in prop::collection::vec(any::<u8>(), 0..400)) {
        let got = journal_lines(&bytes);
        prop_assert!(got.len() <= bytes.iter().filter(|b| **b == b'\n').count() + 1);
    }

    #[test]
    fn prop_curl_status_lines_never_panic(t in nasty()) {
        prop_assert!(http_status(&t) < 1000);
    }

    #[test]
    fn prop_traces_parse_without_panic_into_at_most_one_frame_a_line(t in nasty()) {
        prop_assert!(parse_frames(&t).len() <= t.lines().count());
        let f = filter_trace(&t);
        prop_assert!(f.lines().count() <= t.lines().count());
    }

    #[test]
    fn prop_journal_arguments_are_plain_for_any_times(a in any::<u64>(), b in any::<Option<u64>>(), uid in nasty()) {
        for x in journal_args(a, b, Some(&uid)).into_iter().chain(journal_args(a, b, None)) {
            prop_assert!(x.starts_with(['-', '_', 'M', 'C']) || x == "json" || x == "500", "{x:?}");
            if x.starts_with("--since") || x.starts_with("--until") {
                prop_assert!(x.split_once('@').unwrap().1.bytes().all(|c| c.is_ascii_digit()));
            }
        }
    }

    #[test]
    fn prop_the_message_cap_holds_on_a_char_boundary(unit in "\\PC{0,40}", reps in 0usize..4000) {
        let s = unit.repeat(reps);
        let c = cap_message(&s);
        prop_assert!(c.len() <= MAX_MESSAGE + 64);
        if s.len() <= MAX_MESSAGE {
            prop_assert_eq!(c, s);
        }
    }

    #[test]
    fn prop_log_lines_are_short_and_plain(s in nasty()) {
        let l = log_text(&s);
        prop_assert!(l.chars().count() <= 400 && no_control(&l));
    }

    #[test]
    fn prop_a_trusted_entry_with_anything_in_it_parses_to_bounded_plain_values(e in entry()) {
        if let Some(d) = Coredump::parse(&e, "1000") {
            prop_assert!(d.comm.chars().count() <= 64 && no_control(&d.comm));
            prop_assert!(d.signal.chars().count() <= 64 && no_control(&d.signal));
            let t = d.time();
            prop_assert!(!t.is_empty() && t.len() <= 40);
            prop_assert!(t.chars().all(|c| c.is_ascii_digit() || "TZ:-+.".contains(c)));
            if !d.exe.is_empty() {
                prop_assert!(valid_exe(&d.exe) && clean(&d.exe, usize::MAX, false) == d.exe);
            }
            // a path that is there but odd is never the host's
            if d.origin == Origin::Host && d.exe.is_empty() {
                prop_assert!(field(&e, "COREDUMP_EXE").is_none());
            }
            // a program outside the OS is not reported unless it is a Flatpak app
            if d.origin == Origin::Host && !d.exe.is_empty() {
                prop_assert!(SYSTEM_PREFIXES.iter().any(|p| d.exe.starts_with(p)));
            }
            // trust never rested on a field the process can write
            let got = field(&e, "_COMM");
            prop_assert_eq!(got.as_deref(), Some("systemd-coredum"));
            let got = field(&e, "_UID");
            prop_assert_eq!(got.as_deref(), Some("1000"));
            let got = field(&e, "COREDUMP_UID");
            prop_assert_eq!(got.as_deref(), Some("1000"));
        }
    }
}

proptest! {
    // these read /proc and /sys for each report, or use the disk
    #![proptest_config(cfg(1000))]


    #[test]
    fn prop_markers_of_any_content_read_without_panic(bytes in prop::collection::vec(any::<u8>(), 0..120)) {
        let d = tempfile::tempdir().unwrap();
        let m = d.path().join("m");
        fs::write(&m, &bytes).unwrap();
        let _ = read_coredump_marker(&m);
        if let Some((t, _)) = read_event_marker(&m, &[]) {
            prop_assert!(looks_like_time(&t));
        }
    }

    #[test]
    fn prop_a_report_is_saved_only_under_a_plain_name_in_its_directory(time in nasty()) {
        let d = tempfile::tempdir().unwrap();
        let dir = d.path().join("pending");
        let mut r = sample();
        r.time = time.clone();
        match write_report(&dir, &r) {
            Ok(p) => {
                prop_assert_eq!(p.parent().unwrap(), dir.as_path());
                let n = p.file_name().unwrap().to_str().unwrap();
                prop_assert!(n.ends_with(".json") && !n.starts_with('.'));
                prop_assert!(n.chars().all(|c| c.is_ascii_digit() || "TZ:-+.json".contains(c)), "{n}");
                prop_assert!(!n.contains('/'));
            }
            Err(e) => prop_assert_eq!(e.kind(), io::ErrorKind::InvalidInput, "{:?}", time),
        }
        // and nothing was made outside the directory
        prop_assert_eq!(fs::read_dir(d.path()).unwrap().count() <= 1, true);
    }

    #[test]
    fn prop_the_rotating_id_is_always_32_hex_whatever_the_file_holds(bytes in prop::collection::vec(any::<u8>(), 0..80)) {
        let d = tempfile::tempdir().unwrap();
        fs::write(d.path().join("crash-id"), &bytes).unwrap();
        let id = crash_id_in(d.path(), SystemTime::now()).unwrap();
        prop_assert!(id.len() == 32 && id.bytes().all(|b| b.is_ascii_hexdigit()));
        prop_assert_eq!(crash_id_in(d.path(), SystemTime::now()).unwrap(), id);
    }

}

proptest! {
    // a process spawned, or /proc and /sys read, for each case
    #![proptest_config(cfg(200))]

    #[test]
    fn prop_a_report_from_any_entry_is_bounded_and_plain(e in entry()) {
        if let Some((_, r)) = coredump_report(&e, &sc(), "1000", |_| Some("pkg 1-1".into())) {
            prop_assert!(r.app_name.len() <= 8192 && no_control(&r.app_name), "{:?}", r.app_name);
            prop_assert!(r.message.len() <= 1024 && no_control(&r.message));
            prop_assert!(r.app_version.as_deref().is_none_or(|v| v.len() <= 1024 && no_control(v)));
            prop_assert!(r.stacktrace.len() <= 4 * 8192 + 64);
            prop_assert!(r.stacktrace.chars().all(|c| c == '\n' || !c.is_control()));
            prop_assert!(r.time.len() <= 40);
            prop_assert!(r.time.chars().all(|c| c.is_ascii_digit() || "TZ:-+.".contains(c)));
            prop_assert_eq!(r.report_type.as_str(), "coredump");
        }
    }
}

/// What every accepted DSN must satisfy (and anything else is `None`).
fn check_dsn(s: &str) -> Result<(), TestCaseError> {
    let Some(ep) = Endpoint::parse(s) else {
        return Ok(());
    };
    let url = &ep.store_url;
    let after = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"))
        .ok_or_else(|| TestCaseError::fail(format!("no scheme: {url}")))?;
    let host = after.split('/').next().unwrap();
    if url.starts_with("http://") {
        let h = host
            .strip_prefix("[::1]")
            .map(|_| "::1")
            .unwrap_or_else(|| host.rsplit_once(':').map_or(host, |x| x.0));
        prop_assert!(
            ["localhost", "127.0.0.1", "::1"].contains(&h),
            "http to {host}"
        );
    }
    prop_assert!(!host.is_empty() && !host.contains('@'), "{url}");
    prop_assert!(url.ends_with("/store/") && url.contains("/api/"));
    prop_assert!(
        url.chars()
            .all(|c| c.is_ascii_alphanumeric() || "-_.:/[]".contains(c)),
        "odd character in {url}"
    );
    prop_assert!(!url.contains("/../") && !url.contains("//",) || url.starts_with("http"));
    prop_assert!(url_part_ok(&ep.key));
    Ok(())
}
