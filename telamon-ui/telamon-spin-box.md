---
title: TelamonSpinBox
summary: A whole-number field with minus and plus buttons, a prefix and a suffix, which can be shown as a plain number field.
section: Fields and pickers
since: "1.3.0"
---

A number field with a minus and a plus button at its ends. `prefix` and `suffix` ("MB", "%") are drawn beside the number. The default width fits the widest value between `from` and `to`. With `showButtons: false` it is a plain number field. For real numbers, use `TelamonDoubleSpinBox`; for a range with no typing, [TelamonSlider](telamon-slider.md).

TelamonSpinBox is a Qt Quick Controls [`SpinBox`](https://doc.qt.io/qt-6/qml-qtquick-templates-spinbox.html); `from`, `to`, `value`, `stepSize` and `editable` work as usual (`editable` is `false` by default).

## Example

```qml
TelamonSpinBox { from: 1; to: 64; value: 8; editable: true; suffix: " GB"; Accessible.name: qsTr("Memory") }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `prefix` | `string` | `""` | Text drawn before the number. |
| `showButtons` | `bool` | `true` | `false` hides the minus and plus buttons. Since 1.4.0. |
| `suffix` | `string` | `""` | Text drawn after the number. |

## Keyboard

Up and Down, Page Up and Page Down (ten steps) and the mouse wheel work with or without the buttons.

> [!NOTE]
> Name the spin box for screen readers with `Accessible.name` (what the number is for); the value is spoken as the description.
