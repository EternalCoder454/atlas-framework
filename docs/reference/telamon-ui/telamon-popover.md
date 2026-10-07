---
title: TelamonPopover
summary: A raised card that opens next to a control, with a soft shadow, a border and an optional arrow pointing at its target.
section: Menus, dialogs and popups
since: "1.4.0"
---

A raised card that opens next to a control: surface colour, rounded corners, a soft shadow and a hairline border, with an optional arrow that points at `target`. It opens below the target, or above when there is no room below, lines up with the target's leading edge (trailing in a right-to-left layout) and is kept inside the window. Escape and a click outside close it, and the focus goes back to the target. While it is open it is placed again when the window is resized or when the target, or anything the target sits in, moves. With no `target` it opens in the middle of the window, with no arrow. Put anything in it.

`side` picks where it opens. If the chosen side has no room it flips to the opposite side; if neither fits it takes the side with more room and is clamped into the window. `placedSide` reports the side in use. `Start` and `End` are logical: `End` is the right of the target in a left-to-right layout and the left in a right-to-left one. A popover on `Start` or `End` is centred on the target vertically, and its arrow sits on the edge that faces the target.

TelamonPopover is a Qt Quick Controls [`Popup`](https://doc.qt.io/qt-6/qml-qtquick-templates-popup.html); `open()`, `close()` and the rest work as usual. It is not modal.

## Example

```qml
TelamonButton { id: more; text: qsTr("More"); onClicked: info.open() }
TelamonPopover {
    id: info
    target: more
    TelamonLabel { text: qsTr("Details go here.") }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `above` | `bool` (read-only) | — | `true` when the popover sits above the target. |
| `content` | `list<QtObject>` (read-only) | — | The default property: items declared inside become the popover's content. |
| `placedSide` | `int` (read-only) | — | The side in use after fitting: `TelamonPopover.Below`, `Above`, `Start` or `End`. |
| `showArrow` | `bool` | `true` | Draws an arrow that points at `target`. |
| `side` | `int` (`TelamonPopover.Side`) | `TelamonPopover.Auto` | Where the popover opens. `Auto` is below the target, else above. |
| `target` | `Item` | `null` | The item the popover belongs to and points at. Set it before opening. |

## Enums

### Side

| Value | Description |
|---|---|
| `TelamonPopover.Auto` | Below the target, else above. |
| `TelamonPopover.Below` | Below the target. |
| `TelamonPopover.Above` | Above the target. |
| `TelamonPopover.Start` | At the leading side of the target (the left in a left-to-right layout). |
| `TelamonPopover.End` | At the trailing side of the target (the right in a left-to-right layout). |
