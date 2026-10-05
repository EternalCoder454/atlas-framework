---
title: AtlasAction
summary: One user action with its text, symbol, shortcut and tooltip in one place, shared by toolbar buttons, menu items and the keyboard.
section: Menus, dialogs and popups
since: "1.4.0"
---

AtlasAction is a Qt Quick Controls `Action` (`text`, `shortcut`, `enabled`, `checkable`, `checked`, `triggered()`) plus a symbol, a tooltip and a section. A toolbar button, a menu item and the keyboard then run the same code and stay in step. Every action registers with [AtlasShortcuts](atlas-shortcuts.md), which warns when two enabled actions share a shortcut and feeds [AtlasShortcutsDialog](atlas-shortcuts-dialog.md).

AtlasAction is a Qt Quick Templates `Action`; its inherited properties work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-action.html>.

## Example

```qml
AtlasAction {
    id: saveAction
    text: qsTr("&Save")
    symbol: Symbols.Save
    shortcut: StandardKey.Save
    section: qsTr("File")
    onTriggered: document.save()
}
```

> [!NOTE]
> Declare it inside an Item so the window it works in is known: shortcuts in the same window conflict, others do not.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `menu` | `Menu` | `null` | A [ContextMenu](context-menu.md) that the action's [ToolbarButton](toolbar-button.md) opens instead of triggering. In an [AtlasAppMenu](atlas-app-menu.md) it shows as a submenu. If both `menu` and `popover` are set, `menu` wins. |
| `popover` | `Popup` | `null` | An [AtlasPopover](atlas-popover.md) that the action's toolbar button opens instead of triggering. Its `target` is set to the button. |
| `section` | `string` | `""` | The group the action shows under in AtlasShortcutsDialog. Empty means the general group. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | The icon; 0 for none. ToolbarButton, ContextMenuItem and MenuButton show it when given this action. |
| `toolTip` | `string` | `text` without its `&` mnemonic marker | The tooltip of a button that shows this action. |
