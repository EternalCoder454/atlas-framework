---
title: AtlasGlobalShortcut
summary: A system-wide keyboard shortcut through the desktop portal, working while the app has no focus.
section: Services
since: "1.5.0"
---

AtlasGlobalShortcut asks the desktop (the xdg-desktop-portal GlobalShortcuts interface) for a shortcut that works in every window. The user can change the key in System Settings. It has no visuals.

One portal session is made for the app, when the first shortcut is ready. Every shortcut declared in the same turn of the event loop goes into one `BindShortcuts` call (KDE activates a shortcut only then); one declared later is bound with another call on the same session. Every D-Bus call is asynchronous and has a timeout, so nothing blocks the interface. Without a session bus or portal the type is unavailable, and `errorString` says why in plain words. It is not final: when the portal appears or restarts the shortcuts are bound again, and after a failed attempt (a timeout, a refusal, an unreadable answer) the session tries again by itself, after 2, 4, 8, 16 and 32 seconds, starting over after a success or when a shortcut is added or changed. A session the portal closes is made again at once.

## Example

```qml
import Atlas.Ui

AtlasGlobalShortcut {
    name: "show-window"
    description: qsTr("Show the window")
    preferredTrigger: "Meta+Shift+M"
    onActivated: window.raise()
}
```

> [!NOTE]
> `name` is the id the portal and the user's settings know the shortcut by, so keep it stable. It is letters, digits, `.`, `_` and `-`, at most 64 characters, and unique in the app; anything else leaves the shortcut unavailable, with a warning. A shortcut refused for a name already in use is tried again when that name is free. Everything the portal sends back is checked: only the names this app declared are accepted, and every value must have the type the portal's specification gives.

> [!NOTE]
> The portal has no way to unbind. Removing or renaming a shortcut stops this app from using it, but the desktop keeps the old entry in System Settings until the app's session ends.

> [!WARNING]
> `trigger` and `errorString` come from outside the app (the portal). Show them with `textFormat: Text.PlainText`, never as rich text. `activated()` carries no proof that a person pressed the key: a program that can talk to the portal may be the one that caused it, so an action that deletes or sends something should ask for confirmation first.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | `""` | A stable id, unique in the app. Changing it after creation registers the shortcut again. |
| `description` | `string` | `""` | Shown in System Settings. When empty, `name` is sent. |
| `preferredTrigger` | `string` | `""` | The key the app would like, in portable form such as `"Meta+Shift+M"`. The user may change it in System Settings, and the desktop may refuse it. |
| `trigger` | `string` (read-only) | `""` | What the portal reports as bound, as text for the user. Empty until bound. |
| `available` | `bool` (read-only) | `false` | The portal and session work and accepted this shortcut. `false` until the first bind has finished. |
| `errorString` | `string` (read-only) | `""` | Why not, in plain words: no session bus, no portal, no support, a refusal, a timeout. Empty when `available`, and before the first attempt. |

## Signals

| Name | Description |
|---|---|
| `activated()` | The user pressed the shortcut. |
| `deactivated()` | The user released it. |
