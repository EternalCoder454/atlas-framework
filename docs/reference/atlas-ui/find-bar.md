---
title: FindBar
summary: A find and replace bar that slides down above an editor.
section: Text and code
---

FindBar is the find (and replace) bar for an editor or viewer. The owner does the searching: it binds `findText` and the three toggles to its search, answers `findNext()` and the other signals, and reports `matchCount` and `currentMatch` back. Open it with `open(withReplace)`.

## Example

```qml
FindBar {
    id: findBar
    findText: editor.searchText
    matchCount: editor.hits
    currentMatch: editor.currentHit
    onFindNext: editor.next()
    onFindPrevious: editor.previous()
    onReplaceOne: editor.replaceCurrent(replaceText)
    onReplaceAll: editor.replaceEvery(replaceText)
}
Shortcut { sequence: "Ctrl+F"; onActivated: findBar.open(false) }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `countText` | `string` (read-only) | — | The text of the count label: `error` if set, empty without a search text, "No results" or "3 of 12". |
| `currentMatch` | `int` | `0` | The position of the current hit, 1-based; 0 for none. Set by the owner. |
| `error` | `string` | `""` | Replaces the count, for a regular expression that does not compile. |
| `failed` | `bool` (read-only) | — | True when `error` is set or a non-empty search has no matches; the field shows its invalid state. |
| `findText` | `string` | `""` | The text in the find field. |
| `fullHeight` | `real` (read-only) | — | The height the bar needs when open, for the owner to reserve. |
| `matchCase` | `bool` | `false` | The match case toggle. |
| `matchCount` | `int` | `0` | How many hits there are. Set by the owner. |
| `opened` | `bool` | `false` | Whether the bar is shown; use `open()` and `close()`. |
| `regularExpression` | `bool` | `false` | The regular expression toggle. |
| `replaceText` | `string` | `""` | The text in the replace field. |
| `replaceVisible` | `bool` | `false` | Whether the replace row is shown. |
| `wholeWords` | `bool` | `false` | The whole words toggle. |

## Signals

| Name | Description |
|---|---|
| `closed()` | Emitted when the bar closes. |
| `findNext()` | Emitted when Enter is pressed in the find field or the next button is clicked. |
| `findPrevious()` | Emitted for Shift+Enter or the previous button. |
| `replaceAll()` | Emitted when replace all is clicked. |
| `replaceOne()` | Emitted when replace is clicked or Enter is pressed in the replace field. |

## Methods

| Signature | Description |
|---|---|
| `close(): var` | Closes the bar and emits `closed()`. |
| `open(var withReplace): var` | Opens the bar and focuses the find field with its text selected. `withReplace` also shows the replace row. |

## Keyboard

Enter finds the next match, Shift+Enter the previous one and Escape closes the bar. Enter in the replace field replaces.
