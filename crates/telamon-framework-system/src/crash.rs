//! Crash reports: the only telemetry a Telamon app may have. Opt-in, off by
//! default, and the user sees the exact payload before every send.
//!
//! - [`Settings`]: per-user switch, `~/.config/telamon/crash-reporting.toml`
//!   (`enabled = false`). When off, nothing is collected or written. Until
//!   that file exists the one framework 1.x kept, `~/.config/atlas/...`, counts.
//! - [`Endpoint`]: a Sentry-compatible DSN from
//!   `/etc/telamon/crash-reporting.toml` (else `/etc/atlas/...`, which an
//!   administrator of 1.x may have written), default `/usr/share/telamon/...`: the
//!   Telamon OS relay, which posts each report it gets as a **public** issue in
//!   github.com/EternalCoder454/AtlasOS. An empty dsn in `/etc` turns
//!   sending off: [`send`] then fails with "no endpoint configured".
//! - Sources: Rust panics ([`install`], [`record_fatal`]), systemd-coredump
//!   entries of the user's own processes on the host, not those of containers
//!   or of programs outside the OS ([`collect_coredumps`]) and update
//!   and rollback events from the helper ([`collect_events`]).
//! - Reports wait in `$XDG_STATE_HOME/telamon/crash-reports/pending/` for the
//!   user's decision ([`pending`], [`discard`]); sent ones move to `sent/`
//!   and are pruned after 90 days. The first time, the directory framework
//!   1.x used (`$XDG_STATE_HOME/atlas`: reports, markers, the rotating ID) is
//!   moved there whole, so reports waiting for a decision are not lost.
//!
//! Collected: Telamon OS version, channel, previous version; app name, version
//! and category; the stack trace; kernel; GPU model and driver; uptime (whole
//! hours, rounded down); CPU model, RAM total (whole GB) and use; a timestamp
//! and the report type. A rotating
//! random ID (new every 30 days; never `/etc/machine-id`) stays on the
//! machine: it is not sent, so public reports can't be linked to each other.
//! Never: core dumps, usernames, hostnames, MAC/IP addresses, email addresses,
//! credentials and tokens, installed apps, file contents, command
//! lines, environment or working directory. Every string is scrubbed
//! ([`Scrubber`]). The report collects no hardware serial number; one that
//! turns up in a message is hidden when it is named (`serial=`, `ID_SERIAL=`,
//! `imei=`) or has the shape of an IMEI, not in any other form.
//!
use std::cell::Cell;
use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::history::{self, now_rfc3339};

pub const SYSTEM_CONFIG: &str = "/etc/telamon/crash-reporting.toml";
pub const DEFAULT_CONFIG: &str = "/usr/share/telamon/crash-reporting.toml";
/// Where framework 1.x kept them (as `atlas`). Read after the ones above, so
/// an administrator's `dsn = ""` there still turns sending off.
pub const LEGACY_SYSTEM_CONFIG: &str = "/etc/atlas/crash-reporting.toml";
pub const LEGACY_DEFAULT_CONFIG: &str = "/usr/share/atlas/crash-reporting.toml";
const SENT_KEEP: Duration = Duration::from_secs(90 * 86_400);
const ID_MAX_AGE: Duration = Duration::from_secs(30 * 86_400);
const COREDUMP_MESSAGE_ID: &str = "fc2e22bc6ee647b6b90729ab34a250b1";

/// Identifies the Telamon app that installs the panic hook.
pub use telamon_framework_core::AppInfo;

/// One crash or event report. [`Report::payload`] is what gets sent.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Report {
    pub schema: u32,
    /// 32 hex chars; the Sentry event ID.
    pub event_id: String,
    /// `panic`, `fatal`, `coredump` or an event name such as `update-failed`.
    pub report_type: String,
    /// RFC 3339 UTC.
    pub time: String,
    /// The rotating anonymous ID.
    pub crash_id: String,
    pub atlasos_version: Option<String>,
    pub channel: Option<String>,
    pub previous_version: Option<String>,
    pub app_name: String,
    pub app_version: Option<String>,
    /// `Plasma`, `KWin`, `Telamon app` or `other`.
    pub category: String,
    pub message: String,
    pub stacktrace: String,
    pub kernel: Option<String>,
    pub gpu: Option<String>,
    pub gpu_driver: Option<String>,
    pub uptime_secs: u64,
    pub cpu_model: Option<String>,
    pub ram_total_kb: u64,
    pub mem_used_kb: u64,
    /// Server-side event ID once sent.
    #[serde(default)]
    pub sent_event_id: Option<String>,
    /// The public GitHub issue the relay filed for it, once sent.
    #[serde(default)]
    pub issue_url: Option<String>,
    /// Where the report is stored; not part of the report.
    #[serde(skip)]
    pub path: Option<PathBuf>,
}

/// The longest payload [`Report::payload`] makes, serialized, in bytes. A
/// longer one has its stack trace cut, and as a last resort its message.
pub const MAX_PAYLOAD: usize = 64 * 1024;

/// A message over this is cut first when the payload is too long.
const MESSAGE_BUDGET: usize = 8 * 1024;

impl Report {
    /// The exact Sentry event JSON that [`send`] posts. At most
    /// [`MAX_PAYLOAD`] bytes: when the report is bigger, frames are dropped
    /// from the far end of the stack (the top of the stack stays), then the
    /// message is cut; `extra.trace_frames_dropped` says how many frames went.
    /// Uptime is in whole hours and RAM total in whole GB, however the report
    /// stored them.
    pub fn payload(&self) -> Value {
        let frames = parse_frames(&self.stacktrace);
        let mut keep = frames.len();
        let mut message = self.message.clone();
        loop {
            let ev = self.event(
                &message,
                &frames[frames.len() - keep..],
                frames.len() - keep,
            );
            let size = serde_json::to_vec(&ev).map_or(0, |v| v.len());
            if size <= MAX_PAYLOAD {
                return ev;
            }
            if message.len() > MESSAGE_BUDGET {
                // the message is in the payload twice: it goes first, down to
                // a size that leaves room for a trace
                // (room left for the note)
                let mut end = MESSAGE_BUDGET - 16;
                while !message.is_char_boundary(end) {
                    end -= 1;
                }
                message.truncate(end);
                message.push_str(" [... cut]");
            } else if keep > 0 {
                keep /= 2;
            } else if message.is_empty() {
                // the other fields alone are too long: nothing left to cut
                return ev;
            } else if message.len() <= 32 {
                message.clear();
            } else {
                let mut end = message.len() / 2;
                while !message.is_char_boundary(end) {
                    end -= 1;
                }
                message.truncate(end);
                message.push_str(" [... cut]");
            }
        }
    }

    /// One Sentry event with `message` and the given frames.
    fn event(&self, message: &str, frames: &[Value], dropped: usize) -> Value {
        // a report file is only JSON: no field is trusted to be short
        let tag = |v: &Option<String>| {
            v.as_deref()
                .map_or_else(|| "unknown".to_string(), |s| s.chars().take(512).collect())
        };
        let (uptime, ram) = (
            coarse_uptime(self.uptime_secs),
            coarse_ram_kb(self.ram_total_kb),
        );
        let mut event = json!({
            "event_id": self.event_id,
            "timestamp": self.time,
            "platform": "native",
            "level": "fatal",
            "logger": "atlas-core",
            "release": format!("atlasos@{}", tag(&self.atlasos_version)),
            "environment": tag(&self.channel),
            "message": message,
            "tags": {
                "app": self.app_name,
                "app_version": tag(&self.app_version),
                "category": self.category,
                "atlasos_version": tag(&self.atlasos_version),
                "channel": tag(&self.channel),
                "previous_version": tag(&self.previous_version),
                "kernel": tag(&self.kernel),
                "gpu": tag(&self.gpu),
                "gpu_driver": tag(&self.gpu_driver),
                "report_type": self.report_type,
            },
            "contexts": {
                "os": {"name": "AtlasOS", "version": tag(&self.atlasos_version),
                       "kernel_version": tag(&self.kernel)},
                "gpu": {"name": tag(&self.gpu), "version": tag(&self.gpu_driver)},
                // saturating: a report file is only JSON, any number may be in it
                "device": {"cpu": tag(&self.cpu_model), "memory_size": ram.saturating_mul(1024),
                           "free_memory": ram.saturating_sub(self.mem_used_kb).saturating_mul(1024)},
                "runtime": {"uptime_secs": uptime},
            },
        });
        if !frames.is_empty() {
            event["exception"] = json!({"values": [{
                "type": self.report_type,
                "value": message,
                "stacktrace": {"frames": frames},
            }]});
        }
        if dropped > 0 {
            event["extra"] = json!({"trace_frames_dropped": dropped});
        }
        event
    }

    /// The payload as pretty JSON, for the "Show report" view.
    pub fn to_json_pretty(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(&self.payload())
    }
}

/// Frames in Sentry order (oldest call first) from a systemd-coredump style
/// (`#0  0x7f.. func (lib.so + 0x1)`) or Rust (`  0: func`) trace.
fn parse_frames(trace: &str) -> Vec<Value> {
    let mut frames = Vec::new();
    for line in trace.lines() {
        let l = line.trim();
        let (body, rust) = if let Some(rest) = l.strip_prefix('#') {
            (
                rest.split_once(char::is_whitespace)
                    .map_or("", |x| x.1)
                    .trim(),
                false,
            )
        } else if let Some((n, rest)) = l.split_once(": ")
            && !n.is_empty()
            && n.chars().all(|c| c.is_ascii_digit())
        {
            (rest.trim(), true)
        } else {
            continue;
        };
        if rust {
            frames.push(json!({"function": body}));
            continue;
        }
        let mut addr = None;
        let mut rest = body;
        if let Some(a) = body
            .split_whitespace()
            .next()
            .filter(|a| a.starts_with("0x"))
        {
            addr = Some(a.to_string());
            rest = body[a.len()..].trim();
        }
        let (func, module) = match rest.split_once('(') {
            Some((f, m)) => (
                f.trim(),
                m.trim_end_matches(')')
                    .split(" + ")
                    .next()
                    .unwrap_or("")
                    .trim(),
            ),
            None => (rest, ""),
        };
        let mut f = json!({"function": if func.is_empty() { "n/a" } else { func }});
        if let Some(a) = addr {
            f["instruction_addr"] = json!(a);
        }
        if !module.is_empty() {
            f["package"] = json!(module);
            f["module"] = json!(module);
        }
        frames.push(f);
    }
    frames.reverse();
    frames
}

// ---------------------------------------------------------------- settings

/// An environment path, only if absolute (XDG says to ignore the rest).
fn abs_env(name: &str) -> Option<PathBuf> {
    let v = PathBuf::from(std::env::var_os(name).filter(|v| !v.is_empty())?);
    v.is_absolute().then_some(v)
}

fn config_home() -> Option<PathBuf> {
    abs_env("XDG_CONFIG_HOME").or_else(|| Some(abs_env("HOME")?.join(".config")))
}

fn state_home() -> Option<PathBuf> {
    abs_env("XDG_STATE_HOME").or_else(|| Some(abs_env("HOME")?.join(".local/state")))
}

/// `key = "value"` / `key = true` lookup in a tiny TOML subset. `Some("")`
/// when the key is present but empty.
fn toml_value(text: &str, key: &str) -> Option<String> {
    text.lines().find_map(|l| {
        let l = l.split('#').next()?.trim();
        let (k, v) = l.split_once('=')?;
        (k.trim() == key).then(|| v.trim().trim_matches('"').to_string())
    })
}

/// The per-user opt-in. Off unless the file says `enabled = true`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Settings {
    pub enabled: bool,
}

impl Settings {
    pub fn path() -> Option<PathBuf> {
        Some(config_home()?.join("telamon/crash-reporting.toml"))
    }

    /// Where framework 1.x kept the switch (`~/.config/atlas/...`).
    pub fn legacy_path() -> Option<PathBuf> {
        Some(config_home()?.join("atlas/crash-reporting.toml"))
    }

    /// The switch: the file at [`path`](Self::path), or while there is none
    /// the one at [`legacy_path`](Self::legacy_path), so a user who opted in
    /// (or out) before 2.0.0 keeps that choice. [`save`](Self::save) writes
    /// the new file only; from then on the old one is not read.
    pub fn load() -> Settings {
        match (Self::path(), Self::legacy_path()) {
            (Some(new), Some(old)) => Self::load_either(&new, &old),
            (Some(new), None) => Self::load_from(&new),
            _ => Settings::default(),
        }
    }

    /// `new`, or `old` while `new` does not exist (not even as a link).
    fn load_either(new: &Path, old: &Path) -> Settings {
        if fs::symlink_metadata(new).is_ok() {
            Self::load_from(new)
        } else {
            Self::load_from(old)
        }
    }

    pub fn load_from(path: &Path) -> Settings {
        let on = fs::read_to_string(path)
            .ok()
            .and_then(|t| toml_value(&t, "enabled"))
            .is_some_and(|v| v == "true");
        Settings { enabled: on }
    }

    /// Save the setting. Turning reporting on starts the coredump and event
    /// markers at "now", so nothing from before the opt-in is ever queued.
    /// Turning it off deletes every pending and quarantined report; of the
    /// sent history only reports older than 90 days go, as on every
    /// `pending()` and `sent()`.
    pub fn save(&self) -> io::Result<()> {
        let p = Self::path().ok_or_else(|| io::Error::other("no config directory"))?;
        let was = Self::load().enabled;
        self.save_to(&p)?;
        if self.enabled && !was {
            reset_markers();
        }
        if !self.enabled {
            prune_sent();
            // Off means off: reports still waiting were queued under the old
            // opt-in and are not kept, nor are unreadable ones.
            if let Some(d) = reports_dir() {
                for sub in ["pending", QUARANTINE] {
                    for e in fs::read_dir(d.join(sub)).into_iter().flatten().flatten() {
                        let _ = fs::remove_file(e.path());
                    }
                }
            }
        }
        Ok(())
    }

    pub fn save_to(&self, path: &Path) -> io::Result<()> {
        if let Some(d) = path.parent() {
            fs::create_dir_all(d)?;
        }
        let text = format!(
            "# Telamon crash reporting; see docs. Off unless true.\nenabled = {}\n",
            self.enabled
        );
        // Temp file next to the target (never follows a symlink), then rename:
        // a planted symlink at `path` is replaced, not written through.
        let name = path.file_name().ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                "settings path has no file name",
            )
        })?;
        let mut tmp_name = name.to_os_string();
        tmp_name.push(format!(".tmp{}", std::process::id()));
        let tmp = path.with_file_name(tmp_name);
        let _ = fs::remove_file(&tmp);
        let res = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o644)
            .custom_flags(libc::O_NOFOLLOW)
            .open(&tmp)
            .and_then(|mut f| {
                f.write_all(text.as_bytes())?;
                f.sync_all()
            })
            .and_then(|()| fs::rename(&tmp, path));
        if res.is_err() {
            let _ = fs::remove_file(&tmp);
        }
        res
    }
}

/// A GlitchTip DSN: `https://<key>@<host>[/prefix]/<project>`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    pub key: String,
    /// Full store URL: `https://host/api/<project>/store/`.
    pub store_url: String,
}

fn url_part_ok(s: &str) -> bool {
    !s.is_empty()
        && s != "."
        && s != ".."
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || "-_.".contains(c))
}

impl Endpoint {
    /// The configured endpoint. If `/etc/telamon/crash-reporting.toml` (or
    /// `/etc/atlas/...`, from before 2.0.0) has a `dsn` key it alone decides
    /// (empty means none); only without the key does the shipped default apply.
    pub fn load() -> Option<Endpoint> {
        Self::load_from_files(&[
            SYSTEM_CONFIG,
            LEGACY_SYSTEM_CONFIG,
            DEFAULT_CONFIG,
            LEGACY_DEFAULT_CONFIG,
        ])
    }

    /// The first of `files` with a `dsn` key decides.
    fn load_from_files(files: &[&str]) -> Option<Endpoint> {
        for p in files {
            if let Some(v) = fs::read_to_string(p)
                .ok()
                .and_then(|t| toml_value(&t, "dsn"))
            {
                return Self::parse(&v);
            }
        }
        None
    }

    pub fn load_from(path: &Path) -> Option<Endpoint> {
        Self::parse(&toml_value(&fs::read_to_string(path).ok()?, "dsn")?)
    }

    /// `https` only; `http` is accepted for localhost, 127.0.0.1 and [::1].
    /// The key must be a plain public key (a legacy `key:secret` is refused).
    pub fn parse(dsn: &str) -> Option<Endpoint> {
        let (scheme, rest) = dsn.trim().split_once("://")?;
        let (key, rest) = rest.split_once('@')?;
        let (host, path) = rest.split_once('/')?;
        let (host_only, host_ok) = match host.strip_prefix("[::1]") {
            Some(port) => (
                "::1",
                port.is_empty()
                    || port
                        .strip_prefix(':')
                        .is_some_and(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_digit())),
            ),
            None => (
                host.rsplit_once(':').map_or(host, |x| x.0),
                !host.is_empty()
                    && host
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || "-.:".contains(c)),
            ),
        };
        let loopback = matches!(host_only, "localhost" | "127.0.0.1" | "::1");
        match scheme {
            "https" => {}
            "http" if loopback => {}
            _ => return None,
        }
        let segs: Vec<&str> = path.trim_matches('/').split('/').collect();
        if !host_ok || !url_part_ok(key) || !segs.iter().all(|s| url_part_ok(s)) {
            return None;
        }
        let (project, prefix) = segs.split_last()?;
        let prefix = if prefix.is_empty() {
            String::new()
        } else {
            format!("/{}", prefix.join("/"))
        };
        Some(Endpoint {
            key: key.into(),
            store_url: format!("{scheme}://{host}{prefix}/api/{project}/store/"),
        })
    }
}

/// Start both markers at "now": only crashes after this are ever collected.
fn reset_markers() {
    if let Some(d) = state_dir() {
        reset_markers_in(&d);
    }
}

fn reset_markers_in(dir: &Path) {
    let now_micros = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_micros() as u64);
    let _ = write_private(
        &dir.join("coredump-last"),
        now_micros.to_string().as_bytes(),
        true,
    );
    // Events already in the log with this very second's time are not new.
    let now = now_rfc3339();
    let same = crate::events::read(Path::new(crate::events::DEFAULT_PATH))
        .iter()
        .filter(|e| e.time == now)
        .count();
    let _ = write_private(
        &dir.join("events-last"),
        format!("{now} {same}").as_bytes(),
        true,
    );
}

// ---------------------------------------------------------------- scrubbing

/// Replaces home directories, user names, host names, MAC and IP addresses,
/// machine/boot IDs, email addresses, credentials and tokens in strings.
/// Matching is case-insensitive.
#[derive(Debug, Clone, Default)]
pub struct Scrubber {
    users: Vec<String>,
    hosts: Vec<String>,
    homes: Vec<String>,
}

/// The names and home directories of `uid` in /etc/passwd `text`: the login
/// name, the full name (the first GECOS field) as a whole and each word of it
/// of 3 or more characters (a report may say "Smith" or "zachary" alone), and
/// the home.
fn passwd_names(text: &str, uid: &str) -> (Vec<String>, Vec<String>) {
    let (mut users, mut homes) = (Vec::new(), Vec::new());
    for l in text.lines() {
        let f: Vec<&str> = l.split(':').collect();
        if f.len() >= 6 && f[2] == uid {
            users.push(f[0].to_string());
            if let Some(full) = f[4].split(',').next() {
                users.push(full.to_string());
                users.extend(
                    full.split_whitespace()
                        .map(|w| w.trim_matches(|c: char| !c.is_alphanumeric()))
                        .filter(|w| w.chars().count() >= 3)
                        .map(str::to_string),
                );
            }
            homes.push(f[5].to_string());
        }
    }
    (users, homes)
}

/// Names too common to hide: scrubbing them would mangle ordinary text
/// (`/dev/null`, `atlas_core::...`, image names), and a home directory
/// called after one is still handled by the `/home/<name>` rule.
const COMMON_NAMES: &[&str] = &[
    "telamon",
    "atlas",
    "user",
    "users",
    "test",
    "admin",
    "root",
    "fedora",
    "localhost",
    "host",
    "dev",
    "pc",
    "bin",
    "usr",
    "home",
    "tmp",
    "var",
    "etc",
    "local",
    "localdomain",
    "laptop",
    "desktop",
    "nobody",
    "guest",
    "default",
    "core",
    "updater",
    "eterneon",
    "linux",
    "system",
    "computer",
];

fn clean_list(items: impl IntoIterator<Item = String>) -> Vec<String> {
    let mut v: Vec<String> = items
        .into_iter()
        .map(|s| s.trim().to_string())
        .filter(|s| s.chars().count() >= 2)
        .filter(|s| !COMMON_NAMES.iter().any(|c| c.eq_ignore_ascii_case(s)))
        .collect();
    v.sort_by_key(|s| std::cmp::Reverse(s.len()));
    v.dedup_by(|a, b| a.eq_ignore_ascii_case(b));
    v
}

impl Scrubber {
    /// `users` are user names and full names, `hosts` host names (their first
    /// label is added), `homes` literal home directories.
    pub fn new(users: &[&str], hosts: &[&str], homes: &[&str]) -> Self {
        use unicode_normalization::UnicodeNormalization;
        let mut h: Vec<String> = hosts.iter().map(|s| s.to_string()).collect();
        h.extend(
            hosts
                .iter()
                .filter_map(|s| s.split('.').next().map(str::to_string)),
        );
        Scrubber {
            users: clean_list(users.iter().map(|s| s.to_string())),
            hosts: clean_list(h),
            homes: clean_list(
                homes
                    .iter()
                    // NFC like the text they are matched against (`scrub`)
                    .map(|s| s.trim_end_matches('/').nfc().collect::<String>())
                    .filter(|s| s.len() > 1),
            ),
        }
    }

    /// Everything about this user and machine that could identify them:
    /// $USER, $LOGNAME, $HOME, the passwd name, full name and home, and the
    /// kernel, static and pretty host names.
    pub fn from_env() -> Self {
        let mut users: Vec<String> = ["USER", "LOGNAME"]
            .iter()
            .filter_map(|k| std::env::var(k).ok())
            .collect();
        let mut homes: Vec<String> = std::env::var("HOME").ok().into_iter().collect();
        if let Some(h) = homes.first() {
            users.extend(
                Path::new(h)
                    .file_name()
                    .map(|n| n.to_string_lossy().into_owned()),
            );
        }
        let (u, h) = passwd_names(&read("/etc/passwd"), &own_uid());
        users.extend(u);
        homes.extend(h);
        let mut hosts = vec![read("/proc/sys/kernel/hostname"), read("/etc/hostname")];
        hosts.extend(toml_value(&read("/etc/machine-info"), "PRETTY_HOSTNAME"));
        let (u, h, hm): (Vec<&str>, Vec<&str>, Vec<&str>) = (
            users.iter().map(String::as_str).collect(),
            hosts.iter().map(String::as_str).collect(),
            homes.iter().map(String::as_str).collect(),
        );
        Scrubber::new(&u, &h, &hm)
    }

    /// Only the host names (for the root helper, which has no user).
    pub fn for_system() -> Self {
        let mut hosts = vec![read("/proc/sys/kernel/hostname"), read("/etc/hostname")];
        hosts.extend(toml_value(&read("/etc/machine-info"), "PRETTY_HOSTNAME"));
        let h: Vec<&str> = hosts.iter().map(String::as_str).collect();
        Scrubber::new(&[], &h, &[])
    }

    /// `/home/<name>` and `/var/home/<name>` become `.../USER`, user names
    /// `USER`, host names `HOST`; MAC and IP addresses, interface names with
    /// a MAC, and machine/boot IDs go.
    ///
    /// The text is normalized to NFC first (the result stays NFC), so a name
    /// typed with combining marks still matches. Remaining limits: case
    /// folding is per character, so `ß` does not match `SS`, and `İ` only
    /// matches itself.
    pub fn scrub(&self, s: &str) -> String {
        use unicode_normalization::UnicodeNormalization;
        let s: String = s.nfc().collect();
        let mut out = scrub_homes(&s);
        for h in &self.homes {
            out = out.replace(h.as_str(), "/home/USER");
        }
        for u in &self.users {
            out = replace_ci(&out, u, "USER");
        }
        for h in &self.hosts {
            out = replace_ci(&out, h, "HOST");
        }
        scrub_addresses(&scrub_hex(&scrub_blobs(&scrub_webhooks(&scrub_secrets(
            &out,
        )))))
    }

    /// [`scrub`](Self::scrub), then hide paths that can name a file the user
    /// had open. For panic messages and stack traces.
    pub fn scrub_message(&self, s: &str) -> String {
        redact_paths(&self.scrub(s))
    }
}

/// Replace the name after `/home/` and `/var/home/` with `USER`.
fn scrub_homes(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find("/home/") {
        let end = i + "/home/".len();
        out.push_str(&rest[..end]);
        rest = &rest[end..];
        let name_end = rest
            .find(|c: char| c == '/' || c.is_whitespace() || "'\"`:;,)>]".contains(c))
            .unwrap_or(rest.len());
        if name_end > 0 {
            out.push_str("USER");
        }
        rest = &rest[name_end..];
    }
    out.push_str(rest);
    out
}

/// Case-insensitive replace of a whole name: it matches where no letter
/// touches it (digits, `_` and punctuation do not count, so `zach1` and
/// `backup-zach2024` are scrubbed but `zachary` and `channel` stay).
fn replace_ci(s: &str, needle: &str, with: &str) -> String {
    // One char at a time, so byte offsets always refer to `s` (a lowercase
    // form can be longer than the original, so the strings are never
    // lowercased whole). A char whose lowercase is not a single char is
    // compared as it is.
    fn fold(c: char) -> char {
        let mut l = c.to_lowercase();
        match (l.next(), l.next()) {
            (Some(x), None) => x,
            _ => c,
        }
    }
    use unicode_normalization::UnicodeNormalization;
    let pat: Vec<char> = needle.nfc().map(fold).collect();
    if pat.is_empty() {
        return s.to_string();
    }
    let hay: Vec<(usize, char)> = s.char_indices().map(|(i, c)| (i, fold(c))).collect();
    let byte_at = |p: usize| hay.get(p).map_or(s.len(), |h| h.0);
    let mut out = String::with_capacity(s.len());
    let (mut pos, mut p) = (0, 0);
    while p + pat.len() <= hay.len() {
        if hay[p..p + pat.len()]
            .iter()
            .map(|h| h.1)
            .eq(pat.iter().copied())
        {
            let (at, end) = (byte_at(p), byte_at(p + pat.len()));
            // a combining mark belongs to the letter before it
            let letter = |c: Option<char>| {
                c.is_some_and(|c| {
                    c.is_alphabetic() || unicode_normalization::char::is_combining_mark(c)
                })
            };
            let whole = !letter(s[..at].chars().next_back()) && !letter(s[end..].chars().next());
            out.push_str(&s[pos..at]);
            out.push_str(if whole { with } else { &s[at..end] });
            pos = end;
            p += pat.len();
        } else {
            p += 1;
        }
    }
    out.push_str(&s[pos..]);
    out
}

fn is_mac(t: &str) -> bool {
    let sep = if t.contains(':') { ':' } else { '-' };
    let parts: Vec<&str> = t.split(sep).collect();
    parts.len() == 6
        && parts
            .iter()
            .all(|p| p.len() == 2 && p.chars().all(|c| c.is_ascii_hexdigit()))
}

fn is_ipv4(t: &str) -> bool {
    t.parse::<std::net::Ipv4Addr>().is_ok()
}

/// A real IPv6 address, not a Rust path like `c2::e1`: it must parse, hold a
/// digit, and look like one (starts with `::`, has a 4-digit first group, or
/// is long).
fn is_ipv6(t: &str) -> bool {
    t.parse::<std::net::Ipv6Addr>().is_ok()
        && t.chars().any(|c| c.is_ascii_digit())
        && (t.starts_with("::")
            || t.split(':').next().is_some_and(|g| g.len() == 4)
            || t.matches(':').count() >= 3)
}

fn all_hex(t: &str) -> bool {
    !t.is_empty() && t.chars().all(|c| c.is_ascii_hexdigit())
}

/// 15 digits with a valid Luhn check digit: the shape of an IMEI. (One in ten
/// other 15-digit numbers passes the check too; there are few of them.)
fn is_imei(t: &str) -> bool {
    if t.len() != 15 || !t.bytes().all(|b| b.is_ascii_digit()) {
        return false;
    }
    let sum: u32 = t
        .bytes()
        .rev()
        .enumerate()
        .map(|(i, b)| {
            let d = u32::from(b - b'0');
            if i % 2 == 1 {
                let x = d * 2;
                x / 10 + x % 10
            } else {
                d
            }
        })
        .sum();
    sum.is_multiple_of(10)
}

/// What a whole word is, if it is an address or ID: `<mac>`, `<ip>` or `<id>`.
fn classify(word: &str) -> Option<&'static str> {
    let mut w = word;
    if let Some((head, _zone)) = w.split_once('%')
        && head.contains(':')
    {
        w = head;
    }
    if let Some((h, port)) = w.rsplit_once(':')
        && is_ipv4(h)
        && !port.is_empty()
        && port.chars().all(|c| c.is_ascii_digit())
    {
        w = h;
    }
    let has_letter = w.chars().any(|c| c.is_ascii_alphabetic());
    let dotted_mac = {
        let p: Vec<&str> = w.split('.').collect();
        p.len() == 3 && p.iter().all(|x| x.len() == 4 && all_hex(x))
    };
    let uuid = {
        let p: Vec<&str> = w.split('-').collect();
        p.len() == 5
            && p.iter()
                .zip([8, 4, 4, 4, 12])
                .all(|(x, n)| x.len() == n && all_hex(x))
    };
    let iface = w.len() == 15 && (w.starts_with("enx") || w.starts_with("wlx")) && all_hex(&w[3..]);
    if is_mac(w) || dotted_mac || iface || (w.len() == 12 && all_hex(w) && has_letter) {
        Some("<mac>")
    } else if is_ipv4(w) || is_ipv6(w) {
        Some("<ip>")
    } else if (w.len() == 32 && all_hex(w)) || uuid {
        Some("<id>")
    } else if w.len() >= 40 && all_hex(w) {
        // SHA-1 and SHA-256 digests, key material in hex
        Some("<id>")
    } else if is_imei(w) {
        Some("<id>")
    } else {
        None
    }
}

fn scrub_word(tok: &str) -> String {
    // trailing sentence dot or colon (but keep the `::` of `2001:db8::`)
    let mut core = tok.trim_end_matches('.');
    if core.ends_with(':') && !core.ends_with("::") {
        core = &core[..core.len() - 1];
    }
    let suffix = &tok[core.len()..];
    if let Some(k) = classify_secret(core) {
        return format!("{k}{suffix}");
    }
    if let Some(k) = classify(core) {
        return format!("{k}{suffix}");
    }
    // a label in front: `host:10.0.0.1`, `inet:192.168.0.2` (not in a long
    // word: every colon would classify the rest, which is quadratic)
    for (i, _) in core.match_indices(':').filter(|_| core.len() <= 128) {
        if let Some(k) = classify(&core[i + 1..]) {
            return format!("{}:{k}{suffix}", &core[..i]);
        }
    }
    tok.to_string()
}

/// Names whose value is a secret: `token=...`, `Password: ...`,
/// `access_token=...`, `Authorization: Bearer ...`; also identifiers that
/// name one device (`serial=`, `ID_SERIAL=`, `imei=`).
const SECRET_KEYS: &[&str] = &[
    "token",
    "secret",
    "password",
    "passwd",
    "pwd",
    "pass",
    "passphrase",
    "key",
    "apikey",
    "auth",
    "authorization",
    "bearer",
    "basic",
    "credential",
    "credentials",
    "session",
    "sessionid",
    "cookie",
    "signature",
    "sig",
    "code",
    "code_verifier",
    "serial",
    "serialnumber",
    "serial_number",
    "serial_short",
    "imei",
];

/// Names that count at the end of a longer word too (`PGPASSWORD`,
/// `dbPassword`, `csrftoken`). The short ones do not: `monkey` is no key.
/// (A name also starts after a lower case letter in camel case: `apiKey`.)
const INNER_KEYS: &[&str] = &[
    "token",
    "secret",
    "password",
    "passwd",
    "passphrase",
    "apikey",
    "authorization",
    "credential",
    "credentials",
];

/// Where a name starts: at a word, after `_`, `-` or punctuation, at a
/// camel case boundary, or (for [`INNER_KEYS`]) inside a word.
fn name_starts(b: &[u8], i: usize, key: &str) -> bool {
    let Some(p) = i.checked_sub(1).map(|p| b[p]) else {
        return true;
    };
    !p.is_ascii_alphanumeric()
        || INNER_KEYS.contains(&key)
        || (b[i].is_ascii_uppercase() && (p.is_ascii_lowercase() || p.is_ascii_digit()))
}

/// `Word`, `word` or `WordWord`: letters only, every capital followed by a
/// lower case letter, ending in one. Real base64 is not.
fn wordy(t: &[u8]) -> bool {
    t.iter().all(u8::is_ascii_alphabetic)
        && t.last().is_some_and(u8::is_ascii_lowercase)
        && t.windows(2)
            .all(|w| !w[0].is_ascii_uppercase() || w[1].is_ascii_lowercase())
}

/// What follows `Basic `: a base64 credential (`dXNlcjpwYXNz`), not a word
/// of the text (`Basic configuration`).
fn basic_credential(rest: &[u8]) -> bool {
    let n = rest
        .iter()
        .position(|c| !(c.is_ascii_alphanumeric() || b"+/=_-".contains(c)))
        .unwrap_or(rest.len());
    n >= 12 && !wordy(&rest[..n])
}

