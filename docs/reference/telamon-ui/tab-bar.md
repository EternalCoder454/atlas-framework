---
title: TabBar
summary: A strip of document tabs with an unsaved dot, a close button, a new-tab button and drag to reorder.
section: Navigation
since: "1.2.0"
---

TabBar is the strip of document tabs of an editor, after Windows 11 Notepad. Each tab is softly rounded like a [SidebarItem](sidebar-item.md), the current one has an accent tint (one highlight that slides to the new tab), a tab with unsaved changes shows a dot, and a close button shows on the hovered tab and always on the current one. A "+" after the last tab asks for a new one. When the tabs overflow, the strip shrinks to the bar (the "+" stays in view), scrolls sideways with the wheel, and keeps the current tab in view. For page switching use [TelamonViewSwitcher](telamon-view-switcher.md).

TabBar is an `Item`. The bar owns no data: the app changes `currentIndex` and the model in answer to the signals. Items put inside the bar sit at its far end.

## Example

```qml
TabBar {
    model: documents
    currentIndex: documents.current
    onActivated: index => documents.current = index
    onCloseRequested: index => documents.close(index)
    onNewRequested: documents.create()
    onMoved: (from, to) => documents.move(from, to)
    onContextMenuRequested: (index, position) => tabMenu.popup(tabBar, position)
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `currentIndex` | `int` | `-1` | The current tab; change it in answer to `activated()`. |
| `density` | `int` | `TelamonStyle.density` | `TelamonStyle.Normal` or `TelamonStyle.Compact`; Compact shrinks the height to about 75%. |
| `maxTabWidth` | `real` (read-only) | — | The widest a tab grows before its title is elided. |
| `model` | `var` | `null` | A `ListModel` or `QAbstractItemModel` with the roles `title`, `modified` (the unsaved dot) and `toolTip`. |
| `trailing` | `list<Item>` (read-only) | — | The default property: items at the bar's far end. |

## Signals

| Name | Description |
|---|---|
| `activated(int index)` | Emitted when the user picks a tab. |
| `closeRequested(int index)` | Emitted when the close button or a middle click on a tab asks to close it. |
| `contextMenuRequested(int index, QPointF position)` | Emitted on a right click on a tab, or Menu or Shift+F10 on the focused tab. `position` is in the bar's coordinates, ready for `ContextMenu.popup(tabBar, position)`: the pointer for a click, the tab's bottom-left for a key. |
| `moved(int from, int to)` | Emitted when a tab is dragged to a new place; the app moves it in the model. |
| `newRequested()` | Emitted when the "+" button is clicked. |

## Methods

| Signature | Description |
|---|---|
| `ensureCurrentVisible(): var` | Scrolls the strip so the current tab is in view. Called when the current index, the count or the width changes. |

> [!NOTE]
> The name is the same as QtQuick.Controls' `TabBar`, so import Controls qualified (`as QQC2`) in a file that uses this one.

## Keyboard

Tab reaches the current tab, and clicking never takes the keyboard focus from the editor. Menu or Shift+F10 on the focused tab emits `contextMenuRequested`. Tabs take no other keys: the app gives Ctrl+Tab and Ctrl+W.
