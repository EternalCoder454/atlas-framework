---
title: AtlasPopover
summary: A raised card that opens next to a control, with a soft shadow, a border and an optional arrow pointing at its target.
section: Menus, dialogs and popups
since: "1.4.0"
---

A raised card that opens next to a control: surface colour, rounded corners, a soft shadow and a hairline border, with an optional arrow that points at `target`. It opens below the target, or above when there is no room below, lines up with the target's leading edge (trailing in a right-to-left layout) and is kept inside the window. Escape and a click outside close it, and the focus goes back to the target. Put anything in it.

AtlasPopover is a Qt Quick Controls [`Popup`](https://doc.qt.io/qt-6/qml-qtquick-templates-popup.html); `open()`, `close()` and the rest work as usual. It is not modal.

## Example

```qml
AtlasButton { id: more; text: qsTr("More"); onClicked: info.open() }
AtlasPopover {
    id: info
    target: more
    AtlasLabel { text: qsTr("Details go here.") }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `above` | `bool` (read-only) | — | `true` when the popover sits above the target. |
| `content` | `list<QtObject>` (read-only) | — | The default property: items declared inside become the popover's content. |
| `showArrow` | `bool` | `true` | Draws an arrow that points at `target`. |
| `target` | `Item` | `null` | The item the popover belongs to and points at. Set it before opening. |