/// Hide the value after a [`SECRET_KEYS`] name (`=`, `:` or, for `bearer`
/// and `basic`, a space). A name counts at the end of a word (`access_token`,
/// `api-key`) but not inside one (`monkey`), nor as part of a `::` path
/// (`zbus::auth::handshake`, `Session::open`). A quoted value is hidden up to
/// its closing quote, spaces and all. `pass` needs a `=`, `code` a URL query
/// (`?code=`), and `basic` a base64 credential after it.
fn scrub_secrets(s: &str) -> String {
    // Bytes, not str slices: a name only starts on an ASCII byte, and text
    // around it may be any UTF-8.
    let lower = s.to_ascii_lowercase().into_bytes();
    let b = s.as_bytes();
    let mut out = String::with_capacity(s.len());
    let mut copied = 0;
    let mut i = 0;
    while i < b.len() {
        let key = SECRET_KEYS.iter().find(|k| {
            lower[i..].starts_with(k.as_bytes())
                && !b
                    .get(i + k.len())
                    .is_some_and(|c| c.is_ascii_alphanumeric() || *c == b'_' || *c == b'-')
        });
        let Some(key) = key.filter(|k| name_starts(b, i, k)) else {
            i += 1;
            continue;
        };
        let mut j = i + key.len();
        // `code` only in a URL query: `?code=abc&state=x`
        if matches!(*key, "code" | "code_verifier")
            && !(i > 0 && matches!(b[i - 1], b'?' | b'&') && b.get(j) == Some(&b'='))
        {
            i += key.len();
            continue;
        }
        let quoted_name = matches!(b.get(j), Some(b'"' | b'\''));
        // `"key": "value"`, `key = value`, `Bearer value`
        while j < b.len() && matches!(b[j], b' ' | b'\t' | b'"' | b'\'') {
            j += 1;
        }
        let sep = j < b.len() && matches!(b[j], b'=' | b':');
        // `pass` is a common word: `pass=x` or `"pass": "x"`, not `pass: 3`
        // `basic` is one too: only `Basic <credential>`
        if (*key == "pass" && sep && b[j] == b':' && !quoted_name) || (*key == "basic" && sep) {
            i += key.len();
            continue;
        }
        let path = |at: usize| b.get(at..at + 2) == Some(b"::".as_slice());
        // `zbus::auth::x`, `Session::open`; but `cfg::password=x` is a value
        let assign = sep && !path(j);
        if (sep && path(j)) || (i >= 2 && path(i - 2) && !assign) {
            i += key.len();
            continue;
        }
        let mut quote = None;
        if sep {
            j += 1;
            while j < b.len() && matches!(b[j], b' ' | b'\t') {
                j += 1;
            }
            if j < b.len() && matches!(b[j], b'"' | b'\'') {
                quote = Some(b[j]);
                j += 1;
            }
            // `Authorization: Bearer x`: hide the word after the scheme too
            // (any number of spaces or tabs between them)
            for scheme in ["bearer", "basic", "token"] {
                if lower[j..].starts_with(scheme.as_bytes())
                    && matches!(b.get(j + scheme.len()), Some(b' ' | b'\t'))
                {
                    j += scheme.len();
                    while j < b.len() && matches!(b[j], b' ' | b'\t') {
                        j += 1;
                    }
                }
            }
        } else {
            let value = j > i + key.len();
            let ok = match *key {
                "bearer" => value,
                "basic" => value && basic_credential(&b[j..]),
                _ => false,
            };
            if !ok {
                i += key.len();
                continue;
            }
        }
        let end = match quote {
            // up to the closing quote (not an escaped one), else the end of
            // the line; `""` hides nothing
            Some(q) => {
                let mut k = j;
                while k < b.len() && b[k] != q && b[k] != b'\n' {
                    k += if b[k] == b'\\' { 2 } else { 1 };
                }
                k.min(b.len())
            }
            None => b[j..]
                .iter()
                .position(|c| c.is_ascii_whitespace() || b"&\"',;)]}<>".contains(c))
                .map_or(b.len(), |n| j + n),
        };
        if end > j {
            out.push_str(&s[copied..j]);
            out.push_str("REDACTED");
            copied = end;
        }
        i = end.max(i + 1);
    }
    out.push_str(&s[copied..]);
    out
}

/// Where a service hands out a secret in the URL path itself.
const WEBHOOKS: &[&str] = &[
    "hooks.slack.com/services/",
    "discord.com/api/webhooks/",
    "discordapp.com/api/webhooks/",
];

/// `https://hooks.slack.com/services/T0/B0/xyz` (any case): the rest of the
/// path is the secret.
fn scrub_webhooks(s: &str) -> String {
    let lower = s.to_ascii_lowercase().into_bytes();
    let b = s.as_bytes();
    let mut out = String::with_capacity(s.len());
    let (mut copied, mut i) = (0, 0);
    while i < b.len() {
        let Some(h) = WEBHOOKS
            .iter()
            .find(|h| lower[i..].starts_with(h.as_bytes()))
        else {
            i += 1;
            continue;
        };
        let start = i + h.len();
        let end = b[start..]
            .iter()
            .position(|c| c.is_ascii_whitespace() || b"\"'`<>)]}".contains(c))
            .map_or(b.len(), |n| start + n);
        if end > start {
            out.push_str(&s[copied..start]);
            out.push_str("<token>");
            copied = end;
        }
        i = end.max(i + 1);
    }
    out.push_str(&s[copied..]);
    out
}

/// A base64 secret the word rules cut in pieces: it holds a `/` (which ends a
/// word) or ends in `=` padding. The whole run becomes `<token>` when it is
/// long, mixed case, has digits (or `+`, or padding) and a path's few slashes
/// do not make it up (`/usr/lib64/Foo/Bar2` is no secret).
fn scrub_blobs(s: &str) -> String {
    let b = s.as_bytes();
    let body = |c: u8| c.is_ascii_alphanumeric() || matches!(c, b'+' | b'/' | b'_' | b'-');
    let mut out = String::with_capacity(s.len());
    let (mut copied, mut i) = (0, 0);
    while i < b.len() {
        if !body(b[i]) {
            i += 1;
            continue;
        }
        let start = i;
        while i < b.len() && body(b[i]) {
            i += 1;
        }
        let run = &b[start..i];
        let pad = b[i..].iter().take(2).take_while(|c| **c == b'=').count();
        let after = b.get(i + pad).copied();
        // `==` is padding; one `=` only before the end of the value (a long
        // `settingName=value` is no secret)
        let padded = pad == 2
            || (pad == 1
                && match after {
                    None => true,
                    Some(c) if c.is_ascii_whitespace() || matches!(c, b',' | b';') => true,
                    Some(c @ (b'"' | b'\'')) => start > 0 && b[start - 1] == c,
                    Some(_) => false,
                });
        let slashes = run.iter().filter(|c| **c == b'/').count();
        let count = |f: fn(&u8) -> bool| run.iter().filter(|c| f(c)).count();
        let (digits, plus) = (count(u8::is_ascii_digit), run.contains(&b'+'));
        // random enough: `==` is enough by itself, one `=` wants a digit
        let random = if pad == 2 && padded {
            true
        } else if padded {
            digits >= 1 || plus
        } else {
            digits >= 2 || plus
        };
        if run.len() >= 24
            && (slashes > 0 || padded)
            && run[0] != b'/'
            && slashes * 12 <= run.len()
            && count(u8::is_ascii_uppercase) > 0
            && count(u8::is_ascii_lowercase) > 0
            && random
        {
            let end = if padded { i + pad } else { i };
            out.push_str(&s[copied..start]);
            out.push_str("<token>");
            copied = end;
            i = end;
        }
    }
    out.push_str(&s[copied..]);
    out
}

/// Every run of 40 or more hex digits (a SHA-1 or SHA-256 digest, key
/// material) becomes `<id>`, wherever it sits in a word: `build-<hex>`,
/// `0x<hex>`, `<hex>.json`. The compiler commit after `/rustc/` stays.
fn scrub_hex(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = String::with_capacity(s.len());
    let (mut copied, mut i) = (0, 0);
    while i < b.len() {
        if !b[i].is_ascii_hexdigit() {
            i += 1;
            continue;
        }
        let start = i;
        while i < b.len() && b[i].is_ascii_hexdigit() {
            i += 1;
        }
        if i - start >= 40 && !s[..start].ends_with("/rustc/") {
            out.push_str(&s[copied..start]);
            out.push_str("<id>");
            copied = i;
        }
    }
    out.push_str(&s[copied..]);
    out
}

/// systemd unit suffixes: `user@1000.service` is a unit, not an address.
const UNIT_SUFFIXES: &[&str] = &[
    ".service",
    ".socket",
    ".target",
    ".slice",
    ".scope",
    ".mount",
    ".timer",
    ".path",
    ".device",
    ".swap",
    ".automount",
];

/// `<email>` for an email address, `REDACTED@host` for credentials in a
/// URL (`user:pass@host`), `<token>` for an access token or key.
fn classify_secret(w: &str) -> Option<String> {
    if let Some(at) = w.rfind('@')
        && at > 0
        && at + 1 < w.len()
    {
        let (local, domain) = (&w[..at], &w[at + 1..]);
        if local == "REDACTED" {
            // the result of this function: scrubbing again changes nothing
            return None;
        }
        if local.contains(':') {
            return Some(format!("REDACTED@{domain}"));
        }
        let tld = domain.rsplit('.').next().unwrap_or_default();
        let unit = UNIT_SUFFIXES.iter().any(|u| domain.ends_with(u));
        if domain.contains('.')
            && !unit
            && tld.len() >= 2
            && tld.chars().all(|c| c.is_ascii_alphabetic())
        {
            return Some("<email>".into());
        }
    }
    const PREFIXES: &[&str] = &[
        "ghp_",
        "gho_",
        "ghu_",
        "ghs_",
        "ghr_",
        "github_pat_",
        "glpat-",
        "sk-",
        "xoxb-",
        "xoxp-",
        "xoxa-",
        "xoxs-",
        "AKIA",
        "ASIA",
        "eyJ",
    ];
    let tokenish = |c: char| c.is_ascii_alphanumeric() || "_-+.~".contains(c);
    if w.len() >= 16 && w.chars().all(tokenish) && PREFIXES.iter().any(|p| w.starts_with(p)) {
        return Some("<token>".into());
    }
    // A long random-looking word: upper and lower case letters and digits
    // (hex IDs, symbol hashes and words are one case or have no digits).
    if w.len() >= 24
        && w.chars().all(tokenish)
        && !w.starts_with("_ZN")
        && w.chars().any(|c| c.is_ascii_uppercase())
        && w.chars().any(|c| c.is_ascii_lowercase())
        && w.chars().filter(|c| c.is_ascii_digit()).count() >= 2
    {
        return Some("<token>".into());
    }
    None
}

/// Replace MAC, IP addresses and machine/boot IDs with `<mac>`, `<ip>`, `<id>`.
fn scrub_addresses(s: &str) -> String {
    let delim = |c: char| c.is_whitespace() || "'\"`(),;[]{}<>=/|\\".contains(c);
    let mut out = String::with_capacity(s.len());
    let mut tok = String::new();
    // the word before the last delimiter, and that delimiter
    let (mut prev, mut sep) = (String::new(), ' ');
    // `/rustc/<40 hex>/library/...`: the commit of the compiler, in every
    // panic location of the standard library
    let word = |tok: &str, prev: &str, sep: char| {
        if sep == '/' && prev == "rustc" && tok.len() >= 40 && all_hex(tok) {
            tok.to_string()
        } else {
            scrub_word(tok)
        }
    };
    for c in s.chars() {
        if delim(c) {
            out.push_str(&word(&tok, &prev, sep));
            if !tok.is_empty() {
                prev = std::mem::take(&mut tok);
            }
            sep = c;
            out.push(c);
        } else {
            tok.push(c);
        }
    }
    out.push_str(&word(&tok, &prev, sep));
    out
}

const PRIVATE_PREFIXES: &[&str] = &[
    "/home/",
    "/var/home/",
    "/run/user/",
    "/run/media/",
    "/media/",
    "/mnt/",
    "/var/mnt/",
    "/tmp/",
    "/var/tmp/",
    "/root",
    "/var/roothome",
    "/srv/",
    "file://",
    "~/",
];

/// Prefixes that name a private place wherever they appear in a token
/// (`/sysroot/ostree/deploy/default/var/home/zach/...`).
const ANYWHERE: &[&str] = &[
    "/home/",
    "/var/home/",
    "/run/media/",
    "/run/user/",
    "/var/roothome",
];

/// A private prefix starting at byte `i` of `s`, if any. Most must start a path
/// (not sit inside a longer name: `/usr/tmp/x` is not `/tmp/`), and `/root`
/// must not be the start of `/rootfs`; [`ANYWHERE`] ones match anywhere.
fn private_prefix_at(s: &str, i: usize) -> bool {
    let rest = &s[i..];
    let Some(p) = PRIVATE_PREFIXES.iter().find(|p| rest.starts_with(**p)) else {
        return false;
    };
    let anywhere = ANYWHERE.contains(p);
    let before = s[..i].chars().next_back();
    if !anywhere && before.is_some_and(|c| c.is_alphanumeric() || "_.-/".contains(c)) {
        return false;
    }
    if !p.ends_with('/') && p.starts_with('/') {
        // `/root`, `/var/roothome`: the whole last component
        return !rest[p.len()..]
            .chars()
            .next()
            .is_some_and(|c| c.is_alphanumeric() || "_.-".contains(c));
    }
    true
}

/// Directories whose contents belong to the system, not to the user: a path
/// under one of them is shown. Any other absolute path may name a file the
/// user had open (`/data/clients/Acme/q3.xlsx`, `/storage/photos/me.jpg`,
/// `/Volumes/x`) and is hidden. (`/run/user`, `/run/media` and the places of
/// [`PRIVATE_PREFIXES`] are hidden first.) `/rustc` and `/builddir` are where
/// the standard library and a package build remap their sources to.
const SYSTEM_DIRS: &[&str] = &[
    "usr",
    "bin",
    "sbin",
    "lib",
    "lib64",
    "opt",
    "app",
    "etc",
    "proc",
    "sys",
    "dev",
    "boot",
    "run",
    "sysroot",
    "ostree",
    "rustc",
    "builddir",
    "var/lib/flatpak",
    "var/lib/telamon",
    "var/lib/atlas-core",
    "var/log",
];

/// Whether the path at the start of `rest` is under a [`SYSTEM_DIRS`] entry
/// (or is one): `/usr/lib/x`, `/etc`, but not `/usr.bak` or `/devices`.
fn under_system_dir(rest: &str) -> bool {
    let Some(r) = rest.strip_prefix('/') else {
        return false;
    };
    SYSTEM_DIRS.iter().any(|d| {
        r.strip_prefix(d).is_some_and(|more| {
            !more.starts_with(|c: char| c.is_alphanumeric() || "_.-".contains(c))
        })
    })
}

/// An absolute path starting at byte `i` of `s` that is not the system's: it
/// starts a word (after a space, a quote, a bracket, `=`, `,`, `;`, `|` or
/// `:`; not `://` of a URL, not `</div>`, not a Qt resource `qrc:/...`), and
/// is not under a [`SYSTEM_DIRS`] entry.
fn foreign_path_at(s: &str, i: usize) -> bool {
    let rest = &s[i..];
    let mut chars = rest.chars();
    if chars.next() != Some('/') {
        return false;
    }
    if !chars
        .next()
        .is_some_and(|c| c.is_alphanumeric() || "._-~@+".contains(c))
    {
        return false;
    }
    let before = &s[..i];
    let starts_word = before
        .chars()
        .next_back()
        .is_none_or(|c| c.is_whitespace() || "'\"`([{=,;|:".contains(c));
    // Qt resources, not files: `qrc:/qt/qml/...` and `:/icons/x.png`
    let resource = before.strip_suffix(':').is_some_and(|b| {
        b.ends_with("qrc") || !b.chars().next_back().is_some_and(char::is_alphanumeric)
    });
    starts_word && !resource && !under_system_dir(rest)
}

/// The libc texts of the errors that may follow a redacted path.
const KNOWN_REASONS: &[&str] = &[
    "No such file or directory",
    "Permission denied",
    "Is a directory",
    "Not a directory",
    "File exists",
    "Read-only file system",
    "No space left on device",
    "Operation not permitted",
    "Directory not empty",
    "Invalid argument",
    "Too many open files",
    "Input/output error",
    "Device or resource busy",
    "Connection refused",
    "Broken pipe",
    "Text file busy",
    "Connection reset by peer",
    "Resource temporarily unavailable",
    "Bad file descriptor",
    "Interrupted system call",
    "File name too long",
    "Cannot allocate memory",
    "Timer expired",
    "Connection timed out",
    "Network is unreachable",
    "Address already in use",
];

/// `os error 13` or `(os error 13)`, nothing else.
fn is_os_error(t: &str) -> bool {
    let t = t
        .strip_prefix('(')
        .and_then(|t| t.strip_suffix(')'))
        .unwrap_or(t);
    t.strip_prefix("os error ")
        .is_some_and(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()))
}

/// Whether `rest` (what follows `: ` after a path) is exactly one of the
/// [`KNOWN_REASONS`], optionally followed by ` (os error N)`, or just an
/// `os error N`. Anything more could be file-name text.
fn is_known_reason(rest: &str) -> bool {
    is_os_error(rest)
        || KNOWN_REASONS.iter().any(|p| {
            rest.strip_prefix(p).is_some_and(|more| {
                more.is_empty() || more.strip_prefix(' ').is_some_and(is_os_error)
            })
        })
}

/// Where the path starting at byte `i` ends. Privacy first: file names may
/// hold spaces, quotes, brackets and colons, so a path runs to the end of the
/// line. The one exception is a `: ` followed by nothing but a known error
/// reason (see [`KNOWN_REASONS`]), so "failed to read <path>: Permission
/// denied" keeps its reason.
fn path_end(s: &str, i: usize) -> usize {
    let line_end = s[i..].find(['\n', '\r']).map_or(s.len(), |e| i + e);
    let line = &s[i..line_end];
    for (k, _) in line.match_indices(": ") {
        if is_known_reason(&line[k + 2..]) {
            return i + k;
        }
    }
    line_end
}

/// From a private path prefix on, or from an absolute path outside the
/// system's directories (see [`foreign_path_at`]), replace the path with
/// `<path>` (see [`path_end`]).
fn redact_paths(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        if private_prefix_at(s, i) || foreign_path_at(s, i) {
            out.push_str("<path>");
            i = path_end(s, i);
            continue;
        }
        let c = s[i..].chars().next().unwrap_or(' ');
        out.push(c);
        i += c.len_utf8();
    }
    out
}

fn frame_line(l: &str) -> bool {
    let l = l.trim();
    l.strip_prefix('#')
        .is_some_and(|r| r.starts_with(|c: char| c.is_ascii_digit()))
        || l.split_once(": ")
            .is_some_and(|(n, _)| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()))
}

/// Keep only frame lines (what [`parse_frames`] accepts) and thread headers.
fn filter_trace(trace: &str) -> String {
    trace
        .lines()
        .filter(|l| l.trim_start().starts_with("Stack trace of thread") || frame_line(l))
        .collect::<Vec<_>>()
        .join("\n")
}

// ------------------------------------------------------------- collecting

/// `(model name, logical cores)` from /proc/cpuinfo text.
fn cpu_model(text: &str) -> Option<String> {
    text.lines().find_map(|l| {
        let (k, v) = l.split_once(':')?;
        (k.trim() == "model name").then(|| v.trim().to_string())
    })
}

fn kb_field(text: &str, key: &str) -> Option<u64> {
    let rest = text.lines().find_map(|l| l.strip_prefix(key))?;
    rest.trim_start_matches(':')
        .split_whitespace()
        .next()?
        .parse()
        .ok()
}

fn read(path: &str) -> String {
    fs::read_to_string(path).unwrap_or_default()
}

/// Model name for PCI IDs from pci.ids text (`0x1002`, `0x744c` forms ok).
fn pci_name(ids: &str, vendor: &str, device: &str) -> Option<String> {
    let (v, d) = (
        vendor.trim_start_matches("0x").to_lowercase(),
        device.trim_start_matches("0x").to_lowercase(),
    );
    let mut in_vendor = false;
    for l in ids.lines() {
        if l.starts_with('#') || l.is_empty() {
            continue;
        }
        if !l.starts_with('\t') {
            in_vendor = l.starts_with(&v) && l[v.len()..].starts_with(' ');
        } else if in_vendor && !l.starts_with("\t\t") {
            let t = l.trim_start();
            if t.starts_with(&d) && t[d.len()..].starts_with(' ') {
                return Some(t[d.len()..].trim().to_string());
            }
        }
    }
    None
}

/// `(model or IDs, driver name, driver version)` of the first GPU in sysfs.
fn read_gpu(
    drm: &Path,
    pci_ids: &str,
    modules: &Path,
) -> (Option<String>, Option<String>, Option<String>) {
    let mut cards: Vec<PathBuf> = fs::read_dir(drm)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| {
            let n = e.file_name().to_string_lossy().into_owned();
            n.strip_prefix("card")
                .is_some_and(|d| !d.is_empty() && d.chars().all(|c| c.is_ascii_digit()))
        })
        .map(|e| e.path().join("device"))
        .collect();
    cards.sort();
    for dev in cards {
        let (Ok(v), Ok(d)) = (
            fs::read_to_string(dev.join("vendor")),
            fs::read_to_string(dev.join("device")),
        ) else {
            continue;
        };
        let (v, d) = (v.trim(), d.trim());
        let name = pci_name(pci_ids, v, d).unwrap_or_else(|| {
            format!(
                "{}:{}",
                v.trim_start_matches("0x"),
                d.trim_start_matches("0x")
            )
        });
        let driver = fs::read_link(dev.join("driver"))
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()));
        let version = driver
            .as_ref()
            .and_then(|drv| fs::read_to_string(modules.join(drv).join("version")).ok())
            .map(|s| s.trim().to_string());
        return (Some(name), driver, version);
    }
    (None, None, None)
}

fn category_of(app: &str) -> &'static str {
    let a = app.rsplit('/').next().unwrap_or(app);
    if a == "plasmashell" || a.starts_with("plasma-") || a.starts_with("plasma_") {
        "Plasma"
    } else if a.starts_with("kwin_") || a == "kwin" {
        "KWin"
    } else if [
        "net.eterneon.telamon.",
        "net.eterneon.atlas.",
        "telamon-",
        "atlas-",
    ]
    .iter()
    .any(|p| a.starts_with(p))
    {
        // Still the relay's word for it (see `payload`).
        "Atlas app"
    } else {
        "other"
    }
}

/// The longest version or channel a report keeps.
const MAX_VERSION: usize = 64;

/// `v` up to its first character that a version has no use for (anything but
/// letters, digits and `._+~:-`), at most [`MAX_VERSION`] characters; `None`
/// when nothing is left. The history file is written by root, but it is only
/// a file: its first line must not put free text into a public report.
fn plain_version(v: &str) -> Option<String> {
    let v: String = v
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || "._+~:-".contains(*c))
        .take(MAX_VERSION)
        .collect();
    (!v.is_empty()).then_some(v)
}

/// The version, channel and previous version of the running Telamon OS from a
/// `bootc status --json` document and the history. Each is cut to a plain
/// version (see [`plain_version`]).
pub(crate) fn os_info(
    status: Option<&crate::bootc::Status>,
    hist: &[history::Entry],
) -> (Option<String>, Option<String>, Option<String>) {
    let from_hist =
        |e: Option<&history::Entry>| e.and_then(|e| e.version.as_deref()).and_then(plain_version);
    let version = status
        .and_then(|s| s.status.booted.as_ref())
        .and_then(|b| b.version())
        .and_then(plain_version)
        .or_else(|| from_hist(hist.first()));
    let channel = status
        .and_then(|s| s.channel())
        .and_then(|c| plain_version(&c.to_string()));
    let previous = status
        .and_then(|s| s.status.rollback.as_ref())
        .and_then(|b| b.version())
        .and_then(plain_version)
        .or_else(|| from_hist(hist.get(1)));
    (version, channel, previous)
}

/// What `build_report` needs to know about the crash.
pub(crate) struct Crash<'a> {
    pub report_type: &'a str,
    pub app_name: &'a str,
    pub app_version: Option<&'a str>,
    pub message: &'a str,
    pub stacktrace: &'a str,
}

/// `bytes` random bytes as hex, from the OS; an error is an error (never a
/// constant ID).
fn random_hex(bytes: usize) -> io::Result<String> {
    let mut buf = vec![0u8; bytes];
    getrandom::fill(&mut buf).map_err(|e| io::Error::other(format!("no randomness: {e}")))?;
    Ok(buf.iter().map(|b| format!("{b:02x}")).collect())
}

/// Build a report for `crash` now. All strings are scrubbed and the trace is
/// cut to its frame lines. Does not check [`Settings`]; callers do.
pub(crate) fn build_report(
    crash: &Crash,
    scrubber: &Scrubber,
    time: Option<&str>,
) -> io::Result<Report> {
    let hist = history::read_default().unwrap_or_default();
    let (atlasos_version, channel, previous_version) = os_info(None, &hist);
    let channel = channel.or_else(|| {
        hist.first()
            .and_then(|e| e.image.rsplit_once(':').map(|x| x.1.to_string()))
            .filter(|c| c == "stable" || c == "testing")
    });
    let meminfo = read("/proc/meminfo");
    let total = kb_field(&meminfo, "MemTotal").unwrap_or(0);
    let avail = kb_field(&meminfo, "MemAvailable").unwrap_or(0);
    let (gpu, gpu_driver, gpu_ver) = read_gpu(
        Path::new("/sys/class/drm"),
        &read("/usr/share/hwdata/pci.ids"),
        Path::new("/sys/module"),
    );
    let one = |x: &str, max: usize| scrubber.scrub(&clean(x, max, false));
    Ok(Report {
        schema: 2,
        event_id: random_hex(16)?,
        report_type: one(crash.report_type, 64),
        time: time.map_or_else(now_rfc3339, str::to_string),
        crash_id: crash_id()?,
        atlasos_version: atlasos_version.map(|v| one(&v, MAX_VERSION)),
        channel: channel.map(|v| one(&v, MAX_VERSION)),
        previous_version: previous_version.map(|v| one(&v, MAX_VERSION)),
        app_name: one(crash.app_name, 512),
        app_version: crash.app_version.map(|v| one(v, 128)),
        category: category_of(crash.app_name).to_string(),
        message: untrusted_text(scrubber, &cap_message(crash.message)),
        stacktrace: untrusted_text(scrubber, &cap_trace(&filter_trace(crash.stacktrace))),
        kernel: Some(read("/proc/sys/kernel/osrelease").trim().to_string())
            .filter(|k| !k.is_empty()),
        gpu,
        gpu_driver: gpu_driver.map(|d| match gpu_ver {
            Some(v) => format!("{d} {v}"),
            None => d,
        }),
        uptime_secs: coarse_uptime(
            read("/proc/uptime")
                .split_whitespace()
                .next()
                .and_then(|u| u.parse::<f64>().ok())
                .map_or(0, |u| u as u64),
        ),
        cpu_model: cpu_model(&read("/proc/cpuinfo")),
        ram_total_kb: coarse_ram_kb(total),
        mem_used_kb: total.saturating_sub(avail),
        sent_event_id: None,
        issue_url: None,
        path: None,
    })
}

/// Uptime as a report keeps it: whole hours, rounded down. With the report's
/// time an exact uptime is the boot instant, which would tie two public
/// reports of one boot together.
fn coarse_uptime(secs: u64) -> u64 {
    secs / 3600 * 3600
}

/// RAM total as a report keeps it: whole GB (1 GB at least), rounded to the
/// nearest. The exact figure tells one machine from another.
fn coarse_ram_kb(kb: u64) -> u64 {
    const GB: u64 = 1024 * 1024;
    if kb == 0 {
        return 0;
    }
    (kb / GB + u64::from(kb % GB >= GB / 2))
        .max(1)
        .saturating_mul(GB)
}

/// The longest stack trace a report keeps, in bytes (a report file stays far
/// below the size [`read_reports`] takes).
const MAX_TRACE: usize = 256 * 1024;

/// `trace` cut to [`MAX_TRACE`] bytes at a line end (the top of the stack
/// comes first), else on a character boundary.
fn cap_trace(trace: &str) -> String {
    if trace.len() <= MAX_TRACE {
        return trace.to_string();
    }
    let mut end = 0;
    for l in trace.split_inclusive('\n') {
        if end + l.len() > MAX_TRACE {
            break;
        }
        end += l.len();
    }
    if end == 0 {
        end = MAX_TRACE;
        while !trace.is_char_boundary(end) {
            end -= 1;
        }
    }
    trace[..end].trim_end().to_string()
}

/// Text that comes from outside the framework (a panic or fatal message, a
/// frame, a journal line): without control, invisible and bidi characters
/// (they could split a secret from the scrubber, or reverse the text a reader
/// sees), scrubbed, hidden paths, and made inert for GitHub (see [`defang`]).
fn untrusted_text(scrubber: &Scrubber, text: &str) -> String {
    // defanged before the scrubber too: it reads `@<hex>` as one word, and
    // the result must not change when it is run again
    defang(&scrubber.scrub_message(&defang(&clean(text, usize::MAX, true))))
}

/// Whether the `]` at `chars[i]` closes a `[...]` that follows a word, a `]`
/// or a `)`: an index expression, not a link label.
fn is_index(chars: &[char], i: usize) -> bool {
    let from = i.saturating_sub(100);
    let Some(open) = chars[from..i].iter().rposition(|c| *c == '[' || *c == ']') else {
        return false;
    };
    let open = from + open;
    chars[open] == '['
        && open > 0
        && (chars[open - 1].is_alphanumeric() || "_])".contains(chars[open - 1]))
}

/// Whether the `]` at `chars[i]` ends the label of a link reference
/// definition: `[x]: https://...` at the start of a line (up to 3 spaces in
/// front), with an address that has a scheme or `//`.
fn ref_definition(chars: &[char], i: usize) -> bool {
    // the label is short: look back a little only (a line may be huge)
    let from = i.saturating_sub(300);
    let line = match chars[from..i].iter().rposition(|c| *c == '\n') {
        Some(n) => from + n + 1,
        None if from == 0 => 0,
        None => return false,
    };
    let label = &chars[line..i];
    let indent = label.iter().take_while(|c| **c == ' ').count();
    if indent > 3 || label.get(indent) != Some(&'[') || label[indent + 1..].contains(&']') {
        return false;
    }
    let after: String = chars[i + 2..]
        .iter()
        .skip_while(|c| **c == ' ' || **c == '\t')
        .take_while(|c| !c.is_whitespace())
        .take(256)
        .collect();
    let after = after.trim_start_matches('<');
    after.starts_with("//") || after.contains("://") || after.starts_with("mailto:")
}

/// Text that GitHub would act on, made plain: `@name` (it would notify the
/// person), `[text](url)` and `![alt](url)` (a link, or an image the reader's
/// browser loads), and HTML elements with attributes that link or load
/// (`<img src=...>`, `<a href=...>`, `<iframe src=...>`, ...), also `[a][ref]`,
/// a `[x]: https://...` definition and a `<https://...>` autolink. A space is
/// put in each: `@ name`, `] (url)`, `< img src=...>`.
fn defang(s: &str) -> String {
    const TAGS: &[&str] = &[
        "a", "img", "image", "picture", "source", "video", "audio", "iframe", "script", "style",
        "link", "meta", "base", "object", "embed", "svg", "math", "form", "input", "button",
        "textarea", "details", "summary", "body", "html", "head",
    ];
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::with_capacity(s.len() + 8);
    for (i, &c) in chars.iter().enumerate() {
        out.push(c);
        let next = chars.get(i + 1).copied();
        match c {
            // a mention starts a word
            '@' if next.is_some_and(|n| n.is_alphanumeric())
                && !(i > 0 && (chars[i - 1].is_alphanumeric() || chars[i - 1] == '_')) =>
            {
                out.push(' ');
            }
            // `[a](url)`; `[a][ref]` too, unless it is an index (`v[0][1]`,
            // `grid[i][j]`: the `[` follows a word)
            ']' if next == Some('(') || (next == Some('[') && !is_index(&chars, i)) => {
                out.push(' ')
            }
            // a reference definition at the start of a line: `[x]: https://...`
            ']' if next == Some(':') && ref_definition(&chars, i) => out.push(' '),
            '<' => {
                let rest = &chars[i + 1..];
                let name: String = rest
                    .iter()
                    .take_while(|c| c.is_ascii_alphanumeric())
                    .map(char::to_ascii_lowercase)
                    .collect();
                let tail = &rest[name.len()..];
                // an autolink: `<https://...>`, `<mailto:a@b>` (not the
                // `<alloc::vec::Vec<T> as ...>` of a Rust frame)
                let scheme = rest
                    .iter()
                    .take_while(|c| c.is_ascii_alphanumeric() || "+.-".contains(**c))
                    .count();
                if rest.first().is_some_and(char::is_ascii_alphabetic)
                    && (2..=32).contains(&scheme)
                    && rest.get(scheme) == Some(&':')
                    && rest
                        .get(scheme + 1)
                        .is_some_and(|c| *c != ':' && !c.is_whitespace())
                {
                    out.push(' ');
                }
                // an element with attributes (`<img src=x>`, `<a href=y>`,
                // `<img/src=x>`), not `Vec<Form>`, `<Form as Trait>::f` or a
                // closing tag: those load or link nothing
                if TAGS.contains(&name.as_str())
                    && tail.first().is_some_and(|c| c.is_whitespace() || *c == '/')
                    && !tail.starts_with(&[' ', 'a', 's', ' '])
                {
                    out.push(' ');
                }
            }
            _ => {}
        }
    }
    out
}

// ----------------------------------------------------------------- storage

/// `$XDG_STATE_HOME/telamon`. The first time, `$XDG_STATE_HOME/atlas` (framework
/// 1.x) is moved there: see [`adopt_state_dir`].
fn state_dir() -> Option<PathBuf> {
    let home = state_home()?;
    let dir = home.join("telamon");
    if let Err(e) = adopt_state_dir(&dir, &home.join("atlas")) {
        // Not fatal: the app starts with an empty state, as on a first run.
        eprintln!(
            "telamon-framework: could not move {} to {}: {e}",
            home.join("atlas").display(),
            dir.display()
        );
    }
    Some(dir)
}

/// Moves the state directory of framework 1.x (`old`: crash reports waiting
/// for the user, the sent history, the coredump and event markers, the
/// rotating ID) to `new`, in one `rename`, when `new` does not exist yet.
/// Only a real directory of this user's: a link (a dotfiles setup) or
/// someone else's is left alone. An app of 1.x that runs after this starts a
/// state of its own (its markers start at "now").
fn adopt_state_dir(new: &Path, old: &Path) -> io::Result<bool> {
    if fs::symlink_metadata(new).is_ok() {
        return Ok(false);
    }
    let Ok(meta) = fs::symlink_metadata(old) else {
        return Ok(false);
    };
    // SAFETY: geteuid has no preconditions.
    if !meta.file_type().is_dir()
        || std::os::unix::fs::MetadataExt::uid(&meta) != unsafe { libc::geteuid() }
    {
        return Ok(false);
    }
    match fs::rename(old, new) {
        Ok(()) => Ok(true),
        // Another process moved it first, or made the new one.
        Err(e)
            if matches!(
                e.kind(),
                io::ErrorKind::NotFound | io::ErrorKind::AlreadyExists
            ) =>
        {
            Ok(false)
        }
        Err(e) if e.raw_os_error() == Some(libc::ENOTEMPTY) => Ok(false),
        Err(e) => Err(e),
    }
}

fn reports_dir() -> Option<PathBuf> {
    Some(state_dir()?.join("crash-reports"))
}

/// The rotating anonymous ID: random, replaced when 30 days old or when its
/// creation time is in the future. There is no permanent ID anywhere.
pub(crate) fn crash_id() -> io::Result<String> {
    match state_dir() {
        Some(d) => crash_id_in(&d, SystemTime::now()),
        None => random_hex(16),
    }
}

fn crash_id_in(dir: &Path, now: SystemTime) -> io::Result<String> {
    let path = dir.join("crash-id");
    let secs = |t: SystemTime| t.duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs());
    if let Ok(text) = fs::read_to_string(&path) {
        let mut l = text.lines();
        if let (Some(id), Some(created)) = (l.next(), l.next().and_then(|c| c.parse::<u64>().ok()))
            && id.len() == 32
            && all_hex(id)
            && created <= secs(now)
            && secs(now) - created < ID_MAX_AGE.as_secs()
        {
            return Ok(id.to_string());
        }
    }
    let id = random_hex(16)?;
    write_private(&path, format!("{id}\n{}\n", secs(now)).as_bytes(), true)?;
    Ok(id)
}

