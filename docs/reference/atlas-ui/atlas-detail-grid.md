---
title: AtlasDetailGrid
summary: Names and values in aligned columns for an item's facts, with optional monospace and copy buttons.
section: Lists and tables
since: "1.4.0"
---

AtlasDetailGrid shows a muted label at the trailing edge of its column and the value beside it, for facts like an item's properties. Values can be selected with the mouse. Give it a width (fill it): its height depends on it.

## Example

```qml
AtlasDetailGrid {
    Layout.fillWidth: true
    model: [
        { label: qsTr("Version"), value: "1.4.0" },
        { label: qsTr("Checksum"), value: sha, mono: true, copyable: true }
    ]
}
```

`model` is a list of `{ label, value, mono, copyable }`. `mono` sets the value in the fixed-width font (paths, hashes). `copyable` adds a copy button.

`columns` is how many label and value pairs sit in a row. A column needs `columnsBreakpoint` grid units: below that, the label stacks over its value, and a grid with `columns` above 1 shows fewer pairs per row, as many as fit.

## Accessibility

A screen reader reads each value as "label: value".

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `columns` | `int` | `1` | How many label and value pairs sit in a row. |
| `columnsBreakpoint` | `real` | `20` | The least width of one pair, in grid units. |
| `model` | `var` | `[]` | The pairs: a list of `{ label, value, mono, copyable }`. |
