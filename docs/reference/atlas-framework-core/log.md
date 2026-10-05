---
title: log
summary: The log crate's macros sent straight to the systemd journal with a priority and the app's identifier, falling back to stderr.
order: 30
---

The `log` module sends the `log` crate's macros (`log::info!`, `log::warn!` and the rest) to the systemd journal, tagged with the app's short name, so `journalctl -t atlas-updater` finds an app's messages. Without a journal (a container, a test) messages go to stderr.

An app started through [atlas-framework-ui](../atlas-framework-ui/startup.md) has this installed already. Call `init` yourself only in a tool or service with no GUI start-up.

## Example

```rust
let app = atlas_framework_core::app_info! {
    name: "Atlas Notepad",
    id: "net.eterneon.atlas.notepad",
    repo: "atlasos-notepad",
};
atlas_framework_core::log::init(&app); // once, first thing
log::info!("started");
```

## Behaviour

- Level: `ATLAS_LOG` sets it to `error`, `warn`, `info`, `debug`, `trace` or `off`. The default is `info`, also used for a value that is not a level.
- Journal fields per entry: `MESSAGE`, `PRIORITY` (error 3, warning 4, info 6, debug and trace 7), `SYSLOG_IDENTIFIER` (the app's `short_name()`), `ATLAS_TARGET` (the log target), and `CODE_FILE` and `CODE_LINE` when known. A message with a newline is sent in the journal's length-prefixed form.
- Messages are cut at 32 KiB.
- The socket is non-blocking: a stalled journal never stalls the app. A message it cannot take goes to stderr as `<ident>: <level>: <message>`, with control characters other than newline and tab shown as `\u{..}` escapes.
- The journal socket is `/run/systemd/journal/socket`.

## Items

| Name | Kind | Description |
|---|---|---|
| `init` | `pub fn init(app: &AppInfo)` | Installs the logger for `app` and sets the level. Later calls do nothing, so a library may call it too |
