//! The polkit check behind every admin action of a Telamon root helper (a
//! D-Bus service on the system bus, started on demand):
//!
//! ```ignore
//! #[zbus::interface(name = "net.eterneon.telamon.Example1")]
//! impl Helper {
//!     async fn do_thing(
//!         &self,
//!         #[zbus(header)] header: zbus::message::Header<'_>,
//!         #[zbus(connection)] conn: &zbus::Connection,
//!     ) -> zbus::fdo::Result<()> {
//!         polkit::check(conn, &header, "net.eterneon.telamon.example.do-thing", true)
//!             .await
//!             .map_err(|e| zbus::fdo::Error::AccessDenied(e.to_string()))?;
//!         // ... validate the arguments, then act
//!     }
//! }
//! ```
//!
//! The subject is the caller's unique bus name (`system-bus-name`): polkit
//! asks the bus who is behind it, so a caller can't pass for another process,
//! as it can with a PID (a PID can be reused by the time polkit looks).

use std::collections::HashMap;
use std::fmt;

use zbus::message::Header;
use zbus::zvariant::Value;

/// Let polkit ask the user for a password when the action needs one.
const ALLOW_USER_INTERACTION: u32 = 1;

#[zbus::proxy(
    interface = "org.freedesktop.PolicyKit1.Authority",
    default_service = "org.freedesktop.PolicyKit1",
    default_path = "/org/freedesktop/PolicyKit1/Authority",
    gen_blocking = false
)]
trait Authority {
    #[allow(clippy::type_complexity)]
    fn check_authorization(
        &self,
        subject: &(&str, HashMap<&str, Value<'_>>),
        action_id: &str,
        details: &HashMap<&str, &str>,
        flags: u32,
        cancellation_id: &str,
    ) -> zbus::Result<(bool, bool, HashMap<String, String>)>;

    fn cancel_check(&self, cancellation_id: &str) -> zbus::Result<()>;
}

/// Why an action was refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Denied {
    /// The message has no sender (only possible on a peer-to-peer link).
    NoSender,
    /// polkit couldn't be asked; the action is refused, never allowed.
    Unavailable(String),
    /// polkit said no, or the user cancelled the password prompt.
    NotAuthorized { action: String },
}

impl fmt::Display for Denied {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Denied::NoSender => f.write_str("call has no sender"),
            Denied::Unavailable(e) => write!(f, "cannot ask polkit: {e}"),
            Denied::NotAuthorized { action } => write!(f, "not authorized for {action}"),
        }
    }
}

impl std::error::Error for Denied {}

/// Asks polkit whether the sender of the call in `header` may perform
/// `action`. `interactive` lets polkit prompt for a password. Anything but a
/// clear yes is an error. Needs a Tokio runtime with timers, see
/// [`check_bus_name`].
pub async fn check(
    conn: &zbus::Connection,
    header: &Header<'_>,
    action: &str,
    interactive: bool,
) -> Result<(), Denied> {
    let sender = header.sender().ok_or(Denied::NoSender)?.to_string();
    check_bus_name(conn, &sender, action, interactive).await
}

/// [`check`] for a caller known by its unique bus name (`:1.42`).
///
/// Runs on Tokio, with timers enabled (`#[tokio::main]` and
/// `Builder::enable_all` do that). A non-interactive check gives up after
/// 25 seconds, an interactive one (a password prompt) after 120 seconds.
/// Every check carries its own cancellation id; when it gives up, when the
/// caller's bus name disappears from the bus (checked every 2 seconds), or
/// when the future is dropped, polkit is told with `CancelCheck`, so its
/// password prompt closes. A give-up is `Denied::Unavailable`.
pub async fn check_bus_name(
    conn: &zbus::Connection,
    sender: &str,
    action: &str,
    interactive: bool,
) -> Result<(), Denied> {
    let authority = AuthorityProxy::new(conn)
        .await
        .map_err(|e| Denied::Unavailable(e.to_string()))?;
    let subject = subject(sender);
    let details = HashMap::new();
    let id = cancellation_id();
    let mut guard = CancelGuard {
        conn: conn.clone(),
        id: id.clone(),
        armed: true,
    };
    let call = authority.check_authorization(
        &subject,
        action,
        &details,
        if interactive {
            ALLOW_USER_INTERACTION
        } else {
            0
        },
        &id,
    );
    let limit = if interactive {
        INTERACTIVE_TIMEOUT
    } else {
        NON_INTERACTIVE_TIMEOUT
    };
    // Anything that takes this long is a stuck polkitd or an abandoned
    // prompt, and the answer is no.
    let reply = tokio::select! {
        r = tokio::time::timeout(limit, call) => match r {
            Ok(reply) => {
                guard.armed = false; // polkit has answered: nothing to cancel
                reply
            }
            Err(_) => return Err(Denied::Unavailable("polkit did not answer".into())),
        },
        () = caller_gone(conn, sender) => {
            return Err(Denied::Unavailable("the caller went away".into()));
        }
    };
    let (authorized, _challenge, _details) =
        reply.map_err(|e| Denied::Unavailable(e.to_string()))?;
    if authorized {
        Ok(())
    } else {
        Err(Denied::NotAuthorized {
            action: action.to_string(),
        })
    }
}

