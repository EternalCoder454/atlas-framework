---
title: UsageBar
summary: A stacked bar of how something is shared out, with an optional legend.
section: Charts
---

UsageBar shows how a total is split into parts (memory: Used, Cached, Free), with an optional legend under it. Give it the parts' sizes in `values`, in order; what is left of `total` is drawn as the empty track. `labels` and `texts` may hold one more entry than `values`: the rest of the track, shown in the legend with the track's colour.

UsageBar is a `ColumnLayout`. For a single value use [TelamonProgressBar](telamon-progress-bar.md).

## Example

```qml
UsageBar {
    total: memory.total
    values: [memory.used, memory.cached]
    labels: [qsTr("Used"), qsTr("Cached"), qsTr("Free")]
    texts: [fmt(memory.used), fmt(memory.cached), fmt(memory.free)]
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `barHeight` | `real` | `Math.round(Kirigami.Units.gridUnit * 0.6)` | The height of the bar in pixels. |
| `colors` | `QList<color>` | `[TelamonStyle.accent, Qt.alpha(TelamonStyle.accent, 0.45)]` | One colour per part; parts past the list get the last colour faded. |
| `labels` | `list<string>` | `[]` | The legend's labels. |
| `legend` | `bool` | `labels.length > 0` | Shows the legend under the bar. |
| `mirrored` | `bool` (read-only) | — | True when the layout is mirrored; the bar then fills from the right. |
| `sum` | `real` (read-only) | — | The sum of `values` (negative values count as 0). |
| `texts` | `list<string>` | `[]` | What the legend shows after each label, already formatted. |
| `total` | `real` | `0` | The whole bar. 0 means the sum of `values`. |
| `trackColor` | `color` (read-only) | — | The colour of the empty track. |
| `values` | `QList<real>` | `[]` | The parts' sizes, in order. |
| `whole` | `real` (read-only) | — | The value the bar stands for: `total` if above 0, else `sum`. |

## Methods

| Signature | Description |
|---|---|
| `colorAt(var i): var` | Returns the colour of part `i`: `colors[i]`, or the last colour faded for parts past the list. |

> [!NOTE]
> The bar is a graphic for screen readers, named from `labels` and `texts`; fill both.
