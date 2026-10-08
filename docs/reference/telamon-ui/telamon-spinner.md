---
title: TelamonSpinner
summary: A busy indicator, an accent arc that turns while something loads.
section: Feedback and status
since: "1.3.0"
---

A busy indicator: an accent arc (a third of the ring, with round ends, drawn inside its bounds at any size) that turns. Show it while something loads; `running: false` hides it. It stands still (a fixed arc) while it is not visible, with `animated: false`, or when Plasma's animation speed is "Instant". For content whose shape is known, see [TelamonPlaceholder](telamon-placeholder.md); for a measured task, [TelamonProgressBar](telamon-progress-bar.md).

TelamonSpinner is a Qt Quick Controls [`BusyIndicator`](https://doc.qt.io/qt-6/qml-qtquick-templates-busyindicator.html); `running` works as usual.

## Example

```qml
TelamonSpinner { running: model.loading }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `animated` | `bool` | `true` | Turns the arc. `false` for a fixed arc, for example in screenshots. |
| `color` | `color` | `TelamonStyle.accent` | The arc's colour. Use the button's text colour on a filled button. |
