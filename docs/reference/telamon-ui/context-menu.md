---
title: ContextMenu
summary: A right-click menu in the Telamon look: a raised card with 6 px corners with inset rows.
section: Menus, dialogs and popups
---

ContextMenu is the menu for right clicks and "more" buttons. Fill it with [ContextMenuItem](context-menu-item.md) and [ContextMenuSeparator](context-menu-separator.md), and open it with `popup()` at the pointer, or `popup(item, x, y)` from the keyboard. Rows can be checkable, radio choices or open a submenu.

ContextMenu is a Qt Quick Templates `Menu` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-menu.html)); its inherited properties, signals and methods (`popup()`, `close()`, `addItem()`) work as usual. A menu taller than the window (less its margins) is cut to fit and scrolls; the arrow keys keep the current row in view.

## Example

```qml
ContextMenu {
    id: menu
    ContextMenuItem { text: qsTr("Details"); icon.name: "documentinfo" }
    ContextMenuSeparator {}
    ContextMenuItem { text: qsTr("End Task"); destructive: true }
}
```

## Notes

> [!NOTE]
> Menus are tinted translucent over the blurred window when `Appearance.effective`, solid otherwise. For radio rows see [ContextMenuItem](context-menu-item.md).
