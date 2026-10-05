---
title: AtlasGlobalShortcut
summary: A system-wide keyboard shortcut through the desktop portal, working while the app has no focus.
section: Services
since: "1.5.0"
---

AtlasGlobalShortcut asks the desktop (the xdg-desktop-portal GlobalShortcuts interface) for a shortcut that works in every window. The user can change the key in System Settings. It has no visuals.

One portal session is made for the app, when the first shortcut is ready. Every shortcut declared in the same turn of the event loop goes into one `BindShortcuts` call (KDE activates a shortcut only then); one declared later is bound with another call on the same session. Every D-Bus call is asynchronous and has a timeout, so nothing blocks the interface. Without a session bus or portal the type stays unavailable, and `errorString` says why in plain words.

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
> `name` is the id the portal and the user's settings know the shortcut by, so keep it stable. It is letters, digits, `.`, `_` and `-`, at most 64 characters, and unique in the app; anything else leaves the shortcut unavailable, with a warning. Everything the portal sends back is checked: only the names this app declared are accepted, and every value must have the type the portal's specification gives.

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
