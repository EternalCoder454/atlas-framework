---
title: Toast
summary: A short message that appears at the bottom centre of its parent and goes by itself.
section: Feedback and status
---

Toast shows a short message such as "Copied" or "Saved": call `show("text")`. For "Deleted" with an "Undo", call `showAction("Deleted", "Undo")` and handle `actionTriggered()`; the button is reached with Tab, and clicking it hides the toast. It stays while the pointer is over it or its button has focus. For a message that stays until dismissed use [InfoBanner](info-banner.md).

Toast is an `Item`. Place it as the last child of the window's content so that it draws above the rest. The message is announced to screen readers.

## Example

```qml
Item {
    // ... the window's content
    Toast {
        id: toast
        onActionTriggered: undoDelete()
    }
    Button { text: "Delete"; onClicked: { remove(); toast.showAction(qsTr("Deleted"), qsTr("Undo")) } }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `actionText` | `string` | `""` | The label of the action button (Undo); empty for none. `show()` clears it. |
| `interval` | `int` | `2500` | How long the toast stays, in ms. |
| `text` | `string` | `""` | The message shown. |

## Signals

| Name | Description |
|---|---|
| `actionTriggered()` | Emitted when the action button is clicked; the toast has already hidden itself. |

## Methods

| Signature | Description |
|---|---|
| `hide(): var` | Hides the toast now. |
| `show(var message): var` | Shows `message` without an action button. |
| `showAction(var message, var actionText): var` | Shows `message` with an action button labelled `actionText`. |
