---
title: ContextMenuSeparator
summary: A thin rule between groups of ContextMenuItem rows.
section: Menus, dialogs and popups
---

ContextMenuSeparator draws a thin rule between groups of [ContextMenuItem](context-menu-item.md) rows in a [ContextMenu](context-menu.md). It is a Qt Quick Templates `MenuSeparator` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-menuseparator.html)) and has no properties of its own. A hidden separator takes no room.

## Example

```qml
ContextMenu {
    ContextMenuItem { text: qsTr("Copy") }
    ContextMenuSeparator {}
    ContextMenuItem { text: qsTr("Delete"); destructive: true }
}
```
