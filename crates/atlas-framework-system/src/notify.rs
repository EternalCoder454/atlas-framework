//! Desktop notifications over `org.freedesktop.Notifications`, sent the way
//! KNotification sends the events in the app's `<short-name>.notifyrc`:
//! Plasma groups them under the app and its notification settings apply.
//! Needs feature `notify`.
//!
//! ```no_run
//! # use atlas_framework_system::notify::{Note, Notifier, DEFAULT_ACTION, escape};
//! # let app = atlas_framework_core::app_info! { name: "Atlas Updater", id: "net.eterneon.atlas.updater", repo: "r" };
//! let notifier = Notifier::new(&app);
//! let mut note = Note::new("updateStaged", "Update ready", &escape("44.20261001"));
//! note.actions.push((DEFAULT_ACTION, "Open Atlas Updater".into()));
//! notifier.send_blocking(&note)?; // from a worker thread, nobody acts on it
//! # Ok::<(), String>(())
//! ```
//!
//! Which names the app gives KNotification come from its [`AppInfo`]: the
//! component (the notifyrc's name) is [`AppInfo::short_name`], the desktop
//! entry and the icon are the app ID, the app name is the display name. Ship
//! `<short-name>.notifyrc` in `$datadir/knotifications6/` (see the template).
//!
//! # AtlasOS rules for notifications
//!
//! - Notify only when the user can act on it. News with nothing to do (a
//!   background task that went fine) is not a notification.
//! - Popups only, no sounds: the notifyrc's events say `Action=Popup`.
//! - [`Note::persistent`] only when ignoring the notification has
//!   consequences (a restart that will happen, an update that failed).
//! - Actions are short verbs that open the right page ("Restart now", "Open
//!   Atlas Updater"), never "OK" or "Dismiss". Clicking the notification
//!   itself is [`DEFAULT_ACTION`].
//! - A service running as root sends none (it would show another user's
//!   desktop something, and has no session bus). It records the event and
//!   the user-session app notices it and notifies.
//! - Everything that came from outside (an app name, an error, a version)
//!   goes through [`escape`] before it goes into [`Note::text`].

use std::collections::HashMap;
use std::path::Path;
use std::time::Duration;

use atlas_framework_core::AppInfo;
use atlas_framework_core::settings::{Settings, config_dir};
use zbus::zvariant::Value;

pub const SERVICE: &str = "org.freedesktop.Notifications";
pub const PATH: &str = "/org/freedesktop/Notifications";
pub const INTERFACE: &str = "org.freedesktop.Notifications";

/// The key the server sends when the notification itself is clicked.
pub const DEFAULT_ACTION: &str = "default";

/// How long a call to the notification server may take.
const CALL_TIMEOUT: Duration = Duration::from_secs(10);

/// What the user is told when nothing owns the notification name.
const NO_SERVICE: &str = "No notification service is running";

/// The longest event id [`event_id_ok`] accepts.
const MAX_EVENT_CHARS: usize = 64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Urgency {
    Normal,
    /// KNotification's HighUrgency: the spec has no such level, so it goes
    /// out as normal, as KNotification sends it.
    High,
    Critical,
}

#[derive(Debug, Clone)]
pub struct Note {
    /// The notifyrc event (`updateStaged`, `restartSoon`, …): camelCase,
    /// letters and digits only (see [`event_id_ok`]). [`Notifier::send`]
    /// refuses anything else.
    pub event: &'static str,
    pub title: String,
    /// Body markup: escape anything that came from outside with [`escape`].
    pub text: String,
    /// Empty (the app's own icon), an icon name (letters, digits and
    /// `._+-`) or an absolute path without `..`. Anything else (a URL, a
    /// relative path) is replaced by the app's icon and logged.
    pub icon: String,
    /// (key, label) pairs. [`DEFAULT_ACTION`] is the click on the
    /// notification itself.
    pub actions: Vec<(&'static str, String)>,
    pub urgency: Option<Urgency>,
    /// Stays until the user acts (no timeout).
    pub persistent: bool,
}

impl Note {
    /// A plain notification: the app's icon, no actions, the server's default
    /// urgency and timeout. `text` is markup: [`escape`] what came from outside.
    pub fn new(event: &'static str, title: impl Into<String>, text: impl Into<String>) -> Note {
        Note {
            event,
            title: title.into(),
            text: text.into(),
            icon: String::new(),
            actions: Vec::new(),
            urgency: None,
            persistent: false,
        }
    }
}

/// Escapes text for the body, which the server reads as markup. Control
/// characters other than line feed and tab become spaces.
pub fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            c if (c as u32) < 0x20 && c != '\n' && c != '\t' => out.push(' '),
            c => out.push(c),
        }
    }
    out
}