/// Write `data` to `path` (0600; the directory becomes 0700) atomically: a
/// temp file beside it, fsync, then a rename (`overwrite`) or a link that
/// fails with `AlreadyExists` if `path` is taken, then a directory fsync. A
/// crash leaves the old file or the new one, never a cut one. A symlink at
/// `path` is replaced, never written through.
fn write_private(path: &Path, data: &[u8], overwrite: bool) -> io::Result<()> {
    let dir = path
        .parent()
        .filter(|d| !d.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(dir)?;
    // an older version or a backup may have left it wider
    fs::set_permissions(dir, fs::Permissions::from_mode(0o700))?;
    let name = path
        .file_name()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "path has no file name"))?;
    // `.<name>.<random>.tmp`: not `*.json`, so no reader ever sees it
    let mut tmp_name = std::ffi::OsString::from(".");
    tmp_name.push(name);
    tmp_name.push(format!(".{}{TMP_SUFFIX}", random_hex(6)?));
    let tmp = dir.join(tmp_name);
    let res = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(&tmp)
        .and_then(|mut f| {
            f.write_all(data)?;
            f.sync_all()
        })
        .and_then(|()| {
            if overwrite {
                fs::rename(&tmp, path)
            } else {
                // a link never replaces: `AlreadyExists` like `create_new`
                match fs::hard_link(&tmp, path) {
                    Err(e)
                        if e.kind() != io::ErrorKind::AlreadyExists
                            && fs::symlink_metadata(path).is_err() =>
                    {
                        // a file system without hard links
                        fs::rename(&tmp, path)
                    }
                    r => r,
                }
            }
        });
    let _ = fs::remove_file(&tmp);
    res?;
    sync_dir(dir);
    Ok(())
}

/// The suffix of [`write_private`]'s temp files.
const TMP_SUFFIX: &str = ".tmp";

/// Make a rename or link in `dir` durable (best effort: some file systems
/// refuse to sync a directory).
fn sync_dir(dir: &Path) {
    if let Ok(d) = fs::File::open(dir) {
        let _ = d.sync_all();
    }
}

/// Remove [`write_private`] temp files (`.<name>.<hex>.tmp`) left in `dir` by
/// a process killed mid-write, once they are clearly not in use any more.
fn sweep_temp_files(dir: &Path, now: SystemTime) {
    for e in fs::read_dir(dir).into_iter().flatten().flatten() {
        let name = e.file_name();
        let name = name.to_string_lossy();
        if !(name.starts_with('.') && name.ends_with(TMP_SUFFIX)) {
            continue;
        }
        if is_stale(&e, now) {
            let _ = fs::remove_file(e.path());
        }
    }
}

/// Older than 10 minutes (or dated in the future).
fn is_stale(e: &fs::DirEntry, now: SystemTime) -> bool {
    e.metadata().and_then(|m| m.modified()).is_ok_and(|t| {
        now.duration_since(t)
            .map_or(true, |a| a > Duration::from_secs(600))
    })
}

/// The longest `time` a report is saved with: an RFC 3339 time is 20 to 35
/// characters, and the time is the file name (255 bytes at most).
const MAX_TIME: usize = 40;

/// Save `report` in `dir` as `<time>-<nn>.json` (0600; `dir` becomes 0700).
/// A `time` that is not an RFC 3339 time (empty, over 40 characters or with
/// others than digits and `TZ:-+.`) fails with `InvalidInput`.
pub(crate) fn write_report(dir: &Path, report: &Report) -> io::Result<PathBuf> {
    if report.time.is_empty()
        || report.time.len() > MAX_TIME
        || !report
            .time
            .chars()
            .all(|c| c.is_ascii_digit() || "TZ:-+.".contains(c))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "bad report time",
        ));
    }
    let json = serde_json::to_string_pretty(report).map_err(io::Error::other)?;
    for n in 0..100 {
        let path = dir.join(format!("{}-{n:02}.json", report.time));
        match write_private(&path, json.as_bytes(), false) {
            Ok(()) => return Ok(path),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(io::Error::other("too many reports in the same second"))
}

/// The helper's non-problem events, which an older version queued as reports.
/// Only these (with no stack trace) are deleted from `pending/`, so a real
/// helper panic or coredump is never lost.
const SUCCESS_EVENTS: [&str; 8] = [
    "update-staged",
    "update-applied",
    "rollback-requested",
    "rollback-applied",
    "rollback-cancelled",
    "channel-switched",
    "channel-switch-applied",
    "health-check-passed",
];

/// Helper events that are not problems (an older version queued them).
fn is_stale_event_report(r: &Report) -> bool {
    r.app_name == "atlas-system-helper"
        && r.stacktrace.trim().is_empty()
        && SUCCESS_EVENTS.contains(&r.report_type.as_str())
}

/// The pending reports; ones made from success events are deleted.
fn read_pending(dir: &Path) -> Vec<Report> {
    read_reports(dir)
        .into_iter()
        .filter(|r| {
            if !is_stale_event_report(r) {
                return true;
            }
            if let Some(p) = &r.path {
                let _ = fs::remove_file(p);
            }
            false
        })
        .collect()
}

/// Where unreadable report files go, beside `pending/` and `sent/`.
const QUARANTINE: &str = "quarantine";

/// A file that is not a report and has not changed for a minute (so not one
/// an older version is still writing in place) is moved to `quarantine/`
/// beside `dir`: out of the list, but kept to look at (90 days).
fn quarantine(path: &Path, now: SystemTime) {
    let settled = fs::symlink_metadata(path)
        .and_then(|m| m.modified())
        .is_ok_and(|t| {
            now.duration_since(t)
                .map_or(true, |a| a > Duration::from_secs(60))
        });
    let (Some(dir), Some(name)) = (path.parent().and_then(Path::parent), path.file_name()) else {
        return;
    };
    if !settled {
        return;
    }
    let q = dir.join(QUARANTINE);
    let made = fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&q)
        .and_then(|()| fs::set_permissions(&q, fs::Permissions::from_mode(0o700)));
    if made.is_err() {
        return;
    }
    for n in 0..100 {
        let mut to = name.to_os_string();
        if n > 0 {
            to.push(format!(".{n}"));
        }
        let to = q.join(to);
        if fs::symlink_metadata(&to).is_ok() {
            continue;
        }
        if fs::rename(path, &to).is_ok() {
            sync_dir(&q);
            if let Some(d) = path.parent() {
                sync_dir(d);
            }
        }
        return;
    }
}

/// The biggest report file that is read. A report is far smaller (the
/// message is at most 64 KiB, the trace at most [`MAX_TRACE`]).
const MAX_REPORT_BYTES: u64 = 1024 * 1024;

/// A report file's bytes: never through a symlink, only a regular file (a
/// FIFO would block), at most [`MAX_REPORT_BYTES`] (`InvalidData` when
/// bigger).
fn read_report_file(path: &Path) -> io::Result<Vec<u8>> {
    let f = fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK | libc::O_NOCTTY | libc::O_CLOEXEC)
        .open(path)?;
    let meta = f.metadata()?;
    if !meta.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "not a regular file",
        ));
    }
    let too_big = || io::Error::new(io::ErrorKind::InvalidData, "report file is too large");
    if meta.len() > MAX_REPORT_BYTES {
        return Err(too_big());
    }
    let mut bytes = Vec::new();
    f.take(MAX_REPORT_BYTES + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MAX_REPORT_BYTES {
        return Err(too_big());
    }
    Ok(bytes)
}

fn read_reports(dir: &Path) -> Vec<Report> {
    let mut paths: Vec<PathBuf> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e == "json"))
        .collect();
    paths.sort();
    let now = SystemTime::now();
    paths
        .into_iter()
        .filter_map(|p| {
            let bytes = match read_report_file(&p) {
                Ok(b) => b,
                Err(e) => {
                    // too big for a report: out of the list, kept to look at.
                    // A link, a FIFO or an unreadable file is left alone.
                    if e.kind() == io::ErrorKind::InvalidData {
                        quarantine(&p, now);
                    }
                    return None;
                }
            };
            match serde_json::from_slice::<Report>(&bytes) {
                Ok(mut r) => {
                    r.path = Some(p);
                    Some(r)
                }
                Err(_) => {
                    // A report from before schema 2 (no event_id) can never
                    // be shown or sent: remove it instead of skipping it forever.
                    let old = serde_json::from_slice::<Value>(&bytes)
                        .ok()
                        .is_some_and(|v| v.is_object() && v.get("event_id").is_none());
                    if old {
                        let _ = fs::remove_file(&p);
                    } else {
                        // cut short, damaged or not UTF-8: out of the list
                        quarantine(&p, now);
                    }
                    None
                }
            }
        })
        .collect()
}

/// `r` as it is shown and sent: every string that was copied from outside
/// scrubbed again with the current rules (a report that an older version
/// queued was scrubbed with weaker ones), cleaned of control and bidi
/// characters and made inert for GitHub, the version fields cut to plain
/// versions, and uptime and RAM coarse. Nothing is written back.
fn rescrub(mut r: Report, scrubber: &Scrubber) -> Report {
    let one = |x: &str, max: usize| scrubber.scrub(&clean(x, max, false));
    let version = |v: Option<String>| {
        v.and_then(|v| plain_version(&v))
            .map(|v| one(&v, MAX_VERSION))
    };
    r.report_type = one(&r.report_type, 64);
    // part by part, like a Flatpak app ID in `coredump_report`: a whole long
    // ID looks like an access token
    r.app_name = clean(&r.app_name, 512, false)
        .split('.')
        .map(|part| scrubber.scrub(part))
        .collect::<Vec<_>>()
        .join(".");
    r.app_version = r.app_version.map(|v| one(&v, 128));
    r.atlasos_version = version(r.atlasos_version);
    r.channel = version(r.channel);
    r.previous_version = version(r.previous_version);
    r.kernel = r.kernel.map(|v| one(&v, 256));
    r.gpu = r.gpu.map(|v| one(&v, 256));
    r.gpu_driver = r.gpu_driver.map(|v| one(&v, 256));
    r.cpu_model = r.cpu_model.map(|v| one(&v, 256));
    r.message = untrusted_text(scrubber, &cap_message(&r.message));
    r.stacktrace = untrusted_text(scrubber, &cap_trace(&filter_trace(&r.stacktrace)));
    r.uptime_secs = coarse_uptime(r.uptime_secs);
    r.ram_total_kb = coarse_ram_kb(r.ram_total_kb);
    r
}

/// Reports waiting for the user's decision, oldest first.
pub fn pending() -> Vec<Report> {
    prune_sent();
    reports_dir()
        .map(|d| pending_in(&d.join("pending"), &Scrubber::from_env()))
        .unwrap_or_default()
}

/// [`pending`] for the directory `dir`, scrubbed again with `scrubber`.
fn pending_in(dir: &Path, scrubber: &Scrubber) -> Vec<Report> {
    read_pending(dir)
        .into_iter()
        .map(|r| rescrub(r, scrubber))
        .collect()
}

/// Reports already sent, oldest first (the history list).
pub fn sent() -> Vec<Report> {
    prune_sent();
    reports_dir()
        .map(|d| sent_in(&d.join("sent"), &Scrubber::from_env()))
        .unwrap_or_default()
}

/// [`sent`] for the directory `dir`, scrubbed again with `scrubber`.
fn sent_in(dir: &Path, scrubber: &Scrubber) -> Vec<Report> {
    read_reports(dir)
        .into_iter()
        .map(|r| rescrub(r, scrubber))
        .collect()
}

/// "Don't send": delete the pending report's file. Only a report file in
/// `pending/` is deleted: any other `path` fails with `InvalidInput`.
pub fn discard(report: &Report) -> io::Result<()> {
    let dir = reports_dir()
        .ok_or_else(|| io::Error::other("no state directory"))?
        .join("pending");
    discard_in(&dir, report)
}

fn discard_in(pending: &Path, report: &Report) -> io::Result<()> {
    let p = report
        .path
        .as_ref()
        .ok_or_else(|| io::Error::other("report has no path"))?;
    if !is_pending_file(pending, p) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "not a pending crash report",
        ));
    }
    fs::remove_file(p)
}

/// Whether `p` names a report file (`*.json`, not hidden) directly in the
/// directory `pending`, and is no symlink or directory if it exists. The
/// directories are compared resolved, so `..` and links lead nowhere else.
fn is_pending_file(pending: &Path, p: &Path) -> bool {
    let (Some(parent), Some(name)) = (p.parent(), p.file_name().and_then(|n| n.to_str())) else {
        return false;
    };
    let same_dir = match (fs::canonicalize(parent), fs::canonicalize(pending)) {
        (Ok(a), Ok(b)) => a == b,
        _ => false,
    };
    same_dir
        && name.ends_with(".json")
        && !name.starts_with('.')
        && fs::symlink_metadata(p).map_or(true, |m| m.file_type().is_file())
}

/// Delete sent and quarantined reports older than 90 days, and leftovers of
/// writes and sends that were cut short.
fn prune_sent() {
    let now = SystemTime::now();
    if let Some(d) = state_dir() {
        sweep_send_files(&d, now);
        sweep_temp_files(&d, now);
    }
    if let Some(d) = reports_dir() {
        for sub in ["pending", "sent", QUARANTINE] {
            sweep_temp_files(&d.join(sub), now);
        }
        sweep_claims(&d.join("pending"), now);
        prune_older_than(&d.join("sent"), SENT_KEEP, now);
        prune_older_than(&d.join(QUARANTINE), SENT_KEEP, now);
    }
}

/// `send-*.json` is the body file of a curl call; one left behind (the app was
/// killed mid-send) is removed once it is clearly not in use any more.
fn sweep_send_files(dir: &Path, now: SystemTime) {
    for e in fs::read_dir(dir).into_iter().flatten().flatten() {
        let name = e.file_name();
        let name = name.to_string_lossy();
        if !(name.starts_with("send-") && name.ends_with(".json")) {
            continue;
        }
        if is_stale(&e, now) {
            let _ = fs::remove_file(e.path());
        }
    }
}

/// A modification time in the future (clock skew) counts as old.
fn prune_older_than(dir: &Path, keep: Duration, now: SystemTime) {
    for e in fs::read_dir(dir).into_iter().flatten().flatten() {
        let old = match e.metadata().and_then(|m| m.modified()) {
            Ok(t) => now.duration_since(t).map_or(true, |age| age > keep),
            Err(_) => false,
        };
        if old {
            let _ = fs::remove_file(e.path());
        }
    }
}

/// After a successful POST: record it in `sent/` and drop the pending file.
/// Best effort on both: the data is out, so this never fails the send.
fn finish_sent(report: &Report, server: Server) {
    if let Some(d) = reports_dir() {
        move_to_sent(&d.join("sent"), report, server);
        prune_older_than(&d.join("sent"), SENT_KEEP, SystemTime::now());
    }
}

fn move_to_sent(sent_dir: &Path, report: &Report, server: Server) {
    let mut r = report.clone();
    r.sent_event_id = server.id;
    r.issue_url = server.url;
    let _ = write_report(sent_dir, &r);
    // only a file in the `pending/` beside `sent/`
    let pending = sent_dir.with_file_name("pending");
    if let Some(p) = report
        .path
        .as_ref()
        .filter(|p| is_pending_file(&pending, p))
        && let Err(e) = fs::remove_file(p)
        && e.kind() != io::ErrorKind::NotFound
    {
        // The data is out already; a leftover pending file could be sent
        // again, so say so (the caller still reports success).
        eprintln!(
            "telamon-framework: sent report {} not removed from pending: {e}",
            p.display()
        );
    }
}

/// Save a report to `pending/` if the user enabled crash reporting.
fn queue(report: &Report) -> Option<PathBuf> {
    if !Settings::load().enabled {
        return None;
    }
    let pending = reports_dir()?.join("pending");
    let p = write_report(&pending, report).ok();
    cap_pending(&pending, MAX_PENDING);
    p
}

/// At most this many reports wait in `pending/`.
const MAX_PENDING: usize = 50;

/// Delete the oldest pending reports (by file name: the report's time) until
/// at most `max` are left.
fn cap_pending(dir: &Path, max: usize) {
    let mut paths: Vec<PathBuf> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e == "json"))
        .collect();
    if paths.len() <= max {
        return;
    }
    paths.sort();
    let extra = paths.len() - max;
    for p in &paths[..extra] {
        let _ = fs::remove_file(p);
    }
}

/// Keep the reports whose pending file is still there (the cap may have
/// taken the oldest of a large batch).
fn still_pending(mut out: Vec<Report>) -> Vec<Report> {
    out.retain(|r| r.path.as_ref().is_some_and(|p| p.exists()));
    out
}

// -------------------------------------------------------------------- hooks

static APP: OnceLock<AppInfo> = OnceLock::new();

const MAX_PER_HOUR: usize = 5;

/// At most 5 reports an hour, and the same crash (same message and place)
/// once, in this process; [`ledger_allow`] holds the same limits across
/// processes.
#[derive(Default)]
struct RateLimiter {
    recent: Vec<(Instant, u64)>,
}

impl RateLimiter {
    fn allow(&mut self, now: Instant, key: u64) -> bool {
        let hour = Duration::from_secs(3600);
        self.recent.retain(|(t, _)| now.duration_since(*t) < hour);
        if self.recent.len() >= MAX_PER_HOUR || self.recent.iter().any(|(_, k)| *k == key) {
            return false;
        }
        self.recent.push((now, key));
        true
    }
}

static LIMITER: Mutex<RateLimiter> = Mutex::new(RateLimiter { recent: Vec::new() });

thread_local! {
    static IN_HOOK: Cell<bool> = const { Cell::new(false) };
}

/// The same crash is the same message at the same place (the frames of a
/// trace taken inside the hook are no help: they are hook code). Stable
/// across processes and builds: it is stored in [`RECENT`].
fn crash_key(message: &str, at: Option<&str>) -> u64 {
    fnv1a(&[message.as_bytes(), at.unwrap_or("").as_bytes()])
}

/// FNV-1a over the parts, each followed by a 0 byte.
fn fnv1a(parts: &[&[u8]]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for p in parts {
        for b in p.iter().chain([&0u8]) {
            h ^= u64::from(*b);
            h = h.wrapping_mul(0x0100_0000_01b3);
        }
    }
    h
}

/// A coredump's crash key: the program, the signal and the top
/// [`KEY_FRAMES`] frames of the crashed thread (functions and modules, not
/// addresses, which move with every start). A restart loop is one crash.
fn coredump_key(r: &Report) -> u64 {
    // the first thread in systemd-coredump's trace is the one that crashed
    let first: Vec<&str> = r
        .stacktrace
        .lines()
        .enumerate()
        .take_while(|(i, l)| *i == 0 || !l.trim_start().starts_with("Stack trace of thread"))
        .map(|x| x.1)
        .collect();
    let frames = parse_frames(&first.join("\n"));
    let mut parts: Vec<String> = vec![r.app_name.clone(), r.message.clone()];
    for f in frames.iter().rev().take(KEY_FRAMES) {
        parts.push(format!(
            "{} {}",
            f["function"].as_str().unwrap_or(""),
            f["module"].as_str().unwrap_or("")
        ));
    }
    fnv1a(&parts.iter().map(|p| p.as_bytes()).collect::<Vec<_>>())
}

const KEY_FRAMES: usize = 5;

/// The crashes queued in the last day, shared by every process of the user:
/// `crash-reports/recent`, one `<unix seconds> <16 hex key>` per line.
const RECENT: &str = "recent";
const DEDUPE_FOR: Duration = Duration::from_secs(86_400);

/// Whether a crash with `key` may be queued at `now`, recorded in
/// `dir/recent` if so: the same key at most once a day and, with `cap`, at
/// most [`MAX_PER_HOUR`] reports in the last hour, across processes (an app
/// in a restart loop is a new process each time). Lines are locked with
/// `recent.lock` (waiting at most 200 ms) and written atomically. When the
/// file cannot be used the crash is allowed: the in-process limit remains.
fn ledger_allow(dir: &Path, now: SystemTime, key: u64, cap: bool) -> bool {
    let secs = |t: SystemTime| t.duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs());
    let now_s = secs(now);
    let _lock = lock_file(
        &dir.join(format!("{RECENT}.lock")),
        Duration::from_millis(200),
    );
    let path = dir.join(RECENT);
    let mut recent: Vec<(u64, u64)> = fs::read(&path)
        .map(|b| String::from_utf8_lossy(&b).into_owned())
        .unwrap_or_default()
        .lines()
        .filter_map(|l| {
            let (t, k) = l.split_once(' ')?;
            Some((t.parse().ok()?, u64::from_str_radix(k, 16).ok()?))
        })
        // in the last day; a time ahead of the clock (it was set back)
        // counts as now, unless it is more than a day ahead
        .filter(|(t, _)| {
            now_s.saturating_sub(*t) < DEDUPE_FOR.as_secs()
                && t.saturating_sub(now_s) < DEDUPE_FOR.as_secs()
        })
        .collect();
    if recent.iter().any(|(_, k)| *k == key) {
        return false;
    }
    if cap
        && recent
            .iter()
            .filter(|(t, _)| now_s.saturating_sub(*t) < 3600)
            .count()
            >= MAX_PER_HOUR
    {
        return false;
    }
    recent.push((now_s, key));
    let text: String = recent
        .iter()
        .map(|(t, k)| format!("{t} {k:016x}\n"))
        .collect();
    let _ = write_private(&path, text.as_bytes(), true);
    true
}

/// An exclusive `flock` on `path` (made 0600 if missing), tried until
/// `wait` has passed; `None` if it could not be had. Released on drop.
fn lock_file(path: &Path, wait: Duration) -> Option<fs::File> {
    use std::os::fd::AsRawFd;
    let dir = path.parent()?;
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(dir)
        .ok()?;
    let f = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)
        .ok()?;
    let end = Instant::now() + wait;
    loop {
        // SAFETY: a valid open descriptor; flock has no other preconditions.
        if unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0 {
            return Some(f);
        }
        if Instant::now() >= end {
            return None;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

/// The longest message a report keeps, in bytes.
const MAX_MESSAGE: usize = 64 * 1024;

/// `s` cut to [`MAX_MESSAGE`] bytes on a char boundary, with a note saying
/// so; copies at most that much.
fn cap_message(s: &str) -> String {
    // already cut by an earlier call (a report read again): leave it as is
    let note = "\n[... cut: the message was ";
    if let Some(i) = s.rfind(note)
        && i <= MAX_MESSAGE
        && s.len() - i < 64
        && s.ends_with(" bytes]")
    {
        return s.to_string();
    }
    if s.len() <= MAX_MESSAGE {
        return s.to_string();
    }
    let mut end = MAX_MESSAGE;
    while !s.is_char_boundary(end) {
        end -= 1;
    }
    format!(
        "{}\n[... cut: the message was {} bytes]",
        &s[..end],
        s.len()
    )
}

/// Drop the frames of the hook itself (everything up to the panic runtime).
fn skip_hook_frames(trace: &str) -> String {
    let lines: Vec<&str> = trace.lines().collect();
    let marker = lines
        .iter()
        .position(|l| l.contains("rust_begin_unwind"))
        .or_else(|| lines.iter().position(|l| l.contains("core::panicking")));
    match marker {
        Some(i) => lines[i + 1..].join("\n"),
        None => trace.to_string(),
    }
}

/// Install the panic hook for `app`. Call once, early in `main`. The previous
/// hook (the default one prints the panic) runs first; then, only when crash
/// reporting is enabled, a report is queued (not for a panic inside the hook
/// itself, at most 5 an hour across all processes, each crash once a day).
pub fn install(app: AppInfo) {
    if APP.set(app).is_err() {
        return;
    }
    prune_sent();
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        previous(info);
        if IN_HOOK.replace(true) {
            return;
        }
        // No panic is possible in here: it would abort the process.
        let payload = info.payload();
        let message = payload
            .downcast_ref::<&str>()
            .copied()
            .or_else(|| payload.downcast_ref::<String>().map(String::as_str))
            .unwrap_or("Box<dyn Any>");
        // cut before any copy: a huge payload would cost many times its
        // size in the scrubber
        let message = cap_message(message);
        let at = info
            .location()
            .map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()));
        let _ = save("panic", &message, at.as_deref());
        IN_HOOK.set(false);
    }));
}

/// Queue a report for a fatal error that is not a Rust panic (a Qt fatal
/// message handler). Needs [`install`]; does nothing when disabled.
pub fn record_fatal(message: &str) -> Option<PathBuf> {
    save("fatal", message, None)
}

fn save(kind: &str, message: &str, at: Option<&str>) -> Option<PathBuf> {
    if !Settings::load().enabled {
        return None;
    }
    let app = APP.get()?;
    let message = &cap_message(message);
    let key = crash_key(message, at);
    if !lock(&LIMITER).allow(Instant::now(), key) {
        return None;
    }
    // the same limits across processes: a restart loop is one crash
    if let Some(d) = reports_dir()
        && !ledger_allow(&d, SystemTime::now(), key, true)
    {
        return None;
    }
    let msg = match at {
        Some(a) => format!("{message} at {a}"),
        None => message.to_string(),
    };
    let trace = skip_hook_frames(&filter_trace(
        &std::backtrace::Backtrace::force_capture().to_string(),
    ));
    let crash = Crash {
        report_type: kind,
        app_name: &app.id,
        app_version: Some(&app.version),
        message: &msg,
        stacktrace: &trace,
    };
    queue(&build_report(&crash, &Scrubber::from_env(), None).ok()?)
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

// ------------------------------------------------------------ coredumps

fn last_seen_path(name: &str) -> Option<PathBuf> {
    Some(state_dir()?.join(name))
}

fn field(v: &Value, key: &str) -> Option<String> {
    match v.get(key)? {
        Value::String(s) => Some(s.clone()),
        // journald prints non-UTF-8 and some multi-line values as byte arrays
        Value::Array(a) => Some(
            String::from_utf8_lossy(
                &a.iter()
                    .filter_map(|n| n.as_u64().map(|b| b as u8))
                    .collect::<Vec<u8>>(),
            )
            .into_owned(),
        ),
        _ => None,
    }
}

/// An absolute path with no control characters or `..`, of sane length.
fn valid_exe(e: &str) -> bool {
    e.starts_with('/')
        && e.len() <= 4096
        && !e.chars().any(char::is_control)
        && !e.split('/').any(|c| c == "..")
}

/// Drops control characters (newlines and tabs kept only if `multiline`) and
/// invisible Unicode format/bidi characters (zero-width ones, the bidi
/// overrides and isolates, interlinear marks, "tag" characters), then keeps at
/// most `max` chars.
fn clean(s: &str, max: usize, multiline: bool) -> String {
    s.chars()
        .filter(|&c| {
            if c == '\n' || c == '\t' {
                return multiline;
            }
            !c.is_control()
                && !matches!(c, '\u{ad}' | '\u{61c}' | '\u{180e}'
                    | '\u{200b}'..='\u{200f}' | '\u{202a}'..='\u{202e}'
                    | '\u{2060}'..='\u{206f}' | '\u{feff}' | '\u{fff9}'..='\u{fffb}'
                    | '\u{e0000}'..='\u{e007f}')
        })
        .take(max)
        .collect()
}

/// True when journald itself says systemd-coredump wrote the entry (trusted
/// `_COMM`/`_SYSTEMD_UNIT`; a user cannot run in a system unit) and the dump
/// is of `uid`'s process, by both the trusted `_UID` and COREDUMP_UID.
fn trusted_coredump(entry: &Value, uid: &str) -> bool {
    !uid.is_empty()
        && field(entry, "_COMM").as_deref() == Some("systemd-coredum")
        && field(entry, "_SYSTEMD_UNIT")
            .is_some_and(|u| u.starts_with("systemd-coredump@") && u.ends_with(".service"))
        && field(entry, "_UID").as_deref() == Some(uid)
        && field(entry, "COREDUMP_UID").as_deref() == Some(uid)
}

/// Where a crashed process lived, read from the fields systemd-coredump
/// records about it. Only the host's own crashes (and Flatpak apps) are the
/// owner's to report: development containers share the kernel, so the host's
/// systemd-coredump records every crash in them, test binaries and Plasma
/// processes run inside a podman test image included.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Origin {
    /// A program of the OS, running on the host.
    Host,
    /// A Flatpak app, by its app ID.
    Flatpak(String),
    /// In a container or machine (podman, toolbox, distrobox, docker, nspawn,
    /// LXC, Kubernetes): not the host's crash.
    Container,
    /// A program that is not part of the OS (`/work`, `/tmp`, a build tree
    /// or anything else outside [`SYSTEM_PREFIXES`]) and not a Flatpak app.
    Foreign,
}

impl Origin {
    /// Whether a crash of this origin is left out of the reports.
    fn ignored(&self) -> bool {
        matches!(self, Origin::Container | Origin::Foreign)
    }
}

/// Whether one cgroup path component (or unit name) holds a container or a
/// machine. Container managers name their scopes after the runtime
/// (`libpod-<id>.scope` for podman, toolbox and distrobox, `docker-<id>.scope`,
/// `crio-<id>.scope`, `machine-<name>.scope` for systemd-nspawn and libvirt),
/// and `docker/<id>`, `lxc.payload.<name>` and `kubepods*` are theirs when the
/// runtime uses cgroupfs.
fn is_container_cgroup(component: &str) -> bool {
    // podman's own supervisor runs on the host, in a scope of this name
    if component.starts_with("libpod-conmon-") {
        return false;
    }
    const PREFIXES: &[&str] = &[
        "libpod-",
        "libpod_",
        "docker-",
        "crio-",
        "cri-containerd-",
        "machine-",
        "lxc.payload.",
        "lxc.monitor.",
        "kubepods",
    ];
    const NAMES: &[&str] = &["docker", "lxc", "machine.slice", "libpod_parent"];
    PREFIXES.iter().any(|p| component.starts_with(p)) || NAMES.contains(&component)
}

/// The app ID of a Flatpak scope (`app-flatpak-<id>-<n>.scope`, or the
/// `flatpak-<id>-<n>.scope` older Flatpaks used); `None` for any other name
/// or an ID that is not a valid reverse-DNS name.
fn flatpak_scope_app(component: &str) -> Option<String> {
    let body = component.strip_suffix(".scope")?;
    let body = body
        .strip_prefix("app-flatpak-")
        .or_else(|| body.strip_prefix("flatpak-"))?;
    // systemd escapes a dash in a name as \x2d
    let (id, n) = body.rsplit_once('-')?;
    let id = id.replace("\\x2d", "-");
    let valid = n.chars().all(|c| c.is_ascii_digit())
        && !n.is_empty()
        && (3..=255).contains(&id.len())
        && id.contains('.')
        && id.split('.').all(|p| {
            !p.is_empty()
                && p.chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        });
    valid.then_some(id)
}

/// Where the crashed process of a coredump entry lived. `exe` is its
/// validated `COREDUMP_EXE` (empty when missing or odd).
///
/// In order: a container's cgroup (`COREDUMP_CGROUP`, else the unit fields)
/// or, without one, a hostname that differs from the host's while the process
/// sits in another PID namespace (`COREDUMP_CONTAINER_CMDLINE` is set) means
/// a container; a Flatpak scope means that Flatpak app; a program outside the
/// OS's own directories is foreign. Without these fields (older systemd) an
/// entry counts as the host's, so a real crash is never lost to a missing
/// field.
fn coredump_origin(entry: &Value, exe: &str) -> Origin {
    let mut flatpak = None;
    for key in ["COREDUMP_CGROUP", "COREDUMP_USER_UNIT", "COREDUMP_UNIT"] {
        let Some(v) = field(entry, key) else { continue };
        for component in v.split('/').filter(|c| !c.is_empty()) {
            if is_container_cgroup(component) {
                return Origin::Container;
            }
            if flatpak.is_none() {
                flatpak = flatpak_scope_app(component);
            }
        }
    }
    if flatpak.is_none()
        && field(entry, "COREDUMP_CONTAINER_CMDLINE").is_some()
        && matches!(
            (field(entry, "_HOSTNAME"), field(entry, "COREDUMP_HOSTNAME")),
            (Some(host), Some(theirs)) if !host.eq_ignore_ascii_case(&theirs)
        )
    {
        return Origin::Container;
    }
    if let Some(id) = flatpak {
        return Origin::Flatpak(id);
    }
    if !exe.is_empty() && !SYSTEM_PREFIXES.iter().any(|p| exe.starts_with(p)) {
        return Origin::Foreign;
    }
    Origin::Host
}

/// What a trusted coredump entry says, before it becomes a report.
struct Coredump {
    ts: u64,
    exe: String,
    comm: String,
    signal: String,
    origin: Origin,
}

impl Coredump {
    /// `None` for an entry systemd-coredump did not write for `uid` (see
    /// [`trusted_coredump`]) or one without a timestamp.
    fn parse(entry: &Value, uid: &str) -> Option<Coredump> {
        if !trusted_coredump(entry, uid) {
            return None;
        }
        let ts: u64 = field(entry, "COREDUMP_TIMESTAMP")?.parse().ok()?;
        let exe = field(entry, "COREDUMP_EXE")
            .filter(|e| valid_exe(e))
            .unwrap_or_default();
        let comm = clean(
            &field(entry, "COREDUMP_COMM").unwrap_or_default(),
            64,
            false,
        );
        let signal = field(entry, "COREDUMP_SIGNAL_NAME")
            .map(|s| clean(&s, 64, false))
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "unknown signal".into());
        let origin = coredump_origin(entry, &exe);
        Some(Coredump {
            ts,
            exe,
            comm,
            signal,
            origin,
        })
    }

    fn time(&self) -> String {
        history::rfc3339_from_unix(self.ts / 1_000_000)
    }

    /// The program as a host crash names it: its path as [`redact_exe`]
    /// shows it, else the command name.
    fn host_name(&self, scrubber: &Scrubber) -> String {
        let name = if self.exe.is_empty() {
            self.comm.clone()
        } else {
            redact_exe(&self.exe, scrubber)
        };
        scrubber.scrub(&name)
    }

    fn host_message(&self, scrubber: &Scrubber) -> String {
        format!(
            "{} crashed with {}",
            scrubber.scrub(&self.comm),
            self.signal
        )
    }
}

/// One coredump journal entry (`journalctl -o json`) as a report plus its
/// timestamp in microseconds. Entries not written by systemd-coredump for
/// `uid` are dropped (COREDUMP_* fields can be forged by any local user; the
/// `_`-prefixed ones are added by journald and cannot), and so are crashes
/// that are not the host's (see [`Origin`]). Reads only COREDUMP_EXE, COMM,
/// SIGNAL_NAME, TIMESTAMP, PACKAGE_NAME/VERSION and MESSAGE (and only frame
/// lines of it), and for the origin the cgroup, unit and host name fields,
/// of which nothing is copied.
fn coredump_report(
    entry: &Value,
    scrubber: &Scrubber,
    uid: &str,
    rpm_version: impl Fn(&str) -> Option<String>,
) -> Option<(u64, Report)> {
    let dump = Coredump::parse(entry, uid)?;
    if dump.origin.ignored() {
        return None;
    }
    let (name, version) = match &dump.origin {
        // the host's rpm database knows nothing of a sandbox
        Origin::Flatpak(id) => (
            id.clone(),
            field(entry, "COREDUMP_PACKAGE_VERSION")
                .map(|v| clean(&v, 128, false))
                .filter(|v| !v.is_empty()),
        ),
        _ => (
            dump.host_name(scrubber),
            match (
                field(entry, "COREDUMP_PACKAGE_NAME"),
                field(entry, "COREDUMP_PACKAGE_VERSION"),
            ) {
                (_, Some(v)) => Some(clean(&v, 128, false)).filter(|v| !v.is_empty()),
                _ if !dump.exe.is_empty() => rpm_version(&dump.exe),
                _ => None,
            },
        ),
    };
    let time = dump.time();
    let crash = Crash {
        report_type: "coredump",
        app_name: &name,
        app_version: version.as_deref(),
        message: &dump.host_message(scrubber),
        stacktrace: &clean(&field(entry, "MESSAGE").unwrap_or_default(), 8192, true),
    };
    let mut report = build_report(&crash, scrubber, Some(&time)).ok()?;
    if let Origin::Flatpak(id) = &dump.origin {
        // The app ID labels the report. Scrubbing a whole long ID takes it for
        // an access token, so each part is scrubbed on its own.
        report.app_name = id
            .split('.')
            .map(|part| scrubber.scrub(part))
            .collect::<Vec<_>>()
            .join(".");
    }
    Some((dump.ts, report))
}

