//! Every kind of secret in fixtures/secrets.txt must be gone after scrubbing.
//!
//! The fixture holds templates (`{GHP}`, `{ALNUM_24_A}`, ...). The values are
//! built here at run time, with each well-known prefix assembled from pieces,
//! so no string that looks like a real token is committed.

use std::path::PathBuf;
use telamon_framework_system::crash::Scrubber;

const ALNUM: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
const UPPER_DIGITS: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const DIGITS: &str = "0123456789";
const HEX: &str = "0123456789abcdef";
const B64: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B64URL: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
const IDENT: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-";

/// `n` characters of `set`, the same every run for the same `seed`.
fn tail(seed: &str, set: &str, n: usize) -> String {
    let mut x = seed.bytes().fold(0xcbf2_9ce4_8422_2325u64, |h, b| {
        (h ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3)
    }) | 1;
    let set: Vec<char> = set.chars().collect();
    (0..n)
        .map(|_| {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            set[(x >> 11) as usize % set.len()]
        })
        .collect()
}

/// The value of `{name}`; None if the name is unknown.
fn build(name: &str) -> Option<String> {
    let t = |set, n| tail(name, set, n);
    Some(match name {
        "GHP" => [concat!("gh", "p_"), &t(ALNUM, 36)].concat(),
        "GHO" => [concat!("gh", "o_"), &t(ALNUM, 36)].concat(),
        "GH_FINE" => [
            concat!("github", "_pat_"),
            &t(ALNUM, 22),
            "_",
            &t(ALNUM, 59),
        ]
        .concat(),
        "GITLAB" => [concat!("gl", "pat-"), &t(IDENT, 20)].concat(),
        "SLACK_B" | "SLACK_P" | "SLACK_A" => [
            "xo",
            "x",
            &name[6..].to_lowercase(),
            "-",
            &t(DIGITS, 11),
            "-",
            &t(DIGITS, 12),
            "-",
            &t(ALNUM, 24),
        ]
        .concat(),
        "AWS_AKID" => [concat!("AK", "IA"), &t(UPPER_DIGITS, 16)].concat(),
        "GOOGLE" => [concat!("AI", "za"), &t(IDENT, 35)].concat(),
        "STRIPE" | "STRIPE_B" => [concat!("sk", "_li"), "ve_", &t(ALNUM, 24)].concat(),
        "JWT" => [
            concat!("e", "yJ"),
            &t(B64URL, 15),
            ".",
            concat!("e", "yJ"),
            &t(B64URL, 40),
            ".",
            &t(B64URL, 32),
        ]
        .concat(),
        "PEM_BEGIN_RSA" => ["-----BEGIN RSA ", "PRIVATE", " KEY-----"].concat(),
        "PEM_END_RSA" => ["-----END RSA ", "PRIVATE", " KEY-----"].concat(),
        "PEM_BEGIN" => ["-----BEGIN ", "PRIVATE", " KEY-----"].concat(),
        "PEM_END" => ["-----END ", "PRIVATE", " KEY-----"].concat(),
        "SSH_BEGIN" => ["-----BEGIN OPENSSH ", "PRIVATE", " KEY-----"].concat(),
        "SSH_END" => ["-----END OPENSSH ", "PRIVATE", " KEY-----"].concat(),
        _ => {
            // KIND_LENGTH or KIND_LENGTH_SUFFIX: ALNUM_24_A, B64_40_B, HEX_32_C
            let mut p = name.split('_');
            let set = match p.next()? {
                "ALNUM" => ALNUM,
                "HEX" => HEX,
                "B64" => B64,
                "B64URL" => B64URL,
                _ => return None,
            };
            t(set, p.next()?.parse().ok()?)
        }
    })
}