/// Whether `event` can name a notifyrc group: 1 to 64 ASCII letters and
/// digits, not starting with a digit (KNotification's camelCase ids). The
/// id becomes part of a settings group name (`Event/<id>`), so nothing else
/// (`]`, `/`, line breaks) may get through.
pub fn event_id_ok(event: &str) -> bool {
    !event.is_empty()
        && event.len() <= MAX_EVENT_CHARS
        && event.bytes().all(|b| b.is_ascii_alphanumeric())
        && !event.as_bytes()[0].is_ascii_digit()
}

/// Whether `icon` may go to the server: empty, an icon name, or an absolute
/// path without `..`. A URL or a relative path would make the server fetch
/// or resolve something the sender never meant.
pub fn icon_ok(icon: &str) -> bool {
    if icon.is_empty() {
        return true;
    }
    if icon.starts_with('/') {
        return !icon.chars().any(char::is_control) && !icon.split('/').any(|part| part == "..");
    }
    icon.bytes()
        .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'+' | b'-'))
}

/// Whether a D-Bus error name says nobody owns the notification service.
fn no_service_name(name: &str) -> bool {
    matches!(
        name,
        "org.freedesktop.DBus.Error.ServiceUnknown" | "org.freedesktop.DBus.Error.NameHasNoOwner"
    )
}

/// Logs the raw error and returns the one the user can read: a missing
/// service (or no session bus to find it on) in plain words, anything else
/// unchanged. `connecting`: the error came from opening the session bus.
fn plain(e: zbus::Error, connecting: bool) -> zbus::Error {
    log::warn!("notification: {e}");
    let missing = connecting
        || matches!(&e, zbus::Error::MethodError(name, _, _) if no_service_name(name.as_str()));
    if missing {
        zbus::Error::Failure(NO_SERVICE.into())
    } else {
        e
    }
}

/// A notification the server showed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sent {
    pub id: u32,
    /// The server's unique bus name: only its signals are about `id`.
    pub server: Option<String>,
}

/// Sends an app's notifications under the names its [`AppInfo`] gives.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notifier {
    component: String,
    desktop_entry: String,
    app_name: String,
}

impl Notifier {
    pub fn new(app: &AppInfo) -> Notifier {
        Notifier {
            component: app.short_name(),
            desktop_entry: app.id.clone(),
            app_name: app.name.clone(),
        }
    }

    /// The notifyrc's name (KNotification's component name): the app's
    /// [`AppInfo::short_name`].
    pub fn component(&self) -> &str {
        &self.component
    }

    /// The desktop file's name, which is the app ID.
    pub fn desktop_entry(&self) -> &str {
        &self.desktop_entry
    }

    pub fn app_name(&self) -> &str {
        &self.app_name
    }

    /// The app's own icon: its ID.
    pub fn app_icon(&self) -> &str {
        &self.desktop_entry
    }

    /// Whether `event` pops up. Plasma's notification settings write the
    /// user's choice to `~/.config/<component>.notifyrc` (`[Event/<id>]
    /// Action=`, a `|`-separated list); without one, the shipped file's
    /// `Popup` applies. An event id that is not valid never pops up.
    pub fn popup_enabled(&self, event: &str) -> bool {
        event_id_ok(event)
            && popup_in(
                &config_dir().join(format!("{}.notifyrc", self.component)),
                event,
            )
    }

