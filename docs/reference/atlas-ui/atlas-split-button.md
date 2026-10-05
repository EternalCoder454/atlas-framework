---
title: AtlasSplitButton
summary: A main button joined to an arrow that opens a menu of variants of the action, such as Save and Save As.
section: Buttons
since: "1.4.0"
---

A main button joined to an arrow part that opens a menu: the common action ("Save") and its variants ("Save As...", "Save a Copy"). Put `ContextMenuItem` and `ContextMenuSeparator` children inside, as in `MenuButton`. `prominent` fills it with the accent. The main part runs `action` and emits `clicked()`. For a single action, use [AtlasButton](atlas-button.md).

## Example

```qml
AtlasSplitButton {
    text: qsTr("Save")
    symbol: Symbols.Save
    prominent: true
    onClicked: document.save()
    ContextMenuItem { text: qsTr("Save As..."); onTriggered: document.saveAs() }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `action` | `Action` | `null` | An `Action` or [AtlasAction](atlas-action.md). Optional: it also supplies `text`, `symbol` and the enabled state when those are not set. |
| `items` | `list<QtObject>` (read-only) | — | The default property: the menu's items declared inside. |
| `menu` | `ContextMenu` (read-only) | — | The menu the arrow opens. |
| `mirrored` | `bool` (read-only) | — | Whether the layout is mirrored (right to left). |
| `prominent` | `bool` | `false` | Fills the button with the accent. |
| `symbol` | `int` (a `Symbols.<Name>` value) | `0` | A symbol on the main part; `0` for none. See [Symbols](symbols.md). |
| `text` | `string` | `""` | The main part's label, and its accessible name. |

## Signals

| Name | Description |
|---|---|
| `clicked()` | The main part was pressed. |

## Methods

| Signature | Description |
|---|---|
| `openMenu()` | Opens the menu under the arrow. |

## Keyboard

Two Tab stops: the main part, then the arrow. Alt+Down or the Menu key on the main part opens the menu too. Enter and Space activate the focused part.

## Accessibility

The main part's accessible name is `text`; the arrow's is "More options".
