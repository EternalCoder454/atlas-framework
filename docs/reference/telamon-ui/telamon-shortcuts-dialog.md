---
title: TelamonShortcutsDialog
summary: A modal list of the app's keyboard shortcuts grouped by section, with search, scrolling and a Close button.
section: Menus, dialogs and popups
since: "1.4.0"
---

A modal list of the app's keyboard shortcuts: every `TelamonAction` that has one ([TelamonShortcuts](telamon-shortcuts.md)`.actions`), grouped by the action's `section`, each with its text and a [TelamonShortcutLabel](telamon-shortcut-label.md). The search field filters by action text or shortcut, and the list scrolls when it is long. Actions without a section go under "General", which comes first; the other sections, and the rows in each, are in alphabetical order. An empty result shows an empty state.

TelamonShortcutsDialog is a Qt Quick Controls [`Popup`](https://doc.qt.io/qt-6/qml-qtquick-controls-popup.html); `open()` and `close()` work as usual. Open it from a menu or a shortcut of its own.

## Example

```qml
TelamonShortcutsDialog { id: shortcutsDialog }
TelamonAction {
    text: qsTr("Keyboard Shortcuts")
    shortcut: StandardKey.HelpContents
    onTriggered: shortcutsDialog.open()
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `collection` | `TelamonActionCollection` | `null` | The app's [TelamonActionCollection](telamon-action-collection.md): its actions are listed instead of every registered action, grouped by `category`. When its `shortcutsEditable` is set the user can change shortcuts, see below. |
| `title` | `string` | `"Keyboard Shortcuts"` | The dialog's title. Translated. |

## Changing shortcuts

When the collection's `shortcutsEditable` is set, each row of an action that is in the collection and has an `objectName` gets a Change button. It shows a [TelamonShortcutField](telamon-shortcut-field.md): press the new keys. A shortcut another action already has is refused, and the dialog says which action has it ("Already used by “Save”. Choose another shortcut."); the field then records again. Escape cancels. A changed shortcut shows a Reset button for that row, Reset puts the declared shortcut back unless another action has it now (the dialog then says which); Reset all in the footer puts every declared shortcut back. Escape while recording cancels the recording and leaves the dialog open, also when the key is held and then released. If a change cannot be used or saved, the dialog says so under the list. The conflict check covers every registered enabled action of the app, which is wider than the warning in [TelamonShortcuts](telamon-shortcuts.md). Shortcuts need Ctrl, Alt or Meta with a key, or are an F key. The scroll position stays when a shortcut changes. Changes apply at once everywhere and are kept in the collection's `settings`.

## Keyboard

Escape clears the search, and then closes the dialog. The Close button closes it too.
