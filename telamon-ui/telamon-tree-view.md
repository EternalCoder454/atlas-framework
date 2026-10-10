---
title: TelamonTreeView
summary: A tree of rows in the Telamon list look, on Qt Quick's TreeView.
section: Lists and tables
since: "1.4.0"
---

TelamonTreeView shows any `QAbstractItemModel` as a tree: rows as tall as `TelamonStyle.rowHeight`, a hover tint, selected rows as a small rounded accent-tint highlight, a chevron to expand (mirrored in right-to-left layouts) and one indent per level. Only the rows on screen are made. [TelamonTreeModel](telamon-tree-model.md) builds a model from nested JS objects. For a flat list use [TelamonListView](telamon-list-view.md).

TelamonTreeView is a Qt Quick Templates `Control` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-control.html)); its inherited properties work as usual.

## Example

```qml
TelamonTreeModel {
    id: files
    items: [ { text: "Docs", symbol: Symbols.Folder,
        children: [ { text: "Report.odt" } ] } ]
}
TelamonTreeView {
    model: files
    symbolRole: "symbol"
    selectionMode: TelamonTreeView.MultiSelection
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
| `selectionMode` | `int` | `TelamonTreeView.SingleSelection` | How many rows can be selected; the values match `DataTable` and `TelamonListView`. |
| `selectionModel` | `QItemSelectionModel*` (read-only) | — | An `ItemSelectionModel` holding the selected rows, for the app to read. |
| `status` | `int` (`TelamonStatus` value) | `TelamonStatus.Ready` | What the view shows in place of its rows: Loading, Empty, NoResults or Error (see [TelamonStatus](telamon-status.md)). Since 1.5.0. |
| `statusAction` | `TelamonAction` | `null` | One button under the explanation (Retry, Clear search, ...): its text and symbol, and `trigger()` when clicked. Not shown while the action is disabled. Since 1.5.0. |
| `statusSymbol` | `int` (a `Symbols.<Name>` value) | `0` | The symbol above the heading; `0` gives the status's own (Inbox for Empty, SearchOff for NoResults, Error for Error). Since 1.5.0. |
| `statusText` | `string` | `""` | The explanation under the heading; plain text. Since 1.5.0. |
| `statusTitle` | `string` | per status | The heading. Empty gives "Nothing here" (Empty), "No results" (NoResults) or "Something went wrong" (Error). Loading has none unless set. Since 1.5.0. |
| `symbolRole` | `string` | `""` | The model role that holds a [Symbols](symbols.md) value; empty means none. |
| `textRole` | `string` | `"display"` | The model role shown as the row's text. |

## Status

`status` swaps the rows for one of four things; `Ready` (the default) shows them. **Loading** shows a [TelamonSpinner](telamon-spinner.md) only after 300 ms, so a fast load never flashes, and announces nothing. **Empty**, **NoResults** and **Error** show a [TelamonEmptyState](telamon-empty-state.md) with the title, text, symbol and action; **Error** is announced to screen readers once, when the status becomes Error (the heading and the text). While a status shows, the tree's keys do nothing.

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
| `TelamonTreeView.SingleSelection` | At most one row is selected. |
| `TelamonTreeView.MultiSelection` | Several rows can be selected (Ctrl toggles, Shift extends). |
| `TelamonTreeView.NoSelection` | No row is selected; only the current row moves. |

## Keyboard

TelamonTreeView is one Tab stop.

- Up, Down, Home, End, Page Up and Page Down move the current row.
- Right expands the row or enters its first child; Left collapses it or goes to the parent (swapped when mirrored).
- Return activates; Space selects (toggles in multi selection).
- Menu or Shift+F10 asks for the context menu.
- Letters jump to the next row whose text starts with what was typed in the last 500 ms.
- In multi selection Shift+Up and Shift+Down extend the selection, Ctrl+A selects all and Ctrl+Up and Ctrl+Down move without selecting.

Clicks: Ctrl toggles and Shift extends (multi selection), a double click activates, a right click asks for the context menu. Collapsing a row that hides the current one moves the current row to the collapsed row.
