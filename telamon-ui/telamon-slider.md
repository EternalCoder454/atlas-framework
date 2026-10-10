---
title: TelamonSlider
summary: A slider with a thin accent track with round ends and a knob, horizontal or vertical, with Page Up, Page Down, Home and End keys.
section: Fields and pickers
since: "1.3.0"
---

A slider: a thin track with round ends filled with the accent up to a knob in the theme's background colour. It can be vertical. For a whole number with typing, see [TelamonSpinBox](telamon-spin-box.md).

TelamonSlider is a Qt Quick Controls [`Slider`](https://doc.qt.io/qt-6/qml-qtquick-templates-slider.html); `from`, `to`, `value`, `stepSize`, `orientation` and `moved` work as usual.

## Example

```qml
TelamonSlider { from: 0; to: 100; value: 40; onMoved: volume = value; Accessible.name: qsTr("Volume") }
```

## Keyboard

Besides the arrow keys, Page Up and Page Down move a tenth of the range, and Home and End go to the ends.

## Accessibility

> [!NOTE]
> Name the slider for screen readers with `Accessible.name`; the value is spoken as its description.
