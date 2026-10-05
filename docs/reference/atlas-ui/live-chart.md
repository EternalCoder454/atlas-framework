---
title: LiveChart
summary: A live line-and-area chart of the last 60 samples in the theme's colours.
section: Charts
---

LiveChart draws one or two series of samples as a line with a filled area, with captions around the plot. Feed it `values` (and `values2`) as a list of numbers, oldest first; it repaints when they change. It sets the accent for the first series, the neutral colour for the second and the theme's small font for the captions, and names itself for screen readers from `label` and `valueText`. For a single small trend line use [AtlasSparkline](atlas-sparkline.md).

LiveChart is a [LiveChartItem](live-chart-item.md): all its properties are those of that type. It is drawn with `QPainter`, so it renders on the software backend as well as on the GPU.

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

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `captions` | `bool` | `true` | Draws the caption texts (`label`, `valueText`, `topText`, `spanText` and a 0 at the bottom right). |
| `color2` | `color` | `LiveChart`: `Kirigami.Theme.neutralTextColor` (an amber in Plasma); the item itself `#f67400` | The colour of the second series. |
| `color` | `color` | `LiveChart`: `AtlasStyle.accent`; the item itself `#3daee9` | The colour of the first series. |
| `font` | `QFont` | `LiveChart`: the Atlas caption font; the item itself the application font | The font of the captions. |
| `label` | `string` | `""` | The caption at the top left; also the chart's accessible name in `LiveChart`. |
| `maximum` | `real` | `0` | The value at the top of the plot. 0 scales to the samples: 1.25 times the highest one shown, and at least `minimumScale`. |
| `minimumScale` | `real` | `1` | The smallest value the automatic scale shows at the top. |
| `scaleTop` | `real` (read-only) | — | The value the top of the plot stands for now, for a caption. |
| `spanText` | `string` | `""` | The caption at the bottom left ("60 seconds"). |
| `textColor` | `color` | `LiveChart`: the theme's text colour; the item itself `#232629` | The colour of the captions. |
| `topText` | `string` | `""` | The caption at the top right ("100%"). |
| `valueText` | `string` | `""` | The caption next to `label` at the top left, e.g. the current value; also the chart's accessible description in `LiveChart`. |
| `values2` | `QList<real>` | `[]` | An optional second series (upload beside download), drawn over the first. Oldest first; only the last 60 are drawn. |
| `values` | `QList<real>` | `[]` | The samples, oldest first. Only the last 60 are drawn; the newest sits at the right edge. |
