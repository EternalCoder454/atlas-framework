---
title: AtlasSparkline
summary: A small line chart with no axes or captions that shows the trend of a figure in a card or a row.
section: Charts
since: "1.4.0"
---

A small line chart with no axes or captions: the trend of a figure in a card or a row. `values` is a list of numbers, oldest first, spread over the full width; a `NaN` is a gap. It scales to the values unless `minimum` and `maximum` are set, and an automatic scale never shows less than `minimumRange`, so a nearly flat series stays flat. It repaints only when the values really change.

AtlasSparkline is an [AtlasSparklineItem](atlas-sparkline-item.md) with the theme's accent colour and a default size; its properties are the same.

## Example

```qml
AtlasSparkline {
    values: cpu.usageHistory
    minimum: 0
    maximum: 100
    fill: true
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `color` | `color` | `AtlasStyle.accent` | The line's colour. |
| `fill` | `bool` | `false` | Adds a soft area under the line. |
| `lineWidth` | `real` | `1.5` | The line's width. |
| `maximum` | `real` | `NaN` | The value at the top of the item. `NaN` scales to the samples. |
| `minimum` | `real` | `NaN` | The value at the bottom of the item. `NaN` scales to the samples. |
| `minimumRange` | `real` | `0` | The least span an automatic scale shows. |
| `values` | `list<real>` | `[]` | The samples, oldest first. A `NaN` is a gap. |

> [!NOTE]
> Inside [AtlasStat](atlas-stat.md) the sparkline is decorative, because the stat describes the figure. On its own, give it an `Accessible.name`.
