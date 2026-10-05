---
title: DataTable
summary: A sortable table in the Section style that only makes the rows on screen.
section: Lists and tables
---

DataTable is a card with 6 px corners with a header that sorts and inset rows below it. It scrolls its own rows and makes only the ones on screen, so a list of a thousand processes costs what twenty do. It supports resizable and hideable columns, multi-selection, row context menus and a flattened tree. For a simple list of rows use [AtlasListView](atlas-list-view.md).

DataTable is a `FocusScope`, one Tab stop. Name it for screen readers with `Accessible.name`.

The table doesn't sort: a header click sets `sortRole` and `sortOrder`, and the model follows them (a Rust `QAbstractItemModel` that moves rows, not one that resets).

## Example

```qml
DataTable {
    model: apps
    columns: [
        { title: qsTr("Name"), role: "name", fill: true, iconRole: "icon" },
        { title: qsTr("CPU"), role: "cpu", width: 5, align: Qt.AlignRight,
          heat: 100, text: v => v.toFixed(1) + "%" },
    ]
    onActivated: row => open(row)
    onContextMenuRequested: (row, x, y) => menu.popup()
    Accessible.name: qsTr("Apps")
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `cellPadding` | `real` (read-only) | — | The horizontal padding inside a cell. |
| `collapsedText` | `string` (read-only) | — | The accessible description of a collapsed tree row (translated). |
| `columnWidths` | `QList<real>` | `[]` | Every column's width in pixels once the user has resized; empty means automatic. Writable: save it from `columnResized` and restore it on start. The fill column's entry is informational only. |
| `columns` | `var` | `[]` | The columns, as a list of objects (see Columns below). |
| `columnsMenu` | `bool` | `false` | True opens a menu of checkable column titles on a right click of the header (and emits `headerMenuRequested`). |
| `count` | `int` (read-only) | — | The number of rows. |
| `currentIndex` | `int` | `-1` | The current row. |
| `density` | `int` | `AtlasStyle.density` | `AtlasStyle.Normal` or `AtlasStyle.Compact`; Compact makes the rows about 75% as tall. |
| `depthRole` | `string` | `""` | For a tree the model has flattened: the role holding a row's depth; the first column indents by it. |
| `expandableRole` | `string` | `""` | The role that says whether a row can be expanded; the first column then shows a chevron that emits `toggleRequested`. |
| `expandedRole` | `string` | `""` | The role that says whether an expandable row is open. |
| `expandedText` | `string` (read-only) | — | The accessible description of an expanded tree row (translated). |
| `hiddenColumns` | `QList<int>` | `[]` | The indexes of the hidden columns; writable. At least one column always stays visible. |
| `mirrored` | `bool` (read-only) | — | True when the layout is mirrored (right-to-left); the table mirrors every cell and the header with it. |
| `model` | `var` | `undefined` | The rows: any list model. |
| `padding` | `real` (read-only) | — | The padding around the header and rows inside the card. |
| `placeholderText` | `string` | `""` | Shown in the middle when there are no rows ("No Apps Match"). |
| `pointerInside` | `bool` (read-only) | — | True while the pointer is over the rows. A live model should hold its order still then, so the row under the pointer stays put; hold it while a context menu opened on a row is up, too. |
| `resizableColumns` | `bool` | `false` | True lets the user drag the boundary between two columns; a double click fits the column to its widest visible cell. |
| `rowHeight` | `real` (read-only) | — | The height of a row, from `density`. |
| `selectedRows` | `QList<int>` (read-only) | — | The selected row numbers, ascending. Selection is by row number: a live model that moves rows leaves it where it was, and a change of `model` clears it. |
| `selectionMode` | `int` | `DataTable.SingleSelection` | How rows are selected (`DataTable.SelectionMode`). |
| `sortOrder` | `int` | `Qt.DescendingOrder` | The sort direction the model should follow; a click on the sorted header flips it. |
| `sortRole` | `string` | `""` | The model role the table is sorted by; a header click sets it. |
| `widths` | `var` (read-only) | — | The pixel width of each column (0 for a hidden one); the fill column takes what the others leave. |

## Signals

| Name | Description |
|---|---|
| `activated(int row)` | Emitted when a row is activated with Return, Enter or a double click. |
| `columnResized(int column, real width)` | Emitted when the user resizes a column, also while dragging; `width` is in pixels. |
| `contextMenuRequested(int row, real x, real y)` | Emitted on a right click on a row, the Menu key or Shift+F10; `x` and `y` are in the table. |
| `deleteRequested(int row)` | Emitted when Delete is pressed on the current row. |
| `headerMenuRequested(real x, real y)` | Emitted on a right click on the header, at `x`, `y` in the table, for a menu of the columns to show. |
| `rowContextMenuRequested(int row, QPointF pos)` | The same request as `contextMenuRequested`, with the position as a point. A right click selects the row first, unless it is already part of a selection. |
| `toggleRequested(int row)` | Emitted when the chevron of a tree row is clicked, or Left or Right is pressed to fold or unfold it; the app flattens the tree. |

## Methods

| Signature | Description |
|---|---|
| `clearSelection(): var` | Clears the selection. |
| `openMenuAtCurrent(): var` | Opens the row context menu on the current row (as the Menu key does) and returns whether there was a row. |
| `selectAll(): var` | Selects every row (`MultiSelection` only). |
| `selectRows(var rows): var` | Selects the given row numbers (`MultiSelection`); in `SingleSelection` the first one becomes current. |
| `sortBy(var i): var` | Sorts by column `i` as a header click does: flips the direction on the sorted column, else sorts by it (figures biggest first, names A to Z). Does nothing for a column with `sortable: false`. |

## Enums

### SelectionMode

| Value | Description |
|---|---|
| `DataTable.SingleSelection` | The current row is the selection. |
| `DataTable.MultiSelection` | Ctrl click toggles, Shift click and Shift+arrows extend, Ctrl+A selects all, Space toggles the current row. |
| `DataTable.NoSelection` | No selection. |

## Columns

A column is an object with these keys:

| Key | Meaning |
|---|---|
| `title`, `role` | The header text and the model role the column shows. |
| `width` | Width in grid units. Or `fill: true` for the column that takes what is left (the first one, if none says so; a second `fill` is sized by its width). |
| `align` | `Qt.AlignLeft` (default) or `Qt.AlignRight` for figures. |
| `text(value, row)` | Formats the value; `row` is the delegate's model object. |
| `heat` | A short bar under the cell's text, as wide as `value / heat` of the cell (load columns); 0 or absent for none. |
| `iconRole` | A role holding an icon name, drawn before the text. |
| `cell` | A Component for anything else (a status dot, a switch); it gets `value`, `row` and `column`. |
| `sortable` | `false` keeps the header from sorting (default true). |

> [!NOTE]
> Rows are reused as the list scrolls, so a `cell` shows only what `value`, `row` and `column` say and keeps no state of its own.

## Keyboard

Up, Down, Page Up, Page Down, Home and End move the current row. Return or Enter activates it, Delete emits `deleteRequested`, Menu or Shift+F10 opens the row menu. In multi selection Shift+arrows extend, Ctrl+A selects all and Space toggles the current row. On a tree row, Right unfolds and Left folds (swapped when mirrored).
