---
title: SearchField
summary: A search field with a magnifier, a clear button and a debounced query.
section: Fields and pickers
---

SearchField is a text field with small rounded corners, a magnifier and a clear button once there is text (both Material Symbols, at the same inset from their edge of the field, with the text clear of them). `query` follows the text after a short pause, so a live list filters once per word rather than per key: bind to `query`, not to `text`. Escape clears the field and, when it is already empty, lets the key go on to close whatever the field is in.

SearchField is a Qt Quick Templates `TextField` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-textfield.html)); its inherited properties work as usual. For a general text input use [TelamonTextField](telamon-text-field.md).

## Example

```qml
SearchField {
    placeholderText: qsTr("Search apps")
    onQueryChanged: model.filter = query
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `delay` | `int` | `150` | How many milliseconds without typing before `query` follows the text. |
| `query` | `string` | `""` | The text after `delay` ms without typing; empty at once when the field is cleared. |
| `rtl` | `bool` (read-only) | — | True when the layout is mirrored (a TextField has no `mirrored` of its own). |

## Accessibility

The field is exposed as a search edit, named by its `placeholderText` ("Search" by default).
