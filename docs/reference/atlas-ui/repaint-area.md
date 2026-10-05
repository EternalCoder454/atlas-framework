---
title: RepaintArea
summary: An invisible item that repaints its whole area as one rectangle whenever its content changes.
section: Charts
---

RepaintArea is a performance helper for Qt Quick's software backend, which repaints only what changed. A table row whose figures change dirties one rectangle per label, and the renderer then carries a region of hundreds of slivers through every node of the window. Laid over a row and given the row's values, RepaintArea turns that into one rectangle per row (and rows next to each other into one). It draws nothing, and on the GPU backends it has no node at all.

RepaintArea is a Qt Quick `Item` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-item.html)); its inherited properties work as usual. Most apps get it through [DataTable](data-table.md) and don't use it directly.

## Example

```qml
Row {
    // ... the labels showing the figures
    RepaintArea {
        anchors.fill: parent
        content: [model.name, model.cpu, model.memory]
    }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `content` | `list<var>` | `[]` | What the area shows, e.g. the row's values. Each change repaints the whole area. |
