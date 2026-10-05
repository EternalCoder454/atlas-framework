---
title: AtlasTextView
summary: A virtualized text view for very large text such as logs and files, with selection, copy, line numbers and follow mode.
section: Text
since: "1.5.0"
---

A text view that only lays out the lines in view, so a file of hundreds of megabytes scrolls as smoothly as a short one. The text lives in a piece tree, not in a `QString`. It is read-only in this release: the editing members do nothing yet.

Load a big file with `beginLoad()`, `appendBytes()` and `endLoad()`: the view stays responsive, `loadProgress` reports how far it is, and `loadFailed` is set if the load could not finish. `text` and `appendText()` are for small and live content. With `follow` on, the view stays at the end while text is appended, until the user scrolls up; `maximumLines` drops the oldest lines of a log.

Only the lines in view are highlighted. `syntax` and `syntaxTheme` are stored but the built-in highlighter is not in this release; a C++ highlighter or `setDecorationPairs()` colours the text.

## Example

```qml
AtlasTextView {
    anchors.fill: parent
    follow: true
    maximumLines: 100000
    showLineNumbers: true
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `text` | `string` | `""` | The whole text. Setting it replaces the content at once; reading it copies everything, so avoid it for huge text. |
| `readOnly` | `bool` | `true` | Reserved for editing; the view is read-only in this release. |
| `wrap` | `bool` | `false` | Wraps lines at the view's width. Very long lines are laid out in windows. |
| `font` | `font` | monospace | The font. |
| `tabWidth` | `int` | `4` | Width of a tab in characters. |
| `lineCount` | `int` | `1` | Number of lines. Read-only. |
| `length` | `int` | `0` | Length in UTF-16 units. Read-only. |
| `cursorPosition` | `int` | `0` | The caret's position. |
| `selectionStart` | `int` | `0` | Start of the selection. Read-only. |
| `selectionEnd` | `int` | `0` | End of the selection. Read-only. |
| `selectedText` | `string` | `""` | The selected text. Read-only. |
| `contentX` | `real` | `0` | Horizontal scroll offset. |
| `contentY` | `real` | `0` | Vertical scroll offset. |
| `contentWidth` | `real` | | Width of the text. Read-only. |
| `contentHeight` | `real` | | Height of the text. Read-only. |
| `firstVisibleLine` | `int` | `0` | First line in view. Read-only. |
| `lastVisibleLine` | `int` | `0` | Last line in view. Read-only. |
| `lineEnding` | `enum` | `LF` | The line ending found: `LF`, `CRLF`, `CR` or `Mixed`. Read-only. |
| `modified` | `bool` | `false` | The text changed since `markSaved()`. Read-only. |
| `canUndo` | `bool` | `false` | Reserved for editing. Read-only. |
| `canRedo` | `bool` | `false` | Reserved for editing. Read-only. |
| `undoLimit` | `int` | `1000` | Reserved for editing. |
| `loading` | `bool` | `false` | A load is running. Read-only. |
| `loadProgress` | `real` | `0` | Fraction loaded, 0 to 1. Read-only. |
| `hadInvalidText` | `bool` | `false` | The loaded bytes held invalid UTF-8 that was replaced with U+FFFD. Read-only. |
| `loadFailed` | `bool` | `false` | The last load failed. The view is empty. Read-only. |
| `syntax` | `string` | `""` | Syntax name. Stored only; no built-in highlighter yet. |
| `syntaxTheme` | `string` | `""` | Highlighting theme name. Stored only. |
| `highlightLimit` | `int` | `0` | Longest text, in characters, that is highlighted. |
| `showLineNumbers` | `bool` | `false` | Shows the line-number gutter. |
| `highlightCurrentLine` | `bool` | `false` | Tints the caret's line. |
| `follow` | `bool` | `false` | Keeps the view at the end while text is appended. Scrolling up pauses it; scrolling to the end resumes it. |
| `maximumLines` | `int` | `0` | Drops the oldest lines beyond this count. `0` is no limit. |
| `textColor` | `color` | theme text | The text colour. |
| `selectionColor` | `color` | theme accent | The selection colour. |
| `lineNumberColor` | `color` | theme muted | The gutter's number colour. |

## Methods

| Name | Description |
|---|---|
| `textInRange(start, end)` | The text between two positions. |
| `positionAt(point)` | The position nearest a point in the item. |
| `rectangleAt(position)` | The caret rectangle at a position, in item coordinates. |
| `positionOfLine(line)` | The position where a line starts. |
| `lineOf(position)` | The line a position is on. |
| `columnOf(position)` | The column of a position in its line. |
| `beginLoad()` | Starts a streamed load and clears the text. |
| `appendBytes(utf8)` | Adds UTF-8 bytes to a streamed load. |
| `endLoad()` | Finishes a streamed load. |
| `appendText(text)` | Appends text to the end. |
| `markSaved(revision)` | Marks a revision as saved, which clears `modified`. |
| `select(start, end)` | Selects a range. |
| `selectAll()` | Selects everything. |
| `copy()` | Copies the selection to the clipboard. |
| `ensureVisible(position)` | Scrolls to show a position. |
| `lineY(line)` | The y coordinate of a line in the content. |
| `setDecorationPairs(layer, pairs, style)` | Sets a decoration layer from a flat list `[start, end, ...]` with a style number. |
| `clearDecorations(layer)` | Removes a decoration layer. |

## Signals

| Name | Description |
|---|---|
| `contentsChange(position, removed, added)` | The text changed. |
| `loaded()` | A load finished. |

> [!NOTE]
> Give the view an `Accessible.name`. It exposes its text, caret and selection to screen readers.
