---
title: TelamonRadioButton
summary: A round radio button with a label; buttons with the same parent form a group and the arrow keys move the choice.
section: Buttons
since: "1.3.0"
---

A round radio button with a label. Radio buttons with the same parent form a group: checking one unchecks the others. For a choice between a few views, see [TelamonSegmentedControl](telamon-segmented-control.md).

TelamonRadioButton is a Qt Quick Controls [`RadioButton`](https://doc.qt.io/qt-6/qml-qtquick-templates-radiobutton.html); `text`, `checked` and the rest work as usual.

## Example

```qml
Column {
    TelamonRadioButton { text: qsTr("Light"); checked: true }
    TelamonRadioButton { text: qsTr("Dark") }
}
```

## Keyboard

Tab visits one radio button of a group: the checked one, or the first if none is. The arrow keys move the choice to the next or previous button of the group, wrapping round (Left and Right swap in right-to-left layouts).
