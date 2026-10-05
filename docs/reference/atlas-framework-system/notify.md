---
title: notify
summary: Desktop notifications over org.freedesktop.Notifications, sent the way KNotification sends them so Plasma groups them under the app and honours the user's per-event choice, with the notify feature.
order: 60
---

The `notify` module is the one way an Atlas app sends a desktop notification. It needs the `notify` feature of atlas-framework-system. It sends KDE's hints (`desktop-entry`, `x-kde-appname`, `x-kde-eventId`), so Plasma groups the notifications under the app and honours the user's choice per event in System Settings.

## Example

```rust
use atlas_framework_system::notify::{DEFAULT_ACTION, Note, Notifier, escape};

let app = atlas_framework_core::app_info! {
    name: "Atlas Updater",
    id: "net.eterneon.atlas.updater",
    repo: "atlasos-updater",
};
let notifier = Notifier::new(&app);
let mut note = Note::new("updateStaged", "Update ready", escape("44.20261001"));
note.actions.push((DEFAULT_ACTION, "Open Atlas Updater".into()));
notifier.send_blocking(&note)?; // from a worker thread, when nobody acts on it
```

In async code, use `notifier.send(&conn, &note).await` on a session-bus `zbus::Connection`.

## The notifyrc file

The names the app gives KNotification come from its `AppInfo`: the component (the notifyrc's name) is `AppInfo::short_name()`, the desktop entry and the icon are the app ID, and the app name is the display name. Each app ships `<short name>.notifyrc` (`atlas-` and the last part of the app ID) in `/usr/share/knotifications6/` with `DesktopEntry=<app id>` and one camelCase `[Event/<eventId>]` per kind of notification, whose `Action=` says `Popup`. The app template has one. Plasma writes the user's choice to `~/.config/<component>.notifyrc` (`[Event/<id>] Action=`, a `|`-separated list); without a user file, an `[Event/<id>]` group or an `Action` key there, the event pops up.

## AtlasOS rules for notifications

- Notify only when the user can act on it, or must know: not for progress or success they did not wait for.
- Popups only, no sounds. Leave `urgency` as `None` or `Normal` (`Critical` only when ignoring it has consequences); `persistent` only when ignoring the notification has consequences (a restart is due).
- Actions are short verbs that open the right page ("Restart now", "Open Atlas Updater"), never "OK" or "Dismiss". `DEFAULT_ACTION` is the click on the notification itself.
- Never from root to a user's session. A system service records the event, and the user-session app notices it and notifies.
- Do Not Disturb is Plasma's: do not second-guess it.
- Everything that came from outside (an app name, an error, a version) goes through `escape` before it goes into `Note::text`.

## Errors and limits

- Calls to the server give up after 10 seconds. The server may still show the notification after that, so do not retry blindly.
- With no notification service (or no session bus), the error reads "No notification service is running".
- `send` and `close` need a Tokio runtime with the time driver (`#[tokio::main]` and `enable_all()` have it); without one the timeout panics.
- `send_blocking` runs on a thread of its own with a runtime of its own, so it is safe to call inside an existing Tokio runtime's `spawn_blocking`, but not from the UI thread or from async code.
- An event ID that is not valid is refused with an error. An `icon` that is not valid is replaced by the app icon and logged.

## Note

`#[derive(Debug, Clone)] pub struct Note`

| Field | Type | Description |
|---|---|---|
| `event` | `&'static str` | The notifyrc event (`updateStaged`, `restartSoon`, ...): camelCase, letters and digits only |
| `title` | `String` | |
| `text` | `String` | Body markup: `escape` anything that came from outside |
| `icon` | `String` | Empty (the app's own icon), an icon name (letters, digits and `._+-`) or an absolute path without `..`. Anything else is replaced by the app's icon |
| `actions` | `Vec<(&'static str, String)>` | (key, label) pairs. `DEFAULT_ACTION` is the click on the notification itself |
| `urgency` | `Option<Urgency>` | `None` leaves the server's default |
| `persistent` | `bool` | Stays until the user acts (no timeout) |

`Note::new(event: &'static str, title: impl Into<String>, text: impl Into<String>) -> Note` is a plain notification: the app's icon, no actions, the server's default urgency and timeout.

`#[derive(Debug, Clone, Copy, PartialEq, Eq)] pub enum Urgency { Normal, High, Critical }`. `High` is KNotification's HighUrgency: the spec has no such level, so it goes out as normal. `Critical` goes out as level 2.

## Notifier

`#[derive(Debug, Clone, PartialEq, Eq)] pub struct Notifier`

| Method | Description |
|---|---|
| `fn new(app: &AppInfo) -> Notifier` | Takes the names from the app's `AppInfo` |
| `fn component(&self) -> &str` | The notifyrc's name: the app's `short_name()` |
| `fn desktop_entry(&self) -> &str` | The desktop file's name, which is the app ID |
| `fn app_name(&self) -> &str` | The display name |
| `fn app_icon(&self) -> &str` | The app's own icon: its ID |
| `fn popup_enabled(&self, event: &str) -> bool` | Whether `event` pops up, from the user's notifyrc. An event ID that is not valid never pops up |
| `async fn send(&self, conn: &zbus::Connection, n: &Note) -> zbus::Result<Option<Sent>>` | Sends `n`. `Ok(None)` means the user turned this event's popup off |
| `fn send_blocking(&self, n: &Note) -> Result<(), String>` | `send` over a new session-bus connection, blocking, for a notification nobody acts on (its actions are not followed) |

`#[derive(Debug, Clone, PartialEq, Eq)] pub struct Sent { pub id: u32, pub server: Option<String> }`: `id` is the server's notification ID, and `server` is the server's unique bus name (only its signals are about `id`).

## Functions and constants

| Name | Signature or value | Description |
|---|---|---|
| `SERVICE`, `PATH`, `INTERFACE` | `"org.freedesktop.Notifications"`, `"/org/freedesktop/Notifications"`, `"org.freedesktop.Notifications"` | The notification server's bus name, object path and interface |
| `DEFAULT_ACTION` | `"default"` | The key the server sends when the notification itself is clicked |
| `escape` | `pub fn escape(s: &str) -> String` | Escapes text for the body, which the server reads as markup: `&`, `<`, `>`, `"` and `'` become entities, and control characters other than line feed and tab become spaces |
| `event_id_ok` | `pub fn event_id_ok(event: &str) -> bool` | 1 to 64 ASCII letters and digits, not starting with a digit |
| `icon_ok` | `pub fn icon_ok(icon: &str) -> bool` | Empty, an icon name, or an absolute path without `..` and control characters. A URL or relative path is not |
| `close` | `pub async fn close(conn: &zbus::Connection, id: u32) -> zbus::Result<()>` | Closes notification `id`. Gives up after 10 seconds |
