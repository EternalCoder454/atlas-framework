---
title: AtlasActionCollection
summary: The app's actions declared once, read by the command palette, the shortcuts dialog and the app menu, with shortcuts the user can change and that are kept.
section: Menus, dialogs and popups
since: "1.5.0"
---

AtlasActionCollection holds every [AtlasAction](atlas-action.md) of the app. Declare the actions inside it once, and give it to [AtlasCommandPalette](atlas-command-palette.md), [AtlasShortcutsDialog](atlas-shortcuts-dialog.md) and [AtlasAppMenu](atlas-app-menu.md) as their `collection`. They read its actions when set; a list of their own (`actions`, `menus`) wins when it is not empty.

The collection registers each action with [AtlasShortcuts](atlas-shortcuts.md), so a shortcut conflict is reported once. It keeps the shortcuts the user changed in an [AtlasSettings](atlas-settings.md) under the key `shortcuts/<objectName>`. A changed shortcut replaces the declared one everywhere: menu text, tooltips, the palette and the dialog. Resetting brings the declared one back, also when it was a binding.

## Example

```qml
AtlasActionCollection {
    id: actions
    settings: AtlasSettings { group: "Shortcuts" }
    shortcutsEditable: true

    AtlasAction { objectName: "save"; text: qsTr("&Save"); shortcut: StandardKey.Save; category: qsTr("File") }
    AtlasAction { objectName: "quit"; text: qsTr("&Quit"); shortcut: StandardKey.Quit; category: qsTr("File") }
}
AtlasShortcutsDialog { collection: actions }
AtlasCommandPalette { collection: actions }
```

> [!NOTE]
> Every action needs an `objectName` to keep a user shortcut; one without it logs a warning, once, and its shortcut cannot be changed. The actions are read when the collection is created: declare them in it, do not add them later.

> [!NOTE]
> The values in the settings file are not trusted. A value that is not a key sequence Qt reads, is longer than 64 characters or has more than 4 chords is ignored, and the declared shortcut stays.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `actions` | `list<AtlasAction>` (default) | | The app's actions: declare them as children. |
| `settings` | `AtlasSettings` | `null` | Where the user's shortcuts are kept, one key `shortcuts/<objectName>` each. Give it a group of its own, set as a literal. With null, a change lasts until the app quits. A change another process makes to the file is picked up. |
| `shortcutsEditable` | `bool` | `false` | AtlasShortcutsDialog lets the user change shortcuts. |

## Methods

| Signature | Description |
|---|---|
| `action(name: string): var` | The action whose `objectName` is `name`; `null` when there is none. |
| `hasCustomShortcut(name: string): bool` | True when the user changed that action's shortcut. |
| `resetShortcut(name: string): void` | Back to the declared shortcut of one action. |
| `resetShortcuts(): void` | Back to the declared shortcuts of all actions. |
| `setShortcut(name: string, sequence: string): bool` | Makes `sequence` (portable text such as `"Ctrl+Shift+K"`) that action's shortcut and keeps it in `settings`. False, and nothing changes, for an unknown action or text that is not a valid shortcut. It does not look for conflicts; the dialog does. |
