---
title: AtlasIconGrid
summary: A scrolling grid of icons over names that makes cells only for what is on screen, for folders of files or apps.
section: Lists and tables
since: "1.3.0"
---

A grid of files or apps: an icon over a name, with the current one in a rounded highlight. It scrolls on its own and builds cells only for what is visible, so a folder of ten thousand files costs what a screenful does. For a single column of rows, use [AtlasListView](atlas-list-view.md).

AtlasIconGrid is a Qt Quick Controls [`Control`](https://doc.qt.io/qt-6/qml-qtquick-templates-control.html); its inherited properties work as usual.

## Example

```qml
AtlasIconGrid {
    model: files                  // a QAbstractItemModel, or a JS array
    textRole: "name"
    iconRole: "icon"              // an icon name or an image url
    symbolRole: "symbol"          // or a Symbols.<Name> value, if no icon
    placeholderText: qsTr("This Folder Is Empty")
    Accessible.name: qsTr("Files")
    onActivated: index => open(index)
    onContextMenuRequested: (index, x, y) => menu.popup(this, x, y)
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `count` | `int` (read-only) | — | The number of items in the model. |
| `currentIndex` | `int` | `0` | The current item, drawn in the highlight. `-1` for none. |
| `iconRole` | `string` | `""` | The model role (or key of an array's objects) holding an icon name or an image url. |
| `iconSize` | `real` | about 3.4 grid units | The icon's side in pixels. Cells grow with it. |
| `model` | `var` | `undefined` | A `QAbstractItemModel`, a `ListModel` or a JS array. An array of plain strings shows the strings as names. |
| `placeholderText` | `string` | `""` | Shown in the middle when there are no items ("This Folder Is Empty"). Nothing shows while empty. |
| `symbolRole` | `string` | `""` | The model role holding a [Symbols](symbols.md) value (`int`), used when the item has no icon. |
| `textRole` | `string` | `"text"` | The model role (or key of an array's objects) holding each item's name. |

A cell with neither an icon nor a symbol shows a generic file symbol.

## Signals

| Name | Description |
|---|---|
| `activated(int index)` | An item was opened: double click, Enter, or the screen reader's press action. |
| `contextMenuRequested(int index, real x, real y)` | A right click, the Menu key or Shift+F10 asked for a context menu on item `index`. `x` and `y` are in the grid's coordinates, ready for a menu's `popup()`. |

## Keyboard

The grid is one Tab stop. A click selects. The arrow keys, Home, End, Page Up and Page Down move the current item (left and right swap in right-to-left layouts), Enter activates it, and the Menu key or Shift+F10 asks for a context menu.

> [!NOTE]
> Name the grid for screen readers with `Accessible.name` ("Files").
