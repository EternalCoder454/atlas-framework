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

## Keyboard

Up and Down move over the rows that can be chosen and wrap at the ends: separators, disabled rows and hidden rows are passed over, so the highlight never rests where Enter would do nothing. Home and End go to the first and the last of those rows. Enter and Space choose the current row (or open its submenu), and Escape closes the menu (one submenu at a time).

Right opens the current row's submenu and Left closes it; in a right-to-left layout it is the other way round. In the top menu these two keys do nothing.

A row of your own, such as a `MenuItem` that holds several buttons side by side, receives the keys first. It handles the ones it needs (Left, Right, Enter) and lets the rest go on to the menu with `event.accepted = false`, or the arrow keys stop on it.

The menu does its own keyboard navigation. An app that turned the list's off (`contentItem.keyNavigationEnabled = false`) to get this can drop that line; keeping it does no harm.

## Notes

> [!NOTE]
> Menus are tinted translucent over the blurred window when `Appearance.effective`, solid otherwise. For radio rows see [ContextMenuItem](context-menu-item.md).
