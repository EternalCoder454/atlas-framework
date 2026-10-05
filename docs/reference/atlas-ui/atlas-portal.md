---
title: AtlasPortal
summary: A singleton for what an app asks the desktop to do: open a link with the default app and show a desktop notification.
section: Services
since: "1.4.0"
---

`AtlasPortal` is a singleton. `openUrl()` opens a link with the user's default app (through the OpenURI portal under Flatpak), after checking the URL. `notify()` shows a desktop notification over `org.freedesktop.Notifications`. Use these instead of `Qt.openUrlExternally()` or a hand-built notification.

## Example

```qml
AtlasButton { text: qsTr("Help"); onClicked: AtlasPortal.openUrl("https://example.com/help") }

Component.onCompleted: {
    const id = AtlasPortal.notify(qsTr("Update ready"), qsTr("Restart to finish."),
        [{ id: "default", text: qsTr("Open") }, { id: "restart", text: qsTr("Restart") }],
        { eventId: "updateStaged" });
}
Connections {
    target: AtlasPortal
    function onActionInvoked(notificationId, actionId) { /* ... */ }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `extraSchemes` | `list<string>` | `[]` | URL schemes `openUrl()` accepts besides http, https, mailto and file. The file and host rules still apply to those four. |

## Signals

| Name | Description |
|---|---|
| `actionInvoked(string notificationId, string actionId)` | The user picked an action of a notification this app sent. `notificationId` is the id `notify()` returned; `"default"` is a click on the notification itself. |

## Methods

| Signature | Description |
|---|---|
| `escape(string text): string` | Returns `text` safe for a notification body with `options.markup: true`: markup characters are escaped and control characters become spaces. |
| `notify(string title, string body): string` | Shows a notification with no actions. |
| `notify(string title, string body, list actions): string` | Shows a notification with actions: a list of `{ id, text }`. |
| `notify(string title, string body, list actions, object options): string` | Shows a notification with actions and options (see below). |
| `openUrl(url url): bool` | Opens the link with the default app. Returns `false`, with a warning in the log, for any URL that is refused. |

`notify()` returns the notification's id at once, or `""` when nothing was sent (the user turned the event's popup off, or the arguments are bad).

## What `openUrl()` opens

- `http` and `https`, with a host.
- `mailto`, with an address. Only `subject` and `body` are kept; any other query key, such as `attach` or `bcc`, is dropped and logged.
- `file`, for a local path that exists. The real path behind symbolic links is checked, and a program, a launcher or any executable file is refused, by content and not by name. Directories are fine.
- Any scheme listed in `extraSchemes`.

## Notification arguments

- `body` is plain text; the portal escapes it.
- `actions` is a list of `{ id, text }`. At most 8, with ids of letters, digits and `.`, `_` or `-`. The id `"default"` is a click on the notification itself.

The `options` object takes:

| Key | Meaning |
|---|---|
| `markup` | `true` says the body is markup that the caller has escaped (use `escape()` on everything that came from outside); the server shows it as markup. |
| `eventId` | The notifyrc event name: camelCase letters and digits. Default `"notification"`. The user's choice in System Settings is honoured. |
| `urgency` | `"low"` or `"normal"` (the default). Anything else is normal. There are no sounds. |
| `persistent` | Stays until the user acts. Use only when ignoring the notification has consequences. |
| `icon` | An icon name or an absolute path. Anything else shows the app's own icon. |

> [!NOTE]
> An app that uses `eventId` ships a `<short name>.notifyrc`. The component name (`x-kde-appname`) and the desktop entry are derived from the app ID, the same as in the Rust crate's `notify`.
