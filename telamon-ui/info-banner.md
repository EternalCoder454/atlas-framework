---
title: InfoBanner
summary: An inline banner above the content for notices such as "File changed on disk" or "Could not save".
section: Feedback and status
---

InfoBanner is an inline banner that slides open above the content. `type` tints it: `"info"` with the accent, `"warning"` with the theme's neutral colour and `"error"` with `TelamonStyle.error`. The icon is a Material Symbol in that tint (the accent for `"info"`), not a theme icon, so it follows the palette on any icon theme. Each entry of `actions` becomes a button at the trailing end, and `closable` adds a small cross that dismisses it; the banner then stays closed until it gets a new `text` or `type`, or `shown` is written true again. For a message that goes by itself use [Toast](toast.md).

A dismissed banner comes back when it gets a new `text` or `type`. This applies to every closable banner, also in an app that never touches `shown`. A closable banner whose text changes often (a live count or a progress) therefore comes back after each change: make such a banner non-closable, or keep its text stable.

InfoBanner is an `Item`. Screen readers announce it when it appears or its text changes.

## Example

```qml
InfoBanner {
    type: "warning"
    text: qsTr("The file changed on disk.")
    closable: true
    actions: [ QQC2.Action { text: qsTr("Reload"); onTriggered: reload() } ]
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `actions` | `list<Item>` (read-only) | — | Qt Quick Controls `Action`s (declare them as children of the list); each becomes a button at the trailing end. |
| `animated` | `bool` | `true` | `false` opens and shuts the banner at once, with no slide. For a banner shown in the same turn as a large document, so the content under it does not move (and re-render) on each frame of the slide. Since 1.5.0. |
| `closable` | `bool` | `false` | Shows a cross that dismisses the banner. |
| `closeName` | `string` | `qsTr("Close")` | The accessible name and tooltip of the close button. |
| `dismissed` | `bool` (read-only) | `false` | The user closed the banner. It stays true until a new `text` or `type`, or `shown` written true. |
| `iconName` | `string` (read-only) | — | The theme icon name for the `type`. Not drawn since 2.0.6 (the banner draws a Symbol); kept for apps that read it. |
| `shown` | `bool` | `true` | Slides the banner open or shut (at once when animations are off). The banner never writes it, so `shown: condition` stays bound; while it is dismissed it holds `shown` false. A new `text` or `type`, or `shown` written true, shows it again. A binding that goes false and true again while dismissed does not, until one of those. |
| `text` | `string` | `""` | The message. |
| `tint` | `color` (read-only) | — | The colour for the `type`. |
| `type` | `string` | `"info"` | `"info"`, `"warning"` or `"error"`. |

## Signals

| Name | Description |
|---|---|
| `closed()` | Emitted when the user dismisses the banner. `shown` is not written. |

> [!NOTE]
> Use `shown`, not `visible`: `visible` cannot be animated.
