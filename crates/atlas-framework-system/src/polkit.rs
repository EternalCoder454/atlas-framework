//! The polkit check behind every admin action of an Atlas root helper (a
//! D-Bus service on the system bus, started on demand):
//!
//! ```ignore
//! #[zbus::interface(name = "net.eterneon.atlas.Example1")]
//! impl Helper {
//!     async fn do_thing(
//!         &self,
//!         #[zbus(header)] header: zbus::message::Header<'_>,
//!         #[zbus(connection)] conn: &zbus::Connection,
//!     ) -> zbus::fdo::Result<()> {
//!         polkit::check(conn, &header, "net.eterneon.atlas.example.do-thing", true)
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
/// clear yes is an error.
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
    let call = authority.check_authorization(
        &subject,
        action,
        &details,
        if interactive {
            ALLOW_USER_INTERACTION
        } else {
            0
        },
        "",
    );
    // A password prompt waits for the person; anything else that takes this
    // long is a stuck polkitd, and the answer is no.
    let reply = if interactive {
        call.await
    } else {
        tokio::time::timeout(NON_INTERACTIVE_TIMEOUT, call)
            .await
            .map_err(|_| Denied::Unavailable("polkit did not answer".into()))?
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
    fn denials_read_well() {
        let d = Denied::NotAuthorized {
            action: "net.eterneon.atlas.x".into(),
        };
        assert_eq!(d.to_string(), "not authorized for net.eterneon.atlas.x");
    }

    #[tokio::test]
    async fn no_polkit_is_a_refusal() {
        // A bus with no polkit on it: the check must fail closed. Only on a
        // private bus (`ATLAS_TEST_PRIVATE_BUS=1` under dbus-run-session),
        // never the user's session bus.
        if std::env::var_os("ATLAS_TEST_PRIVATE_BUS").is_none() {
            return;
        }
        let Ok(builder) = zbus::connection::Builder::session() else {
            return;
        };
        let Ok(conn) = builder.build().await else {
            return; // no session bus here
        };
        let r = check_bus_name(&conn, ":1.1", "net.eterneon.atlas.x", false).await;
        assert!(matches!(r, Err(Denied::Unavailable(_))), "{r:?}");
    }
}
