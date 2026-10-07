---
title: On-disk formats
summary: Every file the system crate and the core crate read or write for other programs, with exact paths, keys, fields and permissions, and the format-version rule.
order: 70
---

These files are contracts: an app, the root helper and a newer or older release all read them. Every file an app or a service writes for another to read carries its format version.

## The format-version rule

- `"format": 1` on each line of `history.jsonl` and `events.jsonl` (`history::FORMAT`, `events::FORMAT`). `version` in those lines is the OS version, so the format has its own name.
- `Format=1` under `[Telamon]` in settings files (`settings::FORMAT`).
- Readers accept a missing format (written before 1.3.0) and a higher one (written by a newer program; unknown fields are ignored) forever.
- The number is raised only for a change an old reader would misread.
- `crates/*/tests/fixtures/` holds files written by older versions. Tests read them, and they are never edited, only added to.

## Settings file

`$XDG_CONFIG_HOME/telamon-<app>rc` (default `~/.config`), KConfig INI. Written by [`settings`](../telamon-framework-core/settings.md) and by Telamon.Ui's [TelamonSettings](../telamon-ui/telamon-settings.md), under the lock file `.telamon-<app>rc.lock` beside it.

```text
[Telamon]
Format=1

[Restart]
ScheduledAt=1700000000
```

## History

`/var/lib/atlas-core/history.jsonl`, mode 0644, written by `atlas-system-helper record-boot` as root. One JSON object per line, appended when the booted digest differs from the newest line. The path keeps the old atlas-core name because existing systems hold data there. Read by [`history`](history.md).

```json
{"format":1,"version":"44.20261003","digest":"sha256:...","image":"ghcr.io/eternalcoder454/atlasos:stable","timestamp":"2026-10-03T04:00:00Z","first_booted":"2026-10-04T08:12:00Z"}
```

| Field | Description |
|---|---|
| `format` | `1`. Absent on lines from before 1.3.0 |
| `version` | OS version; may be `null` or absent |
| `digest` | Image digest |
| `image` | Image reference; may be `null` or absent |
| `timestamp` | Image build time, RFC 3339; may be `null` or absent |
| `first_booted` | When this machine first booted it, RFC 3339 UTC |

## Events

`/var/lib/atlas-core/events.jsonl`, mode 0644, with the lock file `events.jsonl.lock` (0600) beside it. One JSON object per line. When the file passes 512 KiB it is cut to the newest lines (at most 1000 lines and 256 KiB). Read by [`events`](events.md) and by `crash::collect_events`.

```json
{"format":1,"event":"update-failed","version":"44.20261003","error":"...","time":"2026-10-04T08:12:00Z"}
```

| Field | Description |
|---|---|
| `format` | `1`. Absent on older lines |
| `event` | `update-staged`, `update-failed`, `rollback-requested`, `rollback-failed`, `channel-switched`, `channel-switch-failed`, `update-applied`, `rollback-applied`, `automatic-rollback`, `health-check-failed` or `health-check-passed` |
| `version` | OS version. Left out when unknown |
| `error` | Scrubbed error text, at most 300 characters. Left out when none |
| `time` | RFC 3339 UTC |

## Boot health

`/var/lib/atlasos/bad-image-digests` (`bootc::BAD_IMAGE_DIGESTS`): digests of images that failed their boot health checks and were rolled back by greenboot, one per line, newest last, at most 20. The Telamon OS image's greenboot `red.d` script adds a digest and its `green.d` script removes one that later boots healthy. Readable without root.

## Crash reporting

All user files except `crash-reporting.toml` (0644) are under XDG directories and written with mode 0600 in directories of mode 0700, without following symlinks. Each is written atomically: a temp file `.<name>.<hex>.tmp` beside it, fsync, a rename (or, for a new report, a link that never replaces one) and a directory fsync. Temp files left by a killed process are swept after 10 minutes.

