---
title: TelamonTextView
summary: A virtualized text view for very large text such as logs and files, with selection, copy, line numbers and follow mode.
section: Text and code
since: "1.5.0"
---

A text view that only lays out the lines in view, so a file of hundreds of megabytes scrolls as smoothly as a short one. The text lives in a piece tree, not in a `QString`. It is read-only in this release: the editing members do nothing yet.

Load a big file with `beginLoad()`, `appendBytes()` and `endLoad()`: the view stays responsive, `loadProgress` reports how far it is, and `loadFailed` is set if the load could not finish. The view has no file API: the caller opens the file and owns the path, symlink, size and permission checks, then feeds the bytes in. `text` and `appendText()` are for small and live content. With `follow` on, the view stays at the end while text is appended, until the user scrolls up; `maximumLines` drops the oldest lines of a log.

Only the lines in view are highlighted. `syntax` and `syntaxTheme` are stored but the built-in highlighter is not in this release; a C++ highlighter or `setDecorationPairs()` colours the text.

## Example

```qml
TelamonTextView {
    anchors.fill: parent
    follow: true
    maximumLines: 100000
    showLineNumbers: true
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `text` | `string` | `""` | The whole text. Setting it replaces the content at once; reading it copies everything, so avoid it for huge text; it is empty when there is not enough memory for the copy. |
| `readOnly` | `bool` | `true` | Reserved for editing; the view is read-only in this release. |
| `wrap` | `bool` | `false` | Wraps lines at the view's width. Very long lines are laid out in windows. |
| `font` | `font` | monospace | The font. |
| `tabWidth` | `int` | `4` | Width of a tab in characters. |
| `lineCount` | `int` | `1` | Number of lines. Read-only. |
| `length` | `int` | `0` | Length in UTF-16 units. Read-only. |
| `cursorPosition` | `int` | `0` | The caret's position. |
| `selectionStart` | `int` | `0` | Start of the selection. Read-only. |
| `selectionEnd` | `int` | `0` | End of the selection. Read-only. |
| `hasSelection` | `bool` | `false` | Part of the text is selected. Read-only. Use it instead of reading `selectedText` to find out. |
| `selectedText` | `string` | `""` | The selected text. Read-only. It is empty when the selection is larger than 32 million characters; `copy()` has the same limit. |
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
| `loadProgress` | `real` | `1` | Fraction loaded, 0 to 1. It is 1 when no load is running. Read-only. |
| `hadInvalidText` | `bool` | `false` | The loaded bytes held invalid UTF-8 that was replaced with U+FFFD. Read-only. |
| `loadFailed` | `bool` | `false` | The last load failed. The view keeps the clean text that arrived before the failure. Read-only. |
| `syntax` | `string` | `""` | Syntax name. Stored only; no built-in highlighter yet. |
| `syntaxTheme` | `string` | `""` | Highlighting theme name. Stored only. |
| `highlightLimit` | `int` | `52428800` | Longest line, in characters, that is highlighted (50 MiB). |
| `showLineNumbers` | `bool` | `false` | Shows the line-number gutter. |
| `highlightCurrentLine` | `bool` | `false` | Tints the caret's line. |
| `follow` | `bool` | `false` | Keeps the view at the end while text is appended. Scrolling up pauses it; scrolling to the end resumes it. |
| `maximumLines` | `int` | `0` | Drops the oldest lines beyond this count, also after a load or `text` is set. `0` is no limit. |
| `textColor` | `color` | theme text | The text colour. |
| `selectionColor` | `color` | theme accent | The selection colour. |
| `lineNumberColor` | `color` | theme muted | The gutter's number colour. |

## Enumerations

The values of `lineEnding`:

| Name | Description |
|---|---|
| `LF` | Lines end with `\n`. |
| `CRLF` | Lines end with `\r\n`. |
| `CR` | Lines end with `\r`. |
| `Mixed` | More than one kind. |

## Methods

| Name | Description |
|---|---|
| `textInRange(start, end)` | The text between two positions. |
| `positionAt(point)` | The position nearest a point in the item. |
| `rectangleAt(position)` | The caret rectangle at a position, in item coordinates. |
| `positionOfLine(line)` | The position where a line starts. |
| `lineOf(position)` | The line a position is on. |
| `columnOf(position)` | The column of a position in its line. |
| `beginLoad()` | Starts a streamed load and clears the text and every decoration layer. |
| `appendBytes(utf8)` | Adds UTF-8 bytes to a streamed load. |
| `endLoad()` | Finishes a streamed load. |
| `appendText(text)` | Appends text to the end. |
| `markSaved(revision)` | Marks a revision as saved, which clears `modified`. |
| `select(start, end)` | Selects a range. |
| `selectAll()` | Selects everything. |
| `copy()` | Copies the selection to the clipboard. |
| `ensureVisible(position)` | Scrolls to show a position. |
| `lineY(line)` | The y coordinate of a line in the content. |
| `setDecorationPairs(layer, pairs, style)` | Sets a decoration layer from a flat list `[start, end, ...]` with a style number. `beginLoad()` and `setText` clear every decoration layer. |
| `clearDecorations(layer)` | Removes a decoration layer. |

## Signals

| Name | Description |
|---|---|
| `contentsChange(position, removed, added)` | The text changed. |
| `loaded()` | A load finished. |

> [!NOTE]
> Give the view an `Accessible.name` and, if it helps, an `Accessible.description`: they are what a screen reader announces. The view also exposes its text, caret and selection. It has no accessible value text, because that would be the whole file, and a screen reader gets at most about a million characters of a very long line at a time.
