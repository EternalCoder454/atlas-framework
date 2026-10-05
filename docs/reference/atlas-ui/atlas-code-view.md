---
title: AtlasCodeView
summary: Read-only monospace text for a command, log excerpt, snippet or config, with optional line numbers and a copy button.
section: Text and code
since: "1.4.0"
---

AtlasCodeView shows selectable (mouse, Ctrl+A, Ctrl+C) plain text: nothing in it is taken as HTML. It is as tall as its text up to `maximumHeight`, then it scrolls, down and sideways (unless `wrap`). `framed` draws a card around it, `showCopy` adds a copy button in the top trailing corner, and `lineNumbers` adds a number column (a wrapped line has one number).

## Example

```qml
AtlasCodeView {
    text: "flatpak install flathub org.example.App"
    showCopy: true
}
AtlasCodeView { text: log; lineNumbers: true; maximumHeight: 240 }
```

## Accessibility

Screen readers get the text field, named "Code". Set `Accessible.name` on the view to say what the code is ("Install command").

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `framed` | `bool` | `true` | Draws a card around the text. |
| `lineNumbers` | `bool` | `false` | Adds a line-number column. |
| `maximumHeight` | `real` | `Infinity` | Taller text scrolls. `Infinity` is as tall as the text. |
| `showCopy` | `bool` | `false` | Adds a copy button in the top trailing corner. |
| `text` | `string` | `""` | The text to show. |
| `wrap` | `bool` | `false` | Wraps long lines instead of scrolling sideways. |
