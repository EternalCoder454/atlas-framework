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
> The values in the settings file are not trusted. A value is ignored, and the declared shortcut stays, when it is not one key chord Qt reads, is longer than 64 characters, has a control, bidirectional or other invisible format character, or is not allowed: a user shortcut needs Ctrl, Alt or Meta with a key, or is an F key (F1 to F35, with any modifiers). Shift and a key, a lone key and a chord of modifiers only are refused. A saved shortcut that another enabled action of the collection already has is ignored too, with one warning. A conflict that comes from outside (another process or a hand-edited file) is only warned about, never resolved for the user.

> [!NOTE]
> The declared shortcut of each action is read when the collection is created; that is what a reset goes back to, also when it is a binding or a `StandardKey`.

> [!NOTE]
> The global menu ([AtlasAppMenu](atlas-app-menu.md) with a desktop global menu) shows no shortcuts for a collection's actions: the effective shortcut cannot be shown there without registering it a second time. The menu button inside the window does show them.

> [!NOTE]
> The conflict check in AtlasShortcutsDialog is wider than the warning in AtlasShortcuts: it compares with every registered enabled action of the app, not only those in the same window or collection.

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
| `declaredConflict(name: string): string` | The text of another enabled action of the app that has the shortcut `name` would go back to on reset; `""` when none does. |
| `resetShortcut(name: string): bool` | Back to the declared shortcut of one action. False, and nothing changes, when another action has that shortcut now or the settings cannot be written. |
| `resetShortcuts(): bool` | Back to the declared shortcuts of all actions. False when a change could not be saved; that one stays. |
| `setShortcut(name: string, sequence: string): bool` | Makes `sequence` (portable text such as `"Ctrl+Shift+K"`, one chord, see the note on what is allowed) that action's shortcut and keeps it in `settings`. The declared shortcut as `sequence` removes the change. False, and nothing changes, for an unknown action, a value that is not allowed, or a settings file that refuses it. It does not look for conflicts; the dialog does. |
