---
title: TelamonCodeEditor
summary: An editable code editor with syntax highlighting by language or file name, a line-number gutter, marks for changed lines and edits that arrive from outside without moving the caret or the view.
section: Text and code
since: "2.1.1"
---

TelamonCodeEditor edits plain text in the monospace font, coloured by [KSyntaxHighlighting](https://api.kde.org/frameworks/syntax-highlighting/html/index.html) for the language you give it (`language`) or that the file name implies (`fileName`). The colours come from the Telamon theme and follow Light, Dark and high contrast. It has a line-number gutter, tints the caret's row, and can mark lines an app changed (`markLines`). For a read-only view of a log or a command's output use [TelamonCodeView](telamon-code-view.md) or [TelamonConsoleView](telamon-console-view.md).

Lines are numbered from 1 in the whole API: `cursorLine`, `scrollToLine()`, `markLines()`, `firstVisibleLine`.

`setTextPreserving()` is for text that changes under the reader, such as an assistant's edit of the open file: it rewrites only what differs and leaves the caret, the selection and the scroll position where they were.

## Example

```qml
TelamonCodeEditor {
    anchors.fill: parent
    fileName: "main.rs"
    text: source
    onTextEdited: dirty = true
}
```

An edit that arrives from outside, with the changed lines marked for a moment:

```qml
editor.setTextPreserving(newSource)
editor.markLines([[12, 18], 40], TelamonCodeEditor.Changed, 3000)
editor.scrollToLine(12)
```

## What the text is

- **Plain text only.** Nothing in the text is taken as HTML or Markdown, and a link in it is not a link. The text field is a plain text field.
- **Line breaks read back as LF.** CR, CRLF and U+2029 in a text you set become `\n`. An app that must keep CRLF files converts them back when it saves. Other characters, a no-break space included, come back as they went in. The two code points U+FDD0 and U+FDD1, which the text engine reads as frame markers, are replaced by U+FFFD.
- **Bidirectional controls are shown.** The editor draws the text as it is, so a file with bidirectional control characters (U+202A to U+202E, U+2066 to U+2069) can show its code in another order than the compiler reads it. The characters are kept so that a save changes nothing; an app that opens files it does not trust should look for them in `text` and tell the user.
- **Setting `text` loads a document.** The undo history is cleared, the marks are cleared and `modified` is false. `textEdited` is not emitted: it tells the app about the user's edits only.

## Large files

Qt's text engine lays out a line in about 70 microseconds, redraws in time proportional to the number of lines at each change (about 8 ms per 1,000 lines on the software renderer) and uses about 75 MB of memory per MiB of text. Typing in a text of a few thousand lines is smooth; at 15,000 lines (about 1 MiB) a change takes about 120 ms to draw, at 100,000 lines most of a second. That is why `maximumSize` is 1 MiB by default and why a larger text goes to the viewer. An app can raise it for files it knows are worth the cost.

Setting a big `text` does not stop the window: a text of more than 64 KiB is put into the document a few lines at a time from the event loop (about 0.8 s for 900 KiB, with no stall over about 110 ms). `loading` is `true` meanwhile, `text` already returns all of it, the editor is read-only (the lines that have arrived can be scrolled and selected), and `loaded()` is emitted at the end. Setting another `text` or calling `setTextPreserving()` while it loads starts over.

The editor never hands a text it cannot edit smoothly to the text field. A text is "too large" when it has more than `maximumSize` characters (1 MiB by default), or a line longer than 200,000 characters. It is then shown in a read-only viewer ([TelamonTextView](telamon-text-view.md), built for any size) under a note that says why. `tooLarge` is true, `text` still returns the text, `modified` stays false and typing does nothing. The marks are not drawn. Setting a text under the limits makes the editor editable again.

Highlighting is lazy: only the lines in view, and a margin around them, are coloured, and the lines above them are read in short slices from the event loop, so opening a big file never stops the window. A line longer than 4,000 characters is left unhighlighted (a regular expression over a line that long is a stall); the lines around it are coloured as usual.

## Keyboard

| Keys | Action |
|---|---|
| Tab | Inserts spaces (or a tab character, with `insertSpaces` off) to the next tab stop; indents every selected line when several lines are selected. |
| Shift+Tab | Outdents the selected lines, or the caret's line. |
| Escape, then Tab | Moves the focus on instead of indenting, so the keyboard is never trapped. |
| Home | Goes to the first character that is not white space, and from there to the start of the line. Shift+Home selects. |
| Ctrl+Z, Ctrl+Shift+Z (or Ctrl+Y) | Undo and redo. |
| Ctrl+A, Ctrl+C, Ctrl+X, Ctrl+V | Select all, copy, cut and paste. |

In a read-only editor Tab moves the focus on.

## Accessibility

Screen readers get the text field, named "Code editor". Set `Accessible.name` on the editor to say which file it holds ("main.rs"). The keyboard focus ring shows only for keyboard focus. Marked lines are told apart by more than colour: an added line has a solid gutter bar, a changed one a dashed bar. In high contrast the syntax is shown without colour: keywords are bold, comments italic.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `text` | `string` | `""` | The whole text. Reading it copies the text. Setting it loads a document (see above). |
| `modified` | `bool` | `false` | The text differs from what was loaded or last marked saved. Set it to `false` when the app saves. |
| `readOnly` | `bool` | `false` | The text cannot be edited; it can still be selected and copied. |
| `language` | `string` | `""` | A language name (`"C++"`, `"Rust"`, `"python"`; any case), an alternative name or an extension (`"py"`). When it names no language, `fileName` is used. |
| `fileName` | `string` | `""` | A file name or path. Its name and extension pick the language (`main.cpp`, `Makefile`, `Cargo.toml`). |
| `syntaxName` | `string` | `""` | The language in use, `""` for plain text. Read-only. |
| `cursorLine` | `int` | `1` | The caret's line, from 1. Set it to move the caret. A line past the end is the last line. |
| `cursorColumn` | `int` | `1` | The caret's column, from 1, counting UTF-16 units. Set it to move the caret. |
| `lineCount` | `int` | `1` | The number of lines. Read-only. |
| `firstVisibleLine` | `int` | `1` | The first line in view. Read-only. |
| `lastVisibleLine` | `int` | `1` | The last line in view. Read-only. |
| `canUndo` | `bool` | `false` | There is something to undo. Read-only. |
| `canRedo` | `bool` | `false` | There is something to redo. Read-only. |
| `showLineNumbers` | `bool` | `true` | Shows the line-number gutter. |
| `highlightCurrentLine` | `bool` | `true` | Tints the caret's row while the editor has focus. |
| `wrap` | `bool` | `false` | Wraps long lines at the width of the editor instead of scrolling sideways. |
| `tabWidth` | `int` | `4` | The width of a tab stop, and of one indentation, in characters. |
| `insertSpaces` | `bool` | `true` | Tab inserts spaces (`true`) or a tab character. |
| `framed` | `bool` | `true` | Draws a card around the editor. |
| `maximumSize` | `int` | `1048576` | The most characters (UTF-16 units) the editor edits; a longer text is shown read-only. Between 1,024 and 268,435,456. |
| `tooLarge` | `bool` | `false` | The text is shown read-only in the viewer. Read-only. |
| `loading` | `bool` | `false` | A big text is being put into the editor a few lines at a time. Read-only. |
| `markFadeDuration` | `int` | `0` | How long `markLines()` marks last by default, in milliseconds. `0` keeps them until `clearMarks()`. |

## Enumerations

The values of the `kind` of `markLines()`:

| Name | Description |
|---|---|
| `Added` | Lines that are new: a solid gutter bar and a green band. |
| `Changed` | Lines that were rewritten: a dashed gutter bar and an amber band. |

## Signals

| Name | Description |
|---|---|
| `textEdited()` | The user changed the text: typing, paste, drop, undo, redo or indentation. Not emitted when the app sets `text` or calls `setTextPreserving()`. |
| `cursorMoved()` | The caret moved, by the user or the app. |
| `loaded()` | A text that was loaded in slices is all in the editor. |

## Methods

| Name | Description |
|---|---|
| `setTextPreserving(newText)` | Replaces the text from outside. Only the part that differs is rewritten. The caret and the selection stay at the same line and column (clamped to the new text), and the view keeps the same first visible line, so a reader's place does not jump while text arrives. The undo history is cleared, `modified` becomes `true` when the text differs, and `textEdited()` is not emitted. Cheap enough to call for every chunk of a streamed edit; a change of more than 64 KiB is loaded in slices like `text` (then `modified` is `false`, and the caret and the selection stay at the same line and column as far as the text has arrived). |
| `markLines(ranges, kind, fadeMs)` | Marks lines with a bar in the gutter and a tinted band behind the text. `ranges` is a list of line numbers (from 1), `[first, last]` pairs or `{first, last}` objects; a range past the end stops at the last line, an invalid one is ignored, and at most 10,000 ranges are taken at a time. `kind` is `TelamonCodeEditor.Added` or `.Changed`. With `fadeMs` above 0 (omit it for `markFadeDuration`) the marks fade out after that long; under reduced motion they stay as they are for that long and then go. Marks move with the lines when the text is edited, and are cleared when `text` is set. Call it after `setTextPreserving()`, which rewrites the lines it marks. |
| `clearMarks()` | Removes every mark. |
| `scrollToLine(n)` | Scrolls so line `n` (from 1) is in view. A line that is already in view does not move the text; otherwise it is placed a third of the way down. |
| `undo()`, `redo()` | Undo and redo, as Ctrl+Z and Ctrl+Shift+Z do. |
| `selectAll()` | Selects all the text. |
| `copy()` | Copies the selection to the clipboard. |

> [!NOTE]
> TelamonCodeEditor is a `FocusScope`: `forceActiveFocus()` puts the focus in the text field.
