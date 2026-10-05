---
title: AtlasAppMenu
summary: The app's menus for the header bar: exported to the desktop's global menu when there is one, else a menu button.
section: Menus, dialogs and popups
since: "1.4.0"
---

AtlasAppMenu goes in [AtlasHeaderBar](atlas-header-bar.md)'s `leading`. With a global menu on the desktop (Plasma's app menu widget; see [AtlasWindowChrome](atlas-window-chrome.md)'s `globalMenu`), the menus are exported through DBusMenu and the item shows nothing. Without one, it is a menu button in the header that opens the same menus as submenus.

## Entries

`menus` is a list of groups, each `{ title, actions }`. An entry of `actions` may be:

| Entry | Meaning |
|---|---|
| an [AtlasAction](atlas-action.md) or Qt `Action` | The action. An action with a `menu` shows here as a submenu (its `popover` is ignored). |
| `null` | A separator. |
| `{ action, shortcut }` | An action with the key sequence to export (a string or a `StandardKey`). |
| `{ title, actions }` | A nested submenu, to eight levels. A deeper one is ignored, with one warning. |
| `{ id, title, model, textRole, lead, trail, emptyText }` | A submenu whose rows come from `model`, between the `lead` and `trail` lists of actions and `null`s. |

Both the button's menus and the exported global menu nest to the same depth. The arrow keys follow [ContextMenu](context-menu.md): Right opens a submenu (Left in a right-to-left layout), the opposite key closes it.

**Model-driven rows.** A row's text is `modelData` for a model of strings, else `modelData[textRole]` (a `ListModel` is read through `textRole`). Choosing a row emits `modelActivated(id, modelData, index)` and does nothing else. With no rows and `emptyText` set, one disabled row shows it. The submenu's entry is disabled when it has no rows and no enabled action in `lead` or `trail`. The rows are read when the menu opens (for the global menu, when its group is about to show), so a change of the model while the menu is open takes effect when it closes.

**Shortcuts in the export.** Without `exportShortcuts` nothing changes. With it, the global menu's items hold each `{ action, shortcut }` entry's `shortcut` (the global-menu protocol shows it) and the button's rows show it as text. The action must then leave its own `shortcut` empty, or the key has two owners and neither fires: [AtlasShortcuts](atlas-shortcuts.md)' duplicate warning covers a mistake.

In button mode the shortcut is only shown: the app handles the key itself (the action's own `shortcut` stays empty, so the app binds the key elsewhere). With a global menu, the desktop shows it and the key reaches the app as usual.

**Changes while it is open.** A change to `menus` while the button's menu is open applies at the next open. In the global menu, a model's rows are read again when a group shows and, a moment after the model changes (a count change or a model signal); a change to `menus` is applied on the next event-loop turn, once for any number of changes, so setting it from a row's `triggered` is safe. `modelActivated` gets a plain copy of the row, never the live model object. A row that is itself a QObject (an Action) is not copied: its text, `checked` and `enabled` stay live and it is what `modelActivated` gets. A model entry with no model yet (`model: undefined`) shows disabled, with `emptyText`; an entry that fits no shape is ignored with one warning.

A menu taller than the window already scrolls (ContextMenu caps its height at the window's), so long groups need no workaround. Text of entries, `title` and `emptyText` is plain, never HTML.

## Example

```qml
AtlasHeaderBar {
    leading: AtlasAppMenu {
        menus: [
            { title: qsTr("File"), actions: [openAction, null, quitAction] },
            { title: qsTr("Edit"), actions: [undoAction, redoAction] }
        ]
    }

    AtlasAction { id: openAction; text: qsTr("&Open") }
    AtlasAction { id: quitAction; text: qsTr("&Quit") }
    AtlasAction { id: undoAction; text: qsTr("&Undo") }
    AtlasAction { id: redoAction; text: qsTr("&Redo") }
}
```

> [!NOTE]
> The native export is made only when a global menu is there, so a desktop without one never creates a menu bar of its own. Detection is an asynchronous D-Bus check with a timeout: until it answers, the button shows.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accessibleName` | `string` | `qsTr("Main menu")` | The name of the menu button for screen readers, and its tooltip. |
| `collection` | `AtlasActionCollection` | `null` | The app's [AtlasActionCollection](atlas-action-collection.md). While `menus` is empty, the menus are its actions grouped by `category` (an empty category is "General"), in the order each category first appears. A `menus` list that is not empty wins. The desktop's global menu shows no shortcuts for a collection's actions. |
| `exportShortcuts` | `bool` | `false` | Shows each `{ action, shortcut }` entry's `shortcut` in the global menu, and in the button's rows. |
| `menus` | `var` | `[]` | A list of groups, each `{title, actions}`. See Entries above for what `actions` may hold. The item is hidden while the list is empty. |

## Methods

| Signature | Description |
|---|---|
| `open(): QVariant` | Opens the button's menu. No effect with a global menu. |

## Signals

| Signature | Description |
|---|---|
| `modelActivated(string id, var modelData, int index)` | A row of a model-driven submenu was chosen. |
