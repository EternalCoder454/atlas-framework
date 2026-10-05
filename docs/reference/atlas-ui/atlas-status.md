---
title: AtlasStatus
summary: The values of `status` on lists, tables, trees and pages: Ready, Loading, Empty, NoResults and Error.
section: Feedback and status
since: "1.5.0"
---

`AtlasStatus` is a singleton that only holds an enum: the values of the `status` property of [AtlasListView](atlas-list-view.md), [DataTable](data-table.md), [AtlasTreeView](atlas-tree-view.md) and [AtlasPage](atlas-page.md). It cannot be created and has no properties. A view shows what its `status` says in place of its rows, so an app sets one value instead of building a spinner, an empty state and an error state by hand.

## Example

```qml
AtlasListView {
    model: files
    status: files.loading ? AtlasStatus.Loading
          : files.failed ? AtlasStatus.Error
          : files.count === 0 ? (query.length > 0 ? AtlasStatus.NoResults : AtlasStatus.Empty)
          : AtlasStatus.Ready
    statusText: files.failed ? qsTr("The folder could not be read.") : ""
    statusAction: AtlasAction {
        text: files.failed ? qsTr("Retry") : qsTr("Clear search")
        onTriggered: files.failed ? files.reload() : query = ""
    }
}
```

## Enums

### Status

| Value | Number | The view shows |
|---|---|---|
| `Ready` | 0 | Its rows (the default). A list or table with no rows still shows its `placeholderText`. |
| `Loading` | 1 | An [AtlasSpinner](atlas-spinner.md), only after 300 ms: a load that ends sooner shows no flash. Nothing is announced. `statusTitle` and `statusText` show under the spinner when set. |
| `Empty` | 2 | An [AtlasEmptyState](atlas-empty-state.md) with the Inbox symbol and the heading "Nothing here". |
| `NoResults` | 3 | The same with the SearchOff symbol and "No results". |
| `Error` | 4 | The same with the Error symbol and "Something went wrong". It is announced to screen readers once, when the status becomes Error. |

The heading, the explanation, the symbol and one action button come from the view's `statusTitle`, `statusText`, `statusSymbol` and `statusAction`. The status replaces the rows and keeps the header: a [DataTable](data-table.md)'s column header and an [AtlasPage](atlas-page.md)'s title stay.