    /// Sends `n`. `Ok(None)`: the user turned this event's popup off.
    pub async fn send(&self, conn: &zbus::Connection, n: &Note) -> zbus::Result<Option<Sent>> {
        if !event_id_ok(n.event) {
            return Err(zbus::Error::Failure(format!(
                "not a notification event id: {:?}",
                n.event
            )));
        }
        if !self.popup_enabled(n.event) {
            return Ok(None);
        }
        let mut actions: Vec<&str> = Vec::with_capacity(n.actions.len() * 2);
        for (key, label) in &n.actions {
            actions.push(key);
            actions.push(label);
        }
        let mut hints: HashMap<&str, Value<'_>> = HashMap::new();
        hints.insert("desktop-entry", Value::from(self.desktop_entry.as_str()));
        hints.insert("x-kde-appname", Value::from(self.component.as_str()));
        hints.insert("x-kde-eventId", Value::from(n.event));
        if let Some(u) = n.urgency {
            let level: u8 = match u {
                Urgency::Normal | Urgency::High => 1,
                Urgency::Critical => 2,
            };
            hints.insert("urgency", Value::from(level));
        }
        let icon = if n.icon.is_empty() {
            self.app_icon()
        } else if icon_ok(&n.icon) {
            n.icon.as_str()
        } else {
            log::warn!(
                "notification {}: icon {:?} is not a name or an absolute path; using the app icon",
                n.event,
                n.icon
            );
            self.app_icon()
        };
        let timeout: i32 = if n.persistent { 0 } else { -1 };
        let body = (
            self.app_name.as_str(),
            0u32,
            icon,
            n.title.as_str(),
            n.text.as_str(),
            actions,
            hints,
            timeout,
        );
        let call = conn.call_method(Some(SERVICE), PATH, Some(INTERFACE), "Notify", &body);
        let reply = match tokio::time::timeout(CALL_TIMEOUT, call).await {
            Ok(r) => r.map_err(|e| plain(e, false))?,
            Err(_) => return Err(timed_out()),
        };
        let id = reply.body().deserialize::<u32>()?;
        let server = reply.header().sender().map(|s| s.to_string());
        Ok(Some(Sent { id, server }))
    }

    /// [`Notifier::send`] from a worker thread, for a notification nobody
    /// acts on (its actions are not followed). Blocking; gives up after 10
    /// seconds. Not for the UI thread, and refuses inside a Tokio runtime
    /// (use [`Notifier::send`] there).
    pub fn send_blocking(&self, n: &Note) -> Result<(), String> {
        if tokio::runtime::Handle::try_current().is_ok() {
            return Err("send_blocking cannot run inside a Tokio runtime; use send".into());
        }
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| e.to_string())?;
        rt.block_on(async {
            let go = async {
                let conn = zbus::Connection::session()
                    .await
                    .map_err(|e| plain(e, true))?;
                self.send(&conn, n).await
            };
            match tokio::time::timeout(CALL_TIMEOUT, go).await {
                Ok(r) => r.map(|_| ()).map_err(|e| e.to_string()),
                Err(_) => Err(timed_out().to_string()),
            }
        })
    }
}

fn timed_out() -> zbus::Error {
    log::warn!("notification: the server did not answer in {CALL_TIMEOUT:?}");
    zbus::Error::Failure("the notification server did not answer".into())
}

/// Closes notification `id`. Gives up after 10 seconds.
pub async fn close(conn: &zbus::Connection, id: u32) -> zbus::Result<()> {
    let call = conn.call_method(
        Some(SERVICE),
        PATH,
        Some(INTERFACE),
        "CloseNotification",
        &id,
    );
    match tokio::time::timeout(CALL_TIMEOUT, call).await {
        Ok(r) => r.map(|_| ()).map_err(|e| plain(e, false)),
        Err(_) => Err(timed_out()),
    }
}

