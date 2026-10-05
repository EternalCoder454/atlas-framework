---
title: AtlasDialog
summary: The general modal dialog: a title row, a scrolling body and a row of buttons, over a dimmed window.
section: Menus, dialogs and popups
since: "1.4.0"
---

AtlasDialog has a title row, a scrolling body and a row of buttons. For a yes or no question use `ConfirmDialog`. The window behind is dimmed, Escape closes the dialog, and the focus starts on the first thing in the body that can take it; when the body has nothing focusable it stays on the dialog itself, never on a header or footer button, so pressing Return right after opening does not close it. A body taller than the window scrolls instead of outgrowing it, and the dialog is never wider than the window.

The header has an optional Back button at the leading edge (`showBack`, then `backRequested()`; the dialog does not close itself), the `title`, `headerTrailing` items, and a Close button at the trailing edge (`showClose`, on by default; it rejects the dialog). `footerContent` holds the buttons, right-aligned, in KDE order: the main action last.

AtlasDialog is a Qt Quick Templates `Dialog`; its inherited properties (`title`, `open()`, `close()`, `accepted`, `rejected`) work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-dialog.html>.

## Example

```qml
AtlasDialog {
    title: qsTr("Add account")
    footerContent: [
        SecondaryButton { text: qsTr("Cancel"); onClicked: close() },
        PrimaryButton { text: qsTr("Add"); onClicked: { add(); close() } }
    ]
    AtlasTextField { Layout.fillWidth: true; placeholderText: qsTr("Name") }
}
```

## Keyboard

Escape closes the dialog, and so does a press outside it.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `content` | `list<QtObject>` (default, read-only) | — | Items declared inside the dialog: the body. |
| `footerContent` | `list<QtObject>` (read-only) | — | The buttons, in KDE order (cancel first, the main action last). |
| `headerTrailing` | `list<QtObject>` (read-only) | — | Items in the header, before the Close button. |
| `preferredWidth` | `real` | 30 grid units | The width of the dialog, capped to the parent's width less 2 grid units; the body is narrower by the padding. |
| `showBack` | `bool` | `false` | Shows a Back button at the leading edge of the header. |
| `showClose` | `bool` | `true` | Shows a Close button at the trailing edge; it rejects the dialog. |

## Signals

| Name | Description |
|---|---|
| `backRequested()` | The Back button was used. The dialog does not close itself. |
