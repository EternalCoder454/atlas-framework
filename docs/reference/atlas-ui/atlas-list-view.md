---
title: AtlasListView
summary: A ListView in the Atlas look with selection, type-ahead, a default row from model roles, a context menu and optional drag reordering.
section: Lists and tables
since: "1.4.0"
---

A list in the Atlas look: rows of `AtlasStyle.rowHeight`, a hover tint, the selected rows in a rounded accent highlight (4 px corners), and a focus ring on the current row when the keyboard moved there. It makes rows only for what is on screen, so ten thousand rows cost what a screenful does. For icons in a grid, use [AtlasIconGrid](atlas-icon-grid.md).

AtlasListView is a Qt Quick [`ListView`](https://doc.qt.io/qt-6/qml-qtquick-listview.html); `model`, `delegate`, `currentIndex`, `count` and the rest work as usual.

## Example

```qml
AtlasListView {
    model: files                   // a QAbstractItemModel, or a JS array
    textRole: "name"
    subtitleRole: "path"
    symbolRole: "symbol"           // a Symbols.<Name> value
    selectionMode: AtlasListView.MultiSelection
    placeholderText: qsTr("No files")
    placeholderSymbol: Symbols.FolderOpen
    Accessible.name: qsTr("Files")
    onActivated: index => open(index)
    onContextMenuRequested: (index, pos) => menu.popup(this, pos.x, pos.y)
}
```

Without a `delegate`, each row shows the symbol, the text and the subtitle from the model's roles (keys of an array's objects; an array of plain strings shows the strings). With your own delegate, the view still does the clicking, selecting, the keyboard and the context menu; draw the selection with `list.isSelected(index)`, which re-evaluates when the selection changes.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `placeholderSymbol` | `int` (a `Symbols.<Name>` value) | `0` | The symbol shown above `placeholderText` when there are no rows. See [Symbols](symbols.md). |
| `placeholderText` | `string` | `""` | Shown in the middle when there are no rows. |
| `reorderable` | `bool` | `false` | Default rows show a drag grip, and Alt+Up and Alt+Down move the current row. The list emits `moveRequested`. |
| `selectedIndexes` | `list<int>` (read-only) | — | The selected row indexes, ascending. |
| `selectedRows` | `list<int>` (read-only) | — | The same list as `selectedIndexes`, named as in DataTable. |
| `selectionMode` | `int` (AtlasListView.SelectionMode) | `AtlasListView.SingleSelection` | How many rows can be selected. |
| `status` | `int` (`AtlasStatus` value) | `AtlasStatus.Ready` | What the view shows in place of its rows: Loading, Empty, NoResults or Error (see [AtlasStatus](atlas-status.md)). Since 1.5.0. |
| `statusAction` | `AtlasAction` | `null` | One button under the explanation (Retry, Clear search, ...): its text and symbol, and `trigger()` when clicked. Not shown while the action is disabled. Since 1.5.0. |
| `statusSymbol` | `int` (a `Symbols.<Name>` value) | `0` | The symbol above the heading; `0` gives the status's own (Inbox for Empty, SearchOff for NoResults, Error for Error). Since 1.5.0. |
| `statusText` | `string` | `""` | The explanation under the heading; plain text. Since 1.5.0. |
| `statusTitle` | `string` | per status | The heading. Empty gives "Nothing here" (Empty), "No results" (NoResults) or "Something went wrong" (Error). Loading has none unless set. Since 1.5.0. |
| `subtitleRole` | `string` | `""` | The model role for a second, smaller line. Rows are taller when it is set. |
| `symbolRole` | `string` | `""` | The model role holding a [Symbols](symbols.md) value (`int`) for the row's leading symbol. |
| `textRole` | `string` | `"text"` | The model role holding the row's text. |

Selection works by row index. It is cleared when `model` changes, resets or moves rows, and follows the rows when a `QAbstractItemModel` or `ListModel` inserts or removes some. A JS array just drops indexes past its end.

## Status

`status` swaps the rows for one of four things; `Ready` (the default) shows them. **Loading** shows an [AtlasSpinner](atlas-spinner.md) only after 300 ms, so a fast load never flashes, and announces nothing. **Empty**, **NoResults** and **Error** show an [AtlasEmptyState](atlas-empty-state.md) with the title, text, symbol and action; **Error** is announced to screen readers once, when the status becomes Error (the heading and the text). The rows are hidden and the list's own `header` stays. While a status shows, the list's keys do nothing. A Ready list with no rows still shows `placeholderText`.

## Signals

| Name | Description |
|---|---|
| `activated(int index)` | A row was opened: double click or Return. |
| `contextMenuRequested(int index, point pos)` | A right click (which first selects an unselected row), the Menu key or Shift+F10. `pos` is in the list's coordinates. |
| `moveRequested(int from, int to)` | With `reorderable`, the user dragged a row, or pressed Alt+Up or Alt+Down. |

> [!NOTE]
> On `moveRequested`, move the model's row to `to` at once, inside the handler. The list then selects the moved row.

## Methods

| Signature | Description |
|---|---|
| `clearSelection()` | Clears the selection. |
| `isSelected(int index): bool` | Whether row `index` is selected. A binding on it re-runs when the selection changes. |
| `select(int index)` | Makes `index` the current and only selected row. Out-of-range indexes and `NoSelection` do nothing. |
| `selectAll()` | Selects every row. Only in `MultiSelection`; otherwise no effect. |
| `selectRows(list<int> rows)` | Selects exactly these rows; out-of-range ones are ignored. Single selection takes the first valid one; `NoSelection` ignores the call. |

## Enums

### SelectionMode

| Value | Description |
|---|---|
| `AtlasListView.SingleSelection` | One row at a time. The default. |
| `AtlasListView.MultiSelection` | Ctrl-click toggles, Shift-click extends. |
| `AtlasListView.NoSelection` | Rows can't be selected. |

## Keyboard

A click selects. In `MultiSelection`, Ctrl-click toggles, Shift-click and Shift+arrows extend, Ctrl+A selects all and Space toggles; in single selection Space selects the current row. Return emits `activated`. The Menu key or Shift+F10 emits `contextMenuRequested`. Typing jumps to the next row whose text starts with what was typed (for an array, a `ListModel` or a model's `display` role; the buffer clears after 500 ms).

> [!NOTE]
> Name the list for screen readers with `Accessible.name`.
