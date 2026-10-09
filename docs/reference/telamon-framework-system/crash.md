---
title: crash
summary: Opt-in crash reports, the only telemetry a Telamon app may have, with the per-user switch, the endpoint, scrubbing, the pending queue and sending after the user has seen the exact payload.
order: 10
---

Crash reports are opt-in, off by default, and the user sees the exact payload before every send. When reporting is off nothing is collected or written.

A GUI app started through [telamon-framework-ui](../telamon-framework-ui/startup.md) already has the panic hook and the fatal Qt message hook installed. What an app adds is a settings switch and a page that lists pending reports, shows the payload and sends or discards them.

## How it works

- **Switch:** [`Settings`](#settings), per user, in `~/.config/telamon/crash-reporting.toml` (`enabled = false`).
- **Endpoint:** a Sentry-compatible DSN from `/etc/telamon/crash-reporting.toml`, default `/usr/share/telamon/crash-reporting.toml`. It is the Telamon OS relay, which posts each report it receives as a **public** issue in `github.com/EternalCoder454/AtlasOS`. An empty `dsn` in `/etc` turns sending off: `send` then fails with "no endpoint configured".
- **Sources:** Rust panics (`install`), fatal errors that are not panics (`record_fatal`), systemd-coredump entries of the user's own processes on the host, not those in containers (`collect_coredumps`) and update and rollback failures from the helper (`collect_events`).
- **Queue:** reports wait in `$XDG_STATE_HOME/telamon/crash-reports/pending/` for the user's decision (`pending`, `discard`). Sent ones move to `sent/` and are pruned after 90 days. A report file is read only as a regular file of at most 1 MiB, never through a symlink (a bigger one is moved to `quarantine/`, a link, a FIFO or a directory is left alone), and `pending` and `sent` scrub every string of a report again with the current rules when they list it, so a report an older version queued with weaker rules is shown and sent scrubbed (the file is not rewritten). Every report and marker is written atomically (a temp file, fsync, rename), so a crash while saving leaves the old file or the new one, never a cut one. A file in `pending/` or `sent/` that is not a report (damaged, cut short by an older version) is moved to `quarantine/` and kept there for 90 days; it is never listed or sent.

What a report holds: Telamon OS version, channel and previous version; app name, version and category; the stack trace; kernel; GPU model and driver; uptime (whole hours, rounded down); CPU model, RAM total (whole GB, rounded to the nearest) and use; a timestamp and the report type. The exact values would give the boot instant and tell machines apart, which would link public reports. A rotating random ID (new every 30 days, never `/etc/machine-id`) stays on the machine and is not sent, so public reports cannot be linked to each other. Never collected: core dumps, user names, host names, MAC or IP addresses, email addresses, credentials and tokens, installed apps (except the app ID of a Flatpak app that crashed), file contents, command lines, environment or working directory. Every string is scrubbed with [`Scrubber`](#scrubber). No hardware serial number is read; one that appears in a message is hidden when it is named (`serial=`, `ID_SERIAL=`, `imei=`) or has the shape of an IMEI (15 digits with a valid check digit), and not in any other form.

Text that comes from outside the framework (panic and fatal messages, frames, journal lines, the copied parts of events) also loses control characters and invisible or bidirectional Unicode (zero-width characters, `U+202E`, tag characters) before it is scrubbed, so they cannot split a secret from the scrubber or reverse what a reader sees. What GitHub would act on is made plain: `@name` becomes `@ name` (no one is notified; also after `-`, `.`, `+` and other non-word characters, not after a letter, digit or `_`), `](` becomes `] (` (no link, no image), `][` too unless it follows a word (`v[0][1]`), a `[x]: https://...` definition at the start of a line becomes `[x] : https://...`, an autolink `<https://...>` gets a space after the `<`, and so does an HTML element with attributes that links or loads (`<img src=...>`, `<a href=...>`, `<iframe src=...>`...). Scrubbing and this step are idempotent: running a stored report through them again changes nothing.

**Which core dumps count.** systemd-coredump on the host records the crashes of every process that shares its kernel, so those of containers (the test containers of developers and agents among them) are in the journal too. A core dump is skipped, with no report and no notification, when it was made by:

- a **container or machine**: its cgroup (`COREDUMP_CGROUP`, else `COREDUMP_USER_UNIT` or `COREDUMP_UNIT`) holds a `libpod-*` (podman, toolbox, distrobox), `docker-*`, `crio-*`, `cri-containerd-*`, `machine-*` (systemd-nspawn, libvirt), `lxc.payload.*` or `kubepods*` scope, or a `docker`, `lxc`, `machine.slice` or `libpod_parent` group; or, without such a cgroup, it sits in another PID namespace (`COREDUMP_CONTAINER_CMDLINE` is set) and has a host name other than the host's;
- a **program outside the OS**: its path is not under `/usr`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/opt`, `/app` or `/var/lib/flatpak` (`/tmp`, `/var/tmp`, `/work`, a build tree, a home directory, `/mnt`), unless it is a Flatpak app. A program path that is there but odd (control or invisible characters, `..`, not absolute, over 4096 bytes) counts as outside the OS too; only a missing path (an older systemd) counts as the host's.

A crash in a Flatpak app (an `app-flatpak-<app ID>-<n>.scope` cgroup) is kept, and its report's `app_name` is the Flatpak app ID. A core dump without these fields counts as the host's, so a crash is not lost to a missing one. Only whether `COREDUMP_CONTAINER_CMDLINE` is set is read, never its value, and none of these fields goes into a report.

The first collection after an update that raised the rules deletes the pending coredump reports they would have skipped (a report keeps no cgroup, so each is matched to its journal entry by time, program and message; one for a program in a home directory or another place outside the OS needs no journal). Nothing is shown about it: the reports are just gone.

Limits hold across every app of the user, so an app in a restart loop queues one report, not some per start. Panic and fatal reports are limited to 5 an hour, and the same crash (same message and location) is saved once a day. The same coredump (same program, signal and top five frames of the crashed thread) is also queued once a day. At most 50 reports wait in `pending/`; past that the oldest are deleted.

## Example

```rust
use telamon_framework_system::crash;

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

Collect on a timer or at start-up, on a worker thread (both block): `crash::collect_coredumps(None)` and `crash::collect_events(None)` queue what is new since the last call (both return nothing when reporting is off).

## Settings

`#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)] pub struct Settings { pub enabled: bool }`

Off unless the file says `enabled = true`.

| Method | Description |
|---|---|
| `fn path() -> Option<PathBuf>` | `$XDG_CONFIG_HOME/telamon/crash-reporting.toml` (or `~/.config/...`); `None` without an absolute config directory |
| `fn legacy_path() -> Option<PathBuf>` | Where 1.x kept the switch: `$XDG_CONFIG_HOME/atlas/crash-reporting.toml`. `load` reads it while the file at `path()` does not exist (so a choice made before 2.0.0 stands, an opt-out too), and `save` writes only `path()`. Since 2.0.0 |
| `fn load() -> Settings` | Reads the switch; missing or unreadable means off |
| `fn load_from(path: &Path) -> Settings` | Reads another file |
| `fn save(&self) -> io::Result<()>` | Saves the switch. Turning reporting **on** starts the coredump and event markers at "now", so nothing from before the opt-in is queued. Turning it **off** deletes every pending and quarantined report and removes sent reports older than 90 days (as `pending()` and `sent()` also do) |
| `fn save_to(&self, path: &Path) -> io::Result<()>` | Writes one file: a temp file beside it (never through a symlink), then a rename |

## Endpoint

`#[derive(Debug, Clone, PartialEq, Eq)] pub struct Endpoint { pub key: String, pub store_url: String }`

A GlitchTip DSN of the form `https://<key>@<host>[/prefix]/<project>`. `store_url` is `https://host/api/<project>/store/`.

| Method | Description |
|---|---|
| `fn load() -> Option<Endpoint>` | The configured endpoint. If `/etc/telamon/crash-reporting.toml` (or else `/etc/atlas/crash-reporting.toml`, written by an administrator of 1.x) has a `dsn` key it alone decides (empty means none); only without the key does the shipped default apply (`/usr/share/telamon/...`, then `/usr/share/atlas/...`) |
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
| `app_name` | `String` | The app ID, or for a coredump the crashed program: for a Flatpak app its app ID, otherwise its whole path under `/usr`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/opt`, `/app` or `/var/lib/flatpak`; otherwise `<home>/<program>` for one in a home directory and `<path>/<program>` for any other place |
| `app_version` | `Option<String>` | |
| `category` | `String` | `Plasma`, `KWin`, `Telamon app` or `other` |
| `message`, `stacktrace` | `String` | Scrubbed. `message` is at most 64 KiB: a longer one is cut on a character boundary and ends with `[... cut: the message was <n> bytes]` |
| `kernel`, `gpu`, `gpu_driver`, `cpu_model` | `Option<String>` | |
| `uptime_secs`, `ram_total_kb`, `mem_used_kb` | `u64` | Uptime is a multiple of 3600 (rounded down) and RAM total a multiple of 1 GB (1 048 576 kB, rounded to the nearest, 1 GB at least); `payload` applies both to a report an older version stored with exact values |
| `sent_event_id` | `Option<String>` | The server's event ID, once sent |
| `issue_url` | `Option<String>` | The public GitHub issue the relay filed, once sent. Check it with `is_issue_url` wherever it is shown |
| `path` | `Option<PathBuf>` | Where the report is stored; not part of the report (never serialized) |

| Method | Description |
|---|---|
| `fn payload(&self) -> Value` | The exact Sentry event JSON that `send` posts, as `serde_json::Value`, at most `MAX_PAYLOAD` (64 KiB) serialized: a longer message is cut to 8 KiB first (it is in the payload twice), then frames are dropped from the far end of the stack (the top stays) and `extra.trace_frames_dropped` says how many, and as a last resort the message is cut further. Uptime and RAM total are coarse as described under Report. Tags: `app`, `app_version`, `category`, `atlasos_version`, `channel`, `previous_version`, `kernel`, `gpu`, `gpu_driver`, `report_type`; missing values read `unknown`; `release` is `atlasos@<version>` |
| `fn to_json_pretty(&self) -> Result<String, serde_json::Error>` | The payload as pretty JSON, for a "Show report" view |

## Scrubber

`#[derive(Debug, Clone, Default)] pub struct Scrubber`. Replaces home directories, user names, host names, MAC and IP addresses, machine and boot IDs, email addresses, credentials and tokens in strings. Matching is case-insensitive, and the text is normalized to NFC first.

A secret name (`token`, `secret`, `password`, `passwd`, `passphrase`, `apikey`, `authorization`, `credential(s)`) hides its value also at the end of a longer word (`PGPASSWORD=...`, `dbPassword=...`); the short names (`key`, `sig`, `auth`, `pwd`, `pass`) count at a word start or a camel-case boundary only (`apiKey=`, `DB_PASS=`), `pass` only with `=`, and `code` / `code_verifier` only in a URL query (`?code=...`). `Authorization: Bearer` and `Basic` hide the credential after any number of spaces or tabs, and a standalone `Basic <base64>` is hidden. Hex runs of 40 or more characters (SHA-1 and SHA-256 digests, key material; also inside a word: `build-<hex>`, `0x<hex>`, `<hex>.json`) become `<id>`, except the compiler commit after `/rustc/`; a base64 secret that contains `/` or ends in `=` is hidden whole; the path of a Slack or Discord webhook after `hooks.slack.com/services/` in any case.

| Method | Description |
|---|---|
| `fn new(users: &[&str], hosts: &[&str], homes: &[&str]) -> Self` | `users` are user names and full names, `hosts` host names (their first label is added), `homes` literal home directories |
| `fn from_env() -> Self` | Everything about this user and machine that could identify them: `$USER`, `$LOGNAME`, `$HOME`, the passwd name, full name and each word of it of 3 or more characters, home, and the kernel, static and pretty host names |
| `fn for_system() -> Self` | Only the host names, for a root helper that has no user |
| `fn scrub(&self, s: &str) -> String` | `/home/<name>` and `/var/home/<name>` become `/home/USER` and `/var/home/USER`, user names `USER`, host names `HOST`; addresses and IDs go |
| `fn scrub_message(&self, s: &str) -> String` | `scrub`, then hides paths that can name a file the user had open: a path in a home directory, `/run/user`, `/run/media`, `/media`, `/mnt`, `/tmp`, `/srv`, `/root` and, since 2.0.8, **every absolute path outside the system's directories** (`/data/clients/Acme/q3.xlsx`, `/storage/...`, `/Volumes/...`). Shown whole: paths under `/usr`, `/bin`, `/sbin`, `/lib`, `/lib64`, `/opt`, `/app`, `/etc`, `/proc`, `/sys`, `/dev`, `/boot`, `/run`, `/sysroot`, `/ostree`, `/rustc`, `/builddir`, `/var/lib/flatpak`, `/var/lib/telamon`, `/var/lib/atlas-core` and `/var/log`, URLs and Qt resources (`qrc:/...`). For panic messages and stack traces |

## Functions

| Name | Signature | Description |
|---|---|---|
| `install` | `pub fn install(app: AppInfo)` | Installs the panic hook for `app`. Call once, early in `main` (telamon-framework-ui does it). The previous hook runs first, then, only when reporting is on, a report is queued (not for a panic inside the hook itself) |
| `record_fatal` | `pub fn record_fatal(message: &str) -> Option<PathBuf>` | Queues a report for a fatal error that is not a Rust panic (a Qt fatal message handler). Needs `install`; does nothing when disabled |
| `opt_out` | `pub fn opt_out(app: &AppInfo)` | Writes the app's program path and app ID to `$XDG_STATE_HOME/telamon/crash-optout` (0600, at most 64 entries) so that `collect_coredumps` of any Telamon app never reports its crashes, even when the user turned reporting on. The core dump itself stays with systemd-coredump. `telamon-framework-ui` calls it for an app with `crash: false` in `app!`; an app that does not use that crate can call it itself |
| `pending` | `pub fn pending() -> Vec<Report>` | Reports waiting for the user's decision, oldest first. Also prunes old sent reports |
| `sent` | `pub fn sent() -> Vec<Report>` | Reports already sent, oldest first: the history list |
| `discard` | `pub fn discard(report: &Report) -> io::Result<()>` | "Don't send": deletes the pending report's file. The report needs a `path` (the ones from `pending` have one), and only a report file (`*.json`, not a symlink) directly in `pending/` is deleted: any other path fails with `InvalidInput` |
| `collect_coredumps` | `pub fn collect_coredumps(since_micros: Option<u64>) -> Vec<Report>` | New systemd-coredump crashes of the user's own processes on the host (see "Which core dumps count"; not those in containers or of programs outside the OS) since the last call (or since `since_micros`), queued as pending and returned. The first call after opting in starts at "now"; an empty or damaged marker counts from when it was last written. Tries the user journal, then the system journal filtered to the user's UID (readable for members of `wheel` or `systemd-journal`). Empty when disabled. **Blocks** for up to about 25 s: `journalctl` gets 10 s a call (two at most) and `rpm -qf`, asked for a program without a package field, 5 s; past its limit a command is killed, and after one `rpm` timeout (an update holding the rpmdb lock) the call asks no more. The first call after an update that raised the rules for which core dumps count also looks the pending ones up in the journal (at most 12 more `journalctl` calls, 10 s each, once). Call it from a worker thread |
| `collect_events` | `pub fn collect_events(since: Option<&str>) -> Vec<Report>` | Reports for helper failures (`update-failed`, `rollback-failed`, `channel-switch-failed`, `automatic-rollback`, `health-check-failed`) newer than the last call (or `since`, an RFC 3339 time), queued as pending. Successes are skipped. Strings copied from the log are scrubbed again, and the version is cut to 64 characters of letters, digits and `._+~:-`; an event whose `time` is longer than 40 characters is skipped (it could not be a file name). Empty when disabled. Blocks on file I/O: call it from a worker thread |
| `send` | `pub fn send(report: &Report) -> io::Result<()>` | POSTs the payload to the endpoint (the Sentry store API) with `/usr/bin/curl` (https only, TLS 1.2 or newer, no proxy, no redirects, 30 s limit; an answer that is not 2xx fails, a 3xx included) and moves the report to `sent/`. The caller must have shown the user the payload and got a yes. For the time of the POST the pending file is taken (renamed to `<name>.json.sending`, so no list shows it): a second sender of the same report, or a report no longer pending, fails with `AlreadyExists` instead of filing a second public issue. A failed POST puts it back. A report whose payload is still over `MAX_PAYLOAD` after the cuts (a field other than the message and trace is huge) is not sent: it fails as `Rejected`. A report whose `path` is not a file in `pending/` is sent, but its file is neither taken nor deleted. Fails with `PermissionDenied` when reporting is off and `NotFound` ("no endpoint configured") without an endpoint. A failed POST carries a [`SendFailure`](#sendfailure) (read it with `send_failure`) |
| `send_failure` | `pub fn send_failure(e: &io::Error) -> Option<&SendFailure>` | The `SendFailure` inside an error from `send`, or `None` for the other errors (reporting off, no endpoint, a file error) |
| `is_issue_url` | `pub fn is_issue_url(u: &str) -> bool` | Whether `u` is an issue of the Telamon OS project (`https://github.com/EternalCoder454/AtlasOS/issues/<number>`): the only link a sent report may carry |
| `github_issue_url` | `pub fn github_issue_url(r: &Report, repo: &str) -> String` | A prefilled `https://github.com/EternalCoder454/<repo>/issues/new?...` URL, at most about 7 KB: the trace is cut to fit, a message too long on its own is cut too, and as a last resort the URL itself (never inside a character). A secondary route to `send`. The trace is in a code fence longer than any run of backticks in it (a run over 8 gets a space every 8, so the fence stays short; each trace line is cut to 400 characters), so a frame cannot end the block |

## SendFailure

Why a send failed, in words an app shows as they are (after "Could not send the crash report: ", or alone). Its `Display` is that sentence. Each variant also sets the `io::Error`'s kind: `ConnectionRefused` for `Unreachable`, `WouldBlock` for `RateLimited` and `ServerTrouble` (try later), `InvalidData` for `Rejected`, `Other` for the rest; never `NotFound`, `PermissionDenied` or `AlreadyExists`, which mean "no endpoint", "reporting is off" and "already being sent". The HTTP status is read from curl's `--write-out`. The full curl error goes to stderr (the journal), never to the user.

| Variant | When | Shown as |
|---|---|---|
| `Unreachable` | No answer: no connection, DNS failure, timeout | "the crash report server could not be reached. Check the internet connection and try again later." |
| `RateLimited` | HTTP 429: the relay's hourly or daily limit | "the crash report server has had too many reports today. Try again tomorrow." |
| `ServerTrouble` | HTTP 5xx | "the crash report server is having trouble. Try again later." |
| `Rejected` | HTTP 400 or 413: the server will never take this report | "the server can't accept this report. You can delete it with Don't Send." |
| `Refused(u16)` | Any other HTTP error (401, 403, 404...) | "the crash report server refused it (HTTP n). Try again after the next update." |
| `BadAnswer` | An answer came but curl failed on it (cut off, too big, a redirect) | "the server's answer was not understood. Try again later." |

## Constants and re-exports

| Name | Value | Description |
|---|---|---|
| `SYSTEM_CONFIG` | `"/etc/telamon/crash-reporting.toml"` | The system endpoint file |
| `DEFAULT_CONFIG` | `"/usr/share/telamon/crash-reporting.toml"` | The shipped endpoint file |
| `LEGACY_SYSTEM_CONFIG`, `LEGACY_DEFAULT_CONFIG` | `"/etc/atlas/crash-reporting.toml"`, `"/usr/share/atlas/crash-reporting.toml"` | The same two files as 1.x named them, read after the ones above. Since 2.0.0 |
| `AppInfo` | re-export | `telamon_framework_core::AppInfo` |
| `MAX_PAYLOAD` | `65536` | The most bytes `Report::payload` makes when serialized. Since 2.0.8 |
