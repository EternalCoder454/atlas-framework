---
title: TelamonDoubleSpinBox
summary: A number field with decimals, minus and plus buttons, a prefix and a suffix.
section: Fields and pickers
since: "1.4.0"
---

TelamonDoubleSpinBox is [TelamonSpinBox](telamon-spin-box.md) for numbers with decimals: the same small rounded field with a minus and a plus button, `prefix`, `suffix` and `showButtons`, and the same keys. `from`, `to`, `value`, `stepSize` and `editable` are reals, and `decimals` (default 2) says how many digits follow the decimal separator.

The text is written in the field's locale ("1,5" in German). Typed text the field cannot read is dropped and the old value comes back. Without `prefix` and `suffix`, the field also refuses characters that cannot be part of a number as they are typed.

TelamonDoubleSpinBox is a Qt Quick Templates `DoubleSpinBox`; its inherited properties work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-doublespinbox.html>.

## Example

```qml
TelamonDoubleSpinBox {
    from: 0; to: 10; value: 2.5; stepSize: 0.5; decimals: 1
    editable: true; suffix: " s"
    Accessible.name: qsTr("Delay")
}
```

## Keyboard

Up and Down change the value by one step, PageUp and PageDown by ten steps, and the mouse wheel steps it.

## Accessibility

Name it with `Accessible.name` (what the number is for). The value itself is spoken as the description.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `prefix` | `string` | `""` | Text drawn before the number. |
| `showButtons` | `bool` | `true` | `false` hides the minus and plus buttons. |
| `suffix` | `string` | `""` | Text drawn after the number. |
