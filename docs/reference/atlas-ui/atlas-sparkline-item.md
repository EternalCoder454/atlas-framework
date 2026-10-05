---
title: AtlasSparklineItem
summary: The painted item behind AtlasSparkline, a small axis-less line chart drawn with QPainter.
section: Charts
since: "1.4.0"
---

The C++ item behind [AtlasSparkline](atlas-sparkline.md): a small line chart with no axes or captions, for the trend of a figure in a card or a row. It is drawn with `QPainter`, so it renders on Qt Quick's software backend as well as on the GPU. Use [AtlasSparkline](atlas-sparkline.md) instead, which gives it the theme's accent colour and an accessible role; the properties are the same.

AtlasSparklineItem is a Qt Quick `Item`; its inherited properties work as usual.

## Example

```qml
AtlasSparklineItem {
    values: cpu.usageHistory
    minimum: 0
    maximum: 100
    color: "steelblue"
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `color` | `color` | `#3daee9` | The line's colour. |
| `fill` | `bool` | `false` | Adds a soft area under the line. |
| `lineWidth` | `real` | `1.5` | The line's width. |
| `maximum` | `real` | `NaN` | The value at the top of the item. `NaN` or an infinite value scales to the samples. Samples above it are drawn at the top edge. |
| `minimum` | `real` | `NaN` | The value at the bottom of the item. `NaN` or an infinite value scales to the samples. Samples below it are drawn at the bottom edge. |
| `minimumRange` | `real` | `0` | The least span an automatic scale shows, so a nearly flat series is not blown up. |
| `values` | `list<real>` | `[]` | The samples, oldest first, spread over the full width. Any value that is not finite (`NaN` or infinity) is a gap: the line breaks there. A single sample between gaps, or alone, is drawn as a dot. |
