---
title: AtlasStat
summary: A figure with a small muted label, a big value with a unit, an optional trend arrow and an optional sparkline.
section: Feedback and status
since: "1.4.0"
---

A figure: a small muted label over a big value (with a `unit` beside it), an optional trend and an optional sparkline. `trend` is a number or `NaN` (none): above 0 shows an up arrow in the success colour, below 0 a down arrow in the error colour, and `trendText` ("+4.2%") sits beside it. `invertTrend` swaps the colours where lower is better (latency, errors). `sparkline` is a list of numbers drawn small under the value (fewer than two numbers draw none), as an [AtlasSparkline](atlas-sparkline.md). Figures have equal widths, so a changing value does not jiggle.

## Example

```qml
AtlasStat {
    label: qsTr("Download")
    value: "48.2"
    unit: "MB/s"
    symbol: Symbols.Download
    trend: 4.2
    trendText: "+4.2%"
    sparkline: net.history
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `invertTrend` | `bool` | `false` | Lower is better: an increase is shown in the error colour. |
| `label` | `string` | `""` | The small muted caption. |
| `sparkline` | `list<real>` | `[]` | The numbers drawn small under the value. Empty shows none. |
| `symbol` | `int` (a `Symbols.<Name>` value) | `0` | A symbol before the label; `0` for none. See [Symbols](symbols.md). |
| `trend` | `real` | `NaN` | The direction of change. Above 0 is an up arrow, below 0 a down arrow, `NaN` or 0 none. |
| `trendText` | `string` | `""` | Text beside the arrow, such as `"+4.2%"`. |
| `unit` | `string` | `""` | The unit beside the value, such as `"MB/s"`. |
| `value` | `string` | `""` | The big figure, as text you format. |

## Accessibility

A screen reader gets one text, "label: value unit", and the trend as its description ("Up +4.2%"). The sparkline is decorative.
