---
title: AtlasAppMenu
summary: The app's menus for the header bar: exported to the desktop's global menu when there is one, else a menu button.
section: Menus, dialogs and popups
since: "1.4.0"
---

AtlasAppMenu goes in [AtlasHeaderBar](atlas-header-bar.md)'s `leading`. With a global menu on the desktop (Plasma's app menu widget; see [AtlasWindowChrome](atlas-window-chrome.md)'s `globalMenu`), the menus are exported through DBusMenu and the item shows nothing. Without one, it is a menu button in the header that opens the same menus as submenus.

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
| `menus` | `var` | `[]` | A list of groups, each `{title, actions}`. `actions` holds [AtlasAction](atlas-action.md) or Qt `Action` items, and `null` for a separator. The item is hidden while the list is empty. |

## Methods

| Signature | Description |
|---|---|
| `open(): QVariant` | Opens the button's menu. No effect with a global menu. |
