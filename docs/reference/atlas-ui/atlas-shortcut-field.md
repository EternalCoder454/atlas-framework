---
title: AtlasShortcutField
summary: A field that records a key combination and reports conflicts with other registered actions.
section: Fields and pickers
since: "1.4.0"
---

A field that records a key combination. Click it, or press Space or Return while it has the focus, then press the shortcut: the first key that is not a modifier, with the modifiers held, becomes `sequence` and recording stops. Escape cancels and keeps the old value, Backspace or Delete clears it, and losing the focus cancels. While recording, the window's own shortcuts are suspended, so Ctrl+S can be recorded instead of saving.

AtlasShortcutField is a Qt Quick Controls [`Control`](https://doc.qt.io/qt-6/qml-qtquick-templates-control.html); its inherited properties work as usual.

The field only reports: the app decides whether to accept the shortcut, in `onEdited`.

## Example

```qml
AtlasShortcutField {
    sequence: saveAction.shortcut
    ignoreAction: saveAction
    onEdited: saveAction.shortcut = sequence
    Accessible.name: qsTr("Save shortcut")
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `conflictText` | `string` (read-only) | — | Set when another registered `AtlasAction` already uses `sequence`. It names that action and shows under the field. Empty when there is no conflict. See [AtlasShortcuts](atlas-shortcuts.md). |
| `ignoreAction` | `QtObject` | `null` | The action being edited: its own shortcut is no conflict. |
| `placeholderText` | `string` | `"Press a shortcut"` | Shown while there is no shortcut. Translated. |
| `recording` | `bool` (read-only) | — | `true` while the field waits for the keys. |
| `sequence` | `string` | `""` | The shortcut as portable text (`"Ctrl+Shift+K"`); empty for none. |

## Signals

| Name | Description |
|---|---|
| `edited()` | The user recorded or cleared the shortcut. `sequence` already holds the new value; to reject it, assign the old (or another) value to `sequence` in the handler. |

## Methods

| Signature | Description |
|---|---|
| `startRecording()` | Starts recording and takes the focus, as a click does. Does nothing while disabled. |

## Keyboard

Click, or Space or Return, starts recording. The first non-modifier key sets the shortcut, Escape cancels, and Backspace or Delete clears it.

Since 1.5.0: Escape, Backspace and Delete cancel or clear only when pressed alone; with Ctrl, Shift, Alt or Meta held they are recorded.
