---
title: ConfirmDialog
summary: A modal dialog in the Atlas look with small rounded buttons, an optional third button and a destructive style.
section: Menus, dialogs and popups
---

ConfirmDialog asks the user to confirm or cancel something. It is a card with 8 px corners over a dimmed window with two buttons by default (`rejectText`, `acceptText`). A non-empty `alternativeText` ("Don't Save") adds a third button at the leading edge. For a dialog with its own content and buttons use [AtlasDialog](atlas-dialog.md).

ConfirmDialog is a Qt Quick Controls `Popup` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-popup.html)); its inherited properties work as usual. Items declared inside it go into `body` and are as wide as the card; the text and the body wrap, and scroll when they are taller than the window.

## Example

```qml
ConfirmDialog {
    title: qsTr("Save changes?")
    acceptText: qsTr("Save")
    alternativeText: qsTr("Don't Save")
    onAccepted: save()
    onAlternative: discard()
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `acceptText` | `string` | `qsTr("OK")` | The text of the confirming button. |
| `alternativeText` | `string` | `""` | The text of a third button before Cancel; empty for none. |
| `body` | `list<Item>` (read-only) | — | The default property: items shown under `text`. |
| `closeOnAccept` | `bool` | `true` | Closes the dialog after `accepted()` or `alternative()`. |
| `defaultButton` | `string` | `"accept"` | `"accept"`, `"reject"` or `"alternative"`: the button that is drawn filled, starts with the focus and that Return and Enter activate from anywhere in the dialog. A name that names no shown button falls back to accept. |
| `destructive` | `bool` | `false` | Gives the accept button the `Destructive` look of [AtlasButton](atlas-button.md) (error text and border on a faint error fill) in place of the filled one, for deleting or resetting. |
| `focusReject` | `bool` | `false` | Starts the focus on Cancel. Use it for destructive dialogs; informational ones start on the main button. |
| `rejectText` | `string` | `qsTr("Cancel")` | The text of the cancelling button. |
| `showReject` | `bool` | `true` | Shows the cancelling button. |
| `text` | `string` | `""` | The message under the title. |
| `title` | `string` | `""` | The heading of the dialog. |

## Signals

| Name | Description |
|---|---|
| `accepted()` | Emitted when the accept button or Return on it is activated. |
| `alternative()` | Emitted when the alternative (third) button is activated. |

## Keyboard

Escape or a click outside closes the dialog. Return and Enter activate the `defaultButton` from anywhere in the dialog.

> [!NOTE]
> Return pressed in a field of the body does not run a destructive accept, nor anything on a dialog that starts on Cancel; the buttons still take Return themselves.