/// Where installed programs live: a crashed program's path under one of
/// these is kept whole.
const SYSTEM_PREFIXES: &[&str] = &[
    "/usr/",
    "/bin/",
    "/sbin/",
    "/lib/",
    "/lib64/",
    "/opt/",
    "/app/",
    "/var/lib/flatpak/",
];

/// A crashed program's path as it may be shown: a system path whole; under
/// a home directory `<home>/<program>`; anywhere else (`/mnt/clients/...`,
/// `/srv/...`, a build tree) `<path>/<program>`. The program name stays: it
/// is the crash's subject, and the message has it already.
fn redact_exe(exe: &str, scrubber: &Scrubber) -> String {
    if SYSTEM_PREFIXES.iter().any(|p| exe.starts_with(p)) {
        return exe.to_string();
    }
    let base = exe.rsplit('/').next().unwrap_or("");
    // `/home/`, `/var/home/` and the same inside an ostree deployment
    let home = exe.contains("/home/")
        || ["/root/", "/var/roothome/"]
            .iter()
            .any(|p| exe.starts_with(p))
        || scrubber.homes.iter().any(|h| {
            exe.strip_prefix(h.as_str())
                .is_some_and(|r| r.starts_with('/'))
        });
    format!("{}/{base}", if home { "<home>" } else { "<path>" })
}

fn own_uid() -> String {
    read("/proc/self/status")
        .lines()
        .find_map(|l| {
            l.strip_prefix("Uid:")?
                .split_whitespace()
                .next()
                .map(str::to_string)
        })
        .unwrap_or_default()
}

/// How long one `journalctl` call may take.
const JOURNAL_LIMIT: Duration = Duration::from_secs(10);
/// How long one `rpm -qf` may take: it waits on the rpmdb lock while an
/// update runs.
const RPM_LIMIT: Duration = Duration::from_secs(5);
/// The most of journalctl's output that is kept (500 entries of capped
/// fields are far less).
const JOURNAL_MAX_OUT: usize = 16 * 1024 * 1024;

/// Run `cmd` (no stdin or stderr, a clean environment) for at most `limit`.
/// Past it the command's whole process group is killed and `None` returned.
/// At most `max_out` bytes of its output are kept; the rest is read and
/// dropped, so it never blocks on a full pipe.
fn output_within(
    cmd: &mut Command,
    limit: Duration,
    max_out: usize,
) -> Option<(std::process::ExitStatus, Vec<u8>)> {
    use std::os::unix::process::CommandExt;
    let end = Instant::now() + limit;
    let mut child = cmd
        .env_clear()
        .env("PATH", "/usr/bin")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        // its own group, so a child it started dies with it
        .process_group(0)
        .spawn()
        .ok()?;
    let Some(mut stdout) = child.stdout.take() else {
        kill_group(&mut child);
        return None;
    };
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = (&mut stdout).take(max_out as u64).read_to_end(&mut buf);
        let _ = io::copy(&mut stdout, &mut io::sink());
        let _ = tx.send(buf);
    });
    let status = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s,
            Ok(None) if Instant::now() < end => std::thread::sleep(Duration::from_millis(5)),
            _ => {
                kill_group(&mut child);
                return None;
            }
        }
    };
    // The output is whole once the pipe closes; something it left running
    // that holds the pipe gets until the deadline.
    let wait = end
        .saturating_duration_since(Instant::now())
        .max(Duration::from_millis(100));
    match rx.recv_timeout(wait) {
        Ok(out) => Some((status, out)),
        Err(_) => {
            kill_group(&mut child);
            None
        }
    }
}

/// SIGKILL to the group `child` leads (see [`output_within`]), then reap it.
fn kill_group(child: &mut std::process::Child) {
    if let Ok(pid) = i32::try_from(child.id()) {
        // SAFETY: kill has no memory preconditions; -pid is the process
        // group the child was made the leader of.
        unsafe { libc::kill(-pid, libc::SIGKILL) };
    }
    let _ = child.kill();
    let _ = child.wait();
}

fn journal(args: &[String]) -> Vec<Value> {
    journal_with(Path::new("/usr/bin/journalctl"), args, JOURNAL_LIMIT)
}

/// The JSON lines `program args` prints within `limit`; nothing on an
/// error or past the limit.
fn journal_with(program: &Path, args: &[String], limit: Duration) -> Vec<Value> {
    match output_within(Command::new(program).args(args), limit, JOURNAL_MAX_OUT) {
        Some((status, out)) if status.success() => String::from_utf8_lossy(&out)
            .lines()
            .filter_map(|l| serde_json::from_str(l).ok())
            .collect(),
        _ => Vec::new(),
    }
}

/// The journal fields we read; `--output-fields` keeps the rest (command
/// line, environment, working directory, ...) out of this process. The last
/// six only tell a crash on the host from one in a container (see [`Origin`]);
/// whether `COREDUMP_CONTAINER_CMDLINE` is set matters, never its value.
const JOURNAL_FIELDS: &str = "MESSAGE,COREDUMP_EXE,COREDUMP_COMM,COREDUMP_SIGNAL_NAME,COREDUMP_TIMESTAMP,COREDUMP_PACKAGE_NAME,COREDUMP_PACKAGE_VERSION,COREDUMP_UID,_UID,_COMM,_SYSTEMD_UNIT,COREDUMP_CGROUP,COREDUMP_USER_UNIT,COREDUMP_UNIT,COREDUMP_CONTAINER_CMDLINE,COREDUMP_HOSTNAME,_HOSTNAME";

/// journalctl arguments for coredump entries after `since_micros` (and, when
/// given, before `until_micros`).
fn journal_args(since_micros: u64, until_micros: Option<u64>, uid: Option<&str>) -> Vec<String> {
    let mut a: Vec<String> = ["--no-pager", "--all", "-o", "json", "-n", "500"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    a.push(format!("--output-fields={JOURNAL_FIELDS}"));
    a.push(format!("--since=@{}", since_micros / 1_000_000));
    if let Some(until) = until_micros {
        a.push(format!("--until=@{}", until / 1_000_000));
    }
    a.push(format!("MESSAGE_ID={COREDUMP_MESSAGE_ID}"));
    // trusted field (journald sets it; comm is truncated to 15 chars)
    a.push("_COMM=systemd-coredum".into());
    match uid {
        Some(u) => {
            // trusted uid, filtered by journald before the -n limit so
            // forged entries of other users can't push ours out
            a.push(format!("_UID={u}"));
            a.push(format!("COREDUMP_UID={u}"));
        }
        None => a.insert(0, "--user".into()),
    }
    a
}

/// The user's coredump entries in the journal after `since_micros` (and
/// before `until_micros`): the user journal, else the system journal filtered
/// to our UID (readable for members of `wheel`/`systemd-journal`).
fn coredump_entries(since_micros: u64, until_micros: Option<u64>) -> Vec<Value> {
    let entries = journal(&journal_args(since_micros, until_micros, None));
    if !entries.is_empty() {
        return entries;
    }
    journal(&journal_args(since_micros, until_micros, Some(&own_uid())))
}

/// The package owning `exe`; `Err` (`TimedOut`) when rpm took longer than
/// [`RPM_LIMIT`].
fn rpm_version(exe: &str) -> io::Result<Option<String>> {
    let mut cmd = Command::new("/usr/bin/rpm");
    cmd.args(["-qf", "--qf", "%{NAME} %{VERSION}-%{RELEASE}", "--", exe]);
    let (status, out) = output_within(&mut cmd, RPM_LIMIT, 4096)
        .ok_or_else(|| io::Error::new(io::ErrorKind::TimedOut, "rpm took too long"))?;
    Ok(status
        .success()
        .then(|| String::from_utf8_lossy(&out).trim().to_string())
        .filter(|s| !s.is_empty()))
}

/// Package lookups for one collection run: each program is asked once, and
/// after a lookup times out (the rpmdb is locked by an update) none is
/// asked again, so a run of many crashes costs one timeout, not one each.
struct RpmLookup<F: Fn(&str) -> io::Result<Option<String>>> {
    query: F,
    seen: std::cell::RefCell<std::collections::HashMap<String, Option<String>>>,
    off: Cell<bool>,
}

impl<F: Fn(&str) -> io::Result<Option<String>>> RpmLookup<F> {
    fn new(query: F) -> Self {
        RpmLookup {
            query,
            seen: Default::default(),
            off: Cell::new(false),
        }
    }

    fn version(&self, exe: &str) -> Option<String> {
        if self.off.get() {
            return None;
        }
        if let Some(v) = self.seen.borrow().get(exe) {
            return v.clone();
        }
        match (self.query)(exe) {
            Ok(v) => {
                self.seen.borrow_mut().insert(exe.to_string(), v.clone());
                v
            }
            Err(_) => {
                self.off.set(true);
                None
            }
        }
    }
}

/// New systemd-coredump crashes of the user's own processes since the last
/// call (or since `since_micros`), queued as pending reports. Returns them.
/// The first call after opting in starts at "now": nothing older is read.
/// Tries the user journal, then the system journal filtered to our UID
/// (readable for members of `wheel`/`systemd-journal`). Empty when disabled.
///
/// Blocks: it runs `journalctl` (up to twice, 10 s each at most) and
/// `rpm -qf` for programs without a package field (5 s at most; after one
/// timeout, as when an update holds the rpmdb lock, no more this call), so
/// up to about 25 s (once, after an update that raised the origin rules, up
/// to 12 more journal lookups for the pending reports). Call it from a worker
/// thread, never the GUI thread.
pub fn collect_coredumps(since_micros: Option<u64>) -> Vec<Report> {
    if !Settings::load().enabled {
        return Vec::new();
    }
    prune_sent();
    purge_ignored_pending();
    let Some(marker) = last_seen_path("coredump-last") else {
        return Vec::new();
    };
    let Some(since) = since_micros.or_else(|| read_coredump_marker(&marker)) else {
        reset_markers(); // first run: only crashes from now on
        return Vec::new();
    };
    let entries = coredump_entries(since, None);
    let scrubber = Scrubber::from_env();
    let uid = own_uid();
    let rpm = RpmLookup::new(rpm_version);
    let mut newest = since;
    let mut out = Vec::new();
    for e in &entries {
        // cheap check first: no rpm, no report for entries already seen
        let Some(ts) = field(e, "COREDUMP_TIMESTAMP").and_then(|t| t.parse::<u64>().ok()) else {
            continue;
        };
        if ts <= since {
            continue;
        }
        // not the host's crash (a container, a build tree): never a report,
        // and the marker moves past it
        if Coredump::parse(e, &uid).is_some_and(|d| d.origin.ignored()) {
            newest = newest.max(ts);
            continue;
        }
        let Some((_, report)) = coredump_report(e, &scrubber, &uid, |x| rpm.version(x)) else {
            continue;
        };
        let Some(d) = reports_dir() else { break };
        // opted out while collecting: write nothing more
        if !Settings::load().enabled {
            break;
        }
        // the same crash again (a restart loop): seen, not queued
        if !ledger_allow(&d, SystemTime::now(), coredump_key(&report), false) {
            newest = newest.max(ts);
            continue;
        }
        let mut r = report;
        match write_report(&d.join("pending"), &r) {
            Ok(path) => r.path = Some(path),
            // Not written (disk full, ...): the marker stays before this
            // entry, so the next run tries again.
            Err(_) => break,
        }
        newest = newest.max(ts);
        out.push(r);
    }
    // Switched off during the run (the opt-out deletes pending files, and may
    // have run before our last write): take back what this call wrote.
    if !Settings::load().enabled {
        discard_written(&out);
        return Vec::new();
    }
    if newest > since {
        let _ = write_private(&marker, newest.to_string().as_bytes(), true);
    }
    if let Some(d) = reports_dir() {
        cap_pending(&d.join("pending"), MAX_PENDING);
    }
    still_pending(out)
}

/// The coredump marker in microseconds; `None` only when there is none. An
/// empty or damaged one (an older version wrote it in place and was cut
/// short) counts from when it was last written, its modification time, so
/// it neither restarts at "now" (skipping every crash since) nor reads the
/// whole journal again.
fn read_coredump_marker(marker: &Path) -> Option<u64> {
    let text = match fs::read(marker) {
        Ok(t) => t,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return None,
        Err(_) => Vec::new(),
    };
    if let Some(n) = std::str::from_utf8(&text)
        .ok()
        .and_then(|t| t.trim().parse::<u64>().ok())
    {
        return Some(n);
    }
    marker_mtime(marker).map(|d| d.as_micros() as u64)
}

/// When a marker file was last written, since the epoch.
fn marker_mtime(marker: &Path) -> Option<Duration> {
    fs::symlink_metadata(marker)
        .and_then(|m| m.modified())
        .ok()?
        .duration_since(UNIX_EPOCH)
        .ok()
}

/// Delete the pending files of reports a collector just wrote.
fn discard_written(reports: &[Report]) {
    for r in reports {
        if let Some(p) = &r.path {
            let _ = fs::remove_file(p);
        }
    }
}

/// The version of [`coredump_origin`]'s rules the pending queue was last
/// cleaned with (`coredump-rules` in the state directory). Raise it when the
/// rules start leaving out more, and the next collection cleans again.
const ORIGIN_RULES: &str = "1";

/// Once per [`ORIGIN_RULES`] version: deletes the pending coredump reports
/// that the current rules would not have queued (an older version queued
/// every crash it found, container ones included). The marker is written when
/// the journal could be asked, so a failed `journalctl` is tried again.
fn purge_ignored_pending() {
    let (Some(dir), Some(marker)) = (reports_dir(), last_seen_path("coredump-rules")) else {
        return;
    };
    if fs::read_to_string(&marker).is_ok_and(|t| t.trim() == ORIGIN_RULES) {
        return;
    }
    let done = purge_ignored_in(
        &dir.join("pending"),
        &Scrubber::from_env(),
        &own_uid(),
        |since, until| coredump_entries(since, Some(until)),
    );
    if done.is_some() {
        let _ = write_private(&marker, ORIGIN_RULES.as_bytes(), true);
    }
}

/// Deletes the coredump reports in `pending` whose crash the rules ignore and
/// returns how many. A report keeps no cgroup, so each is matched to its
/// journal entry (`lookup(since, until)` in microseconds) by its time, program
/// and message; one made from a program outside the OS is known by its name
/// alone (`<path>/...`, `<home>/...`). `None` when reports were left
/// undecided because the journal had nothing for them.
fn purge_ignored_in(
    pending: &Path,
    scrubber: &Scrubber,
    uid: &str,
    lookup: impl Fn(u64, u64) -> Vec<Value>,
) -> Option<usize> {
    let remove = |r: &Report| {
        if let Some(p) = &r.path {
            let _ = fs::remove_file(p);
        }
    };
    let mut removed = 0;
    let mut undecided = Vec::new();
    for r in read_reports(pending)
        .into_iter()
        .filter(|r| r.report_type == "coredump")
    {
        if r.app_name.starts_with("<path>/") || r.app_name.starts_with("<home>/") {
            remove(&r);
            removed += 1;
        } else {
            undecided.push(r);
        }
    }
    if undecided.is_empty() {
        return Some(removed);
    }
    let mut seconds: Vec<u64> = undecided
        .iter()
        .filter_map(|r| unix_from_rfc3339(&r.time))
        .collect();
    seconds.sort_unstable();
    seconds.dedup();
    let mut ignored = std::collections::HashSet::new();
    let mut kept = std::collections::HashSet::new();
    let mut found = false;
    let mut i = 0;
    let mut groups = 0;
    while i < seconds.len() && groups < MAX_PURGE_LOOKUPS {
        // One journal call for crashes that are close together, never for a
        // span longer than [`PURGE_SPAN`]. The journal files an entry when
        // the core has been written and its trace made, which takes a while
        // for a big program: the window reaches [`PURGE_LATE`] seconds past
        // the crash.
        let (first, mut last) = (seconds[i], seconds[i]);
        while i + 1 < seconds.len()
            && seconds[i + 1] - last <= 5
            && seconds[i + 1] - first <= PURGE_SPAN
        {
            i += 1;
            last = seconds[i];
        }
        i += 1;
        groups += 1;
        let entries = lookup(
            first.saturating_sub(1) * 1_000_000,
            (last + PURGE_LATE) * 1_000_000,
        );
        found |= !entries.is_empty();
        for d in entries.iter().filter_map(|e| Coredump::parse(e, uid)) {
            let key = (
                d.time(),
                d.host_name(scrubber),
                scrubber.scrub_message(&cap_message(&d.host_message(scrubber))),
            );
            if d.origin.ignored() {
                ignored.insert(key);
            } else {
                kept.insert(key);
            }
        }
    }
    for r in &undecided {
        let key = (r.time.clone(), r.app_name.clone(), r.message.clone());
        // a host crash of the same program in the same second stays
        if ignored.contains(&key) && !kept.contains(&key) {
            remove(r);
            removed += 1;
        }
    }
    found.then_some(removed)
}

/// The most seconds one purge lookup spans, how long after a crash its entry
/// may be filed, and how many lookups one purge makes.
const PURGE_SPAN: u64 = 60;
const PURGE_LATE: u64 = 120;
const MAX_PURGE_LOOKUPS: usize = 12;

/// Unix seconds of a `YYYY-MM-DDTHH:MM:SSZ` time (what [`now_rfc3339`] and
/// the coredump reports use); `None` for any other shape.
fn unix_from_rfc3339(t: &str) -> Option<u64> {
    let b = t.as_bytes();
    if b.len() != 20
        || (b[4], b[7], b[10], b[13], b[16], b[19]) != (b'-', b'-', b'T', b':', b':', b'Z')
    {
        return None;
    }
    let n = |r: std::ops::Range<usize>| t.get(r)?.parse::<i64>().ok();
    let (y, m, d) = (n(0..4)?, n(5..7)?, n(8..10)?);
    let (h, mi, sec) = (n(11..13)?, n(14..16)?, n(17..19)?);
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) || h > 23 || mi > 59 || sec > 60 {
        return None;
    }
    // days from civil
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * ((m + 9) % 12) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    u64::try_from(days * 86_400 + h * 3600 + mi * 60 + sec).ok()
}

// --------------------------------------------------------------- events

/// Reports for helper events (update and rollback results) newer than the
/// last call (or `since`, an RFC 3339 time), queued as pending. The first call
/// after opting in starts at "now". Every string copied from the event log is
/// scrubbed again. Empty when disabled.
///
/// Blocks on file I/O (the event log, the history, `/proc` and `/sys`):
/// call it from a worker thread, like [`collect_coredumps`].
pub fn collect_events(since: Option<&str>) -> Vec<Report> {
    if !Settings::load().enabled {
        return Vec::new();
    }
    prune_sent();
    let (Some(marker), Some(d)) = (last_seen_path("events-last"), reports_dir()) else {
        return Vec::new();
    };
    let events = crate::events::read(Path::new(crate::events::DEFAULT_PATH));
    let scrubber = Scrubber::from_env();
    let enabled = || Settings::load().enabled;
    match collect_events_in(
        &events,
        &marker,
        &d.join("pending"),
        &scrubber,
        &now_rfc3339(),
        since,
        &enabled,
    ) {
        Some(out) => out,
        None => {
            reset_markers(); // first run: only events from now on
            Vec::new()
        }
    }
}

/// The only helper events that become reports: the failures. Successes
/// (`update-staged`, `update-applied`, ...) are skipped.
const REPORTED_EVENTS: [&str; 5] = [
    "update-failed",
    "rollback-failed",
    "channel-switch-failed",
    "automatic-rollback",
    "health-check-failed",
];

/// The work of [`collect_events`] with every input given: `None` when there is
/// no marker yet (and no `since`). `enabled` is asked again right before each
/// report is written, so turning reporting off mid-run writes nothing more.
///
/// A marker without a count (written by an older version) means "the events
/// at that time were taken": they are counted from `events`. `since` is
/// inclusive: events at exactly that time are collected.
fn collect_events_in(
    events: &[crate::events::Event],
    marker: &Path,
    pending: &Path,
    scrubber: &Scrubber,
    now: &str,
    since: Option<&str>,
    enabled: &dyn Fn() -> bool,
) -> Option<Vec<Report>> {
    let start = match since {
        Some(s) => (s.to_string(), 0),
        None => read_event_marker(marker, events)?,
    };
    let mut marker_now = start.clone();
    let mut out = Vec::new();
    for e in pick_events(events, &start, now) {
        if !REPORTED_EVENTS.contains(&e.event.as_str()) {
            marker_now = advance_event_marker(marker_now, &e.time);
            continue;
        }
        let name = scrubber.scrub_message(&e.event);
        let version = e.version.as_deref().map(|v| scrubber.scrub_message(v));
        let mut msg = name.clone();
        if let Some(v) = &version {
            msg.push_str(&format!(" (version {v})"));
        }
        if let Some(err) = &e.error {
            msg.push_str(&format!(": {err}"));
        }
        let crash = Crash {
            report_type: &name,
            app_name: "atlas-system-helper",
            app_version: Some(env!("CARGO_PKG_VERSION")),
            message: &msg,
            stacktrace: "",
        };
        let Ok(mut r) = build_report(&crash, scrubber, Some(&e.time)) else {
            // can never be built (a damaged line): skip it for good
            marker_now = advance_event_marker(marker_now, &e.time);
            continue;
        };
        r.report_type = scrubber.scrub_message(&name);
        if r.atlasos_version.is_none() {
            r.atlasos_version = version.as_deref().and_then(plain_version);
        }
        if !enabled() {
            break;
        }
        match write_report(pending, &r) {
            Ok(path) => r.path = Some(path),
            // A line that can never be written (bad time): skip it for good.
            Err(e2) if e2.kind() == io::ErrorKind::InvalidInput => {
                marker_now = advance_event_marker(marker_now, &e.time);
                continue;
            }
            // Not written (disk full ...): the marker stays before this event.
            Err(_) => break,
        }
        marker_now = advance_event_marker(marker_now, &e.time);
        out.push(r);
    }
    if !enabled() {
        discard_written(&out);
        return Some(Vec::new());
    }
    if marker_now != start {
        let _ = write_private(
            marker,
            format!("{} {}", marker_now.0, marker_now.1).as_bytes(),
            true,
        );
    }
    cap_pending(pending, MAX_PENDING);
    Some(still_pending(out))
}

/// The events marker: the time of the last collected event and how many events
/// with exactly that time were taken (second resolution; the helper may append
/// another one in the same second later).
type EventMarker = (String, usize);

/// The events marker; `None` only when there is none. An empty or damaged
/// one counts from its modification time (see [`read_coredump_marker`]),
/// the events of that second taken.
fn read_event_marker(marker: &Path, events: &[crate::events::Event]) -> Option<EventMarker> {
    let text = match fs::read(marker) {
        Ok(t) => String::from_utf8(t).unwrap_or_default(),
        Err(e) if e.kind() == io::ErrorKind::NotFound => return None,
        Err(_) => String::new(),
    };
    let m = parse_event_marker(&text, events);
    if looks_like_time(&m.0) {
        return Some(m);
    }
    let at = history::rfc3339_from_unix(marker_mtime(marker)?.as_secs());
    Some(parse_event_marker(&at, events))
}

/// Starts like an RFC 3339 time: `dddd-dd-ddTdd:dd:dd`.
fn looks_like_time(t: &str) -> bool {
    let b = t.as_bytes();
    b.len() >= 19
        && b[..19].iter().enumerate().all(|(i, c)| match i {
            4 | 7 => *c == b'-',
            10 => *c == b'T',
            13 | 16 => *c == b':',
            _ => c.is_ascii_digit(),
        })
}

fn parse_event_marker(text: &str, events: &[crate::events::Event]) -> EventMarker {
    let mut it = text.split_whitespace();
    let time = it.next().unwrap_or("").to_string();
    // no count: an older marker; those events were already taken
    let n = it
        .next()
        .and_then(|n| n.parse().ok())
        .unwrap_or_else(|| events.iter().filter(|e| e.time == time).count());
    (time, n)
}

fn advance_event_marker(m: EventMarker, time: &str) -> EventMarker {
    if m.0 == time {
        (m.0, m.1 + 1)
    } else {
        (time.to_string(), 1)
    }
}

/// Events (in file order) after the marker. Events dated after `now` (clock
/// skew) wait until their time has come, so they cannot push the marker into
/// the future and hide later ones.
///
/// Events from a time when reporting was off are never collected: opting in
/// again starts the marker at "now" (see `reset_markers`), so what happened
/// while the user had it off is not reported afterwards.
fn pick_events<'a>(
    events: &'a [crate::events::Event],
    marker: &EventMarker,
    now: &str,
) -> Vec<&'a crate::events::Event> {
    let mut at_marker = 0;
    let mut out = Vec::new();
    for e in events {
        if e.time.as_str() > now || e.time < marker.0 {
            continue;
        }
        if e.time == marker.0 {
            at_marker += 1;
            if at_marker <= marker.1 {
                continue;
            }
        }
        out.push(e);
    }
    out
}

// ------------------------------------------------------------- reporting

/// POST the report's [`payload`](Report::payload) to GlitchTip (Sentry store
/// API) and move it to `sent/`. The caller must have shown the user the
/// payload and got a yes. Fails when crash reporting is off or no endpoint is
/// configured. Uses `/usr/bin/curl`.
pub fn send(report: &Report) -> io::Result<()> {
    let pending = reports_dir().map(|d| d.join("pending"));
    send_with(
        report,
        Settings::load().enabled,
        Endpoint::load(),
        pending.as_deref(),
    )
}

/// [`send`] with every input given; `pending` is the pending directory.
fn send_with(
    report: &Report,
    enabled: bool,
    ep: Option<Endpoint>,
    pending: Option<&Path>,
) -> io::Result<()> {
    if !enabled {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "crash reporting is turned off",
        ));
    }
    let ep = ep.ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no endpoint configured"))?;
    // Two senders of one report (two windows, a double click) would file
    // two public issues: the first to claim it sends it.
    // Only a file in `pending/` is taken (and later removed); a report
    // whose path points anywhere else is sent and its file left alone.
    let claim = report
        .path
        .as_deref()
        .filter(|p| pending.is_some_and(|d| is_pending_file(d, p)))
        .map(Claim::take)
        .transpose()?;
    // a failed POST drops the claim, which puts the report back
    let server = post(report, &ep)?;
    finish_sent(report, server);
    if let Some(c) = claim {
        c.finish();
    }
    Ok(())
}

/// The suffix of a pending report taken for sending.
const CLAIM_SUFFIX: &str = ".sending";

/// A pending report taken by one sender: renamed to `<name>.sending`, which
/// no list shows and no other sender can take. Dropped without
/// [`finish`](Claim::finish), it is renamed back; one left by a killed
/// process is put back after 10 minutes ([`sweep_claims`]).
struct Claim {
    from: PathBuf,
    held: PathBuf,
    sent: bool,
}

impl Claim {
    fn take(path: &Path) -> io::Result<Claim> {
        let mut held = path.as_os_str().to_os_string();
        held.push(CLAIM_SUFFIX);
        let held = PathBuf::from(held);
        match fs::rename(path, &held) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                return Err(io::Error::new(
                    io::ErrorKind::AlreadyExists,
                    "the report is being sent, or is no longer pending",
                ));
            }
            Err(e) => return Err(e),
        }
        // a rename keeps the old time: mark when the claim was taken
        if let Ok(f) = fs::File::open(&held) {
            let _ = f.set_modified(SystemTime::now());
        }
        Ok(Claim {
            from: path.to_path_buf(),
            held,
            sent: false,
        })
    }

    /// Sent: the claimed file goes.
    fn finish(mut self) {
        self.sent = true;
        let _ = fs::remove_file(&self.held);
        if let Some(d) = self.held.parent() {
            sync_dir(d);
        }
    }
}

impl Drop for Claim {
    fn drop(&mut self) {
        // (gone if reporting was turned off meanwhile: then it stays gone)
        if !self.sent {
            let _ = fs::rename(&self.held, &self.from);
        }
    }
}

/// Put back the claims of senders that were killed (older than 10 minutes:
/// a send takes 30 s at most).
fn sweep_claims(dir: &Path, now: SystemTime) {
    for e in fs::read_dir(dir).into_iter().flatten().flatten() {
        let p = e.path();
        let Some(name) = p.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        let Some(orig) = name.strip_suffix(CLAIM_SUFFIX) else {
            continue;
        };
        if !orig.ends_with(".json") || !is_stale(&e, now) {
            continue;
        }
        let to = dir.join(orig);
        if fs::symlink_metadata(&to).is_ok() {
            let _ = fs::remove_file(&p);
        } else {
            let _ = fs::rename(&p, &to);
        }
    }
}

/// curl's arguments: no config file, https only (http only for a loopback
/// DSN), no proxy, no redirects; the body comes from `body_file`.
fn curl_args(ep: &Endpoint, body_file: &Path) -> Vec<String> {
    let proto = if ep.store_url.starts_with("http://") {
        "=http"
    } else {
        "=https"
    };
    let auth = format!(
        "X-Sentry-Auth: Sentry sentry_version=7, sentry_key={}, sentry_client=atlas-core/{}",
        ep.key,
        env!("CARGO_PKG_VERSION")
    );
    let mut a: Vec<String> = [
        "-q",
        "--fail",
        "--silent",
        "--show-error",
        // after curl's error text, on stderr: the HTTP status, last line
        "--write-out",
        "%{stderr}\n%{http_code}\n",
        "--max-time",
        "30",
        "--max-redirs",
        "0",
        "--max-filesize",
        "65536",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    a.extend([
        "--proto".into(),
        proto.into(),
        "--noproxy".into(),
        "*".into(),
        "--request".into(),
        "POST".into(),
    ]);
    a.extend([
        "--header".into(),
        "Content-Type: application/json".into(),
        "--header".into(),
        auth,
    ]);
    a.extend([
        "--data-binary".into(),
        format!("@{}", body_file.display()),
        "--url".into(),
        ep.store_url.clone(),
    ]);
    a
}

/// What the relay answered: its event ID and the issue it filed.
#[derive(Debug, Default, PartialEq, Eq)]
struct Server {
    id: Option<String>,
    url: Option<String>,
}

const ISSUE_URL_PREFIX: &str = "https://github.com/EternalCoder454/AtlasOS/issues/";

/// Whether `u` is an issue of the Telamon OS project: the only link a sent
/// report may carry. Check it again wherever a stored link is shown.
pub fn is_issue_url(u: &str) -> bool {
    u.strip_prefix(ISSUE_URL_PREFIX)
        .is_some_and(|n| !n.is_empty() && n.len() <= 12 && n.bytes().all(|b| b.is_ascii_digit()))
}

/// The relay's answer is small; anything longer is not one.
const MAX_ANSWER: usize = 64 * 1024;

/// `{"id": ..., "url": ...}`; the url is kept only if it is an issue of the
/// Telamon OS project (the answer is not trusted to link anywhere else), the id
/// only if it is a plain event ID.
fn parse_server_answer(body: &[u8]) -> Server {
    if body.len() > MAX_ANSWER {
        return Server::default();
    }
    let v = serde_json::from_slice::<Value>(body).unwrap_or(Value::Null);
    let get = |k: &str| v.get(k).and_then(Value::as_str).map(str::to_string);
    Server {
        id: get("id").filter(|id| {
            (1..=64).contains(&id.len())
                && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
        }),
        url: get("url").filter(|u| is_issue_url(u)),
    }
}

/// Why a send failed, in words the app can show as they are (after "Could
/// not send the crash report: " or alone). Found in the [`io::Error`] that
/// [`send`] returns; see [`send_failure`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SendFailure {
    /// No answer: no connection, DNS failure, timeout.
    Unreachable,
    /// 429: too many reports (rate limit or daily quota).
    RateLimited,
    /// 5xx: the relay or GitHub behind it is having trouble or is busy.
    ServerTrouble,
    /// 400 or 413: the server will never take this report.
    Rejected,
    /// Anything else (401, 403, ...), with its HTTP status.
    Refused(u16),
    /// Some answer came but curl failed on it (cut off, too big, redirect).
    BadAnswer,
}

impl SendFailure {
    /// `http` is the status curl saw; 0 when there was no answer.
    fn from_http(http: u16) -> Self {
        match http {
            0 => Self::Unreachable,
            // a status below 400 with curl failed: the answer broke
            1..=399 => Self::BadAnswer,
            429 => Self::RateLimited,
            500..=599 => Self::ServerTrouble,
            400 | 413 => Self::Rejected,
            n => Self::Refused(n),
        }
    }

    fn kind(self) -> io::ErrorKind {
        match self {
            Self::Unreachable => io::ErrorKind::ConnectionRefused,
            Self::RateLimited | Self::ServerTrouble => io::ErrorKind::WouldBlock,
            Self::Rejected => io::ErrorKind::InvalidData,
            Self::Refused(_) | Self::BadAnswer => io::ErrorKind::Other,
        }
    }
}

impl std::fmt::Display for SendFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unreachable => f.write_str(
                "the crash report server could not be reached. Check the internet connection and try again later.",
            ),
            Self::RateLimited => f.write_str(
                "the crash report server has had too many reports today. Try again tomorrow.",
            ),
            Self::ServerTrouble => {
                f.write_str("the crash report server is having trouble. Try again later.")
            }
            Self::Rejected => f.write_str(
                "the server can't accept this report. You can delete it with Don't Send.",
            ),
            Self::BadAnswer => {
                f.write_str("the server's answer was not understood. Try again later.")
            }
            Self::Refused(n) => write!(
                f,
                "the crash report server refused it (HTTP {n}). Try again after the next update."
            ),
        }
    }
}

impl std::error::Error for SendFailure {}

/// The [`SendFailure`] inside an error from [`send`], if it is one.
pub fn send_failure(e: &io::Error) -> Option<&SendFailure> {
    e.get_ref()?.downcast_ref::<SendFailure>()
}

/// The status from the `--write-out` line, the last line of curl's stderr;
/// 0 when there is none (curl failed before an answer).
fn http_status(stderr: &str) -> u16 {
    stderr
        .lines()
        .rev()
        .map(str::trim)
        .find(|l| l.len() == 3 && l.bytes().all(|b| b.is_ascii_digit()))
        .and_then(|l| l.parse().ok())
        .unwrap_or(0)
}

fn post(report: &Report, ep: &Endpoint) -> io::Result<Server> {
    let dir = state_dir().ok_or_else(|| io::Error::other("no state directory"))?;
    post_in(&dir, report, ep)
}

