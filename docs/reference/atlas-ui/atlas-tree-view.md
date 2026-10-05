---
title: AtlasTreeView
summary: A tree of rows in the Atlas list look, on Qt Quick's TreeView.
section: Lists and tables
since: "1.4.0"
---

AtlasTreeView shows any `QAbstractItemModel` as a tree: rows as tall as `AtlasStyle.rowHeight`, a hover tint, selected rows as a small rounded accent-tint highlight, a chevron to expand (mirrored in right-to-left layouts) and one indent per level. Only the rows on screen are made. [AtlasTreeModel](atlas-tree-model.md) builds a model from nested JS objects. For a flat list use [AtlasListView](atlas-list-view.md).

AtlasTreeView is a Qt Quick Templates `Control` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-control.html)); its inherited properties work as usual.

## Example

```qml
AtlasTreeModel {
    id: files
    items: [ { text: "Docs", symbol: Symbols.Folder,
        children: [ { text: "Report.odt" } ] } ]
}
AtlasTreeView {
    model: files
    symbolRole: "symbol"
    selectionMode: AtlasTreeView.MultiSelection
    onActivated: index => open(index)
    onContextMenuRequested: (index, pos) => menu.popup()
    Accessible.name: qsTr("Files")
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `count` | `int` (read-only) | — | The number of rows shown (expanded rows included). |
| `currentIndex` | `var` (read-only) | — | The `QModelIndex` of the current row; invalid when there is none. |
| `iconRole` | `string` | `""` | The model role that holds an icon name or image url; empty means none. |
| `model` | `var` | `null` | Any `QAbstractItemModel`. |
| `selectionMode` | `int` | `AtlasTreeView.SingleSelection` | How many rows can be selected; the values match `DataTable` and `AtlasListView`. |
| `selectionModel` | `QItemSelectionModel*` (read-only) | — | An `ItemSelectionModel` holding the selected rows, for the app to read. |
| `symbolRole` | `string` | `""` | The model role that holds a [Symbols](symbols.md) value; empty means none. |
| `textRole` | `string` | `"display"` | The model role shown as the row's text. |

## Signals

| Name | Description |
|---|---|
| `activated(var index)` | Emitted when a row is activated with Return or a double click; `index` is its `QModelIndex`. |
| `contextMenuRequested(var index, QPointF pos)` | Emitted on a right click, the Menu key or Shift+F10; `index` is the row and `pos` where to open the menu. |

## Methods

| Signature | Description |
|---|---|
| `clearSelection(): var` | Clears the selection. |
| `collapse(var index): var` | Collapses the row at `index`. |
| `collapseAll(): var` | Collapses every row. |
| `expand(var index): var` | Expands the row at `index`. |
| `expandAll(): var` | Expands every row, at every depth. |
| `isExpanded(var index): var` | Returns true when the row at `index` is expanded. |
| `selectAll(): var` | Selects every row that is shown (`MultiSelection` only). |

## Enums

### SelectionMode

| Value | Description |
|---|---|
| `AtlasTreeView.SingleSelection` | At most one row is selected. |
| `AtlasTreeView.MultiSelection` | Several rows can be selected (Ctrl toggles, Shift extends). |
| `AtlasTreeView.NoSelection` | No row is selected; only the current row moves. |

## Keyboard

AtlasTreeView is one Tab stop.

- Up, Down, Home, End, Page Up and Page Down move the current row.
- Right expands the row or enters its first child; Left collapses it or goes to the parent (swapped when mirrored).
- Return activates; Space selects (toggles in multi selection).
- Menu or Shift+F10 asks for the context menu.
- Letters jump to the next row whose text starts with what was typed in the last 500 ms.
- In multi selection Shift+Up and Shift+Down extend the selection, Ctrl+A selects all and Ctrl+Up and Ctrl+Down move without selecting.

Clicks: Ctrl toggles and Shift extends (multi selection), a double click activates, a right click asks for the context menu. Collapsing a row that hides the current one moves the current row to the collapsed row.