fn popup_in(path: &Path, event: &str) -> bool {
    // Only a regular file: anything else would block the reader.
    if !path.is_file() {
        return true;
    }
    match Settings::at(path).get(&format!("Event/{event}"), "Action") {
        Some(actions) => actions.split('|').any(|a| a.trim() == "Popup"),
        None => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(id: &str, name: &str) -> AppInfo {
        AppInfo {
            name: name.into(),
            id: id.into(),
            version: "1".into(),
            repo: "r".into(),
        }
    }

    #[test]
    fn escapes_markup() {
        assert_eq!(
            escape("<b>Tom & \"Jerry's\"</b>"),
            "&lt;b&gt;Tom &amp; &quot;Jerry&#39;s&quot;&lt;/b&gt;"
        );
    }

    #[test]
    fn escape_turns_control_characters_into_spaces() {
        assert_eq!(escape("a\x00b\x07c\x1bd\x1fe"), "a b c d e");
        assert_eq!(escape("line\none\ttab"), "line\none\ttab");
    }

    #[test]
    fn icons_are_names_or_absolute_paths() {
        for ok in [
            "",
            "dialog-information",
            "net.eterneon.atlas.updater",
            "a_b+c-1",
            "/usr/share/icons/x.png",
            "/opt/a..b/x.png",
        ] {
            assert!(icon_ok(ok), "{ok:?}");
        }
        for bad in [
            "https://example.com/x.png",
            "file:///etc/passwd",
            "rel/x.png",
            "./x.png",
            "/usr/../etc/x.png",
            "/a/..",
            "/a\nb",
            "a b",
            "é",
        ] {
            assert!(!icon_ok(bad), "{bad:?}");
        }
    }

    #[test]
    fn a_missing_service_is_said_plainly() {
        assert!(no_service_name("org.freedesktop.DBus.Error.ServiceUnknown"));
        assert!(no_service_name("org.freedesktop.DBus.Error.NameHasNoOwner"));
        assert!(!no_service_name("org.freedesktop.DBus.Error.AccessDenied"));
        let e = plain(zbus::Error::Failure("no bus at /x".into()), true);
        assert_eq!(e.to_string(), NO_SERVICE);
        let other = plain(zbus::Error::Failure("boom".into()), false);
        assert_ne!(other.to_string(), NO_SERVICE);
    }

    #[tokio::test]
    async fn send_blocking_refuses_inside_a_runtime() {
        let n = Notifier::new(&app("net.eterneon.atlas.updater", "Atlas Updater"));
        let err = n
            .send_blocking(&Note::new("updateStaged", "T", "B"))
            .unwrap_err();
        assert!(err.contains("Tokio runtime"), "{err}");
    }

    #[test]
    fn popup_follows_the_users_notifyrc() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("atlas-updater.notifyrc");
        // no file, no group, no key: the shipped default (Popup)
        assert!(popup_in(&p, "updateStaged"));
        std::fs::write(
            &p,
            "[Event/updateStaged]\nAction=Sound\n\n[Event/restartSoon]\nAction=Popup|Sound\n\n[Event/crashReport]\nAction=\n",
        )
        .unwrap();
        assert!(!popup_in(&p, "updateStaged"));
        assert!(popup_in(&p, "restartSoon"));
        assert!(!popup_in(&p, "crashReport"));
        assert!(popup_in(&p, "appUpdatesReady"));
    }

    #[test]
    fn a_setting_that_is_not_a_regular_file_means_popup() {
        let d = tempfile::tempdir().unwrap();
        // a directory, and a fifo that would block a reader
        assert!(popup_in(d.path(), "updateStaged"));
        let fifo = d.path().join("fifo.notifyrc");
        let c = std::ffi::CString::new(fifo.to_str().unwrap()).unwrap();
        // SAFETY: mkfifo with a valid NUL-terminated path.
        assert_eq!(unsafe { libc::mkfifo(c.as_ptr(), 0o600) }, 0);
        assert!(popup_in(&fifo, "updateStaged"));
    }

    #[test]
    fn names_come_from_the_app() {
        let n = Notifier::new(&app("net.eterneon.atlas.updater", "Atlas Updater"));
        assert_eq!(n.component(), "atlas-updater");
        assert_eq!(n.desktop_entry(), "net.eterneon.atlas.updater");
        assert_eq!(n.app_icon(), "net.eterneon.atlas.updater");
        assert_eq!(n.app_name(), "Atlas Updater");
        let m = Notifier::new(&app("net.eterneon.atlas.Monitor", "Atlas Monitor"));
        assert_eq!(m.component(), "atlas-monitor");
        assert_ne!(n, m);
    }

    #[test]
    fn event_ids_are_camel_case_alphanumerics() {
        for ok in ["updateStaged", "a", "restartSoon2", "appUpdatesReady"] {
            assert!(event_id_ok(ok), "{ok}");
        }
        let long = "a".repeat(65);
        for bad in [
            "", "1abc", "a b", "a]b", "a/b", "a\nb", "a=b", "a-b", "é", "a[$i]", "../x", &long,
        ] {
            assert!(!event_id_ok(bad), "{bad:?}");
        }
        assert!(event_id_ok(&"a".repeat(64)));
    }

    #[test]
    fn a_bad_event_id_never_reaches_the_settings_file() {
        let n = Notifier::new(&app("net.eterneon.atlas.updater", "Atlas Updater"));
        assert!(!n.popup_enabled("x]\n[Event/y"));
        assert!(!n.popup_enabled(""));
    }

    #[test]
    fn note_defaults() {
        let n = Note::new("updateStaged", "T", "B");
        assert!(n.icon.is_empty() && n.actions.is_empty());
        assert!(n.urgency.is_none() && !n.persistent);
    }
}