| Path | Contents |
|---|---|
| `~/.config/telamon/crash-reporting.toml` | `enabled = true` or `false`, after a comment line. Off unless `true`. Mode 0644 |
| `/etc/telamon/crash-reporting.toml` | System endpoint: `dsn = "https://<key>@<host>/<project>"`. An empty `dsn` turns sending off |
| `/usr/share/telamon/crash-reporting.toml` | The shipped default endpoint; used only when `/etc` has no `dsn` key |
| `$XDG_STATE_HOME/telamon/crash-reports/pending/<time>-<nn>.json` | Reports waiting for the user's decision. `<time>` is the report's RFC 3339 time and `<nn>` a counter from `00` for reports in the same second. At most 50; the oldest names go first |
| `$XDG_STATE_HOME/telamon/crash-reports/pending/<time>-<nn>.json.sending` | A pending report while `crash::send` posts it; renamed back if the send fails, or after 10 minutes if the sender was killed |
| `$XDG_STATE_HOME/telamon/crash-reports/sent/<time>-<nn>.json` | Sent reports, with `sent_event_id` and `issue_url` filled in. Removed after 90 days |
| `$XDG_STATE_HOME/telamon/crash-reports/recent` | The crashes queued in the last day, for the limits shared by all apps: one line each, `<Unix seconds> <crash key, 16 hex digits>`. The key is an FNV-1a hash (of the message and location for a panic or fatal error; of the program, message and top five frames for a coredump), so it names nothing. Lines older than a day are dropped. Locked with `recent.lock` (0600) beside it |
| `$XDG_STATE_HOME/telamon/crash-reports/quarantine/<file name>` | Files from `pending/` or `sent/` that are not reports (damaged or cut short), unchanged for a minute when found; a clash gets `.<n>` appended. Never listed or sent; removed after 90 days or when reporting is turned off |
| `$XDG_STATE_HOME/telamon/crash-id` | The rotating anonymous ID: line 1 is 32 hex characters, line 2 the creation time in Unix seconds. Replaced after 30 days |
| `$XDG_STATE_HOME/telamon/coredump-last` | The coredump marker: a Unix time in microseconds. An empty or damaged one counts as its modification time |
| `$XDG_STATE_HOME/telamon/events-last` | The event marker: an RFC 3339 time, a space, and how many events at that time were already taken. An empty or damaged one counts as its modification time, the events of that second taken |
| `$XDG_STATE_HOME/telamon/send-*.json` | A transient curl body file during a send; stale ones (older than 10 minutes) are swept |

`$XDG_STATE_HOME` defaults to `~/.local/state`.

### Crash reports

A report file is the pretty-printed JSON of `crash::Report` (schema 2). A report without `event_id` (schema 1) is deleted when found. `path` is never stored.

```json
{
  "schema": 2,
  "event_id": "<32 hex>",
  "report_type": "panic",
  "time": "2026-10-04T08:12:00Z",
  "crash_id": "<32 hex>",
  "atlasos_version": "44.20261003",
  "channel": "stable",
  "previous_version": null,
  "app_name": "net.eterneon.telamon.notepad",
  "app_version": "1.0.0",
  "category": "Telamon app",
  "message": "...",
  "stacktrace": "...",
  "kernel": "...",
  "gpu": null,
  "gpu_driver": null,
  "uptime_secs": 0,
  "cpu_model": null,
  "ram_total_kb": 0,
  "mem_used_kb": 0,
  "sent_event_id": null,
  "issue_url": null
}
```

What `crash::send` posts is not this file but `Report::payload()`, a Sentry event: `event_id`, `timestamp`, `platform` (`native`), `level` (`fatal`), `logger` (`atlas-core`), `release` (`atlasos@<version>`), `environment` (the channel), `message`, `tags`, `contexts` (`os`, `gpu`, `device`, `runtime`) and, when the trace has frames, `exception`. It goes to the endpoint's `store_url` with the header `X-Sentry-Auth: Sentry sentry_version=7, sentry_key=<key>, sentry_client=atlas-core/<version>`.

The relay's answer is JSON `{"id": ..., "url": ...}`. The `url` is kept only if `crash::is_issue_url` accepts it, and the `id` only if it is a plain event ID.

## Notifications

`<short name>.notifyrc`, shipped in `/usr/share/knotifications6/` with `DesktopEntry=<app id>` and one `[Event/<eventId>]` group per kind of notification (`Action=Popup`). The user's choice is written by Plasma to `~/.config/<short name>.notifyrc`. See [notify](notify.md).
