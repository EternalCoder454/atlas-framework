---
title: LiveChartItem
summary: The painted item behind LiveChart: a line-and-area chart of the last 60 samples.
section: Charts
---

LiveChartItem draws the chart, with no theme of its own. Use it through [LiveChart](live-chart.md), which gives it the theme's colours and font and its accessibility. It is drawn with `QPainter`, so it renders on Qt Quick's software backend as well as on the GPU.

LiveChartItem is a `QQuickPaintedItem`; its inherited properties work as usual ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-item.html)).

## Example

```qml
LiveChart {
    values: cpu.usageHistory
    maximum: 100
    label: qsTr("Load")
    valueText: Math.round(cpu.usage) + "%"
    topText: "100%"
    spanText: qsTr("60 seconds")
}
```

Series colours should be opaque: the line is drawn as overlapping segments, which show at the joins with a translucent colour.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `captions` | `bool` | `true` | Draws the caption texts (`label`, `valueText`, `topText`, `spanText` and a 0 at the bottom right). `false` also removes the bands they take at the top and bottom, so the plot grows. |
| `color2` | `color` | `LiveChart`: `Kirigami.Theme.neutralTextColor` (an amber in Plasma); the item itself `#f67400` | The colour of the second series. |
| `color` | `color` | `LiveChart`: `TelamonStyle.accent`; the item itself `#3daee9` | The colour of the first series. |
| `font` | `QFont` | `LiveChart`: the Telamon caption font; the item itself the application font | The font of the captions. |
| `label` | `string` | `""` | The caption at the top left; also the chart's accessible name in `LiveChart`. |
| `maximum` | `real` | `0` | The value at the top of the plot. 0 or less scales to the samples: 1.25 times the highest one shown, and at least `minimumScale`. |
| `minimumScale` | `real` | `1` | The smallest value the automatic scale shows at the top. |
| `scaleTop` | `real` (read-only) | — | The value the top of the plot stands for now, for a caption. |
| `spanText` | `string` | `""` | The caption at the bottom left ("60 seconds"). |
| `textColor` | `color` | `LiveChart`: the theme's text colour; the item itself `#232629` | The colour of the captions. |
| `topText` | `string` | `""` | The caption at the top right ("100%"). Dropped when the chart is too narrow to fit it beside `label` and `valueText`. |
| `valueText` | `string` | `""` | The caption next to `label` at the top left, e.g. the current value; also the chart's accessible description in `LiveChart`. |
| `values2` | `QList<real>` | `[]` | An optional second series (upload beside download), drawn over the first. Oldest first; only the last 60 are drawn. Same rules as `values`. |
| `values` | `QList<real>` | `[]` | The samples, oldest first. Only the last 60 are drawn; the newest sits at the right edge, so fewer than 60 samples fill the right part only. A NaN or infinite sample breaks the line there, and a single sample between breaks draws nothing. |