/// `text` with every `{NAME}` built. Braces around anything else (JSON) stay.
fn expand(text: &str) -> String {
    let mut out = String::new();
    let mut rest = text;
    while let Some(i) = rest.find('{') {
        out.push_str(&rest[..i]);
        rest = &rest[i..];
        let built = rest.find('}').and_then(|j| {
            let name = &rest[1..j];
            let plain = !name.is_empty()
                && name
                    .bytes()
                    .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'_');
            plain.then(|| build(name).map(|v| (v, j + 1)))?
        });
        match built {
            Some((v, used)) => {
                out.push_str(&v);
                rest = &rest[used..];
            }
            None => {
                out.push('{');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

/// (kind, secret, text), built, with "\n" turned into line breaks.
fn cases() -> Vec<(String, String, String)> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/secrets.txt");
    let text = std::fs::read_to_string(path).unwrap();
    text.lines()
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(|l| {
            let f: Vec<&str> = l.splitn(3, '\t').collect();
            assert_eq!(f.len(), 3, "bad fixture line: {l}");
            let un = |s: &str| expand(s).replace("\\n", "\n");
            (f[0].to_string(), un(f[1]), un(f[2]))
        })
        .collect()
}

fn scrubber() -> Scrubber {
    Scrubber::new(&["zachary"], &["fedora-box"], &["/home/zachary"])
}

/// Every case whose secret survived `scrub`, as lines.
fn leaks(scrub: impl Fn(&str) -> String) -> Vec<String> {
    let mut leaks = Vec::new();
    for (kind, secret, text) in cases() {
        assert!(
            text.contains(&secret),
            "{kind}: the fixture's secret is not in its text"
        );
        let out = scrub(&text);
        if out.contains(&secret) {
            leaks.push(format!("{kind}: {out:?}"));
        }
    }
    leaks
}

#[test]
fn scrub_removes_every_secret() {
    let s = scrubber();
    let l = leaks(|t| s.scrub(t));
    assert!(l.is_empty(), "scrub leaks:\n{}", l.join("\n"));
}

#[test]
fn scrub_message_removes_every_secret() {
    let s = scrubber();
    let l = leaks(|t| s.scrub_message(t));
    assert!(l.is_empty(), "scrub_message leaks:\n{}", l.join("\n"));
}

#[test]
fn the_test_bites() {
    // a scrubber that removes nothing must leak every case
    assert_eq!(leaks(str::to_string).len(), cases().len());
}

#[test]
fn built_values_have_the_shape_of_their_kind() {
    assert!(build("GHP").unwrap().len() == 40);
    assert!(build("AWS_AKID").unwrap().len() == 20);
    assert_eq!(
        expand(r#"{"a":"{ALNUM_5}"}"#).len(),
        r#"{"a":""}"#.len() + 5
    );
    assert_eq!(expand("{NOPE} {"), "{NOPE} {");
}

#[test]
fn the_fixture_covers_every_kind() {
    let kinds: Vec<String> = cases().into_iter().map(|c| c.0).collect();
    for want in [
        "github-ghp",
        "github-gho",
        "github-fine-grained",
        "gitlab",
        "slack-xoxb",
        "slack-xoxp",
        "slack-xoxa",
        "aws-access-key-id",
        "aws-secret-access-key",
        "google-api-key",
        "stripe-live",
        "jwt",
        "bearer",
        "basic-auth",
        "url-userinfo",
        "kv-password",
        "kv-passwd",
        "kv-token",
        "kv-api_key",
        "kv-secret",
        "json-password",
        "query-password",
        "pem-private-key-body",
        "ssh-ed25519-private-key",
        "sentry-dsn",
        "cookie",
        "set-cookie",
        "home-path",
        "pgpassword-env",
        "camelcase-password",
        "db-pass",
        "pass-assign",
        "oauth-code",
        "bearer-two-spaces",
        "bearer-tab",
        "basic-standalone",
        "hex-sha256",
        "hex-private-key",
        "base64-with-slash",
        "base64-padded",
        "slack-webhook-upper",
        "serial-key",
        "imei",
    ] {
        assert!(kinds.iter().any(|k| k == want), "no {want} case");
    }
}
