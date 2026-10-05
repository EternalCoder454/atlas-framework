---
title: ContextMenuItem
summary: One row of a ContextMenu: an icon or symbol, the text and a shortcut hint, optionally checkable or a radio choice.
section: Menus, dialogs and popups
---

ContextMenuItem is a row of a [ContextMenu](context-menu.md). It shows an icon or a `symbol`, the text and, dimmed on the right, a shortcut hint. A checked `checkable` row shows a check mark in the icon's place and a row that opens a submenu shows an arrow at the end. A hidden row takes no room.

ContextMenuItem is a Qt Quick Templates `MenuItem` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-menuitem.html)); its inherited properties work as usual. With an `action` (an [AtlasAction](atlas-action.md) or a plain Qt `Action`) the row shows the action's `symbol` and, when `shortcutText` is empty, its shortcut.

## Example

```qml
ButtonGroup { id: sortGroup }
ContextMenuItem { text: qsTr("Name"); radio: true; checked: true; ButtonGroup.group: sortGroup }
ContextMenuItem { text: qsTr("Size"); radio: true; ButtonGroup.group: sortGroup }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `destructive` | `bool` | `false` | Draws the row in the error colour (Kill, Delete). |
| `radio` | `bool` | `false` | A choice among several: draws a dot instead of the check mark when checked. Implies `checkable`. |
| `shortcutText` | `string` | `""` | The shortcut hint shown dimmed on the right ("Del"). It only describes and doesn't bind a key. When empty, the action's shortcut is shown. |
| `showsCheck` | `bool` (read-only) | — | True when the row is checkable, checked and not a radio row. |
| `symbol` | `int` (a `Symbols.<Name>` value) | the action's `symbol`, else `0` | A Material Symbol drawn instead of `icon.name`; see [Symbols](symbols.md). |
| `tint` | `color` (read-only) | — | The colour of the row's text and symbol: disabled, error (destructive) or normal. |

> [!NOTE]
> Rows of one radio choice must share a Qt group, which makes them exclusive and keeps the checked one from being unchecked by a second click: either an exclusive `ActionGroup` (the rows' `action`s) or a `ButtonGroup` (`ButtonGroup.group: group` on each row, from `QtQuick.Controls`).
