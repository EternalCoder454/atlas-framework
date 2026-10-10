---
title: Startup behaviour
summary: What a Telamon app does at start, with one instance per session, the Wayland activation token, journal logging, the Rust panic hook and the fatal Qt message hook.
order: 30
---

This is what `telamon_app_run` (or `telamon_app_init` plus `telamon_app_ready`) gives every Telamon app. See [The C API](c-api.md) for the calls.

## Names and style

`telamon_app_init` takes the app's name, ID, version and repository from [`app!`](app-macro.md) and sets Qt's organization domain and application name from the ID, so KDBusService registers the app ID itself on the session bus (for `net.eterneon.telamon.notepad` the organization domain is `telamon.eterneon.net` and the application name is `notepad`). It also sets the desktop file name to the app ID and the Qt Quick Controls style to `org.kde.desktop`, unless `QT_QUICK_CONTROLS_STYLE` is already set. Afterwards the display name and window icon come from the name and ID, and the repository is stored for `TelamonApp`.

## Single instance

`telamon_app_run` registers a unique KDBusService. A second launch asks the first instance to raise its window, then exits. Without a session bus (ssh, a bare container) there is nobody to ask: it logs "No single-instance service, running as a separate instance" and runs anyway.

When the first instance is asked to raise its window it:

1. clears the minimised state while keeping maximised or full-screen,
2. shows and raises the window,
3. uses the launcher's activation token (KDBusService puts it in the environment, and `KWindowSystem::updateStartupId` reads it) and then activates the window, because without the token Wayland does not let the window come up.

The second launch's arguments are dropped. An app that opens files uses `telamon_app_init`, `telamon_app_ready` and its own `KDBusService`.

## Logging

`telamon_app_init` calls `telamon_framework_core::log::init`: Rust `log` macros go to the systemd journal under the identifier `<short name>` (for example `telamon-notepad`), with a stderr fallback. `TELAMON_LOG=debug` changes the level. See [log](../telamon-framework-core/log.md). Qt's own messages keep going to Qt's default handler (the journal or stderr) after the Telamon hook has seen them. The `telamon.ui` Qt logging category is at warning level by default; the Telamon.Ui version check logs its timing at debug level.

## Crash hooks

Both hooks save a report only when the user turned crash reporting on, and never send anything by themselves. See [crash](../telamon-framework-system/crash.md). An app whose [`app!`](app-macro.md#keeping-an-app-out-of-crash-reports) says `crash: false` (or that called `telamon_app_set_crash_reporting(false)` before `telamon_app_init`) gets neither hook: no panic hook is installed and a fatal Qt message is only logged. `telamon_framework_ui::crash_reporting()` returns which applies.

- **Rust panics.** `telamon_framework_system::crash::install` installs a panic hook. The default hook still prints the panic first. When reporting is enabled, a report is queued in `pending/`, at most 5 an hour and each crash once.
- **Fatal Qt messages.** `telamon_app_init` installs a Qt message handler before `QApplication`, so a fatal while it starts (no display, no platform plugin) is saved too. On a `QtFatalMsg` it logs the text as an error and calls `crash::record_fatal`, then passes the message on to the previous handler, which aborts. Only the first fatal saves a report; a fatal on another thread waits until that report is saved so the abort cannot cut it off. A 10-second alarm ends the process if saving hangs.

## Process-wide state

`start()` is safe to call more than once; only the first call installs the logger and the panic hook. A Rust test or tool may call `telamon_framework_ui::start()` directly instead of `telamon_app_init`.
