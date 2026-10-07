---
title: TelamonFlowLayout
summary: Lays children out left to right and wraps them onto new rows, honouring Layout attached properties.
section: Layout
since: "1.4.0"
---

TelamonFlowLayout works like Qt Quick's `Flow`, but it honours the `Layout` attached properties (from QtQuick.Layouts) that `Flow` ignores: `Layout.preferredWidth`, `Layout.minimumWidth`, `Layout.maximumWidth`, and `Layout.fillWidth`, where the items of a row that have it share the room left in that row (usually the last one). A child is as wide as its preferred width, else its implicit width, and never wider than the layout. Rows are as tall as their tallest child. Hidden children take no room.

`implicitHeight` is the height for the current `width`, so a parent that sizes to it grows as the layout wraps. Give it a `width`. It is written in QML: the work runs once per change of width or of a child's size, not per frame. Right-to-left layouts (`LayoutMirroring`) start rows at the right.

## Example

```qml
TelamonFlowLayout {
    width: parent.width
    spacing: Kirigami.Units.smallSpacing
    Repeater { model: tags; TelamonButton { text: modelData } }
    TelamonTextField { Layout.fillWidth: true; Layout.minimumWidth: 120 }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `rowSpacing` | `real` | `spacing` | Space between rows. |
| `spacing` | `real` | `8` | Space between items of a row. |
