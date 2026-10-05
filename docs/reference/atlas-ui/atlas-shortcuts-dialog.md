---
title: AtlasShortcutsDialog
summary: A modal list of the app's keyboard shortcuts grouped by section, with search, scrolling and a Close button.
section: Menus, dialogs and popups
since: "1.4.0"
---

A modal list of the app's keyboard shortcuts: every `AtlasAction` that has one ([AtlasShortcuts](atlas-shortcuts.md)`.actions`), grouped by the action's `section`, each with its text and an [AtlasShortcutLabel](atlas-shortcut-label.md). The search field filters by action text or shortcut, and the list scrolls when it is long. Actions without a section go under "General". An empty result shows an empty state.

AtlasShortcutsDialog is a Qt Quick Controls [`Popup`](https://doc.qt.io/qt-6/qml-qtquick-controls-popup.html); `open()` and `close()` work as usual. Open it from a menu or a shortcut of its own.

## Example

```qml
AtlasShortcutsDialog { id: shortcutsDialog }
AtlasAction {
    text: qsTr("Keyboard Shortcuts")
    shortcut: StandardKey.HelpContents
    onTriggered: shortcutsDialog.open()
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `title` | `string` | `"Keyboard Shortcuts"` | The dialog's title. Translated. |

## Keyboard

Escape clears the search, and then closes the dialog. The Close button closes it too.
