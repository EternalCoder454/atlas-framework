---
title: TelamonCodeView
summary: Read-only monospace text for a command, log excerpt, snippet or config, with optional line numbers and a copy button.
section: Text and code
since: "1.4.0"
---

TelamonCodeView shows selectable (mouse, Ctrl+A, Ctrl+C) plain text: nothing in it is taken as HTML. It is as tall as its text up to `maximumHeight`, then it scrolls, down and sideways (unless `wrap`). The scroll bars are [TelamonScrollBar](telamon-scroll-bar.md)s; a view wider than its room keeps its horizontal bar under the text, in room of its own, so the bar never covers the last line. `framed` draws a card around it, `showCopy` adds a copy button in the top trailing corner, and `lineNumbers` adds a number column (a wrapped line has one number).

## Example

```qml
TelamonCodeView {
    text: "flatpak install flathub org.example.App"
    showCopy: true
}
TelamonCodeView { text: log; lineNumbers: true; maximumHeight: 240 }
```

## Accessibility

Screen readers get the text field, named "Code". Set `Accessible.name` on the view to say what the code is ("Install command").

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `framed` | `bool` | `true` | Draws a card around the text. |
| `inset` | `bool` | `false` | Gives an unframed view the same leading and trailing room as the text of a `SectionRow`. A framed view already has it, so `inset` changes nothing there. It applies to both sides, also in right-to-left. |
| `lineNumbers` | `bool` | `false` | Adds a line-number column. |
| `maximumHeight` | `real` | `Infinity` | Taller text scrolls. `Infinity` is as tall as the text. |
| `showCopy` | `bool` | `false` | Adds a copy button in the top trailing corner. |
| `text` | `string` | `""` | The text to show. |
| `wrap` | `bool` | `false` | Wraps long lines instead of scrolling sideways. |
