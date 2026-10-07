---
title: TelamonProgressBar
summary: A rounded progress bar in the accent colour, with an indeterminate mode, a text label beside it and normal, paused and error states.
section: Feedback and status
---

A rounded progress bar in the accent colour. `value` runs from 0 to 1; `indeterminate` slides a short segment back and forth instead. While it is working (`"normal"`, with a value above 0 and below 1, or indeterminate) a soft violet-to-sakura shimmer travels along the fill. The shimmer stops when the bar is idle, paused, in error or complete, and under reduced motion (a flat accent fill). For a busy indicator with no bar, use [TelamonSpinner](telamon-spinner.md).

Without `text` the track fills the item's height; with it the track is a thin bar centred beside the label. The fill starts on the right in right-to-left layouts.

## Example

```qml
TelamonProgressBar { value: done / total; text: qsTr("%1 of %2").arg(done).arg(total) }
TelamonProgressBar { value: 0.4; status: "error"; text: qsTr("Failed") }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `animated` | `bool` | `true` | Whether the shimmer travels. `false` holds it still (a screenshot). |
| `indeterminate` | `bool` | `false` | Slides a short segment back and forth instead of showing `value`. |
| `status` | `string` | `"normal"` | `"normal"`, `"paused"` (muted fill, no motion) or `"error"` (error colour). A screen reader hears it. Any other value counts as `"normal"` and is warned about once. Since 1.4.0. |
| `text` | `string` | `""` | A label beside the bar ("3 of 10", "42 %"), on the trailing side and elided when short of room. Since 1.4.0. |
| `value` | `real` | `0` | The progress, from 0 to 1. |

## Accessibility

Screen readers hear the percentage ("Working" when indeterminate). The description holds `text` and the status ("Error" or "Paused").