/// [`post`] with the body file made in `dir`.
fn post_in(dir: &Path, report: &Report, ep: &Endpoint) -> io::Result<Server> {
    let body = serde_json::to_vec(&report.payload()).map_err(io::Error::other)?;
    // `payload` keeps to the limit unless the fields other than the trace and
    // message alone are over it: such a report is never sent
    if body.len() > MAX_PAYLOAD {
        return Err(io::Error::new(
            SendFailure::Rejected.kind(),
            SendFailure::Rejected,
        ));
    }
    let tmp = dir.join(format!("send-{}.json", random_hex(8)?));
    write_private(&tmp, &body, false)?;
    let out = run_curl(ep, &tmp);
    let _ = fs::remove_file(&tmp);
    let (status, stdout, stderr) = out?;
    if stdout.len() > MAX_ANSWER {
        // Sent, but the answer is not a relay's: stopped at the limit
        // (`--max-filesize` only holds when the length is announced).
        return Ok(Server::default());
    }
    if !status.success() {
        let text = String::from_utf8_lossy(&stderr);
        let http = http_status(&text);
        let failure = SendFailure::from_http(http);
        eprintln!(
            "telamon-framework: crash report not sent: {failure} (curl exit {:?}, HTTP {http:?}): {}",
            status.code(),
            text.trim()
        );
        return Err(io::Error::new(failure.kind(), failure));
    }
    Ok(parse_server_answer(&stdout))
}

/// curl's status, its answer (at most [`MAX_ANSWER`] + 1 bytes) and its
/// error text.
fn run_curl(
    ep: &Endpoint,
    body_file: &Path,
) -> io::Result<(std::process::ExitStatus, Vec<u8>, Vec<u8>)> {
    let mut child = Command::new("/usr/bin/curl")
        .args(curl_args(ep, body_file))
        .env_clear()
        .env("PATH", "/usr/bin")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let mut answer = Vec::new();
    let read = child.stdout.take().map_or(Ok(0), |o| {
        o.take(MAX_ANSWER as u64 + 1).read_to_end(&mut answer)
    });
    if read.is_err() || answer.len() > MAX_ANSWER {
        let _ = child.kill();
    }
    let out = child.wait_with_output()?;
    read?;
    Ok((out.status, answer, out.stderr))
}

const MAX_URL: usize = 7000;

fn percent_encode(s: &str) -> String {
    s.bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect()
}

fn is_event_type(t: &str) -> bool {
    !matches!(t, "panic" | "fatal" | "coredump")
}

/// The longest run of backticks left in a trace for the issue URL; a longer
/// one gets a space every this many (the fence is one longer, and stays short
/// enough to fit the URL).
const MAX_TICKS: usize = 8;

/// `s` with a space put into every run of more than [`MAX_TICKS`] backticks.
fn break_backticks(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut run = 0;
    for c in s.chars() {
        if c == '`' {
            if run == MAX_TICKS {
                out.push(' ');
                run = 0;
            }
            run += 1;
        } else {
            run = 0;
        }
        out.push(c);
    }
    out
}

/// A prefilled `https://github.com/EternalCoder454/<repo>/issues/new?...`
/// URL, at most about 7 KB (the trace is cut to fit, and a message too long
/// on its own too). Secondary to [`send`].
pub fn github_issue_url(r: &Report, repo: &str) -> String {
    let is_event = r.stacktrace.trim().is_empty() && is_event_type(&r.report_type);
    let first: String = r
        .message
        .lines()
        .next()
        .unwrap_or("")
        .chars()
        .take(80)
        .collect();
    let title = if is_event {
        match &r.atlasos_version {
            Some(v) => format!("Update problem: {} (version {v})", r.report_type),
            None => format!("Update problem: {}", r.report_type),
        }
    } else {
        format!(
            "Crash in {} {}: {}",
            r.app_name,
            r.app_version.as_deref().unwrap_or(""),
            first
        )
    };
    let base = format!(
        "https://github.com/EternalCoder454/{}/issues/new?title={}&body=",
        percent_encode(repo),
        percent_encode(&title)
    );
    let na = |o: &Option<String>| o.clone().unwrap_or_else(|| "unknown".into());
    let head_with = |message: &str| {
        format!(
            "**App:** {} {}\n**Telamon OS:** {} ({})\n**Kernel:** {}\n**GPU:** {} ({})\n**Type:** {}\n**Message:** {}\n\n",
            r.app_name,
            na(&r.app_version),
            na(&r.atlasos_version),
            na(&r.channel),
            na(&r.kernel),
            na(&r.gpu),
            na(&r.gpu_driver),
            r.report_type,
            message
        )
    };
    // one frame must not take the whole URL: each line is cut to 400 characters
    let trace = break_backticks(
        &filter_trace(&r.stacktrace)
            .lines()
            .map(|l| l.chars().take(400).collect::<String>())
            .collect::<Vec<_>>()
            .join("\n"),
    );
    let has_trace = !trace.trim().is_empty();
    // A fence longer than any run of backticks in the trace: a "```" in a
    // frame cannot end the code block early (and let the rest render as
    // markdown).
    let longest_run = trace.split(|c| c != '`').map(str::len).max().unwrap_or(0);
    let fence = "`".repeat(longest_run.max(2) + 1);
    // The message alone may be over the budget (up to 64 KiB): cut it until
    // the head with an empty trace block fits.
    let chars: Vec<(usize, char)> = r.message.char_indices().collect();
    let mut keep = chars.len();
    let head = loop {
        let msg = if keep < chars.len() {
            let end = chars.get(keep).map_or(r.message.len(), |c| c.0);
            format!("{} ... (message truncated)", &r.message[..end])
        } else {
            r.message.clone()
        };
        let head = head_with(&msg);
        let empty = if has_trace {
            format!("{head}{fence}\n\n{fence}\n")
        } else {
            head.trim_end().to_string()
        };
        if base.len() + percent_encode(&empty).len() <= MAX_URL || keep == 0 {
            break head;
        }
        keep -= (keep / 10).max(1);
    };
    if !has_trace {
        // no stack trace (an event report): no empty code block
        return cap_url(format!("{base}{}", percent_encode(head.trim_end())));
    }
    let head = format!("{head}{fence}\n");
    let lines: Vec<&str> = trace.lines().collect();
    let mut keep = lines.len();
    loop {
        let cut = if keep < lines.len() {
            "\n... (trace truncated)"
        } else {
            ""
        };
        let body = percent_encode(&format!(
            "{head}{}{cut}\n{fence}\n",
            lines[..keep].join("\n")
        ));
        if base.len() + body.len() <= MAX_URL || keep == 0 {
            return cap_url(format!("{base}{body}"));
        }
        keep -= (keep / 10).max(1);
    }
}

