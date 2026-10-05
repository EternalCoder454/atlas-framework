---
title: AtlasPlaceholder
summary: A skeleton block of soft rounded bars with a light sweep, shown where content is still loading.
section: Feedback and status
since: "1.3.0"
---

A skeleton block shown where content is still loading: soft rounded bars with a light sweep over them. Use it for content whose shape is known, and [AtlasSpinner](atlas-spinner.md) when it isn't. Size it with `width`, or let it fill a layout. The sweep stops while the item is not visible, with `animated: false`, or when Plasma's animation speed is "Instant". Screen readers hear "Loading".

## Example

```qml
AtlasPlaceholder { width: 240; lines: 3 }
AtlasPlaceholder { width: 64; height: 64; lines: 1; lineHeight: 64 }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `animated` | `bool` | `true` | Sweeps the light across. `false` for still bars, for example in screenshots. |
| `lineHeight` | `real` | 1 grid unit | The height of each bar. |
| `lines` | `int` | `1` | The number of bars (at least one). The last of several is shorter, like the end of a paragraph. |
