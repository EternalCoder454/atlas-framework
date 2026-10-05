---
title: MiniBars
summary: A row of small upright bars, one per value, wrapping onto more rows when there are many.
section: Charts
---

MiniBars draws one small bar per value, for example one per processor core. Each bar fills from the bottom to `value / maximum` and is numbered underneath when `numbered`. The bars wrap onto more rows when there are many. Every bar is an indicator for screen readers, named with `nameOf` and described with `textOf`.

MiniBars is a `Flow` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-flow.html)); its inherited properties work as usual.

## Example

```qml
MiniBars {
    values: cpu.coreUsage
    maximum: 100
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `barHeight` | `real` | `Kirigami.Units.gridUnit * 2.5` | The height of a bar in pixels. |
| `barWidth` | `real` | `Math.round(Kirigami.Units.gridUnit * 0.9)` | The width of a bar in pixels. |
| `color` | `color` | `AtlasStyle.accent` | The fill colour of the bars. |
| `maximum` | `real` | `100` | The value that fills a bar. |
| `nameOf` | `var` | `i => qsTr("Core %1").arg(i)` | A function from the bar's index to what a screen reader says for it. Change it when the bars are not cores. |
| `numbered` | `bool` | `true` | Numbers each bar underneath. |
| `textOf` | `var` | `v => Math.round(v) + "%"` | A function from a value to its accessible description. |
| `values` | `QList<real>` | `[]` | The values, one bar each. |