/// The last resort when the other fields alone are too long (a long
/// program path): cut the URL to [`MAX_URL`], never inside a `%XX` or a
/// UTF-8 sequence.
fn cap_url(mut url: String) -> String {
    if url.len() <= MAX_URL {
        return url;
    }
    let b = url.as_bytes();
    let continuation = |i: usize| {
        b.get(i) == Some(&b'%')
            && b.get(i + 1..i + 3)
                .and_then(|h| u8::from_str_radix(std::str::from_utf8(h).ok()?, 16).ok())
                .is_some_and(|v| v & 0xC0 == 0x80)
    };
    let mut end = MAX_URL;
    // not in the middle of a `%XX`
    if b[end - 1] == b'%' {
        end -= 1;
    } else if b[end - 2] == b'%' {
        end -= 2;
    }
    // not before a continuation byte: back to the start of its character
    while end > 0 && continuation(end) {
        end -= 3;
    }
    url.truncate(end);
    url
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sc() -> Scrubber {
        Scrubber::new(
            &["zach", "Zachary Smith"],
            &["atlas-box.local"],
            &["/var/home/zach"],
        )
    }

    fn report(trace: &str) -> Report {
        let c = Crash {
            report_type: "panic",
            app_name: "net.eterneon.telamon.updater",
            app_version: Some("0.1.0"),
            message: "boom",
            stacktrace: trace,
        };
        build_report(&c, &sc(), Some("2026-10-02T10:00:00Z")).unwrap()
    }

    #[test]
    fn scrubs_homes_user_and_host() {
        let s = sc();
        assert_eq!(s.scrub("/home/zach/.cargo/x.rs"), "/home/USER/.cargo/x.rs");
        assert_eq!(s.scrub("/var/home/zach/x"), "/var/home/USER/x");
        assert_eq!(
            s.scrub("/var/home/other/x and /home/bob"),
            "/var/home/USER/x and /home/USER"
        );
        assert_eq!(s.scrub("user zach on atlas-box"), "user USER on HOST");
        assert_eq!(s.scrub("zachary zach_x xzach"), "zachary USER_x xzach");
        assert_eq!(s.scrub("a/b /usr/lib/x"), "a/b /usr/lib/x");
    }

    #[test]
    fn scrubs_mac_and_ip_addresses() {
        let s = sc();
        assert_eq!(
            s.scrub("mac aa:bb:cc:dd:ee:ff and AA-BB-CC-DD-EE-FF"),
            "mac <mac> and <mac>"
        );
        assert_eq!(
            s.scrub("ip 192.168.1.20 and 10.0.0.1:8080."),
            "ip <ip> and <ip>."
        );
        assert_eq!(
            s.scrub("v6 fe80::1ff:fe23:4567:890a and 2001:db8:0:0:0:0:0:1"),
            "v6 <ip> and <ip>"
        );
        assert_eq!(s.scrub("::1 up"), "<ip> up");
        // not addresses
        assert_eq!(
            s.scrub("time 10:20:30 ver 1.2.3 at 0x7f12:34"),
            "time 10:20:30 ver 1.2.3 at 0x7f12:34"
        );
        assert_eq!(s.scrub("300.1.1.1"), "300.1.1.1");
    }

    #[test]
    fn message_paths_into_user_data_are_hidden() {
        let m = sc().scrub_message(
            "No such file: '/home/zach/Documents/tax.pdf' (os error 2) /run/media/zach/USB/a",
        );
        assert_eq!(m, "No such file: '<path>");
        assert_eq!(
            sc().scrub_message("see /usr/lib/foo.so"),
            "see /usr/lib/foo.so"
        );
    }

    #[test]
    fn report_has_no_identifying_strings() {
        let c = Crash {
            report_type: "panic",
            app_name: "net.eterneon.telamon.updater",
            app_version: Some("0.1.0"),
            message: "failed at /home/zach/Documents/notes.md for zach on 10.1.2.3",
            stacktrace: "  0: f\n     at /var/home/zach/.cargo/foo.rs:1\n  1: zach::main\n",
        };
        let r = build_report(&c, &sc(), None).unwrap();
        let json = format!(
            "{}{}",
            r.to_json_pretty().unwrap(),
            serde_json::to_string(&r).unwrap()
        );
        for needle in [
            "zach",
            "atlas-box",
            "Documents",
            "notes.md",
            "10.1.2.3",
            "machine-id",
        ] {
            assert!(!json.contains(needle), "{needle} in {json}");
        }
        assert!(json.contains("<path>"));
    }

    #[test]
    fn settings_default_off_and_roundtrip() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("telamon/crash-reporting.toml");
        assert!(!Settings::load_from(&p).enabled);
        Settings { enabled: true }.save_to(&p).unwrap();
        assert!(Settings::load_from(&p).enabled);
        fs::write(&p, "enabled = false\n").unwrap();
        assert!(!Settings::load_from(&p).enabled);
        fs::write(&p, "enabled = maybe\n").unwrap();
        assert!(!Settings::load_from(&p).enabled);
    }

    #[test]
    fn the_switch_of_1_x_counts_until_there_is_a_new_one() {
        let d = tempfile::tempdir().unwrap();
        let new = d.path().join("telamon/crash-reporting.toml");
        let old = d.path().join("atlas/crash-reporting.toml");
        // Neither file: off.
        assert!(!Settings::load_either(&new, &old).enabled);
        // Opted in before 2.0.0: still in.
        Settings { enabled: true }.save_to(&old).unwrap();
        assert!(Settings::load_either(&new, &old).enabled);
        // Opted out there later: still out, until this version writes its own.
        Settings { enabled: false }.save_to(&old).unwrap();
        assert!(!Settings::load_either(&new, &old).enabled);
        Settings { enabled: true }.save_to(&old).unwrap();
        Settings { enabled: false }.save_to(&new).unwrap();
        assert!(
            !Settings::load_either(&new, &old).enabled,
            "the new file decides"
        );
        Settings { enabled: true }.save_to(&new).unwrap();
        Settings { enabled: false }.save_to(&old).unwrap();
        assert!(Settings::load_either(&new, &old).enabled);
    }

    #[test]
    fn a_dsn_of_1_x_still_decides() {
        let d = tempfile::tempdir().unwrap();
        let f = |name: &str, text: &str| {
            let p = d.path().join(name);
            fs::write(&p, text).unwrap();
            p.to_str().unwrap().to_string()
        };
        let new_etc = f("new-etc", "dsn = \"https://k@new.example.net/1\"\n");
        let old_etc_off = f("old-etc", "dsn = \"\"\n");
        let new_share = f("new-share", "dsn = \"https://k@share.example.net/2\"\n");
        let old_share = f("old-share", "dsn = \"https://k@old.example.net/3\"\n");
        let none = d.path().join("none").to_str().unwrap().to_string();
        let host = |ep: Option<Endpoint>| ep.map(|e| e.store_url);
        // The administrator's old "off" beats the shipped default.
        assert_eq!(
            host(Endpoint::load_from_files(&[
                &none,
                &old_etc_off,
                &new_share,
                &old_share
            ])),
            None
        );
        // Their new file beats their old one.
        assert_eq!(
            host(Endpoint::load_from_files(&[
                &new_etc,
                &old_etc_off,
                &new_share,
                &old_share
            ]))
            .as_deref(),
            Some("https://new.example.net/api/1/store/")
        );
        // No admin file: the new default, then the old one.
        assert_eq!(
            host(Endpoint::load_from_files(&[
                &none, &none, &new_share, &old_share
            ]))
            .as_deref(),
            Some("https://share.example.net/api/2/store/")
        );
        assert_eq!(
            host(Endpoint::load_from_files(&[
                &none, &none, &none, &old_share
            ]))
            .as_deref(),
            Some("https://old.example.net/api/3/store/")
        );
    }

    #[test]
    fn the_state_directory_of_1_x_moves_over_once() {
        let d = tempfile::tempdir().unwrap();
        let old = d.path().join("atlas");
        let new = d.path().join("telamon");
        // Nothing to move.
        assert!(!adopt_state_dir(&new, &old).unwrap());
        assert!(!new.exists());

        fs::create_dir_all(old.join("crash-reports/pending")).unwrap();
        fs::write(old.join("crash-reports/pending/a.json"), "{}").unwrap();
        fs::write(old.join("crash-id"), "id\n1\n").unwrap();
        assert!(adopt_state_dir(&new, &old).unwrap());
        assert!(!old.exists());
        assert_eq!(
            fs::read_to_string(new.join("crash-reports/pending/a.json")).unwrap(),
            "{}"
        );
        assert_eq!(fs::read_to_string(new.join("crash-id")).unwrap(), "id\n1\n");

        // A 1.x app that runs later makes its own; the new directory stays.
        fs::create_dir_all(old.join("crash-reports")).unwrap();
        assert!(!adopt_state_dir(&new, &old).unwrap());
        assert!(old.exists());
        assert!(new.join("crash-reports/pending/a.json").exists());
    }

    #[test]
    fn a_linked_or_foreign_state_directory_is_left_alone() {
        let d = tempfile::tempdir().unwrap();
        let real = d.path().join("elsewhere");
        fs::create_dir(&real).unwrap();
        let old = d.path().join("atlas");
        std::os::unix::fs::symlink(&real, &old).unwrap();
        let new = d.path().join("telamon");
        assert!(!adopt_state_dir(&new, &old).unwrap());
        assert!(!new.exists());
        // A plain file at the old name is not a state directory either.
        let d2 = tempfile::tempdir().unwrap();
        fs::write(d2.path().join("atlas"), "x").unwrap();
        assert!(!adopt_state_dir(&d2.path().join("telamon"), &d2.path().join("atlas")).unwrap());
    }

    #[test]
    fn dsn_parsing() {
        let e = Endpoint::parse("https://abc123@glitch.example.net/7").unwrap();
        assert_eq!(
            e,
            Endpoint {
                key: "abc123".into(),
                store_url: "https://glitch.example.net/api/7/store/".into()
            }
        );
        let e = Endpoint::parse("https://k@host:8000/sub/path/3").unwrap();
        assert_eq!(e.store_url, "https://host:8000/sub/path/api/3/store/");
        for bad in [
            "",
            "ftp://k@h/1",
            "https://host/1",
            "https://k@host",
            "https://k@host/",
            "https://k@ho st/1",
            "https://-x@h/1;rm",
            "http://k@example.com/1",
            "https://k:secret@h.example/1",
            "https://k@h.example/../1",
            "https://k@h.example/a/./1",
        ] {
            assert!(Endpoint::parse(bad).is_none(), "{bad:?}");
        }
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("c.toml");
        fs::write(&p, "# comment\ndsn = \"\"  # none\n").unwrap();
        assert!(Endpoint::load_from(&p).is_none());
        fs::write(&p, "dsn = \"https://k@h.example/2\"\n").unwrap();
        assert!(Endpoint::load_from(&p).is_some());
    }

    #[test]
    fn payload_has_sentry_shape() {
        let r = report(
            "#0  0x00007f1 raise (libc.so.6 + 0x9a)\n#1  0x00007f2 main (plasmashell + 0x10)\n",
        );
        let p = r.payload();
        assert_eq!(p["event_id"], r.event_id);
        assert!(p["release"].as_str().unwrap().starts_with("atlasos@"));
        assert_eq!(p["tags"]["app"], "net.eterneon.telamon.updater");
        assert_eq!(p["tags"]["category"], "Atlas app");
        assert_eq!(p["tags"]["report_type"], "panic");
        // reports are public: nothing that links one to another
        assert!(p.get("user").is_none());
        assert!(!p.to_string().contains(&r.crash_id));
        assert!(p["contexts"]["os"].is_object() && p["contexts"]["gpu"].is_object());
        let frames = &p["exception"]["values"][0]["stacktrace"]["frames"];
        assert_eq!(frames.as_array().unwrap().len(), 2);
        // Sentry wants the oldest call first
        assert_eq!(frames[0]["function"], "main");
        assert_eq!(frames[1]["function"], "raise");
        assert_eq!(frames[1]["instruction_addr"], "0x00007f1");
        assert_eq!(frames[1]["package"], "libc.so.6");
        // deterministic: shown payload == sent payload
        assert_eq!(
            serde_json::to_vec(&r.payload()).unwrap(),
            serde_json::to_vec(&r.payload()).unwrap()
        );
    }

    #[test]
    fn rust_backtrace_frames() {
        let f = parse_frames(
            "   0: std::panicking::begin\n             at /rustc/x.rs:1\n   1: app::main\n",
        );
        assert_eq!(f.len(), 2);
        assert_eq!(f[1]["function"], "std::panicking::begin");
    }

    #[test]
    fn categories() {
        assert_eq!(category_of("/usr/bin/plasmashell"), "Plasma");
        assert_eq!(category_of("plasma-discover"), "Plasma");
        assert_eq!(category_of("/usr/bin/kwin_wayland"), "KWin");
        for app in [
            "net.eterneon.telamon.updater",
            "net.eterneon.atlas.updater",
            "telamon-updater",
            "atlas-updater",
        ] {
            assert_eq!(category_of(app), "Atlas app", "{app}");
        }
        assert_eq!(category_of("telamonic"), "other");
        assert_eq!(category_of("/usr/bin/firefox"), "other");
    }

    #[test]
    fn pci_ids_and_gpu_from_sysfs() {
        let ids = "# comment\n1002  Advanced Micro Devices, Inc. [AMD/ATI]\n\t744c  Navi 31 [Radeon RX 7900 XT/7900 XTX]\n\t\t1002 0e3a  sub\n8086  Intel Corporation\n\ta780  Raptor Lake-S GT1\n";
        assert_eq!(
            pci_name(ids, "0x1002", "0x744C").unwrap(),
            "Navi 31 [Radeon RX 7900 XT/7900 XTX]"
        );
        assert_eq!(
            pci_name(ids, "0x8086", "0xa780").unwrap(),
            "Raptor Lake-S GT1"
        );
        assert!(pci_name(ids, "0x1002", "0xffff").is_none());
        let d = tempfile::tempdir().unwrap();
        let dev = d.path().join("drm/card0/device");
        fs::create_dir_all(&dev).unwrap();
        fs::write(dev.join("vendor"), "0x1002\n").unwrap();
        fs::write(dev.join("device"), "0x744c\n").unwrap();
        fs::create_dir_all(d.path().join("drm/card0-DP-1")).unwrap();
        fs::create_dir_all(d.path().join("drivers/amdgpu")).unwrap();
        std::os::unix::fs::symlink("../../../drivers/amdgpu", dev.join("driver")).unwrap();
        fs::create_dir_all(d.path().join("module/amdgpu")).unwrap();
        fs::write(d.path().join("module/amdgpu/version"), "6.1\n").unwrap();
        let (n, drv, ver) = read_gpu(&d.path().join("drm"), ids, &d.path().join("module"));
        assert_eq!(
            (n.as_deref(), drv.as_deref(), ver.as_deref()),
            (
                Some("Navi 31 [Radeon RX 7900 XT/7900 XTX]"),
                Some("amdgpu"),
                Some("6.1")
            )
        );
        let (n, _, _) = read_gpu(&d.path().join("drm"), "", &d.path().join("module"));
        assert_eq!(n.as_deref(), Some("1002:744c"));
    }

    #[test]
    fn coredump_entry_uses_only_allowed_fields() {
        let entry = json!({
            "MESSAGE_ID": COREDUMP_MESSAGE_ID,
            "_COMM": "systemd-coredum",
            "_UID": "1000",
            "_SYSTEMD_UNIT": "systemd-coredump@1-2-3.service",
            "COREDUMP_UID": "1000",
            "COREDUMP_TIMESTAMP": "1790000000000000",
            "COREDUMP_EXE": "/usr/bin/plasmashell",
            "COREDUMP_COMM": "plasmashell",
            "COREDUMP_SIGNAL_NAME": "SIGSEGV",
            "COREDUMP_CMDLINE": "plasmashell --user /home/zach/secret",
            "COREDUMP_ENVIRON": "HOME=/home/zach",
            "COREDUMP_CWD": "/home/zach",
            "MESSAGE": "Process 1 (plasmashell) of user 1000 dumped core.\n\nStack trace of thread 1:\n#0  0x00007f1 raise (libc.so.6 + 0x9a)\n#1  0x00007f2 foo (/home/zach/lib.so + 0x1)"
        });
        let (ts, r) = coredump_report(&entry, &sc(), "1000", |exe| {
            (exe == "/usr/bin/plasmashell").then(|| "plasma-workspace 6.8.0-1.fc44".to_string())
        })
        .unwrap();
        assert_eq!(ts, 1_790_000_000_000_000);
        assert_eq!(r.report_type, "coredump");
        assert_eq!(r.category, "Plasma");
        assert_eq!(
            r.app_version.as_deref(),
            Some("plasma-workspace 6.8.0-1.fc44")
        );
        assert_eq!(r.message, "plasmashell crashed with SIGSEGV");
        assert!(r.stacktrace.starts_with("Stack trace of thread 1:"));
        assert!(r.stacktrace.contains("<path>") && !r.stacktrace.contains("lib.so"));
        let all = serde_json::to_string(&r).unwrap();
        assert!(!all.contains("secret") && !all.contains("zach") && !all.contains("Process 1"));
        assert_eq!(r.time, "2026-09-21T14:13:20Z");
    }

    #[test]
    fn rotating_id_is_stable_then_replaced_after_30_days() {
        let d = tempfile::tempdir().unwrap();
        let t0 = SystemTime::now();
        let a = crash_id_in(d.path(), t0).unwrap();
        assert_eq!(a.len(), 32);
        assert_eq!(
            crash_id_in(d.path(), t0 + Duration::from_secs(29 * 86_400)).unwrap(),
            a
        );
        let b = crash_id_in(d.path(), t0 + Duration::from_secs(31 * 86_400)).unwrap();
        assert_ne!(a, b);
        assert_eq!(
            fs::metadata(d.path().join("crash-id"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
        assert!(
            !fs::read_to_string(d.path().join("crash-id"))
                .unwrap()
                .contains("machine")
        );
    }

    #[test]
    fn pending_sent_and_prune() {
        let d = tempfile::tempdir().unwrap();
        let pend = d.path().join("pending");
        let r = report("");
        let p = write_report(&pend, &r).unwrap();
        assert_eq!(
            fs::metadata(&p).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_ne!(p, write_report(&pend, &r).unwrap());
        let got = read_reports(&pend);
        assert_eq!(got.len(), 2);
        discard_in(&pend, &got[0]).unwrap();
        move_to_sent(
            &d.path().join("sent"),
            &got[1],
            Server {
                id: Some("srv1".into()),
                url: Some(format!("{ISSUE_URL_PREFIX}7")),
            },
        );
        assert!(read_reports(&pend).is_empty());
        let sent = read_reports(&d.path().join("sent"));
        assert_eq!(sent[0].sent_event_id.as_deref(), Some("srv1"));
        assert_eq!(
            sent[0].issue_url.as_deref(),
            Some("https://github.com/EternalCoder454/AtlasOS/issues/7")
        );
        prune_older_than(&d.path().join("sent"), SENT_KEEP, SystemTime::now());
        assert_eq!(read_reports(&d.path().join("sent")).len(), 1);
        prune_older_than(
            &d.path().join("sent"),
            SENT_KEEP,
            SystemTime::now() + Duration::from_secs(91 * 86_400),
        );
        assert!(read_reports(&d.path().join("sent")).is_empty());
    }

    #[test]
    fn send_without_endpoint_fails_cleanly() {
        let e = send_with(&report(""), true, None, None).unwrap_err();
        assert_eq!(e.to_string(), "no endpoint configured");
    }

    #[test]
    fn failure_mapping_and_wording() {
        use SendFailure::*;
        for (code, want) in [
            (0, Unreachable),
            (429, RateLimited),
            (500, ServerTrouble),
            (502, ServerTrouble),
            (503, ServerTrouble),
            (400, Rejected),
            (413, Rejected),
            (401, Refused(401)),
            (200, BadAnswer),
            (302, BadAnswer),
            (403, Refused(403)),
            (404, Refused(404)),
        ] {
            assert_eq!(SendFailure::from_http(code), want, "{code}");
        }
        assert_eq!(
            Unreachable.to_string(),
            "the crash report server could not be reached. Check the internet connection and try again later."
        );
        assert_eq!(
            RateLimited.to_string(),
            "the crash report server has had too many reports today. Try again tomorrow."
        );
        assert_eq!(
            Refused(401).to_string(),
            "the crash report server refused it (HTTP 401). Try again after the next update."
        );
        assert_eq!(
            http_status("curl: (22) The requested URL returned error: 429\n\n429\n"),
            429
        );
        assert_eq!(http_status("curl: (7) Failed to connect\n\n000\n"), 0);
        assert_eq!(http_status("curl: (22) 404 not found\n\n404\nextra\n"), 404);
        assert_eq!(http_status("curl: (22) error 4040\n"), 0);
        for f in [
            SendFailure::Unreachable,
            SendFailure::RateLimited,
            SendFailure::ServerTrouble,
            SendFailure::Rejected,
            SendFailure::Refused(401),
            SendFailure::BadAnswer,
        ] {
            // the app shows these kinds as other things ("turned off", ...)
            assert!(!matches!(
                f.kind(),
                io::ErrorKind::NotFound | io::ErrorKind::PermissionDenied
            ));
        }
        assert_eq!(http_status(""), 0);
    }

    /// One-shot HTTP server on loopback answering `status` to every request.
    fn serve(status: u16) -> (String, std::thread::JoinHandle<()>) {
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        l.set_nonblocking(true).unwrap();
        let port = l.local_addr().unwrap().port();
        let h = std::thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(10);
            let mut c = loop {
                match l.accept() {
                    Ok((c, _)) => break c,
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                        assert!(Instant::now() < deadline, "curl never connected");
                        std::thread::sleep(Duration::from_millis(10));
                    }
                    Err(e) => panic!("accept: {e}"),
                }
            };
            c.set_nonblocking(false).unwrap();
            c.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
            let mut buf = [0u8; 65536];
            let mut got = Vec::new();
            // read until the headers and the whole body are in
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
            let body = "{\"detail\":\"no\"}";
            let _ = write!(
                c,
                "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
        });
        (format!("http://k@127.0.0.1:{port}/1"), h)
    }

    #[test]
    fn post_maps_http_failures() {
        let d = tempfile::tempdir().unwrap();
        for (status, want) in [
            (429, SendFailure::RateLimited),
            (503, SendFailure::ServerTrouble),
            (400, SendFailure::Rejected),
            (401, SendFailure::Refused(401)),
        ] {
            let (dsn, h) = serve(status);
            let ep = Endpoint::parse(&dsn).unwrap();
            let e = post_in(d.path(), &report(""), &ep).unwrap_err();
            h.join().unwrap();
            assert_eq!(send_failure(&e), Some(&want), "{status}: {e}");
        }
    }

    #[test]
    fn post_to_closed_port_is_unreachable() {
        let d = tempfile::tempdir().unwrap();
        let port = {
            let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            l.local_addr().unwrap().port()
        };
        let ep = Endpoint::parse(&format!("http://k@127.0.0.1:{port}/1")).unwrap();
        let e = post_in(d.path(), &report(""), &ep).unwrap_err();
        assert_eq!(send_failure(&e), Some(&SendFailure::Unreachable), "{e}");
    }

    #[test]
    fn issue_url_is_prefilled_and_bounded() {
        let bt: String = (0..2000)
            .map(|i| format!("  {i}: some::function_{i}\n"))
            .collect();
        let small = github_issue_url(&report("  0: f\n"), "atlasos-updater");
        assert!(
            small.starts_with(
                "https://github.com/EternalCoder454/atlasos-updater/issues/new?title="
            )
        );
        let big = github_issue_url(&report(&bt), "atlasos-updater");
        assert!(big.len() <= MAX_URL && big.contains("truncated") && !big.contains(' '));
    }

    // ---- round 3 additions

    #[test]
    fn paths_in_other_shapes_are_redacted() {
        let s = sc();
        assert_eq!(s.scrub_message("path=/home/bob/x.txt"), "path=<path>");
        assert_eq!(
            s.scrub_message("open file:///home/bob/x.txt now"),
            "open <path>"
        );
        assert_eq!(
            s.scrub_message("(/run/user/1000/doc/ab/secret.pdf)"),
            "(<path>"
        );
        assert_eq!(s.scrub_message("in ~/Documents/a"), "in <path>");
        assert_eq!(s.scrub_message("/usr/lib/x.so"), "/usr/lib/x.so");
    }

    #[test]
    fn names_match_case_insensitively_and_short_ones_at_boundaries() {
        let s = Scrubber::new(&["Zach", "al"], &["Atlas-Box"], &[]);
        assert_eq!(
            s.scrub("ZACH and zAcH, host ATLAS-BOX"),
            "USER and USER, host HOST"
        );
        assert_eq!(s.scrub("al said"), "USER said");
        assert_eq!(
            s.scrub("signal al_1 al2 value"),
            "signal USER_1 USER2 value"
        );
        let s = sc();
        assert_eq!(s.scrub("ZACHARY smith wrote"), "USER wrote");
        assert_eq!(s.scrub("by Zachary Smith"), "by USER");
        assert_eq!(s.scrub("/var/home/zach/a"), "/var/home/USER/a");
        assert_eq!(s.scrub("host atlas-box.local"), "host HOST");
        assert_eq!(s.scrub("on atlas-box"), "on HOST");
    }

    #[test]
    fn more_address_shapes() {
        let s = sc();
        assert_eq!(s.scrub("fe80::1%eth0 up"), "<ip> up");
        assert_eq!(s.scrub("bind ::"), "bind ::");
        assert_eq!(s.scrub("host:192.168.0.2"), "host:<ip>");
        assert_eq!(s.scrub("aabbccddeeff"), "<mac>");
        assert_eq!(s.scrub("aabb.ccdd.eeff"), "<mac>");
        assert_eq!(s.scrub("enx001122334455 wlx001122334455"), "<mac> <mac>");
        assert_eq!(s.scrub("id 0123456789abcdef0123456789abcdef"), "id <id>");
        assert_eq!(
            s.scrub("uuid 123e4567-e89b-12d3-a456-426614174000"),
            "uuid <id>"
        );
    }

    #[test]
    fn endpoint_rules() {
        assert!(Endpoint::parse("http://k@127.0.0.1:8000/1").is_some());
        assert!(Endpoint::parse("http://k@localhost/1").is_some());
        assert!(Endpoint::parse("http://k@[::1]:8000/1").is_some());
        assert!(Endpoint::parse("http://k@glitch.example/1").is_none());
        assert!(Endpoint::parse("https://k:secret@glitch.example/1").is_none());
        assert!(Endpoint::parse("https://k@glitch.example/a/../1").is_none());
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("c.toml");
        fs::write(&p, "dsn = \"\"\n").unwrap();
        assert_eq!(
            toml_value(&fs::read_to_string(&p).unwrap(), "dsn").as_deref(),
            Some("")
        );
    }

    #[test]
    fn send_is_refused_when_disabled() {
        let ep = Endpoint::parse("https://k@glitch.example/1");
        let e = send_with(&report(""), false, ep, None).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::PermissionDenied);
    }

    #[test]
    fn curl_arguments_are_locked_down() {
        let ep = Endpoint::parse("https://key@glitch.example/1").unwrap();
        let a = curl_args(&ep, Path::new("/x/body.json"));
        assert_eq!(a[0], "-q");
        let pos = |s: &str| a.iter().position(|x| x == s).unwrap();
        assert_eq!(a[pos("--proto") + 1], "=https");
        assert_eq!(a[pos("--noproxy") + 1], "*");
        assert_eq!(a[pos("--max-redirs") + 1], "0");
        assert_eq!(a[pos("--data-binary") + 1], "@/x/body.json");
        assert!(!a.iter().any(|x| x.contains("sentry_secret")));
        let lo = Endpoint::parse("http://k@127.0.0.1:9/1").unwrap();
        let a = curl_args(&lo, Path::new("/x"));
        assert_eq!(
            a[a.iter().position(|x| x == "--proto").unwrap() + 1],
            "=http"
        );
    }

    fn real_entry() -> Value {
        json!({
            "_COMM": "systemd-coredum",
            "_UID": "1000",
            "_SYSTEMD_UNIT": "systemd-coredump@48-57347-3760438_7887167-0.service",
            "COREDUMP_UID": "1000",
            "COREDUMP_TIMESTAMP": "1790000000000000",
            "COREDUMP_EXE": "/usr/bin/foo",
            "COREDUMP_COMM": "foo",
            "MESSAGE": "Process 1 (foo) dumped core."
        })
    }

    #[test]
    fn forged_or_foreign_coredump_entries_are_dropped() {
        let no_rpm = |_: &str| None;
        assert!(coredump_report(&real_entry(), &sc(), "1000", no_rpm).is_some());
        for (k, v) in [
            ("_UID", "1001"),
            ("_COMM", "evil"),
            ("_SYSTEMD_UNIT", "user@1000.service"),
            ("COREDUMP_UID", "1001"),
        ] {
            let mut e = real_entry();
            e[k] = json!(v);
            assert!(coredump_report(&e, &sc(), "1000", no_rpm).is_none(), "{k}");
        }
        let mut e = real_entry();
        e.as_object_mut().unwrap().remove("_SYSTEMD_UNIT");
        assert!(coredump_report(&e, &sc(), "1000", no_rpm).is_none());
        // an entry for another user is not ours
        assert!(coredump_report(&real_entry(), &sc(), "1001", no_rpm).is_none());
    }

    #[test]
    fn coredump_text_fields_are_filtered_and_capped() {
        let mut e = real_entry();
        e["COREDUMP_COMM"] = json!(format!("fo\u{202e}o\u{1b}[31m{}", "x".repeat(200)));
        e["COREDUMP_SIGNAL_NAME"] = json!("SIG\u{200b}SEGV\n");
        e["COREDUMP_PACKAGE_VERSION"] = json!(format!("1.0\u{7}{}", "9".repeat(300)));
        e["MESSAGE"] = json!(format!("a\u{202e}b\nc\u{0}{}", "y".repeat(20000)));
        let (_, r) = coredump_report(&e, &sc(), "1000", |_| None).unwrap();
        assert!(r.message.contains("crashed with SIGSEGV"), "{}", r.message);
        assert!(!r.message.contains('\u{202e}') && !r.message.contains('\u{1b}'));
        assert!(r.message.chars().count() < 64 + 40);
        assert!(r.app_version.as_deref().unwrap().chars().count() <= 128);
        assert!(!r.app_version.as_deref().unwrap().contains('\u{7}'));
        assert_eq!(clean("a\nb\u{202e}", 10, true), "a\nb");
        assert_eq!(clean("a\nb", 10, false), "ab");
        assert_eq!(clean(&"z".repeat(9000), 8192, true).len(), 8192);
    }

    #[test]
    fn option_looking_exe_is_never_passed_to_rpm() {
        for bad in [
            "--eval=%(touch /tmp/pwn)",
            "-qf",
            "usr/bin/x",
            "/usr/../etc/x",
            "/a\nb",
            "/a\u{1b}b",
        ] {
            let mut e = real_entry();
            e["COREDUMP_EXE"] = json!(bad);
            let (_, r) =
                coredump_report(&e, &sc(), "1000", |x| panic!("rpm called with {x:?}")).unwrap();
            assert!(!r.app_name.contains("eval"), "{bad}");
        }
        assert!(!valid_exe(&format!("/{}", "a".repeat(5000))));
    }

    #[test]
    fn settings_save_replaces_a_symlink_instead_of_following_it() {
        let d = tempfile::tempdir().unwrap();
        let victim = d.path().join("victim");
        fs::write(&victim, "keep").unwrap();
        let p = d.path().join("s.conf");
        std::os::unix::fs::symlink(&victim, &p).unwrap();
        Settings { enabled: true }.save_to(&p).unwrap();
        assert_eq!(fs::read_to_string(&victim).unwrap(), "keep");
        assert!(fs::read_to_string(&p).unwrap().contains("enabled = true"));
    }

    #[test]
    fn journal_arguments_limit_fields_and_start_at_the_marker() {
        let a = journal_args(5_000_000, None, Some("1000"));
        assert!(a.contains(&"--all".to_string()));
        assert!(
            a.iter()
                .any(|x| x.starts_with("--output-fields=MESSAGE,COREDUMP_EXE"))
        );
        // the command line (it can hold anything) and the environment are not
        // read; the container command line only for whether it is set
        let fields = a
            .iter()
            .find_map(|x| x.strip_prefix("--output-fields="))
            .unwrap()
            .split(',')
            .collect::<Vec<_>>();
        for f in ["COREDUMP_CMDLINE", "COREDUMP_ENVIRON", "COREDUMP_CWD"] {
            assert!(!fields.contains(&f), "{f}");
        }
        assert!(fields.contains(&"COREDUMP_CGROUP"));
        assert!(a.contains(&"--since=@5".to_string()));
        assert!(!a.iter().any(|x| x.starts_with("--until")));
        assert!(journal_args(5_000_000, Some(9_000_000), None).contains(&"--until=@9".to_string()));
        assert!(a.contains(&"COREDUMP_UID=1000".to_string()));
        assert!(a.contains(&"_UID=1000".to_string()));
        assert!(a.contains(&"_COMM=systemd-coredum".to_string()));
        assert_eq!(journal_args(0, None, None)[0], "--user");
    }

    #[test]
    fn rate_limiter_caps_and_dedupes() {
        let mut l = RateLimiter::default();
        let t = Instant::now();
        assert!(l.allow(t, 1));
        assert!(!l.allow(t, 1), "same crash twice");
        for k in 2..=5 {
            assert!(l.allow(t, k));
        }
        assert!(!l.allow(t, 6), "sixth in the hour");
        assert!(l.allow(t + Duration::from_secs(3601), 6));
    }

    #[test]
    fn traces_keep_only_frame_lines() {
        let t = "Process 1 (x) of user 1000 dumped core.\n\nCmdline: /home/zach/secret\nStack trace of thread 7:\n#0  0x1 f (a.so + 0x1)\n  1: rust::fn\n     at /home/zach/x.rs:1\n";
        assert_eq!(
            filter_trace(t),
            "Stack trace of thread 7:\n#0  0x1 f (a.so + 0x1)\n  1: rust::fn"
        );
        let url = github_issue_url(
            &Report {
                stacktrace: t.into(),
                ..report("")
            },
            "r",
        );
        assert!(!url.contains("secret") && !url.contains("zach"));
    }

    #[test]
    fn prune_treats_future_mtimes_as_old() {
        let d = tempfile::tempdir().unwrap();
        fs::write(d.path().join("a.json"), "{}").unwrap();
        // "now" is far before the file's mtime
        prune_older_than(
            d.path(),
            SENT_KEEP,
            SystemTime::now() - Duration::from_secs(10 * 86_400),
        );
        assert!(!d.path().join("a.json").exists());
    }

    #[test]
    fn crash_id_with_future_creation_is_replaced() {
        let d = tempfile::tempdir().unwrap();
        let future = format!("{}\n{}\n", "a".repeat(32), 4_000_000_000u64);
        fs::write(d.path().join("crash-id"), future).unwrap();
        let id = crash_id_in(d.path(), SystemTime::now()).unwrap();
        assert_ne!(id, "a".repeat(32));
    }

    #[test]
    fn relative_xdg_paths_are_ignored() {
        // abs_env reads the process environment; test the rule it applies
        assert!(PathBuf::from("rel/dir").is_relative());
        assert!(abs_env("TELAMON_TEST_UNSET_VAR").is_none());
    }

    #[test]
    fn report_time_is_validated() {
        let d = tempfile::tempdir().unwrap();
        let mut r = report("");
        r.time = "../../x".into();
        assert!(write_report(d.path(), &r).is_err());
        r.time = "2026-10-02T10:00:00Z".into();
        let p = write_report(d.path(), &r).unwrap();
        assert!(
            p.file_name()
                .unwrap()
                .to_string_lossy()
                .starts_with("2026-10-02T10:00:00Z-")
        );
        assert_eq!(
            fs::metadata(d.path()).unwrap().permissions().mode() & 0o777,
            0o700
        );
    }

    #[test]
    fn markers_start_at_now_on_first_opt_in() {
        let d = tempfile::tempdir().unwrap();
        let dir = d.path().join("telamon");
        let before = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_micros() as u64;
        reset_markers_in(&dir);
        let m: u64 = fs::read_to_string(dir.join("coredump-last"))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert!(m >= before);
        let e = fs::read_to_string(dir.join("events-last")).unwrap();
        let (time, count) = e.trim().split_once(' ').expect("time and count");
        assert!(time.ends_with('Z'), "{e}");
        assert!(count.parse::<u64>().is_ok(), "{e}");
    }

    // ---- round 4

    #[test]
    fn whole_tokens_only_and_common_names_are_left_alone() {
        let s = Scrubber::new(
            &["zach", "dev", "telamon", "atlas"],
            &["fedora", "pc", "atlas-box"],
            &[],
        );
        assert_eq!(s.scrub("zachary and zach"), "zachary and USER");
        assert_eq!(
            s.scrub("/dev/null x86_64-pc-linux-gnu"),
            "/dev/null x86_64-pc-linux-gnu"
        );
        assert_eq!(
            s.scrub("atlas_core::bootc net.eterneon.telamon.updater quay.io/fedora/fedora-bootc"),
            "atlas_core::bootc net.eterneon.telamon.updater quay.io/fedora/fedora-bootc"
        );
        assert_eq!(s.scrub("on atlas-box"), "on HOST");
    }

    #[test]
    fn names_are_matched_unless_a_letter_touches_them() {
        let s = Scrubber::new(&["zach"], &[], &[]);
        assert_eq!(
            s.scrub("zach1 backup-zach2024.tar zachary"),
            "USER1 backup-USER2024.tar zachary"
        );
    }

    #[test]
    fn decomposed_text_and_marks_after_a_name() {
        let s = Scrubber::new(&["Zoë", "İvan"], &[], &[]);
        // the same name typed with a combining diaeresis
        assert_eq!(s.scrub("Zoe\u{308} wrote"), "USER wrote");
        assert_eq!(s.scrub("ZOE\u{308}"), "USER");
        // a mark right after a match is part of the letter run
        let plain = Scrubber::new(&["zach"], &[], &[]);
        assert_eq!(plain.scrub("zache\u{301}"), "zaché"); // another word
        assert_eq!(s.scrub("İvan and İVAN"), "USER and USER");
    }

    #[test]
    fn homes_are_matched_after_normalisation() {
        // the home is given decomposed, the text arrives (or is made) NFC
        let s = Scrubber::new(&[], &[], &["/srv/zoe\u{308}/files"]);
        assert_eq!(s.scrub("in /srv/zo\u{eb}/files/a"), "in /home/USER/a");
        assert_eq!(s.scrub("in /srv/zoe\u{308}/files/a"), "in /home/USER/a");
    }

    #[test]
    fn non_ascii_names_match_in_any_case() {
        let s = Scrubber::new(&["Zoë", "İvan"], &[], &[]);
        assert_eq!(s.scrub("ZOË and zoë, Ünal"), "USER and USER, Ünal");
        assert_eq!(s.scrub("Zoëlle"), "Zoëlle");
        // a char whose lowercase is longer (İ) must not shift later offsets
        assert_eq!(s.scrub("İ x ZOË"), "İ x USER");
    }

    #[test]
    fn private_prefixes_match_inside_a_longer_path() {
        let s = sc();
        assert_eq!(
            s.scrub_message("/sysroot/ostree/deploy/default/var/home/bob/Documents/tax.pdf"),
            "/sysroot/ostree/deploy/default<path>"
        );
        assert_eq!(s.scrub_message("../home/u/x"), "..<path>");
    }

    #[test]
    fn names_with_spaces_quotes_and_brackets_do_not_leak() {
        let s = sc();
        assert_eq!(
            s.scrub_message("/home/bob/Downloads/invoice (final) tax.pdf"),
            "<path>"
        );
        assert_eq!(s.scrub_message("/home/bob/Bob's Notes/plan.txt"), "<path>");
        assert_eq!(s.scrub_message("/home/bob/[work]/secret.docx"), "<path>");
        assert_eq!(
            s.scrub_message("failed to read /home/bob/x: Permission denied"),
            "failed to read <path>: Permission denied"
        );
        assert_eq!(
            s.scrub_message("cannot open /home/bob/x: No such file or directory (os error 2)"),
            "cannot open <path>: No such file or directory (os error 2)"
        );
        assert_eq!(
            s.scrub_message("cannot open /home/bob/x: os error 13"),
            "cannot open <path>: os error 13"
        );
        // the reviewer's leak cases: everything to the end of the line goes
        for (input, want) in [
            (
                "cannot open '/home/bob/Bob's Notes/plan.txt'",
                "cannot open '<path>",
            ),
            ("(/home/bob/a (1)/x.txt)", "(<path>"),
            ("/home/bob/Report: Q3 layoffs.docx", "<path>"),
            ("/home/bob/Taxes (2023)", "<path>"),
            // a reason that is not only a known one is not kept
            (
                "read /home/bob/x: Permission denied for Bob's file",
                "read <path>",
            ),
        ] {
            assert_eq!(s.scrub_message(input), want, "{input}");
        }
    }

    #[test]
    fn paths_with_spaces_and_root_boundaries() {
        let s = sc();
        assert_eq!(
            s.scrub_message("open /home/bob/My Notes/tax.pdf now"),
            "open <path>"
        );
        assert_eq!(
            s.scrub_message("'/run/media/bob/USB DRIVE/x y' failed"),
            "'<path>"
        );
        assert_eq!(s.scrub_message("(/root/x)"), "(<path>");
        assert_eq!(s.scrub_message("/root"), "<path>");
        // `/root` is a whole component: these are not it (the private-prefix
        // rule), but since 2.0.8 any path outside the system's directories is
        // hidden anyway (`foreign_path_at`), so only the system one is shown
        for p in ["/rootfs/x", "/rootless", "/var/roothomes"] {
            assert!(!private_prefix_at(p, 0), "{p}");
            assert_eq!(s.scrub_message(p), "<path>", "{p}");
        }
        assert_eq!(s.scrub_message("/usr/tmp/x"), "/usr/tmp/x");
    }

    #[test]
    fn ip_detection_is_strict() {
        let s = sc();
        assert_eq!(
            s.scrub("add::dad a::b c2::e1 dead::beef"),
            "add::dad a::b c2::e1 dead::beef"
        );
        assert_eq!(s.scrub("fe80::1 2001:db8::1 ::1"), "<ip> <ip> <ip>");
        assert_eq!(
            s.scrub("1.2.3 1.2.3.400 01.2.3.4"),
            "1.2.3 1.2.3.400 01.2.3.4"
        );
    }

    #[test]
    fn same_panic_is_one_key_even_with_unknown_frames() {
        let a = crash_key("boom", Some("src/main.rs:1:1"));
        assert_eq!(a, crash_key("boom", Some("src/main.rs:1:1")));
        assert_ne!(a, crash_key("boom", Some("src/main.rs:2:1")));
        assert_ne!(a, crash_key("bang", Some("src/main.rs:1:1")));
        let t = "  0: save\n  1: hook\n  2: std::panicking::rust_begin_unwind\n  3: app::main\n";
        assert_eq!(skip_hook_frames(t), "  3: app::main");
        assert_eq!(skip_hook_frames("  0: a\n"), "  0: a\n");
    }

    fn ev(time: &str) -> crate::events::Event {
        crate::events::Event {
            event: "update-failed".into(),
            version: None,
            error: None,
            time: time.into(),
        }
    }

    #[test]
    fn events_in_the_marker_second_are_not_lost_or_repeated() {
        let t = "2026-10-02T10:00:00Z";
        let now = "2026-10-02T11:00:00Z";
        let mut log = vec![ev("2026-10-02T09:00:00Z"), ev(t)];
        let m = ("2026-10-02T09:00:00Z".to_string(), 1);
        let got = pick_events(&log, &m, now);
        assert_eq!(got.len(), 1);
        let m = advance_event_marker(m, &got[0].time);
        assert_eq!(m, (t.to_string(), 1));
        assert!(pick_events(&log, &m, now).is_empty());
        // another event in the same second arrives later
        log.push(ev(t));
        let got = pick_events(&log, &m, now);
        assert_eq!(got.len(), 1);
        assert_eq!(advance_event_marker(m, &got[0].time), (t.to_string(), 2));
        // a future-dated event waits
        log.push(ev("2027-01-01T00:00:00Z"));
        assert_eq!(pick_events(&log, &(t.to_string(), 2), now).len(), 0);
        assert_eq!(
            parse_event_marker("2026-10-02T10:00:00Z 3", &log),
            (t.to_string(), 3)
        );
        // a marker without a count: the events at that time were taken
        let at_t = log.iter().filter(|e| e.time == t).count();
        assert_eq!(
            parse_event_marker("2026-10-02T10:00:00Z", &log),
            (t.to_string(), at_t)
        );
    }

    #[test]
    fn a_bad_event_does_not_block_later_ones_and_off_writes_nothing() {
        let d = tempfile::tempdir().unwrap();
        let (marker, pending) = (d.path().join("events-last"), d.path().join("pending"));
        let sc = Scrubber::new(&[], &[], &[]);
        let now = "2026-10-02T12:00:00Z";
        let log = vec![
            ev("2026-10-02T10:00:00Z"),
            ev("2026-10-02T10:00:01Z#"), // can never be written
            ev("2026-10-02T10:00:02Z"),
        ];
        fs::write(&marker, "2026-10-02T09:00:00Z 0").unwrap();
        let on = || true;
        let out = collect_events_in(&log, &marker, &pending, &sc, now, None, &on).unwrap();
        assert_eq!(out.len(), 2, "the bad one is skipped, both good ones kept");
        let m = fs::read_to_string(&marker).unwrap();
        assert!(m.starts_with("2026-10-02T10:00:02Z"), "{m}");
        // nothing is collected twice
        let again = collect_events_in(&log, &marker, &pending, &sc, now, None, &on).unwrap();
        assert!(again.is_empty());
        // switched off meanwhile: nothing is written and the marker stays
        fs::write(&marker, "2026-10-02T09:00:00Z 0").unwrap();
        let before = fs::read_dir(&pending).unwrap().count();
        let off = || false;
        let none = collect_events_in(&log, &marker, &pending, &sc, now, None, &off).unwrap();
        assert!(none.is_empty());
        assert_eq!(fs::read_dir(&pending).unwrap().count(), before);
        assert_eq!(
            fs::read_to_string(&marker).unwrap(),
            "2026-10-02T09:00:00Z 0"
        );
        // switched off after a write: that report is taken back too
        fs::write(&marker, "2026-10-02T09:00:00Z 0").unwrap();
        let before = fs::read_dir(&pending).unwrap().count();
        let calls = std::cell::Cell::new(0);
        let flips = || {
            calls.set(calls.get() + 1);
            calls.get() <= 1 // on for the first write, off from then on
        };
        let none = collect_events_in(&log, &marker, &pending, &sc, now, None, &flips).unwrap();
        assert!(none.is_empty());
        assert_eq!(fs::read_dir(&pending).unwrap().count(), before);
        // no marker and no `since`: the caller starts one
        assert!(
            collect_events_in(&log, &d.path().join("none"), &pending, &sc, now, None, &on)
                .is_none()
        );
    }

    #[test]
    fn stale_send_files_are_swept_and_old_schema_dropped() {
        let d = tempfile::tempdir().unwrap();
        fs::write(d.path().join("send-abc.json"), "{}").unwrap();
        fs::write(d.path().join("crash-id"), "x").unwrap();
        sweep_send_files(d.path(), SystemTime::now());
        assert!(
            d.path().join("send-abc.json").exists(),
            "fresh: maybe in use"
        );
        sweep_send_files(d.path(), SystemTime::now() + Duration::from_secs(3600));
        assert!(!d.path().join("send-abc.json").exists());
        assert!(d.path().join("crash-id").exists());

        let pend = d.path().join("pending");
        fs::create_dir_all(&pend).unwrap();
        fs::write(pend.join("old.json"), r#"{"schema":1,"message":"x"}"#).unwrap();
        fs::write(pend.join("broken.json"), "{ not json").unwrap();
        write_report(&pend, &report("")).unwrap();
        assert_eq!(read_reports(&pend).len(), 1);
        assert!(!pend.join("old.json").exists());
        assert!(
            pend.join("broken.json").exists(),
            "unknown damage is left alone"
        );
    }

    fn event_report(event: &str) -> Report {
        let c = Crash {
            report_type: event,
            app_name: "atlas-system-helper",
            app_version: Some("0.1.0"),
            message: event,
            stacktrace: "",
        };
        build_report(&c, &sc(), Some("2026-10-02T10:00:00Z")).unwrap()
    }

    #[test]
    fn only_failure_events_become_reports() {
        let d = tempfile::tempdir().unwrap();
        let (marker, pending) = (d.path().join("events-last"), d.path().join("pending"));
        let sc = Scrubber::new(&[], &[], &[]);
        let mut log = Vec::new();
        for (i, name) in [
            "update-staged",
            "update-failed",
            "update-applied",
            "rollback-requested",
            "rollback-failed",
            "channel-switched",
            "channel-switch-failed",
            "rollback-applied",
            "automatic-rollback",
            "health-check-passed",
            "health-check-failed",
        ]
        .iter()
        .enumerate()
        {
            let mut e = ev(&format!("2026-10-02T10:00:{i:02}Z"));
            e.event = name.to_string();
            log.push(e);
        }
        fs::write(&marker, "2026-10-02T09:00:00Z 0").unwrap();
        let on = || true;
        let out = collect_events_in(
            &log,
            &marker,
            &pending,
            &sc,
            "2026-10-02T12:00:00Z",
            None,
            &on,
        )
        .unwrap();
        let got: Vec<&str> = out.iter().map(|r| r.report_type.as_str()).collect();
        assert_eq!(got, REPORTED_EVENTS);
        // the marker went past the last event, skipped or not
        let m = fs::read_to_string(&marker).unwrap();
        assert!(m.starts_with("2026-10-02T10:00:10Z"), "{m}");
        // a log of successes only still moves the marker
        let mut e = ev("2026-10-02T11:00:00Z");
        e.event = "update-staged".into();
        let out = collect_events_in(
            &[e],
            &marker,
            &pending,
            &sc,
            "2026-10-02T12:00:00Z",
            None,
            &on,
        )
        .unwrap();
        assert!(out.is_empty());
        assert!(
            fs::read_to_string(&marker)
                .unwrap()
                .starts_with("2026-10-02T11:00:00Z")
        );
    }

    #[test]
    fn waiting_success_event_reports_are_discarded() {
        let d = tempfile::tempdir().unwrap();
        let pend = d.path().join("pending");
        let staged = write_report(&pend, &event_report("update-staged")).unwrap();
        let failed = write_report(&pend, &event_report("update-failed")).unwrap();
        let panic = write_report(&pend, &report("  0: f\n")).unwrap();
        let got = read_pending(&pend);
        let types: Vec<&str> = got.iter().map(|r| r.report_type.as_str()).collect();
        assert_eq!(types.len(), 2);
        assert!(types.contains(&"update-failed") && types.contains(&"panic"));
        assert!(!staged.exists() && failed.exists() && panic.exists());
    }

    #[test]
    fn a_helper_panic_with_a_trace_survives_pending() {
        let d = tempfile::tempdir().unwrap();
        let pend = d.path().join("pending");
        let mut r = report("  0: f\n");
        r.app_name = "atlas-system-helper".into();
        let p = write_report(&pend, &r).unwrap();
        // even a success-event name with a trace is kept
        let mut s = event_report("update-staged");
        s.stacktrace = "  0: f\n".into();
        let p2 = write_report(&pend, &s).unwrap();
        assert_eq!(read_pending(&pend).len(), 2);
        assert!(p.exists() && p2.exists());
        // a helper panic with no trace is kept too
        let mut e = event_report("panic");
        e.report_type = "panic".into();
        let p3 = write_report(&pend, &e).unwrap();
        assert_eq!(read_pending(&pend).len(), 3);
        assert!(p3.exists());
    }

    #[test]
    fn skipped_and_reported_events_in_the_same_second() {
        let d = tempfile::tempdir().unwrap();
        let (marker, pending) = (d.path().join("events-last"), d.path().join("pending"));
        let sc = Scrubber::new(&[], &[], &[]);
        let t = "2026-10-02T10:00:00Z";
        let (mut a, b) = (ev(t), ev(t));
        a.event = "update-staged".into();
        let log = vec![a, b];
        fs::write(&marker, "2026-10-02T09:00:00Z 0").unwrap();
        let on = || true;
        let out = collect_events_in(
            &log,
            &marker,
            &pending,
            &sc,
            "2026-10-02T12:00:00Z",
            None,
            &on,
        )
        .unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].report_type, "update-failed");
        assert_eq!(fs::read_to_string(&marker).unwrap(), format!("{t} 2"));
        // a later event in the same second is still collected, nothing twice
        let mut c = ev(t);
        c.event = "health-check-failed".into();
        let mut log2 = log.clone();
        log2.push(c);
        let out = collect_events_in(
            &log2,
            &marker,
            &pending,
            &sc,
            "2026-10-02T12:00:00Z",
            None,
            &on,
        )
        .unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].report_type, "health-check-failed");
    }

    #[test]
    fn legacy_marker_without_a_count_skips_the_taken_events() {
        let d = tempfile::tempdir().unwrap();
        let (marker, pending) = (d.path().join("events-last"), d.path().join("pending"));
        let sc = Scrubber::new(&[], &[], &[]);
        let t = "2026-10-02T10:00:00Z";
        let mut a = ev(t);
        a.event = "update-staged".into();
        let log = vec![a, ev(t)];
        // old format: the time only; the events at that time were taken
        fs::write(&marker, t).unwrap();
        let on = || true;
        let now = "2026-10-02T12:00:00Z";
        let out = collect_events_in(&log, &marker, &pending, &sc, now, None, &on).unwrap();
        assert!(out.is_empty());
        let mut c = ev("2026-10-02T10:00:05Z");
        c.event = "rollback-failed".into();
        let mut log2 = log.clone();
        log2.push(c);
        let out = collect_events_in(&log2, &marker, &pending, &sc, now, None, &on).unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].report_type, "rollback-failed");
    }

    #[test]
    fn default_endpoint_store_url() {
        let ep = Endpoint::parse("https://atlasos@telamon.eterneon.net/crash/1").unwrap();
        assert_eq!(ep.key, "atlasos");
        assert_eq!(
            ep.store_url,
            "https://telamon.eterneon.net/crash/api/1/store/"
        );
        let shipped = include_str!("../data/telamon/crash-reporting.toml");
        let dsn = toml_value(shipped, "dsn").unwrap();
        assert_eq!(Endpoint::parse(&dsn), Some(ep));
    }

    #[test]
    fn server_answer_keeps_only_atlasos_issue_links() {
        let ok = parse_server_answer(
            br#"{"id":"abc","url":"https://github.com/EternalCoder454/AtlasOS/issues/12"}"#,
        );
        assert_eq!(ok.id.as_deref(), Some("abc"));
        assert_eq!(
            ok.url.as_deref(),
            Some("https://github.com/EternalCoder454/AtlasOS/issues/12")
        );
        for bad in [
            "https://evil.example/EternalCoder454/AtlasOS/issues/1",
            "http://github.com/EternalCoder454/AtlasOS/issues/1",
            "https://github.com/EternalCoder454/Other/issues/1",
            "https://github.com/EternalCoder454/AtlasOS/issues/",
            "https://github.com/EternalCoder454/AtlasOS/issues/1 x",
            "https://github.com/EternalCoder454/AtlasOS/issues/1/../../x",
            "https://github.com/EternalCoder454/AtlasOS/issues/1?a=b",
        ] {
            let body = format!(r#"{{"id":"abc","url":"{bad}"}}"#);
            let got = parse_server_answer(body.as_bytes());
            assert_eq!(got.id.as_deref(), Some("abc"));
            assert_eq!(got.url, None, "{bad}");
        }
        assert_eq!(parse_server_answer(br#"{"id":"abc"}"#).url, None);
        assert_eq!(parse_server_answer(b"nope"), Server::default());
    }

    #[test]
    fn server_answer_ids_and_size_are_checked() {
        let url = "https://github.com/EternalCoder454/AtlasOS/issues/7";
        for bad in ["", "a b", "<b>x</b>", &"a".repeat(65)] {
            let body = serde_json::json!({"id": bad, "url": url}).to_string();
            let got = parse_server_answer(body.as_bytes());
            assert_eq!(got.id, None, "{bad:?}");
            assert_eq!(got.url.as_deref(), Some(url));
        }
        let mut big = format!(r#"{{"id":"a","url":"{url}","x":""#).into_bytes();
        big.resize(MAX_ANSWER + 10, b' ');
        assert_eq!(parse_server_answer(&big), Server::default());
        assert!(is_issue_url(url));
        assert!(!is_issue_url(
            "https://github.com/EternalCoder454/AtlasOS/issues/1234567890123"
        ));
    }

    #[test]
    fn scrubs_emails_credentials_and_tokens() {
        let s = Scrubber::default();
        let cases = [
            ("mail zach.s+x@example.co.uk now", "mail <email> now"),
            ("<a@b.dev>", "<<email>>"),
            ("user@1000.service failed", "user@1000.service failed"),
            ("atlasos@44.20261003", "atlasos@44.20261003"),
            (
                "GET https://bob:hunter2@example.com/x",
                "GET https://REDACTED@example.com/x",
            ),
            (
                "url?access_token=abc123&x=1",
                "url?access_token=REDACTED&x=1",
            ),
            ("Password: hunter2 next", "Password: REDACTED next"),
            (r#"{"api_key": "s3cr3t"}"#, r#"{"api_key": "REDACTED"}"#),
            (
                "Authorization: Bearer abc.def-ghi",
                "Authorization: Bearer REDACTED",
            ),
            ("bearer abcdef", "bearer REDACTED"),
            ("monkey=banana", "monkey=banana"),
            (
                r#"password="my pass phrase" ok"#,
                r#"password="REDACTED" ok"#,
            ),
            (
                r#"{"secret": "a b c", "n": 1}"#,
                r#"{"secret": "REDACTED", "n": 1}"#,
            ),
            ("pwd='open\nnext", "pwd='REDACTED\nnext"),
            ("in zbus::auth::handshake", "in zbus::auth::handshake"),
            ("cfg::password=hunter2 x", "cfg::password=REDACTED x"),
            ("Config::token: abc", "Config::token: REDACTED"),
            (r#"password="" and "x""#, r#"password="" and "x""#),
            (r#"pwd="pa\"ss word" ok"#, r#"pwd="REDACTED" ok"#),
            ("x::key::y", "x::key::y"),
            ("at Session::open()", "at Session::open()"),
            ("rustls::sign::signature", "rustls::sign::signature"),
            ("keyboard: us", "keyboard: us"),
            ("ghp_abcdefghijklmnop1234", "<token>"),
            (
                "x eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc y",
                "x <token> y",
            ),
            ("k Zm9vYmFyQmF6UXV4MTIzNDU2Nzg5 k", "k <token> k"),
            // stack frames and hashes stay readable
            (
                "_ZN4core3fmt5write17h1a2b3c4d5e6f7a8bE",
                "_ZN4core3fmt5write17h1a2b3c4d5e6f7a8bE",
            ),
            (
                "atlas_core::helper::service::run",
                "atlas_core::helper::service::run",
            ),
        ];
        for (input, want) in cases {
            assert_eq!(s.scrub(input), want, "{input:?}");
        }
    }

    #[test]
    fn old_sent_files_load_without_a_link() {
        let mut v = serde_json::to_value(report("")).unwrap();
        v.as_object_mut().unwrap().remove("issue_url");
        let r: Report = serde_json::from_value(v).unwrap();
        assert_eq!(r.issue_url, None);
    }

    #[test]
    fn event_report_url_has_no_empty_block_and_a_problem_title() {
        let mut r = event_report("update-failed");
        r.atlasos_version = Some("44.20261003-1".into());
        let url = github_issue_url(&r, "AtlasOS");
        assert!(!url.contains("%60%60%60"), "{url}");
        assert!(
            url.contains(
                "title=Update%20problem%3A%20update-failed%20%28version%2044.20261003-1%29"
            ),
            "{url}"
        );
        assert!(!url.contains("Crash%20in"), "{url}");
        // a real crash keeps its block and title
        let c = github_issue_url(&report("  0: f\n"), "AtlasOS");
        assert!(c.contains("%60%60%60") && c.contains("Crash%20in"), "{c}");
    }

    // ---- 1.6.0: crash.rs batch (study 5)

    fn set_mtime(p: &Path, t: SystemTime) {
        fs::File::options()
            .write(true)
            .open(p)
            .unwrap()
            .set_modified(t)
            .unwrap();
    }

    fn names(dir: &Path) -> Vec<String> {
        let mut v: Vec<String> = fs::read_dir(dir)
            .into_iter()
            .flatten()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        v.sort();
        v
    }

    #[test]
    fn markers_and_reports_are_replaced_not_rewritten_in_place() {
        let d = tempfile::tempdir().unwrap();
        let dir = d.path().join("telamon");
        let m = dir.join("coredump-last");
        write_private(&m, b"1", true).unwrap();
        // a second name for the same file: an in-place write would change it
        let other = d.path().join("other");
        fs::hard_link(&m, &other).unwrap();
        write_private(&m, b"2", true).unwrap();
        assert_eq!(fs::read_to_string(&m).unwrap(), "2");
        assert_eq!(fs::read_to_string(&other).unwrap(), "1");
        assert_eq!(
            fs::metadata(&m).unwrap().permissions().mode() & 0o777,
            0o600
        );
        // a new file never replaces one
        let e = write_private(&m, b"3", false).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::AlreadyExists);
        assert_eq!(fs::read_to_string(&m).unwrap(), "2");
        // and no temp file is left either way
        assert_eq!(names(&dir), ["coredump-last"]);
        let p = write_report(&dir.join("pending"), &report("")).unwrap();
        assert_eq!(names(&dir.join("pending")).len(), 1);
        assert_eq!(
            read_reports(&dir.join("pending"))[0].path.as_ref(),
            Some(&p)
        );
    }

    #[test]
    fn leftover_temp_files_are_swept() {
        let d = tempfile::tempdir().unwrap();
        let t = d.path().join(".x.json.0011aa.tmp");
        fs::write(&t, "{").unwrap();
        fs::write(d.path().join("keep.json"), "{}").unwrap();
        sweep_temp_files(d.path(), SystemTime::now());
        assert!(t.exists(), "fresh: maybe being written");
        sweep_temp_files(d.path(), SystemTime::now() + Duration::from_secs(3600));
        assert!(!t.exists());
        assert!(d.path().join("keep.json").exists());
    }

    #[test]
    fn unreadable_reports_are_quarantined() {
        let d = tempfile::tempdir().unwrap();
        let pend = d.path().join("pending");
        let good = write_report(&pend, &report("")).unwrap();
        let cut = pend.join("2026-10-01T00:00:00Z-00.json");
        fs::write(&cut, "{\"schema\": 2, \"event_id\": \"ab").unwrap();
        let binary = pend.join("2026-10-01T00:00:01Z-00.json");
        fs::write(&binary, [0xff, 0xfe, 0x00]).unwrap();
        let fresh = pend.join("2026-10-01T00:00:02Z-00.json");
        fs::write(&fresh, "{").unwrap();
        let old = SystemTime::now() - Duration::from_secs(600);
        set_mtime(&cut, old);
        set_mtime(&binary, old);
        let got = read_reports(&pend);
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].path.as_ref(), Some(&good));
        let q = d.path().join(QUARANTINE);
        assert_eq!(
            names(&q),
            [
                "2026-10-01T00:00:00Z-00.json",
                "2026-10-01T00:00:01Z-00.json"
            ]
        );
        assert_eq!(
            fs::metadata(&q).unwrap().permissions().mode() & 0o777,
            0o700
        );
        // one still being written by an older version is left for now
        assert!(fresh.exists());
        // a second damaged file of the same name does not replace the first
        fs::write(&cut, "{").unwrap();
        set_mtime(&cut, old);
        read_reports(&pend);
        assert_eq!(names(&q).len(), 3);
    }

    #[test]
    fn a_damaged_marker_counts_from_when_it_was_written() {
        let d = tempfile::tempdir().unwrap();
        let m = d.path().join("coredump-last");
        assert_eq!(read_coredump_marker(&m), None, "none: start at now");
        fs::write(&m, "1790000000000000\n").unwrap();
        assert_eq!(read_coredump_marker(&m), Some(1_790_000_000_000_000));
        for bad in ["", "17900000", "x"] {
            fs::write(&m, bad).unwrap();
            if bad == "17900000" {
                // a cut number is still a number: earlier, never later
                assert_eq!(read_coredump_marker(&m), Some(17_900_000));
                continue;
            }
            set_mtime(&m, UNIX_EPOCH + Duration::from_secs(1_790_000_000));
            assert_eq!(
                read_coredump_marker(&m),
                Some(1_790_000_000_000_000),
                "{bad:?}"
            );
        }

        // the events marker: an empty one used to restart at "now"
        let (marker, pending) = (d.path().join("events-last"), d.path().join("pending"));
        fs::write(&marker, "").unwrap();
        // 2026-10-02T09:30:00Z
        set_mtime(&marker, UNIX_EPOCH + Duration::from_secs(1_790_933_400));
        let log = vec![ev("2026-10-02T09:00:00Z"), ev("2026-10-02T10:00:00Z")];
        let sc = Scrubber::new(&[], &[], &[]);
        let on = || true;
        let out = collect_events_in(
            &log,
            &marker,
            &pending,
            &sc,
            "2026-10-02T12:00:00Z",
            None,
            &on,
        )
        .expect("a damaged marker is not a missing one");
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].time, "2026-10-02T10:00:00Z");
        assert!(looks_like_time("2026-10-02T10:00:00Z"));
        assert!(!looks_like_time("2026-10-0"));
    }

    #[test]
    fn the_hourly_limit_and_dedupe_hold_across_processes() {
        // every call reads the file again, as a new process would
        let d = tempfile::tempdir().unwrap();
        let dir = d.path().join("crash-reports");
        let t = UNIX_EPOCH + Duration::from_secs(1_790_000_000);
        let hour = Duration::from_secs(3601);
        assert!(ledger_allow(&dir, t, 1, true));
        assert!(
            !ledger_allow(&dir, t, 1, true),
            "a restart loop: same crash"
        );
        for k in 2..=5 {
            assert!(ledger_allow(&dir, t, k, true));
        }
        assert!(!ledger_allow(&dir, t, 6, true), "sixth in the hour");
        // without the cap (coredumps) only the dedupe applies
        assert!(ledger_allow(&dir, t, 7, false));
        assert!(!ledger_allow(&dir, t, 7, false));
        assert!(ledger_allow(&dir, t + hour, 6, true), "the next hour");
        assert!(
            !ledger_allow(&dir, t + hour, 1, true),
            "same crash: once a day"
        );
        assert!(ledger_allow(&dir, t + DEDUPE_FOR + hour, 1, true));
        let text = fs::read_to_string(dir.join(RECENT)).unwrap();
        assert!(text.lines().count() <= 8, "old lines go: {text}");
        assert_eq!(
            fs::metadata(dir.join(RECENT)).unwrap().permissions().mode() & 0o777,
            0o600
        );
        // a damaged file does not stop reports
        fs::write(dir.join(RECENT), "garbage\n\u{0}\n").unwrap();
        assert!(ledger_allow(&dir, t, 1, true));
        // the key is stable (stored on disk, compared across builds)
        assert_eq!(crash_key("boom", None), 0x4d37_8e81_1928_ea9a);
    }

    #[test]
    fn pending_is_capped_oldest_first() {
        let d = tempfile::tempdir().unwrap();
        let pend = d.path().join("pending");
        for i in 0..MAX_PENDING + 3 {
            let mut r = report("");
            r.time = format!("2026-10-02T10:{:02}:{:02}Z", i / 60, i % 60);
            write_report(&pend, &r).unwrap();
        }
        cap_pending(&pend, MAX_PENDING);
        let left = names(&pend);
        assert_eq!(left.len(), MAX_PENDING);
        assert_eq!(left[0], "2026-10-02T10:00:03Z-00.json", "the oldest went");
        // events collected in one go are capped too
        let (marker, ev_pend) = (d.path().join("events-last"), d.path().join("ev"));
        fs::write(&marker, "2026-10-02T09:00:00Z 0").unwrap();
        let log: Vec<_> = (0..MAX_PENDING + 2)
            .map(|i| ev(&format!("2026-10-02T10:{:02}:{:02}Z", i / 60, i % 60)))
            .collect();
        let sc = Scrubber::new(&[], &[], &[]);
        let on = || true;
        let out = collect_events_in(
            &log,
            &marker,
            &ev_pend,
            &sc,
            "2026-10-02T12:00:00Z",
            None,
            &on,
        )
        .unwrap();
        assert_eq!(names(&ev_pend).len(), MAX_PENDING);
        assert_eq!(
            out.len(),
            MAX_PENDING,
            "only what is still pending is returned"
        );
    }

    #[test]
    fn a_coredump_restart_loop_is_one_crash() {
        let trace = |a: &str| {
            format!(
                "Stack trace of thread 7:\n#0  0x{a}1 raise (libc.so.6 + 0x9a)\n#1  0x{a}2 main (foo + 0x10)\nStack trace of thread 8:\n#0  0x{a}3 poll (libc.so.6 + 0x1)\n"
            )
        };
        let mut a = report(&trace("7f00"));
        a.report_type = "coredump".into();
        let mut b = report(&trace("7e11"));
        b.report_type = "coredump".into();
        b.time = "2026-10-02T10:05:00Z".into();
        assert_eq!(coredump_key(&a), coredump_key(&b), "only addresses differ");
        let mut c = b.clone();
        c.stacktrace = c.stacktrace.replace("main (foo", "other (foo");
        assert_ne!(coredump_key(&a), coredump_key(&c));
        // other threads do not count
        let mut e = b.clone();
        e.stacktrace = e.stacktrace.replace("poll", "select");
        assert_eq!(coredump_key(&a), coredump_key(&e));
        let mut f = b.clone();
        f.app_name = "/usr/bin/bar".into();
        assert_ne!(coredump_key(&a), coredump_key(&f));
    }

    #[test]
    fn journal_and_rpm_calls_have_a_deadline() {
        let sh = Path::new("/bin/sh");
        let args = |s: &str| vec!["-c".to_string(), s.to_string()];
        // a hung journalctl (or rpm on a locked rpmdb): killed at the limit,
        // with the child it started, which holds the pipe
        let t = Instant::now();
        let got = journal_with(sh, &args("sleep 30; echo '{}'"), Duration::from_millis(300));
        assert!(got.is_empty());
        assert!(t.elapsed() < Duration::from_secs(5), "{:?}", t.elapsed());
        let t = Instant::now();
        assert!(
            output_within(
                Command::new("/usr/bin/sleep").arg("30"),
                Duration::from_millis(200),
                10
            )
            .is_none()
        );
        assert!(t.elapsed() < Duration::from_secs(5));
        // a quick one is read whole, even past the pipe's buffer
        let got = journal_with(
            sh,
            &args(
                "i=0; while [ $i -lt 3000 ]; do echo '{\"a\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}'; i=$((i+1)); done",
            ),
            Duration::from_secs(20),
        );
        assert_eq!(got.len(), 3000);
        // more than the cap is dropped, not waited on
        let (status, out) = output_within(
            Command::new("/bin/sh").args(["-c", "head -c 1000000 /dev/zero"]),
            Duration::from_secs(20),
            100,
        )
        .unwrap();
        assert!(status.success() && out.len() == 100);
        // a failed one gives nothing
        assert!(journal_with(sh, &args("echo '{}'; exit 1"), Duration::from_secs(5)).is_empty());
    }

    #[test]
    fn rpm_is_asked_once_per_program_and_not_after_a_timeout() {
        let calls = Cell::new(0);
        let l = RpmLookup::new(|exe: &str| {
            calls.set(calls.get() + 1);
            match exe {
                "/usr/bin/a" => Ok(Some("a 1-1".to_string())),
                "/usr/bin/b" => Ok(None),
                _ => Err(io::Error::new(io::ErrorKind::TimedOut, "locked")),
            }
        });
        assert_eq!(l.version("/usr/bin/a").as_deref(), Some("a 1-1"));
        assert_eq!(l.version("/usr/bin/a").as_deref(), Some("a 1-1"));
        assert_eq!(l.version("/usr/bin/b"), None);
        assert_eq!(l.version("/usr/bin/b"), None);
        assert_eq!(calls.get(), 2);
        assert_eq!(l.version("/usr/bin/locked"), None);
        assert_eq!(l.version("/usr/bin/c"), None);
        assert_eq!(l.version("/usr/bin/d"), None);
        assert_eq!(calls.get(), 3, "no rpm after a timeout");
    }

    #[test]
    fn huge_memory_numbers_do_not_overflow_the_payload() {
        // a report file is plain JSON: any number may be in it
        let mut r = report("");
        r.ram_total_kb = u64::MAX;
        r.mem_used_kb = 1;
        let p = r.payload();
        assert_eq!(p["contexts"]["device"]["memory_size"], u64::MAX);
        assert_eq!(p["contexts"]["device"]["free_memory"], u64::MAX);
    }

    #[test]
    fn one_report_is_sent_by_one_sender() {
        let d = tempfile::tempdir().unwrap();
        let pend = d.path().join("pending");
        let p = write_report(&pend, &report("")).unwrap();
        let a = Claim::take(&p).unwrap();
        // while claimed: not listed, and nobody else can take it
        assert!(read_reports(&pend).is_empty());
        let e = Claim::take(&p).err().expect("a second claim");
        assert_eq!(e.kind(), io::ErrorKind::AlreadyExists);
        let mut r = report("");
        r.path = Some(p.clone());
        let ep = Endpoint::parse("http://k@127.0.0.1:9/1");
        let e = send_with(&r, true, ep, Some(&pend)).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::AlreadyExists, "{e}");
        // a failed send gives it back
        drop(a);
        assert_eq!(read_reports(&pend).len(), 1);
        // a sent one is gone
        Claim::take(&p).unwrap().finish();
        assert!(names(&pend).is_empty());
        // two at once: exactly one wins
        let p = write_report(&pend, &report("")).unwrap();
        let barrier = std::sync::Barrier::new(2);
        let wins: usize = std::thread::scope(|s| {
            let hs: Vec<_> = (0..2)
                .map(|_| {
                    s.spawn(|| {
                        barrier.wait();
                        usize::from(Claim::take(&p).map(Claim::finish).is_ok())
                    })
                })
                .collect();
            hs.into_iter().map(|h| h.join().unwrap()).sum()
        });
        assert_eq!(wins, 1);
    }

    #[test]
    fn claims_of_killed_senders_are_put_back() {
        let d = tempfile::tempdir().unwrap();
        let held = d.path().join("2026-10-02T10:00:00Z-00.json.sending");
        fs::write(&held, "{}").unwrap();
        sweep_claims(d.path(), SystemTime::now());
        assert!(held.exists(), "fresh: a send may be running");
        sweep_claims(d.path(), SystemTime::now() + Duration::from_secs(3600));
        assert_eq!(names(d.path()), ["2026-10-02T10:00:00Z-00.json"]);
        // a claim keeps the time it was taken, not the report's
        let p = d.path().join("2026-10-02T10:00:00Z-00.json");
        set_mtime(&p, SystemTime::now() - Duration::from_secs(86_400));
        let c = Claim::take(&p).unwrap();
        sweep_claims(d.path(), SystemTime::now());
        assert!(c.held.exists(), "a running send is not put back");
    }

    #[test]
    fn a_coredump_names_its_program_without_a_private_path() {
        let s = Scrubber::new(&["zach"], &[], &["/data/zach"]);
        for (exe, want) in [
            ("/usr/bin/plasmashell", "/usr/bin/plasmashell"),
            ("/opt/vendor/bin/tool", "/opt/vendor/bin/tool"),
            ("/app/bin/net.example.App", "/app/bin/net.example.App"),
            ("/mnt/clients/acme/bin/billing", "<path>/billing"),
            ("/srv/acme-payroll/run", "<path>/run"),
            ("/var/home/zach/src/proj/target/debug/proj", "<home>/proj"),
            ("/home/other/bin/x", "<home>/x"),
            ("/root/x", "<home>/x"),
            ("/data/zach/bin/y", "<home>/y"),
            ("/usrlocal/x", "<path>/x"),
        ] {
            assert_eq!(redact_exe(exe, &s), want, "{exe}");
        }
        // such a program is no longer reported at all (see Origin::Foreign);
        // the names above still label the old reports in the queue
        let mut e = real_entry();
        e["COREDUMP_EXE"] = json!("/mnt/clients/acme/bin/billing");
        e["COREDUMP_COMM"] = json!("billing");
        assert!(coredump_report(&e, &sc(), "1000", |_| None).is_none());
        // rpm is asked with the real path of a program of the OS
        e["COREDUMP_EXE"] = json!("/usr/libexec/billing");
        let asked = std::cell::RefCell::new(String::new());
        coredump_report(&e, &sc(), "1000", |x| {
            *asked.borrow_mut() = x.to_string();
            None
        });
        assert_eq!(*asked.borrow(), "/usr/libexec/billing");
    }

    // Entries shaped like the ones systemd-coredump wrote on the owner's PC
    // (cgroups and field names as `journalctl -o json` printed them).

    const HOST: &str = "telamonos";
    const PODMAN_ID: &str = "72bfc6a1528d919c002f92f9aedec8ac8b7e545f6d61588efa6ceebb5f35c8a4";

    fn dump(exe: &str, comm: &str, cgroup: &str, hostname: &str, in_pidns: bool) -> Value {
        let mut e = json!({
            "_COMM": "systemd-coredum",
            "_UID": "1000",
            "_HOSTNAME": HOST,
            "_SYSTEMD_UNIT": "systemd-coredump@14-45057-137975_201220-0.service",
            "COREDUMP_UID": "1000",
            "COREDUMP_TIMESTAMP": "1790000000000000",
            "COREDUMP_EXE": exe,
            "COREDUMP_COMM": comm,
            "COREDUMP_SIGNAL_NAME": "SIGABRT",
            "COREDUMP_CGROUP": cgroup,
            "COREDUMP_UNIT": "user@1000.service",
            "COREDUMP_HOSTNAME": hostname,
            "MESSAGE": "Process 1 (x) dumped core."
        });
        if in_pidns {
            e["COREDUMP_CONTAINER_CMDLINE"] = json!("sleep 3000");
        }
        e
    }

    fn origin_of(e: &Value) -> Origin {
        Coredump::parse(e, "1000").unwrap().origin
    }

    fn kept(e: &Value) -> bool {
        coredump_report(e, &sc(), "1000", |_| None).is_some()
    }

    #[test]
    fn crashes_on_the_host_are_reported() {
        for (exe, comm, cgroup) in [
            (
                "/usr/bin/plasmashell",
                "plasmashell",
                "/user.slice/user-1000.slice/user@1000.service/session.slice/plasma-plasmashell.service",
            ),
            (
                "/usr/bin/telamon-settings",
                "telamon-settings",
                "/user.slice/user-1000.slice/user@1000.service/app.slice/app-net.eterneon.telamon.settings-4242.scope",
            ),
            (
                "/usr/libexec/xdg-desktop-portal-kde",
                "xdg-desktop-por",
                "/user.slice/user-1000.slice/user@1000.service/session.slice/plasma-xdg-desktop-portal-kde.service",
            ),
            // Podman running on the host is not a container itself.
            (
                "/usr/bin/podman",
                "podman",
                "/user.slice/user-1000.slice/user@1000.service/app.slice/podman-4242.scope",
            ),
            (
                "/usr/bin/foo",
                "foo",
                "/user.slice/user-1000.slice/session-3.scope",
            ),
            ("/usr/bin/foo", "foo", ""),
        ] {
            let e = dump(exe, comm, cgroup, HOST, false);
            assert_eq!(origin_of(&e), Origin::Host, "{cgroup}");
            assert!(kept(&e), "{cgroup}");
        }
        // An entry without the fields (older systemd) counts as the host's.
        let mut e = real_entry();
        e["_HOSTNAME"] = json!(HOST);
        assert_eq!(origin_of(&e), Origin::Host);
        assert!(kept(&e));
        // Likewise one whose program is unknown.
        let mut e = dump("", "mystery", "", HOST, false);
        e.as_object_mut().unwrap().remove("COREDUMP_EXE");
        assert!(kept(&e));
    }

    #[test]
    fn crashes_in_containers_are_ignored() {
        let user = "/user.slice/user-1000.slice/user@1000.service";
        let cases = [
            // podman, as the development agents run it (owner's PC): its own
            // host name, a PID namespace of its own
            (
                format!("{user}/user.slice/libpod-{PODMAN_ID}.scope/container"),
                "72bfc6a1528d",
                true,
            ),
            // toolbox and distrobox share the host name and the PID
            // namespace, but still run in a libpod scope
            (
                format!("{user}/user.slice/libpod-{PODMAN_ID}.scope/container"),
                HOST,
                false,
            ),
            // rootful podman
            (
                format!("/machine.slice/libpod-{PODMAN_ID}.scope/container"),
                HOST,
                false,
            ),
            // docker, with systemd and with cgroupfs
            (
                format!("/system.slice/docker-{PODMAN_ID}.scope"),
                "d1e2",
                true,
            ),
            (format!("/docker/{PODMAN_ID}"), "d1e2", true),
            // CRI-O and Kubernetes
            (
                format!("/kubepods.slice/kubepods-burstable.slice/crio-{PODMAN_ID}.scope"),
                "pod",
                true,
            ),
            (
                format!("/kubepods/besteffort/pod1/{PODMAN_ID}"),
                "pod",
                true,
            ),
            // systemd-nspawn and libvirt machines, LXC
            (
                "/machine.slice/machine-fedora.scope/payload".into(),
                "fedora",
                true,
            ),
            ("/lxc.payload.web/init.scope".into(), "web", true),
            // a container runtime that left no cgroup behind: only the
            // other host name and the other PID namespace tell
            (String::new(), "6db81a563ec2", true),
        ];
        for (cgroup, hostname, pidns) in cases {
            for exe in [
                "/usr/libexec/xdg-desktop-portal-kde",
                "/usr/bin/ksecretd",
                "/work/target/debug/deps/telamon_explorer-ca3e",
            ] {
                let e = dump(exe, "x", &cgroup, hostname, pidns);
                assert_eq!(
                    origin_of(&e),
                    Origin::Container,
                    "{cgroup} {hostname} {exe}"
                );
                assert!(!kept(&e), "{cgroup} {exe}");
            }
        }
        // the unit fields say it too when the cgroup field is missing
        let mut e = dump("/usr/bin/plasmashell", "plasmashell", "", HOST, false);
        e["COREDUMP_USER_UNIT"] = json!(format!("libpod-{PODMAN_ID}.scope"));
        assert_eq!(origin_of(&e), Origin::Container);
        // podman's supervisor runs on the host
        let e = dump(
            "/usr/bin/conmon",
            "conmon",
            &format!(
                "/user.slice/user-1000.slice/user@1000.service/user.slice/libpod-conmon-{PODMAN_ID}.scope"
            ),
            HOST,
            false,
        );
        assert!(kept(&e));
        // a program whose own name merely looks like one is not a container
        let e = dump(
            "/usr/bin/docker-compose",
            "docker-compose",
            "/user.slice/user-1000.slice/user@1000.service/app.slice/app-konsole-1.scope",
            HOST,
            false,
        );
        assert!(kept(&e));
    }

    #[test]
    fn a_flatpak_crash_is_labelled_as_that_app() {
        let e = dump(
            "/app/extra/claude-desktop/claude-desktop",
            "claude-desktop",
            "/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-io.github.musmandev092.ClaudeDesktop-2553939532.scope",
            HOST,
            true,
        );
        assert_eq!(
            origin_of(&e),
            Origin::Flatpak("io.github.musmandev092.ClaudeDesktop".into())
        );
        let (_, r) = coredump_report(&e, &sc(), "1000", |x| panic!("rpm asked about {x}")).unwrap();
        assert_eq!(r.app_name, "io.github.musmandev092.ClaudeDesktop");
        assert_eq!(r.message, "claude-desktop crashed with SIGABRT");
        assert_eq!(
            r.payload()["tags"]["app"],
            "io.github.musmandev092.ClaudeDesktop"
        );
        assert_eq!(r.category, "other");
        assert!(r.app_version.is_none());
        // a program of the runtime inside the sandbox is labelled the same
        let mut e = e;
        e["COREDUMP_EXE"] = json!("/usr/bin/bwrap");
        assert!(matches!(origin_of(&e), Origin::Flatpak(_)));
        // a sandbox inside a container is the container's
        e["COREDUMP_CGROUP"] = json!(format!(
            "/user.slice/libpod-{PODMAN_ID}.scope/container/app-flatpak-org.example.App-1.scope"
        ));
        assert_eq!(origin_of(&e), Origin::Container);

        for (scope, want) in [
            (
                "app-flatpak-org.kde.okular-123.scope",
                Some("org.kde.okular"),
            ),
            ("flatpak-org.kde.okular-123.scope", Some("org.kde.okular")),
            (
                "app-flatpak-org.foo.Bar\\x2dBaz-9.scope",
                Some("org.foo.Bar-Baz"),
            ),
            ("app-flatpak-org.foo.Bar-notanumber.scope", None),
            ("app-flatpak-org.foo.Bar.scope", None),
            ("app-flatpak-nodots-5.scope", None),
            ("app-flatpak-org..Bar-5.scope", None),
            ("app-flatpak-org.foo/../x-5.scope", None),
            ("app-flatpak-org.foo.Bar-5.service", None),
            ("app-org.kde.okular-5.scope", None),
        ] {
            assert_eq!(flatpak_scope_app(scope).as_deref(), want, "{scope}");
        }
    }

    #[test]
    fn programs_outside_the_os_are_ignored_unless_they_are_flatpak_apps() {
        let user = "/user.slice/user-1000.slice/user@1000.service/app.slice/app-x-1.scope";
        for exe in [
            "/work/cmake/ids/pageconfig_test",
            "/tmp/kw",
            "/var/tmp/x",
            "/build/glow/telamon-updater-glow",
            "/var/home/zach/Documents/Projects/x/target/debug/x",
            "/home/zach/.local/bin/tool",
            "/home/linuxbrew/.linuxbrew/bin/node",
            "/tmp/.mount_AppIm/usr/bin/app",
            "/mnt/clients/acme/bin/billing",
            "/usrlocal/x",
        ] {
            let e = dump(exe, "x", user, HOST, false);
            assert_eq!(origin_of(&e), Origin::Foreign, "{exe}");
            assert!(!kept(&e), "{exe}");
        }
        for exe in [
            "/usr/bin/x",
            "/usr/libexec/x",
            "/usr/local/bin/x",
            "/bin/x",
            "/sbin/x",
            "/lib64/ld-linux-x86-64.so.2",
            "/opt/vendor/bin/x",
            "/app/bin/x",
            "/var/lib/flatpak/app/org.foo.Bar/current/active/files/bin/x",
        ] {
            let e = dump(exe, "x", user, HOST, false);
            assert!(kept(&e), "{exe}");
        }
        // a test binary run by the user in a Flatpak sandbox, where /tmp is
        // the sandbox's, is that app's
        let e = dump(
            "/tmp/helper",
            "helper",
            "/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-org.foo.Bar-9.scope",
            HOST,
            true,
        );
        assert!(kept(&e));
    }

    #[test]
    fn a_forged_cgroup_cannot_make_a_dump_trusted() {
        // an entry that systemd-coredump did not write is dropped first,
        // whatever cgroup it claims
        let mut e = dump("/usr/bin/x", "x", "/user.slice/x.service", HOST, false);
        e["_COMM"] = json!("evil");
        assert!(Coredump::parse(&e, "1000").is_none());
    }

    #[test]
    fn unix_time_round_trips_with_rfc3339() {
        for secs in [
            0,
            86_399,
            951_782_400,
            1_790_000_000,
            1_791_432_413,
            4_102_444_799,
        ] {
            assert_eq!(
                unix_from_rfc3339(&history::rfc3339_from_unix(secs)),
                Some(secs)
            );
        }
        for bad in [
            "",
            "2026-10-07",
            "2026-13-01T00:00:00Z",
            "2026-10-07 10:00:00Z",
            "x026-10-07T10:00:00Z",
            "2026-10-07T10:00:00+00:00",
        ] {
            assert_eq!(unix_from_rfc3339(bad), None, "{bad}");
        }
    }

    fn queue_dump(pending: &Path, e: &Value) -> Report {
        let d = Coredump::parse(e, "1000").unwrap();
        // as the version that queued every crash made it
        let crash = Crash {
            report_type: "coredump",
            app_name: &d.host_name(&sc()),
            app_version: None,
            message: &d.host_message(&sc()),
            stacktrace: "",
        };
        let mut r = build_report(&crash, &sc(), Some(&d.time())).unwrap();
        r.path = Some(write_report(pending, &r).unwrap());
        r
    }

    #[test]
    fn pending_reports_of_container_crashes_are_dropped_once_found_in_the_journal() {
        let d = tempfile::tempdir().unwrap();
        let pending = d.path().join("pending");
        let podman = format!(
            "/user.slice/user-1000.slice/user@1000.service/user.slice/libpod-{PODMAN_ID}.scope/container"
        );
        let at = |e: &mut Value, micros: u64| e["COREDUMP_TIMESTAMP"] = json!(micros.to_string());
        let mut in_container = dump(
            "/usr/libexec/xdg-desktop-portal-kde",
            "xdg-desktop-por",
            &podman,
            "72bfc6a1528d",
            true,
        );
        at(&mut in_container, 1_790_000_000_000_000);
        let mut on_host = dump(
            "/usr/bin/telamon-settings",
            "telamon-settings",
            "/user.slice/x.service",
            HOST,
            false,
        );
        at(&mut on_host, 1_790_000_100_000_000);
        let mut flatpak = dump(
            "/app/bin/claude-desktop",
            "claude-desktop",
            "/user.slice/user@1000.service/app.slice/app-flatpak-io.github.musmandev092.ClaudeDesktop-1.scope",
            HOST,
            true,
        );
        at(&mut flatpak, 1_790_000_200_000_000);
        let mut build_tree = dump("/work/x/target/debug/x", "x", &podman, "72bfc6a1528d", true);
        at(&mut build_tree, 1_790_000_300_000_000);
        let entries = [
            in_container.clone(),
            on_host.clone(),
            flatpak.clone(),
            build_tree.clone(),
        ];

        let a = queue_dump(&pending, &in_container);
        let b = queue_dump(&pending, &on_host);
        let c = queue_dump(&pending, &build_tree);
        // an old report of a program in a home directory: no journal needed
        let mut old = report("");
        old.report_type = "coredump".into();
        old.app_name = "<home>/proj".into();
        old.time = "2026-09-01T00:00:00Z".into();
        old.path = Some(write_report(&pending, &old).unwrap());
        // a panic is never touched
        let mut panic = report("");
        panic.time = "2026-09-21T14:13:21Z".into();
        panic.path = Some(write_report(&pending, &panic).unwrap());
        // the flatpak crash was queued by the old code under its program path
        let f = queue_dump(&pending, &flatpak);

        // the journal knows nothing: only the name-based rule applies
        let none = purge_ignored_in(&pending, &sc(), "1000", |_, _| Vec::new());
        assert_eq!(none, None);
        assert!(old.path.as_ref().is_some_and(|p| !p.exists()));
        assert!(a.path.as_ref().unwrap().exists(), "needs the journal");
        assert!(
            !c.path.as_ref().unwrap().exists(),
            "a program outside the OS"
        );

        let calls = std::cell::RefCell::new(Vec::new());
        let journal = |since: u64, until: u64| -> Vec<Value> {
            calls.borrow_mut().push((since, until));
            entries
                .iter()
                .filter(|e| {
                    let t: u64 = e["COREDUMP_TIMESTAMP"].as_str().unwrap().parse().unwrap();
                    t >= since && t < until
                })
                .cloned()
                .collect()
        };
        let done = purge_ignored_in(&pending, &sc(), "1000", journal);
        assert_eq!(done, Some(1), "the container report");
        assert!(!a.path.as_ref().unwrap().exists());
        assert!(b.path.as_ref().unwrap().exists(), "host crash stays");
        assert!(f.path.as_ref().unwrap().exists(), "flatpak crash stays");
        assert!(panic.path.as_ref().unwrap().exists());
        // crashes minutes apart are asked for separately, never a whole day;
        // one lookup reaches past the crash for the entry filed late
        assert!(
            calls.borrow().len() >= 2 && calls.borrow().iter().all(|(s, u)| u - s < 200_000_000)
        );
        // and a second pass finds nothing to do
        assert_eq!(purge_ignored_in(&pending, &sc(), "1000", journal), Some(0));
    }

    #[test]
    fn discard_deletes_only_report_files_in_pending() {
        let d = tempfile::tempdir().unwrap();
        let pend = d.path().join("pending");
        let p = write_report(&pend, &report("")).unwrap();
        let victim = d.path().join("victim.json");
        fs::write(&victim, "keep").unwrap();
        let mut r = report("");
        for bad in [
            victim.clone(),
            pend.join("../victim.json"),
            d.path().join("sent").join(p.file_name().unwrap()),
            pend.join(".hidden.json"),
            pend.join("x.txt"),
        ] {
            r.path = Some(bad.clone());
            let e = discard_in(&pend, &r).unwrap_err();
            assert_eq!(e.kind(), io::ErrorKind::InvalidInput, "{}", bad.display());
        }
        assert_eq!(fs::read_to_string(&victim).unwrap(), "keep");
        // a symlink in pending/ is not followed or deleted
        let link = pend.join("link.json");
        std::os::unix::fs::symlink(&victim, &link).unwrap();
        r.path = Some(link.clone());
        assert!(discard_in(&pend, &r).is_err());
        assert!(link.exists() && victim.exists());
        // a real one goes; a second discard says it is gone
        r.path = Some(p.clone());
        discard_in(&pend, &r).unwrap();
        assert!(!p.exists());
        assert_eq!(
            discard_in(&pend, &r).unwrap_err().kind(),
            io::ErrorKind::NotFound
        );
        // a sent report's move never deletes a file outside pending/
        r.path = Some(victim.clone());
        move_to_sent(&d.path().join("sent"), &r, Server::default());
        assert!(victim.exists());
    }

    #[test]
    fn a_huge_message_is_cut_on_a_char_boundary() {
        assert_eq!(cap_message("short"), "short");
        // 2-byte chars, so the byte limit falls inside one
        let big = format!("x{}", "é".repeat(MAX_MESSAGE));
        let c = cap_message(&big);
        assert!(c.len() <= MAX_MESSAGE + 64, "{}", c.len());
        assert!(c.starts_with("xéé"));
        assert!(c.ends_with(&format!("[... cut: the message was {} bytes]", big.len())));
        let c = Crash {
            report_type: "panic",
            app_name: "net.eterneon.telamon.updater",
            app_version: Some("0.1.0"),
            message: &"a".repeat(4 * 1024 * 1024),
            stacktrace: "",
        };
        let r = build_report(&c, &sc(), None).unwrap();
        assert!(r.message.len() <= MAX_MESSAGE + 64, "{}", r.message.len());
    }

    /// `%XX` decoding, for checking the issue URL's body.
    fn percent_decode(s: &str) -> Vec<u8> {
        let b = s.as_bytes();
        let mut out = Vec::new();
        let mut i = 0;
        while i < b.len() {
            if b[i] == b'%' && i + 3 <= b.len() {
                out.push(
                    u8::from_str_radix(std::str::from_utf8(&b[i + 1..i + 3]).unwrap(), 16).unwrap(),
                );
                i += 3;
            } else {
                out.push(b[i]);
                i += 1;
            }
        }
        out
    }

    #[test]
    fn issue_url_shortens_a_long_message_and_other_long_fields() {
        let mut r = report("  0: f\n  1: g\n");
        r.message = format!("{}{}", "m".repeat(20_000), "ü".repeat(3000));
        let url = github_issue_url(&r, "AtlasOS");
        assert!(url.len() <= MAX_URL, "{}", url.len());
        assert!(url.contains("message%20truncated"), "{url}");
        assert!(std::str::from_utf8(&percent_decode(&url)).is_ok());
        // an event report without a trace too
        let mut e = event_report("update-failed");
        e.message = "ü".repeat(MAX_MESSAGE / 2);
        let url = github_issue_url(&e, "AtlasOS");
        assert!(url.len() <= MAX_URL, "{}", url.len());
        // a field that is not the message: the URL is cut, still valid
        let mut l = report("  0: f\n");
        l.app_name = format!("/usr/bin/{}", "ü".repeat(3000));
        let url = github_issue_url(&l, "AtlasOS");
        assert!(url.len() <= MAX_URL, "{}", url.len());
        assert!(!url.ends_with('%') && !url[..url.len() - 1].ends_with('%'));
        assert!(std::str::from_utf8(&percent_decode(&url)).is_ok());
    }

    // ---- 2.0.8: the scrubber's gaps found by the security audit

    #[test]
    fn s1_secret_names_inside_words_and_camel_case() {
        let s = sc();
        for (input, want) in [
            (
                "PGPASSWORD=hunter2 psql -h db",
                "PGPASSWORD=REDACTED psql -h db",
            ),
            ("dbPassword=hunter2", "dbPassword=REDACTED"),
            ("db_password: hunter2", "db_password: REDACTED"),
            ("DB_PASS=abc", "DB_PASS=REDACTED"),
            ("pass=abc", "pass=REDACTED"),
            (r#"{"pass": "abc def"}"#, r#"{"pass": "REDACTED"}"#),
            ("apiKey=abc123", "apiKey=REDACTED"),
            ("csrftoken=abc123", "csrftoken=REDACTED"),
            ("MYSQL_PWD=abc", "MYSQL_PWD=REDACTED"),
        ] {
            assert_eq!(s.scrub(input), want, "{input}");
        }
        // words that only contain a name, and the common word `pass`
        for same in [
            "monkey: 3",
            "turkey=1",
            "pass: 3 fail: 0",
            "the pass completed",
            "passed=4",
            "secretary: Ann",
            "basic: true",
            "Basic configuration is missing",
            "Basic BufferedReader failed",
            "exit code=1 status code: 500",
            "zbus::auth::handshake",
        ] {
            assert_eq!(s.scrub(same), same, "{same}");
        }
    }

    #[test]
    fn s1_oauth_code_only_in_a_url_query() {
        let s = sc();
        assert_eq!(
            s.scrub("GET /cb?code=abcDEF123&state=xyz HTTP/1.1"),
            "GET /cb?code=REDACTED&state=xyz HTTP/1.1"
        );
        assert_eq!(
            s.scrub("https://idp.example/token?x=1&code_verifier=AbC123dEf"),
            "https://idp.example/token?x=1&code_verifier=REDACTED"
        );
        assert_eq!(s.scrub("error code=5"), "error code=5");
        assert_eq!(s.scrub("code: 12"), "code: 12");
    }

    #[test]
    fn s1_authorization_with_more_than_one_space_or_a_tab() {
        let s = sc();
        for (input, want) in [
            (
                "Authorization: Bearer  abc123def",
                "Authorization: Bearer  REDACTED",
            ),
            (
                "Authorization: Bearer abc123def",
                "Authorization: Bearer REDACTED",
            ),
            (
                "Authorization:Bearer\ttoken-value-1",
                "Authorization:Bearer\tREDACTED",
            ),
            (
                "authorization:\tbearer \t abc123def end",
                "authorization:\tbearer \t REDACTED end",
            ),
            (
                "Authorization: Basic   dXNlcjpwYXNz",
                "Authorization: Basic   REDACTED",
            ),
            ("Bearer  abc123def", "Bearer  REDACTED"),
            ("Bearer\tabc123def", "Bearer\tREDACTED"),
        ] {
            assert_eq!(s.scrub(input), want, "{input}");
        }
    }

    #[test]
    fn s1_standalone_basic_credential() {
        let s = sc();
        assert_eq!(s.scrub("Basic dXNlcjpwYXNz"), "Basic REDACTED");
        assert_eq!(
            s.scrub("sent Basic dXNlcjpwYXNzd29yZDEyMw== to the proxy"),
            "sent Basic REDACTED to the proxy"
        );
        assert_eq!(s.scrub("basic dXNlcjpwYXNz"), "basic REDACTED");
    }

    #[test]
    fn s1_long_hex_runs_are_ids() {
        let s = sc();
        let sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
        assert_eq!(s.scrub(&format!("sha256 {sha256} bad")), "sha256 <id> bad");
        assert_eq!(s.scrub(&format!("sum={}", &sha256[..40])), "sum=<id>");
        assert_eq!(s.scrub(&sha256.to_uppercase()), "<id>");
        assert_eq!(s.scrub(&"ab".repeat(100)), "<id>");
        // 32 hex chars still, shorter ones are no id
        assert_eq!(s.scrub(&sha256[..32]), "<id>");
        assert_eq!(s.scrub(&sha256[..39]), &sha256[..39]);
        // the compiler's commit in a standard library panic location
        let loc = format!(
            "at /rustc/{}/library/core/src/option.rs:12:5",
            &sha256[..40]
        );
        assert_eq!(s.scrub_message(&loc), loc);
    }

    #[test]
    fn s1_base64_secrets_with_a_slash_or_padding_go_whole() {
        let s = sc();
        let blob = "AAAAB3NzaC1yc2EAAAADAQABAAABgQC+abc/0123456789ABCDEFG";
        assert_eq!(s.scrub(blob), "<token>");
        assert_eq!(s.scrub(&format!("ssh-rsa {blob} me")), "ssh-rsa <token> me");
        assert_eq!(s.scrub(&format!("key \"{blob}\"")), "key \"<token>\"");
        // padding, with or without digits
        assert_eq!(
            s.scrub("data VGhpcyBpcyBhIHNlY3JldCBtZXNzYWdl== end"),
            "data <token> end"
        );
        assert_eq!(
            s.scrub("data AbCdEfGhIjKlMnOpQrSt1vWxYz= end"),
            "data <token> end"
        );
        assert_eq!(
            s.scrub("data AbCdEfGhIjKlMnOpQrStUvWxYz= end"),
            "data AbCdEfGhIjKlMnOpQrStUvWxYz= end",
            "one `=` and no digit: a name, not a secret"
        );
        // slash early and late, no digit at all but a `+`
        assert_eq!(
            s.scrub("QWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4/eXphYmNkZWZnaGlqa2xtbm9w+QUJD"),
            "<token>"
        );
        // not secrets: paths, identifiers, `name=value`, short strings
        for same in [
            "/usr/lib64/QtQuick/Controls2/Material/impl/ButtonBackground",
            "QtQuick/Controls/Material/impl/ButtonBackground",
            "maximumConnectionTimeoutSeconds=30",
            "maximumConnectionTimeoutSeconds=",
            "Plasma/Lookandfeel5/contents/Foo2",
            "image/svg+xml",
            "https://example.org/Download/File/Abc123/def456xyzQRSTUV",
        ] {
            assert_eq!(s.scrub(same), same, "{same}");
        }
    }

    #[test]
    fn s1_webhook_paths_in_any_case() {
        let s = sc();
        assert_eq!(
            s.scrub(&format!(
                "POST https://hooks.slack.com/services/{}/{}/{} failed",
                "T0123ABCD",
                "B0123ABCD",
                "X".repeat(24)
            )),
            "POST https://hooks.slack.com/services/<token> failed"
        );
        assert_eq!(
            s.scrub(&format!(
                "https://HOOKS.SLACK.COM/SERVICES/{}/{}/{}\"",
                "T0123ABCD",
                "B0123ABCD",
                "X".repeat(24)
            )),
            "https://HOOKS.SLACK.COM/SERVICES/<token>\""
        );
        assert_eq!(
            s.scrub("https://discord.com/api/webhooks/1234567890/ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
            "https://discord.com/api/webhooks/<token>"
        );
        assert_eq!(
            s.scrub("https://hooks.slack.com/"),
            "https://hooks.slack.com/"
        );
    }

    #[test]
    fn s1_serials_and_imeis() {
        let s = sc();
        for (input, want) in [
            ("ID_SERIAL=WD-WX12A3456789", "ID_SERIAL=REDACTED"),
            ("ID_SERIAL_SHORT=WX12A3456789", "ID_SERIAL_SHORT=REDACTED"),
            ("serial: 4C4C4544-0042", "serial: REDACTED"),
            ("SerialNumber=ABC123", "SerialNumber=REDACTED"),
            ("imei=490154203237518", "imei=REDACTED"),
            // a bare IMEI (15 digits, valid check digit)
            ("modem 490154203237518 failed", "modem <id> failed"),
        ] {
            assert_eq!(s.scrub(input), want, "{input}");
        }
        // not an IMEI: wrong check digit, wrong length; not a key: `serial` alone
        for same in [
            "modem 490154203237519 failed",
            "count 4901542032375",
            "the serial port is closed",
            "serial_console=ttyS0 x",
        ] {
            let got = s.scrub(same);
            if same.contains("serial_console") {
                assert!(got.contains("serial_console=ttyS0"), "{got}");
            } else {
                assert_eq!(got, same, "{same}");
            }
        }
    }

    // ---- 2.0.8: paths outside the system's directories are hidden

    #[test]
    fn s2_any_absolute_path_outside_the_system_is_hidden() {
        let s = sc();
        for (input, want) in [
            (
                "open /data/clients/AcmeCorp/q3-report.xlsx failed",
                "open <path>",
            ),
            ("/storage/photos/me.jpg", "<path>"),
            ("see /Volumes/x/y", "see <path>"),
            ("x=/data/y z", "x=<path>"),
            ("'/data/a b/c'", "'<path>"),
            ("(/mnt2/y)", "(<path>"),
            ("a:/srv2/x", "a:<path>"),
            (
                "cannot read /data/x: Permission denied (os error 13)",
                "cannot read <path>: Permission denied (os error 13)",
            ),
            ("/home", "<path>"),
            ("/var/cache/private/x", "<path>"),
            ("/usr.bak/x", "<path>"),
            ("/devices/x", "<path>"),
        ] {
            assert_eq!(s.scrub_message(input), want, "{input}");
        }
    }

    #[test]
    fn s2_system_paths_and_non_paths_stay() {
        let s = sc();
        for same in [
            "/usr/lib64/libfoo.so.1",
            "/usr",
            "/bin/sh -c",
            "/sbin/x /lib/x /lib64/x /opt/x /app/bin/x",
            "/etc/os-release",
            "/etc",
            "/proc/self/maps /sys/class/drm/card0 /dev/dri/renderD128",
            "/boot/efi /run/dbus/system_bus_socket /sysroot/ostree/repo /ostree/deploy",
            "/var/lib/flatpak/app/org.x.Y /var/lib/atlas-core/events.jsonl /var/log/journal",
            "at /rustc/4d91de4e48198da2e33413efdcd9cd2cc0c46688/library/core/src/option.rs:1:1",
            "at /builddir/build/BUILD/telamon-2.0.8/src/lib.rs:1:1",
            "https://example.org/a/b",
            "http://localhost:8080/x",
            "load qrc:/qt/qml/Telamon/Ui/Main.qml:12:5 and :/icons/x.png",
            "a/b and/or 10/12/2026 text/plain km/h",
            "1 / 2 and / alone",
            "unexpected </div> tag",
            "src/main.rs:12:5 ./rel/x ../up",
        ] {
            assert_eq!(s.scrub_message(same), same, "{same}");
        }
        // private places are still hidden first
        assert_eq!(s.scrub_message("/run/user/1000/bus"), "<path>");
        assert_eq!(s.scrub_message("/tmp/x /usr/lib/y"), "<path>");
    }

    // ---- 2.0.8: the full name's words

    #[test]
    fn s3_each_word_of_the_full_name_is_scrubbed() {
        let passwd = "root:x:0:0:Super User:/root:/bin/bash\n\
                      zach:x:1000:1000:Zachary O'Smith,Room 4,555-1,555-2:/var/home/zach:/bin/bash\n\
                      jo:x:1001:1001:Jo Li:/home/jo:/bin/sh\n";
        let (users, homes) = passwd_names(passwd, "1000");
        assert_eq!(homes, ["/var/home/zach"]);
        for want in ["zach", "Zachary O'Smith", "Zachary", "O'Smith"] {
            assert!(users.iter().any(|u| u == want), "{want} in {users:?}");
        }
        // words under 3 characters and the other fields are not names
        assert!(
            !users.iter().any(|u| u == "O" || u.contains("Room")),
            "{users:?}"
        );
        let u: Vec<&str> = users.iter().map(String::as_str).collect();
        let s = Scrubber::new(&u, &[], &["/var/home/zach"]);
        assert_eq!(
            s.scrub("O'Smith wrote, ZACHARY too, smithy and zacharyx not, Zachary O'Smith"),
            "USER wrote, USER too, smithy and zacharyx not, USER"
        );
        // other users' lines and short words
        let (users, _) = passwd_names(passwd, "1001");
        assert_eq!(users, ["jo", "Jo Li"]);
        let (users, _) = passwd_names(passwd, "0");
        // `Super User`: `User` is a common name and is not scrubbed
        let u: Vec<&str> = users.iter().map(String::as_str).collect();
        assert_eq!(Scrubber::new(&u, &[], &[]).scrub("a Super User"), "a USER");
    }

    // ---- 2.0.8: uptime and RAM are coarse

    #[test]
    fn s4_uptime_is_whole_hours_and_ram_whole_gb() {
        assert_eq!(coarse_uptime(0), 0);
        assert_eq!(coarse_uptime(3599), 0);
        assert_eq!(coarse_uptime(3600), 3600);
        assert_eq!(coarse_uptime(98_765), 97_200);
        const GB: u64 = 1024 * 1024;
        assert_eq!(coarse_ram_kb(0), 0);
        assert_eq!(coarse_ram_kb(300_000), GB, "1 GB at least");
        assert_eq!(coarse_ram_kb(33_000_000), 31 * GB); // 31.47 GB
        assert_eq!(coarse_ram_kb(33_500_000), 32 * GB); // 31.95 GB
        assert_eq!(coarse_ram_kb(32 * GB), 32 * GB);
        assert_eq!(
            coarse_ram_kb(u64::MAX),
            u64::MAX,
            "saturates, never overflows"
        );
        // built reports hold the coarse values; the payload applies them to
        // a stored (older) report too
        let r = report("  0: f\n");
        assert_eq!(r.uptime_secs % 3600, 0);
        assert_eq!(r.ram_total_kb % GB, 0);
        let mut old = r.clone();
        old.uptime_secs = 98_765;
        old.ram_total_kb = 33_000_000;
        old.mem_used_kb = 1_000_000;
        let p = old.payload();
        assert_eq!(p["contexts"]["runtime"]["uptime_secs"], 97_200);
        assert_eq!(p["contexts"]["device"]["memory_size"], 31 * GB * 1024);
        assert_eq!(
            p["contexts"]["device"]["free_memory"],
            (31 * GB - 1_000_000) * 1024
        );
    }

    // ---- 2.0.8: text from outside is cleaned and made inert

    #[test]
    fn s5_messages_and_frames_lose_bidi_and_invisible_characters() {
        let c = Crash {
            report_type: "panic",
            app_name: "net.eterneon.telamon.up\u{202e}dater",
            app_version: Some("0.1.\u{200b}0"),
            message: "txt\u{202e}fdp.exe \u{200b}zero\u{feff}width \u{e0041}tag\u{2066}x\u{2069} bell\u{7}\r!",
            stacktrace: "  0: foo\u{202e}bar\n  1: ba\u{200b}z\n",
        };
        let r = build_report(&c, &sc(), Some("2026-10-02T10:00:00Z")).unwrap();
        for text in [&r.message, &r.stacktrace, &r.app_name] {
            assert!(
                !text.chars().any(|c| c.is_control() && c != '\n'
                    || matches!(c, '\u{202a}'..='\u{202e}' | '\u{2060}'..='\u{206f}'
                        | '\u{200b}'..='\u{200f}' | '\u{feff}' | '\u{e0000}'..='\u{e007f}')),
                "{text:?}"
            );
        }
        assert_eq!(r.message, "txtfdp.exe zerowidth tagx bell!");
        assert_eq!(r.stacktrace, "  0: foobar\n  1: baz");
        assert_eq!(r.app_name, "net.eterneon.telamon.updater");
        assert_eq!(r.app_version.as_deref(), Some("0.1.0"));
        // the same in the payload
        let p = r.payload().to_string();
        assert!(!p.contains("202e") && !p.contains('\u{202e}'));
    }

    #[test]
    fn s5_invisible_characters_cannot_split_a_secret_from_the_scrubber() {
        let c = Crash {
            report_type: "fatal",
            app_name: "app",
            app_version: None,
            message: "pass\u{200b}word=hunter2 and tok\u{202e}en: abcdef",
            stacktrace: "",
        };
        let r = build_report(&c, &sc(), Some("2026-10-02T10:00:00Z")).unwrap();
        assert_eq!(r.message, "password=REDACTED and token: REDACTED");
    }

    #[test]
    fn s5_mentions_links_images_and_html_are_made_inert() {
        let c = Crash {
            report_type: "panic",
            app_name: "app",
            app_version: None,
            message: "ping @octocat and @org/team! ![x](http://t.example/p.png) [a](http://e.example) <img src=x> <A href=y> a<img/src=//t.example/p> </iframe> <script> Vec<Form> <Form as Trait>::f",
            stacktrace: "  0: <alloc::vec::Vec<u8> as core::fmt::Debug>::fmt\n  1: f@plt\n",
        };
        let r = build_report(&c, &sc(), Some("2026-10-02T10:00:00Z")).unwrap();
        assert_eq!(
            r.message,
            "ping @ octocat and @ org/team! ![x] (http://t.example/p.png) [a] (http://e.example) < img src=x> < A href=y> a< img/src=//t.example/p> </iframe> <script> Vec<Form> <Form as Trait>::f"
        );
        // generics, `f@plt`, e-mail like words are untouched
        assert_eq!(
            r.stacktrace,
            "  0: <alloc::vec::Vec<u8> as core::fmt::Debug>::fmt\n  1: f@plt"
        );
        assert_eq!(
            defang("Vec<a::b> a<b x@y.z (1)[2]"),
            "Vec<a::b> a<b x@y.z (1)[2]"
        );
        // idempotent: a second pass changes nothing
        assert_eq!(defang(&r.message), r.message);
    }

    #[test]
    fn s5_code_fence_is_longer_than_any_backtick_run_in_the_trace() {
        let r = report("  0: a```b\n  1: c`d\n  2: e``````f\n");
        let url = github_issue_url(&r, "AtlasOS");
        let body = String::from_utf8(percent_decode(&url)).unwrap();
        let body = body.split("&body=").nth(1).unwrap();
        // 6 backticks in a frame: the fence is 7
        assert!(body.contains("\n```````\n  "), "{body}");
        assert!(body.trim_end().ends_with("\n```````"), "{body}");
        assert!(!body.contains("\n``````\n"), "{body}");
        // no backticks in the trace: the usual three
        let url = github_issue_url(&report("  0: f\n"), "AtlasOS");
        let body = String::from_utf8(percent_decode(&url)).unwrap();
        assert!(body.contains("\n```\n  0: f\n```"), "{body}");
        // still bounded when a long trace is cut
        let long: String = (0..2000).map(|i| format!("  {i}: f```{i}\n")).collect();
        let url = github_issue_url(&report(&long), "AtlasOS");
        assert!(url.len() <= MAX_URL);
        let body = String::from_utf8(percent_decode(&url)).unwrap();
        assert!(
            body.contains("\n````\n") && !body.contains("\n```\n"),
            "a run of 3 backticks needs a fence of 4"
        );
    }

    // ---- 2.0.8: events with a time that cannot be a file name

    #[test]
    fn s9_a_very_long_time_is_invalid_input_and_does_not_stall_events() {
        let d = tempfile::tempdir().unwrap();
        let mut r = report("  0: f\n");
        r.time = "0".repeat(300);
        let e = write_report(d.path(), &r).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::InvalidInput);
        r.time = "2".repeat(41);
        assert_eq!(
            write_report(d.path(), &r).unwrap_err().kind(),
            io::ErrorKind::InvalidInput
        );
        r.time = "2026-10-02T10:00:00.123456789+00:00".into();
        write_report(d.path(), &r).unwrap();

        let (marker, pending) = (d.path().join("events-last"), d.path().join("pending"));
        let sc = Scrubber::new(&[], &[], &[]);
        // the long time sorts after the real ones (a longer string with the
        // same start): the event is picked, cannot be written, and is skipped
        let long = format!("2026-10-02T10:00:01Z{}", "0".repeat(300));
        let log = vec![
            ev("2026-10-02T10:00:00Z"),
            ev(&long),
            ev("2026-10-02T10:00:02Z"),
        ];
        fs::write(&marker, "2026-10-02T09:00:00Z 0").unwrap();
        let on = || true;
        let out = collect_events_in(
            &log,
            &marker,
            &pending,
            &sc,
            "2026-10-02T12:00:00Z",
            None,
            &on,
        )
        .unwrap();
        assert_eq!(out.len(), 2, "both good events, the long one skipped");
        let m = fs::read_to_string(&marker).unwrap();
        assert!(m.starts_with("2026-10-02T10:00:02Z"), "{m}");
        let again = collect_events_in(
            &log,
            &marker,
            &pending,
            &sc,
            "2026-10-02T12:00:00Z",
            None,
            &on,
        )
        .unwrap();
        assert!(again.is_empty());
    }

    // ---- 2.0.8: the OS version from the history file

    #[test]
    fn s10_versions_are_plain_and_capped() {
        assert_eq!(
            plain_version("44.20261008.0").as_deref(),
            Some("44.20261008.0")
        );
        assert_eq!(
            plain_version("stable-1.2~rc1+x:3").as_deref(),
            Some("stable-1.2~rc1+x:3")
        );
        // up to the first character a version does not have
        assert_eq!(
            plain_version("1.2.3 (call me @octocat)").as_deref(),
            Some("1.2.3")
        );
        assert_eq!(plain_version("1.2\u{202e}3").as_deref(), Some("1.2"));
        assert_eq!(plain_version("\u{202e}1.2"), None);
        assert_eq!(plain_version(""), None);
        let long = "1".repeat(500);
        assert_eq!(plain_version(&long).unwrap().len(), MAX_VERSION);

        let entry = |v: &str| history::Entry {
            version: Some(v.to_string()),
            digest: "sha256:x".into(),
            image: "ghcr.io/x/y:stable".into(),
            timestamp: None,
            first_booted: "2026-10-01T00:00:00Z".into(),
        };
        let hist = vec![entry(&long), entry("44.1 secret words")];
        let (v, ch, prev) = os_info(None, &hist);
        assert_eq!(v.unwrap().len(), MAX_VERSION);
        assert_eq!(prev.as_deref(), Some("44.1"));
        assert_eq!(ch, None);
    }

    #[test]
    fn s10_an_event_version_is_a_plain_version_in_the_report() {
        let d = tempfile::tempdir().unwrap();
        let (marker, pending) = (d.path().join("events-last"), d.path().join("pending"));
        let sc = Scrubber::new(&[], &[], &[]);
        let mut e = ev("2026-10-02T10:00:00Z");
        e.event = "update-failed".into();
        e.version = Some(format!("9.9{}@octocat {}", "9".repeat(200), "x"));
        fs::write(&marker, "2026-10-02T09:00:00Z 0").unwrap();
        let on = || true;
        let out = collect_events_in(
            &[e],
            &marker,
            &pending,
            &sc,
            "2026-10-02T12:00:00Z",
            None,
            &on,
        )
        .unwrap();
        assert_eq!(out.len(), 1);
        if let Some(v) = &out[0].atlasos_version {
            assert!(v.len() <= MAX_VERSION, "{v}");
            assert!(
                v.chars()
                    .all(|c| c.is_ascii_alphanumeric() || ".-_+~:".contains(c))
            );
        }
    }

    // ---- 2.0.8: reading report files

    fn write_json(dir: &Path, name: &str, r: &Report) -> PathBuf {
        fs::create_dir_all(dir).unwrap();
        let p = dir.join(name);
        fs::write(&p, serde_json::to_vec_pretty(r).unwrap()).unwrap();
        p
    }

    #[test]
    fn s11_report_files_are_not_followed_through_links_nor_read_from_fifos() {
        let d = tempfile::tempdir().unwrap();
        let pend = d.path().join("pending");
        fs::create_dir_all(&pend).unwrap();
        let outside = write_json(d.path(), "outside.json", &report("  0: f\n"));
        std::os::unix::fs::symlink(&outside, pend.join("2026-10-02T10:00:00Z-00.json")).unwrap();
        let fifo = pend.join("2026-10-02T10:00:01Z-00.json");
        let c = std::ffi::CString::new(fifo.to_str().unwrap()).unwrap();
        assert_eq!(unsafe { libc::mkfifo(c.as_ptr(), 0o600) }, 0);
        fs::create_dir(pend.join("2026-10-02T10:00:02Z-00.json")).unwrap();
        // a real one next to them
        write_json(&pend, "2026-10-02T10:00:03Z-00.json", &report("  0: f\n"));
        let got = read_reports(&pend); // returns: the FIFO is not opened for good
        assert_eq!(got.len(), 1, "{got:?}");
        assert!(
            got[0]
                .path
                .as_ref()
                .unwrap()
                .ends_with("2026-10-02T10:00:03Z-00.json")
        );
        // the link, the FIFO and the directory are left where they are
        assert_eq!(fs::read_dir(&pend).unwrap().count(), 4);
        assert!(outside.exists());
    }

    #[test]
    fn s11_a_report_file_over_the_limit_is_not_read_and_is_quarantined() {
        let d = tempfile::tempdir().unwrap();
        let pend = d.path().join("pending");
        fs::create_dir_all(&pend).unwrap();
        let big = pend.join("2026-10-02T10:00:00Z-00.json");
        let f = fs::File::create(&big).unwrap();
        f.set_len(MAX_REPORT_BYTES + 1).unwrap();
        f.set_modified(SystemTime::now() - Duration::from_secs(3600))
            .unwrap();
        drop(f);
        let small = write_json(&pend, "2026-10-02T10:00:01Z-00.json", &report("  0: f\n"));
        assert_eq!(
            read_report_file(&big).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
        let got = read_reports(&pend);
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].path.as_deref(), Some(small.as_path()));
        assert!(!big.exists(), "moved out of pending/");
        assert!(
            d.path()
                .join(QUARANTINE)
                .join("2026-10-02T10:00:00Z-00.json")
                .exists()
        );
    }

    #[test]
    fn s11_an_old_report_is_scrubbed_again_when_listed_and_sent() {
        let d = tempfile::tempdir().unwrap();
        let pend = d.path().join("pending");
        let mut old = report("  0: f\n  1: g\u{202e}h\n");
        old.message =
            "pass=hunter2 \u{202e}cod.exe open /data/clients/Acme/q3.xlsx @octocat zachary Smith"
                .into();
        old.stacktrace = "  0: f(token=abc123 /data/x)\n  1: g\u{202e}h\n  junk line\n".into();
        old.app_name = "net.eterneon.telamon.updater\u{200b}".into();
        old.atlasos_version = Some(format!("44.1 {}", "very secret ".repeat(40)));
        old.channel = Some("stable\u{202e}".into());
        old.uptime_secs = 98_765;
        old.ram_total_kb = 33_000_000;
        write_json(&pend, "2026-10-02T10:00:00Z-00.json", &old);
        // the file itself is as the old version wrote it
        let raw = read_reports(&pend);
        assert!(raw[0].message.contains("hunter2"));

        let listed = pending_in(&pend, &sc());
        assert_eq!(listed.len(), 1);
        let r = &listed[0];
        assert_eq!(r.message, "pass=REDACTED cod.exe open <path>");
        assert_eq!(r.stacktrace, "  0: f(token=REDACTED <path>\n  1: gh");
        assert_eq!(r.app_name, "net.eterneon.telamon.updater");
        assert_eq!(r.atlasos_version.as_deref(), Some("44.1"));
        assert_eq!(r.channel.as_deref(), Some("stable"));
        assert_eq!(r.uptime_secs, 97_200);
        assert_eq!(r.ram_total_kb, 31 * 1024 * 1024);
        assert_eq!(r.path, raw[0].path);
        // what is shown is what is sent
        let shown = r.to_json_pretty().unwrap();
        for leak in ["hunter2", "Acme", "202e", "98765", "octocat"] {
            assert!(!shown.contains(leak), "{leak} in {shown}");
        }
        assert!(!shown.contains('\u{202e}'));
        // the history list too
        let sent = d.path().join("sent");
        write_json(&sent, "2026-10-02T10:00:00Z-00.json", &old);
        assert_eq!(
            sent_in(&sent, &sc())[0].message,
            "pass=REDACTED cod.exe open <path>"
        );
        // a Flatpak app ID is not taken for a token
        let mut fp = report("  0: f\n");
        fp.app_name = "io.github.musmandev092.ClaudeDesktop".into();
        assert_eq!(
            rescrub(fp, &sc()).app_name,
            "io.github.musmandev092.ClaudeDesktop"
        );
        // scrubbing again changes nothing
        let again = rescrub(r.clone(), &sc());
        assert_eq!(&again, r);
    }

    // ---- 2.0.8: the payload has a size limit

    #[test]
    fn payload_is_capped_by_dropping_frames_far_from_the_top() {
        let trace: String = (0..6000)
            .map(|i| format!("  {i}: some::module::function_number_{i}\n"))
            .collect();
        let mut r = report("  0: f\n");
        r.stacktrace = trace;
        r.message = "m".repeat(MAX_MESSAGE);
        let p = r.payload();
        let body = serde_json::to_vec(&p).unwrap();
        assert!(body.len() <= MAX_PAYLOAD, "{}", body.len());
        serde_json::from_slice::<Value>(&body).unwrap();
        let frames = p["exception"]["values"][0]["stacktrace"]["frames"]
            .as_array()
            .unwrap();
        // Sentry order: the top of the stack (frame 0) is the last one
        assert_eq!(
            frames.last().unwrap()["function"],
            "some::module::function_number_0"
        );
        assert!(frames.len() < 6000);
        assert_eq!(
            p["extra"]["trace_frames_dropped"].as_u64().unwrap() as usize,
            6000 - frames.len()
        );
        // a small report is as it was, with no note
        let q = report("  0: f\n").payload();
        assert!(q.get("extra").is_none());
        assert_eq!(
            q["exception"]["values"][0]["stacktrace"]["frames"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn payload_cuts_a_message_that_alone_is_too_long() {
        let mut r = report("");
        r.message = "ü\"\n".repeat(60_000); // escapes make it bigger than it is
        let p = r.payload();
        let body = serde_json::to_vec(&p).unwrap();
        assert!(body.len() <= MAX_PAYLOAD, "{}", body.len());
        let m = p["message"].as_str().unwrap();
        assert!(
            m.ends_with("[... cut]") && m.starts_with("ü\"\n"),
            "{}",
            &m[m.len() - 20..]
        );
        // the other fields too long for any cut: not sent
        let d = tempfile::tempdir().unwrap();
        let mut r = report("  0: f\n");
        r.app_name = "a".repeat(2 * MAX_PAYLOAD);
        let ep = Endpoint {
            key: "k".into(),
            store_url: "https://127.0.0.1:9/api/1/store/".into(),
        };
        let e = post_in(d.path(), &r, &ep).unwrap_err();
        assert_eq!(send_failure(&e), Some(&SendFailure::Rejected));
        assert_eq!(
            fs::read_dir(d.path()).unwrap().count(),
            0,
            "no body file made"
        );
    }

    // ---- 2.0.8, second round: findings of the security review

    #[test]
    fn f1_a_word_full_of_colons_is_scrubbed_in_linear_time() {
        let s = sc();
        for unit in [":", "a:", "1:", "::1", "a:b:"] {
            let word = unit.repeat(256 * 1024 / unit.len());
            let start = Instant::now();
            let _ = s.scrub(&word);
            let _ = untrusted_text(&s, &word);
            let took = start.elapsed();
            assert!(took < Duration::from_secs(5), "{unit:?} took {took:?}");
        }
        // a reported trace line of that kind, listed (`rescrub`)
        let mut r = report("  0: f\n");
        r.stacktrace = format!("  0: {}", ":".repeat(256 * 1024));
        let start = Instant::now();
        let _ = rescrub(r, &s);
        assert!(start.elapsed() < Duration::from_secs(5));
        // short labels still work
        assert_eq!(s.scrub("host:10.0.0.1"), "host:<ip>");
    }

    #[test]
    fn f2_untrusted_text_is_idempotent() {
        let s = sc();
        let hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
        let cases = [
            format!("@{hex}"),
            "@490154203237518".to_string(),
            "x @octocat y".to_string(),
            "a.@victim x-@victim +@victim _@v".to_string(),
            "![x](http://e.example/p.png)[a][b] [x]: https://e.example\n[y]:   //e.example".to_string(),
            "<https://evil.example/x> <mailto:a@b.example> <img src=x> <A href=y>".to_string(),
            "pass\u{200b}word=hunter2 @pass=1 token: @abc".to_string(),
            "@@@octocat @ @1 ]( ][ ]:".to_string(),
            "zachary@fedora-box.local @zachary @fedora-box".to_string(),
            format!("sha-{hex} 0x{hex} {hex}.json @{hex}.json"),
            "/data/x @/data/y </data/z> @/home/zachary".to_string(),
            "AAAAB3NzaC1yc2EAAAADAQABAAABgQC+abc/0123456789ABCDEFG @AAAAB3NzaC1yc2EAAAADAQABAAABgQC+abc/0123456789ABCDEFG".to_string(),
            "Authorization: Bearer  @abc\tBasic dXNlcjpwYXNz".to_string(),
            "```\n``````````````````````````````\n".to_string(),
            "ü@ü <ü> \u{202e}@x".to_string(),
        ];
        for c in &cases {
            let once = untrusted_text(&s, c);
            assert_eq!(untrusted_text(&s, &once), once, "{c:?} -> {once:?}");
        }
        assert!(!untrusted_text(&s, &cases[0]).contains(&hex[..16]));
        assert!(!untrusted_text(&s, &cases[1]).contains("490154203237518"));
    }

    #[test]
    fn f3_long_hex_runs_go_inside_words_too() {
        let s = sc();
        let h64 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
        let h40 = &h64[..40];
        for (input, want) in [
            (format!("build-{h40}"), "build-<id>".to_string()),
            (format!("sha-{h64}"), "sha-<id>".to_string()),
            (format!("0x{h64}"), "0x<id>".to_string()),
            (format!("{h40}.json"), "<id>.json".to_string()),
            (format!("x{h40}y"), "x<id>y".to_string()),
            (format!("a/{h64}/b"), "a/<id>/b".to_string()),
            (format!("{h64}{h64}"), "<id>".to_string()),
            (format!("sha256:{h64}"), "sha256:<id>".to_string()),
        ] {
            assert_eq!(s.scrub(&input), want, "{input}");
        }
        // 39 digits, and the compiler commit, stay
        let h39 = h40[..39].to_string();
        assert_eq!(s.scrub(&format!("x-{h39}")), format!("x-{h39}"));
        let loc = format!("at /rustc/{h40}/library/core/src/option.rs:1:1");
        assert_eq!(s.scrub_message(&loc), loc);
        assert_eq!(s.scrub(&format!("rustc/{h40}")), "rustc/<id>");
    }

    #[test]
    fn f4_a_mention_after_a_non_word_character_is_defanged() {
        assert_eq!(defang("x-@victim"), "x-@ victim");
        assert_eq!(defang("a.@victim"), "a.@ victim");
        assert_eq!(defang("+@victim"), "+@ victim");
        assert_eq!(
            defang("(@victim) \"@victim\" =@victim"),
            "(@ victim) \"@ victim\" =@ victim"
        );
        // after a letter, digit or `_`: not a mention (an address, `icon@2x`)
        assert_eq!(
            defang("a@b.example icon@2x _@v 9@v"),
            "a@b.example icon@2x _@v 9@v"
        );
        let s = sc();
        assert_eq!(s.scrub("mail a@b.example"), "mail <email>");
        assert_eq!(untrusted_text(&s, "mail a@b.example"), "mail <email>");
    }

    #[test]
    fn f5_reference_links_definitions_and_autolinks_are_defanged() {
        assert_eq!(defang("[a][b]"), "[a] [b]");
        assert_eq!(defang("see [a b][c]"), "see [a b] [c]");
        assert_eq!(defang("![a][b]"), "![a] [b]");
        assert_eq!(
            defang("[x]: https://e.example/p"),
            "[x] : https://e.example/p"
        );
        assert_eq!(
            defang("ok\n   [x]: //e.example"),
            "ok\n   [x] : //e.example"
        );
        assert_eq!(
            defang("[x]: <https://e.example>"),
            "[x] : < https://e.example>"
        );
        assert_eq!(defang("<https://e.example/p>"), "< https://e.example/p>");
        assert_eq!(defang("<mailto:a@b.example>"), "< mailto:a@b.example>");
        // normal text and frames are not changed
        for same in [
            "[2026-10-02] [INFO]: started",
            "[x]: not an address",
            "text [x]: https://e.example",
            "     [x]: https://e.example",
            "<alloc::vec::Vec<u8> as core::fmt::Debug>::fmt",
            "<T as core::ops::Drop>::drop",
            "<std::io::Error>::new a < b > c <:",
            "v[0][1] a[i][j] x[1]: y",
            "<foo bar> <3 < 4",
        ] {
            assert_eq!(defang(same), same, "{same}");
        }
        // a huge line of `]:` is no slower
        let start = Instant::now();
        let _ = defang(&"]:".repeat(128 * 1024));
        assert!(start.elapsed() < Duration::from_secs(5));
    }

    #[test]
    fn f6_a_long_run_of_backticks_in_a_frame_keeps_the_trace_in_the_url() {
        let r = report(&format!("  0: a{}b\n  1: g\n", "`".repeat(5000)));
        let url = github_issue_url(&r, "AtlasOS");
        assert!(url.len() <= MAX_URL);
        let body = String::from_utf8(percent_decode(&url)).unwrap();
        assert!(body.contains("1: g"), "{body}");
        assert!(body.contains("  0: a"), "{body}");
        // the fence is at most MAX_TICKS + 1, and no run in the trace reaches it
        let runs = body.split(|c| c != '`').map(str::len).collect::<Vec<_>>();
        assert_eq!(
            runs.iter().filter(|n| **n == MAX_TICKS + 1).count(),
            2,
            "{runs:?}"
        );
        assert!(runs.iter().all(|n| *n <= MAX_TICKS + 1));
        assert_eq!(break_backticks("``````````"), "```````` ``");
        assert_eq!(break_backticks("a`b````"), "a`b````");
    }

    #[test]
    fn f9_a_cut_message_is_not_cut_again() {
        let big = "m".repeat(MAX_MESSAGE + 1000);
        let once = cap_message(&big);
        assert!(once.ends_with(&format!("[... cut: the message was {} bytes]", big.len())));
        assert_eq!(cap_message(&once), once);
        assert_eq!(cap_message(&cap_message(&once)), once);
        // through a re-read
        let mut r = report("  0: f\n");
        r.message = once.clone();
        assert_eq!(rescrub(r, &sc()).message, once);
    }
}