const NON_INTERACTIVE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(25);
const INTERACTIVE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(120);
const OWNER_POLL: std::time::Duration = std::time::Duration::from_secs(2);

/// A cancellation id no other check of this process (or another helper on the
/// bus: the pid is in it) uses.
fn cancellation_id() -> String {
    static COUNT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    format!(
        "telamon-{}-{}",
        std::process::id(),
        COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    )
}

/// Tells polkit to drop a check that was not answered (gave up, caller gone,
/// future dropped). The call runs on a spawned task, errors are only logged.
struct CancelGuard {
    conn: zbus::Connection,
    id: String,
    armed: bool,
}

impl Drop for CancelGuard {
    fn drop(&mut self) {
        if !self.armed {
            return;
        }
        let Ok(rt) = tokio::runtime::Handle::try_current() else {
            return;
        };
        let (conn, id) = (self.conn.clone(), std::mem::take(&mut self.id));
        rt.spawn(async move {
            let r = async { AuthorityProxy::new(&conn).await?.cancel_check(&id).await };
            if let Ok(Err(e)) | Err(e) = tokio::time::timeout(NON_INTERACTIVE_TIMEOUT, r)
                .await
                .map_err(|_| zbus::Error::Failure("timed out".into()))
            {
                log::warn!("polkit CancelCheck {id}: {e}");
            }
        });
    }
}

/// Resolves when `name` no longer has an owner on the bus. A failed
/// `NameHasOwner` call is not taken for "gone".
async fn caller_gone(conn: &zbus::Connection, name: &str) {
    let Ok(bus) = zbus::fdo::DBusProxy::new(conn).await else {
        return std::future::pending().await;
    };
    let Ok(name) = zbus::names::BusName::try_from(name) else {
        return std::future::pending().await;
    };
    loop {
        tokio::time::sleep(OWNER_POLL).await;
        if let Ok(false) = bus.name_has_owner(name.clone()).await {
            return;
        }
    }
}

fn subject(sender: &str) -> (&'static str, HashMap<&'static str, Value<'_>>) {
    (
        "system-bus-name",
        HashMap::from([("name", Value::from(sender))]),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subject_is_the_bus_name() {
        let (kind, details) = subject(":1.42");
        assert_eq!(kind, "system-bus-name");
        assert_eq!(details.len(), 1);
        assert_eq!(details["name"], Value::from(":1.42"));
    }

    #[test]
    fn cancellation_ids_are_unique() {
        let (a, b) = (cancellation_id(), cancellation_id());
        assert_ne!(a, b);
        assert!(a.starts_with(&format!("telamon-{}-", std::process::id())));
    }

    #[test]
    fn interactive_checks_are_bounded() {
        assert!(INTERACTIVE_TIMEOUT > NON_INTERACTIVE_TIMEOUT);
        assert!(INTERACTIVE_TIMEOUT.as_secs() <= 120);
    }

    #[test]
    fn denials_read_well() {
        let d = Denied::NotAuthorized {
            action: "net.eterneon.telamon.x".into(),
        };
        assert_eq!(d.to_string(), "not authorized for net.eterneon.telamon.x");
    }

    #[tokio::test]
    async fn no_polkit_is_a_refusal() {
        // A bus with no polkit on it: the check must fail closed. Only on a
        // private bus (`TELAMON_TEST_PRIVATE_BUS=1` under dbus-run-session),
        // never the user's session bus.
        if std::env::var_os("TELAMON_TEST_PRIVATE_BUS").is_none() {
            return;
        }
        let Ok(builder) = zbus::connection::Builder::session() else {
            return;
        };
        let Ok(conn) = builder.build().await else {
            return; // no session bus here
        };
        let r = check_bus_name(&conn, ":1.1", "net.eterneon.telamon.x", false).await;
        assert!(matches!(r, Err(Denied::Unavailable(_))), "{r:?}");
    }
}
