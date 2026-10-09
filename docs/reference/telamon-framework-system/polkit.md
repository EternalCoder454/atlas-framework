---
title: polkit
summary: The polkit authorization check behind every admin action of a Telamon root D-Bus helper, failing closed, available with the polkit feature.
order: 50
---

The `polkit` module is the check behind every admin action of a Telamon root helper: a D-Bus service on the system bus, started on demand. Call it at the top of each method that does something only an administrator should. It needs the `polkit` feature of telamon-framework-system.

The subject is the caller's unique bus name (`system-bus-name`): polkit asks the bus who is behind it, so a caller cannot pass for another process, as it can with a PID (a PID can be reused by the time polkit looks). Anything but a clear yes is an error, so the check fails closed. The caller's name must be a unique bus name (a well-known name can change owners between the check and the act) and the action must look like an action id; otherwise the check is `Denied::Unavailable` and polkit is not asked. Setting up the connection to polkit is inside the same time limit as the call.

It runs on Tokio with timers enabled (`#[tokio::main]` and `Builder::enable_all` do that). A non-interactive check gives up after 25 seconds; an interactive one (the password prompt) after 120 seconds. Every check carries its own cancellation id, and polkit gets `CancelCheck` when the check gives up, when the caller's bus name disappears from the bus (looked at every 2 seconds), or when the future is dropped, so a stale prompt closes. A give-up is `Denied::Unavailable`.

## Example

```rust
use telamon_framework_system::polkit;

struct Helper;

#[zbus::interface(name = "net.eterneon.telamon.Example1")]
impl Helper {
    async fn do_thing(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(connection)] conn: &zbus::Connection,
    ) -> zbus::fdo::Result<()> {
        polkit::check(conn, &header, "net.eterneon.telamon.example.do-thing", true)
            .await
            .map_err(|e| zbus::fdo::Error::AccessDenied(e.to_string()))?;
        // ... validate the arguments, then act
        Ok(())
    }
}
```

The action ID must be declared in a polkit policy file the helper's package ships.

## Items

| Name | Signature | Description |
|---|---|---|
| `check` | `pub async fn check(conn: &zbus::Connection, header: &Header<'_>, action: &str, interactive: bool) -> Result<(), Denied>` | Asks polkit whether the sender of the call in `header` may perform `action`. `interactive` lets polkit prompt for a password |
| `check_bus_name` | `pub async fn check_bus_name(conn: &zbus::Connection, sender: &str, action: &str, interactive: bool) -> Result<(), Denied>` | `check` for a caller known by its unique bus name (`:1.42`) |
| `action_id_ok` | `pub fn action_id_ok(action: &str) -> bool` | 1 to 255 ASCII letters, digits and `.`, `-`, `_`, starting with a letter. What `check` requires before it asks polkit, so an action built from a caller's argument never reaches the bus unchecked |
| `unique_name_ok` | `pub fn unique_name_ok(name: &str) -> bool` | Whether `name` is a unique bus name (`:1.42`), the only kind `check_bus_name` accepts as the subject |
| `Denied` | `pub enum Denied` | Why an action was refused. Implements `Display`, `Debug`, `Clone`, `PartialEq`, `Eq` and `std::error::Error` |

## Denied

| Variant | Meaning |
|---|---|
| `NoSender` | The message has no sender (only possible on a peer-to-peer link) |
| `Unavailable(String)` | polkit could not be asked (or did not answer in time, or the caller's name or the action id is not valid); the action is refused, never allowed |
| `NotAuthorized { action: String }` | polkit said no, or the user cancelled the password prompt |
