---
title: crash
summary: Opt-in crash reports, the only telemetry an Atlas app may have, with the per-user switch, the endpoint, scrubbing, the pending queue and sending after the user has seen the exact payload.
order: 10
---

Crash reports are opt-in, off by default, and the user sees the exact payload before every send. When reporting is off nothing is collected or written.

A GUI app started through [atlas-framework-ui](../atlas-framework-ui/startup.md) already has the panic hook and the fatal Qt message hook installed. What an app adds is a settings switch and a page that lists pending reports, shows the payload and sends or discards them.

## How it works

- **Switch:** [`Settings`](#settings), per user, in `~/.config/atlas/crash-reporting.toml` (`enabled = false`).
- **Endpoint:** a Sentry-compatible DSN from `/etc/atlas/crash-reporting.toml`, default `/usr/share/atlas/crash-reporting.toml`. It is the AtlasOS relay, which posts each report it receives as a **public** issue in `github.com/EternalCoder454/AtlasOS`. An empty `dsn` in `/etc` turns sending off: `send` then fails with "no endpoint configured".
- **Sources:** Rust panics (`install`), fatal errors that are not panics (`record_fatal`), systemd-coredump entries of the user's own processes (`collect_coredumps`) and update and rollback failures from the helper (`collect_events`).
- **Queue:** reports wait in `$XDG_STATE_HOME/atlas/crash-reports/pending/` for the user's decision (`pending`, `discard`). Sent ones move to `sent/` and are pruned after 90 days.

What a report holds: AtlasOS version, channel and previous version; app name, version and category; the stack trace; kernel; GPU model and driver; uptime; CPU model, RAM total and use; a timestamp and the report type. A rotating random ID (new every 30 days, never `/etc/machine-id`) stays on the machine and is not sent, so public reports cannot be linked to each other. Never collected: core dumps, user names, host names, MAC or IP addresses, serials, email addresses, credentials and tokens, installed apps, file contents, command lines, environment or working directory. Every string is scrubbed with [`Scrubber`](#scrubber).

Panic reports are limited to 5 an hour, and the same crash (same message and location) is saved once.

## Example

```rust
use atlas_framework_system::crash;

// A settings page: the user's switch.
crash::Settings { enabled: true }.save()?;

// A reports page: show each payload, then send on a yes.
for report in crash::pending() {
    println!("{}", report.to_json_pretty()?);
    // after the user agrees:
    crash::send(&report)?;
    // or, if they decline:
    // crash::discard(&report)?;
}
```

Collect on a timer or at start-up: `crash::collect_coredumps(None)` and `crash::collect_events(None)` queue what is new since the last call (both return nothing when reporting is off).

## Settings

`#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)] pub struct Settings { pub enabled: bool }`

Off unless the file says `enabled = true`.

| Method | Description |
|---|---|
| `fn path() -> Option<PathBuf>` | `$XDG_CONFIG_HOME/atlas/crash-reporting.toml` (or `~/.config/...`); `None` without an absolute config directory |
| `fn load() -> Settings` | Reads the switch; missing or unreadable means off |
| `fn load_from(path: &Path) -> Settings` | Reads another file |
| `fn save(&self) -> io::Result<()>` | Saves the switch. Turning reporting **on** starts the coredump and event markers at "now", so nothing from before the opt-in is queued. Turning it **off** deletes every pending report and removes sent reports older than 90 days (as `pending()` and `sent()` also do) |
| `fn save_to(&self, path: &Path) -> io::Result<()>` | Writes one file: a temp file beside it (never through a symlink), then a rename |

## Endpoint

`#[derive(Debug, Clone, PartialEq, Eq)] pub struct Endpoint { pub key: String, pub store_url: String }`

A GlitchTip DSN of the form `https://<key>@<host>[/prefix]/<project>`. `store_url` is `https://host/api/<project>/store/`.

| Method | Description |
|---|---|
| `fn load() -> Option<Endpoint>` | The configured endpoint. If `/etc/atlas/crash-reporting.toml` has a `dsn` key it alone decides (empty means none); only without the key does the shipped default apply |
| `fn load_from(path: &Path) -> Option<Endpoint>` | From one file's `dsn` key |
| `fn parse(dsn: &str) -> Option<Endpoint>` | `https` only; `http` is accepted for `localhost`, `127.0.0.1` and `[::1]`. The key must be a plain public key (a legacy `key:secret` is refused) |

## Report

`#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)] pub struct Report`. The file layout is in [On-disk formats](formats.md#crash-reports).

| Field | Type | Description |
|---|---|---|
| `schema` | `u32` | `2` |
| `event_id` | `String` | 32 hex characters; the Sentry event ID |
| `report_type` | `String` | `panic`, `fatal`, `coredump` or an event name such as `update-failed` |
| `time` | `String` | RFC 3339 UTC |
| `crash_id` | `String` | The rotating anonymous ID |
| `atlasos_version`, `channel`, `previous_version` | `Option<String>` | From `bootc status` and the boot history |
| `app_name` | `String` | The app ID (or the crashed program) |
| `app_version` | `Option<String>` | |
| `category` | `String` | `Plasma`, `KWin`, `Atlas app` or `other` |
| `message`, `stacktrace` | `String` | Scrubbed |
| `kernel`, `gpu`, `gpu_driver`, `cpu_model` | `Option<String>` | |
| `uptime_secs`, `ram_total_kb`, `mem_used_kb` | `u64` | |
| `sent_event_id` | `Option<String>` | The server's event ID, once sent |
| `issue_url` | `Option<String>` | The public GitHub issue the relay filed, once sent. Check it with `is_issue_url` wherever it is shown |
| `path` | `Option<PathBuf>` | Where the report is stored; not part of the report (never serialized) |

| Method | Description |
|---|---|
| `fn payload(&self) -> Value` | The exact Sentry event JSON that `send` posts, as `serde_json::Value`. Tags: `app`, `app_version`, `category`, `atlasos_version`, `channel`, `previous_version`, `kernel`, `gpu`, `gpu_driver`, `report_type`; missing values read `unknown`; `release` is `atlasos@<version>` |
| `fn to_json_pretty(&self) -> Result<String, serde_json::Error>` | The payload as pretty JSON, for a "Show report" view |

## Scrubber

`#[derive(Debug, Clone, Default)] pub struct Scrubber`. Replaces home directories, user names, host names, MAC and IP addresses, machine and boot IDs, email addresses, credentials and tokens in strings. Matching is case-insensitive, and the text is normalized to NFC first.

| Method | Description |
|---|---|
| `fn new(users: &[&str], hosts: &[&str], homes: &[&str]) -> Self` | `users` are user names and full names, `hosts` host names (their first label is added), `homes` literal home directories |
| `fn from_env() -> Self` | Everything about this user and machine that could identify them: `$USER`, `$LOGNAME`, `$HOME`, the passwd name, full name and home, and the kernel, static and pretty host names |
| `fn for_system() -> Self` | Only the host names, for a root helper that has no user |
| `fn scrub(&self, s: &str) -> String` | `/home/<name>` and `/var/home/<name>` become `/home/USER` and `/var/home/USER`, user names `USER`, host names `HOST`; addresses and IDs go |
| `fn scrub_message(&self, s: &str) -> String` | `scrub`, then hides paths that can name a file the user had open. For panic messages and stack traces |

## Functions

| Name | Signature | Description |
|---|---|---|
| `install` | `pub fn install(app: AppInfo)` | Installs the panic hook for `app`. Call once, early in `main` (atlas-framework-ui does it). The previous hook runs first, then, only when reporting is on, a report is queued (not for a panic inside the hook itself) |
| `record_fatal` | `pub fn record_fatal(message: &str) -> Option<PathBuf>` | Queues a report for a fatal error that is not a Rust panic (a Qt fatal message handler). Needs `install`; does nothing when disabled |
| `pending` | `pub fn pending() -> Vec<Report>` | Reports waiting for the user's decision, oldest first. Also prunes old sent reports |
| `sent` | `pub fn sent() -> Vec<Report>` | Reports already sent, oldest first: the history list |
| `discard` | `pub fn discard(report: &Report) -> io::Result<()>` | "Don't send": deletes the pending report's file. The report needs a `path` (the ones from `pending` have one) |
| `collect_coredumps` | `pub fn collect_coredumps(since_micros: Option<u64>) -> Vec<Report>` | New systemd-coredump crashes of the user's own processes since the last call (or since `since_micros`), queued as pending and returned. The first call after opting in starts at "now". Tries the user journal, then the system journal filtered to the user's UID (readable for members of `wheel` or `systemd-journal`). Empty when disabled |
| `collect_events` | `pub fn collect_events(since: Option<&str>) -> Vec<Report>` | Reports for helper failures (`update-failed`, `rollback-failed`, `channel-switch-failed`, `automatic-rollback`, `health-check-failed`) newer than the last call (or `since`, an RFC 3339 time), queued as pending. Successes are skipped. Strings copied from the log are scrubbed again. Empty when disabled |
| `send` | `pub fn send(report: &Report) -> io::Result<()>` | POSTs the payload to the endpoint (the Sentry store API) with `/usr/bin/curl` (https only, no proxy, no redirects, 30 s limit) and moves the report to `sent/`. The caller must have shown the user the payload and got a yes. Fails with `PermissionDenied` when reporting is off and `NotFound` ("no endpoint configured") without an endpoint |
| `is_issue_url` | `pub fn is_issue_url(u: &str) -> bool` | Whether `u` is an issue of the AtlasOS project (`https://github.com/EternalCoder454/AtlasOS/issues/<number>`): the only link a sent report may carry |
| `github_issue_url` | `pub fn github_issue_url(r: &Report, repo: &str) -> String` | A prefilled `https://github.com/EternalCoder454/<repo>/issues/new?...` URL, at most about 7 KB (the trace is cut to fit). A secondary route to `send` |

## Constants and re-exports

| Name | Value | Description |
|---|---|---|
| `SYSTEM_CONFIG` | `"/etc/atlas/crash-reporting.toml"` | The system endpoint file |
| `DEFAULT_CONFIG` | `"/usr/share/atlas/crash-reporting.toml"` | The shipped endpoint file |
| `AppInfo` | re-export | `atlas_framework_core::AppInfo` |
