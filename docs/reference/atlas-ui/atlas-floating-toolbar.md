---
title: AtlasFloatingToolbar
summary: A capsule of icon buttons that floats over content, such as formatting tools over an editor.
section: Navigation
since: "1.4.0"
---

AtlasFloatingToolbar is a rounded surface with a soft shadow. It is an [AtlasToolbar](atlas-toolbar.md) inside, so it has the same `actions` ([AtlasAction](atlas-action.md) or Qt `Action`, with dividers between sections) and its "more" menu when the parent is too narrow. Items put inside it (a drop-down, a colour swatch) follow the buttons.

`shown` fades it in and out with a short slide. While hidden, it takes no input and is not visible. It stays inside its parent: it is drawn at least `margin` from the edges whatever `x` and `y` say (they are not changed), and it is never wider than the parent less the margins.

`orientation: Qt.Vertical` makes a tall capsule (the pill radius is half of the shorter side), and the slide that comes with `shown` then goes sideways, away from the edge nearest it. `overflow` and `focusOnClick` go to the inner [AtlasToolbar](atlas-toolbar.md).

With `autoDim` the capsule is `dimOpacity` until the pointer is within `nearDistance` of its rectangle, even outside it. It is at full strength while a button has the focus, while any menu or popover opened from its buttons is open (see [AtlasAction](atlas-action.md) `menu` and `popover`), while `keepActive` is true (for an app popover the toolbar cannot see), and while a press is down. It is always at full strength under high contrast and with `autoDim` off. The change fades with `AtlasStyle.duration`, which is instant under reduced motion. The pointer is read with one `HoverHandler` on the parent and no timer, so nothing runs while it is still; a hidden capsule tracks nothing.

With `focusable`, Tab enters the strip and moves through the buttons. Escape on a button emits `escaped()` and moves the focus to `returnFocus`; with none, to the item that had the focus before Tab came in, if it is still there. With `focusOnClick: false` a click on a button never takes the focus from the editor.

The room an editor keeps free at the capsule's edge is not a property: read `width + margin * 2`.

## Example

```qml
AtlasFloatingToolbar {
    actions: [boldAction, italicAction, linkAction]
    shown: editor.hasSelection
    x: Math.round((parent.width - width) / 2)
    y: parent.height - height - 16
}
```

> [!NOTE]
> Its buttons never take the keyboard focus by default (`focusable: false`), so the editor keeps typing. Set `focusable: true` to let Tab reach them.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accessibleName` | `string` | `qsTr("Tools")` | The name for screen readers. |
| `actions` | `list<Action>` (read-only) | `[]` | The actions shown as buttons. |
| `content` | `list<QtObject>` (default, read-only) | — | Extra items after the buttons. |
| `autoDim` | `bool` | `false` | Keeps the capsule quiet, at `dimOpacity`, until the pointer is near. |
| `dimOpacity` | `real` | `0.35` | The opacity while quiet. |
| `focusOnClick` | `bool` | `true` | With `focusable`, `false` makes a click on a button not take the focus. |
| `keepActive` | `bool` | `false` | Holds full strength, for an app popover the toolbar cannot see. |
| `near` | `bool` (read-only) | — | `true` at full strength. |
| `nearDistance` | `real` | `80` | How close the pointer must be, in px, to bring the capsule to full strength. |
| `orientation` | `int` (`Qt.Horizontal` or `Qt.Vertical`) | `Qt.Horizontal` | Vertical makes a tall capsule. |
| `overflow` | `int` (`AtlasToolbar.Overflow`) | `AtlasToolbar.Menu` | What happens to buttons that do not fit. See [AtlasToolbar](atlas-toolbar.md). |
| `returnFocus` | `Item` | `null` | Where Escape sends the focus. |
| `focusable` | `bool` | `false` | Lets Tab reach the buttons. `false` keeps the focus in the editor. |
| `margin` | `real` | `AtlasStyle.spacingLarge` | Room kept free between the capsule and the parent's edges. |
| `shown` | `bool` | `true` | `true` shows the capsule; `false` fades it away. |
| `toolbar` | [AtlasToolbar](atlas-toolbar.md) (read-only) | the inner toolbar | The inner toolbar, for example for its "more" menu. |

## Signals

| Signature | Description |
|---|---|
| `escaped()` | Escape was pressed on a button. |
