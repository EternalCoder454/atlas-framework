---
title: TelamonNumberValidator
summary: A validator for a number field that checks a range, a number of decimals and the locale's way of writing numbers.
section: Validators
since: "1.4.0"
---

A validator for a text field's `validator`: a number between `bottom` and `top` with at most `decimals` decimals, written the way the validator's locale writes numbers (group separators are accepted). Only standard notation is accepted (no exponent, so `1e3` is Invalid). A trailing decimal point (`"1."`) is Intermediate while the user types. Text over 64 characters is Invalid, and it uses no regular expressions. `fixup()` drops a trailing decimal point and clamps a number to `bottom` and `top`.

Pair it with `invalidText` on [TelamonTextField](telamon-text-field.md#properties) so the field says what is wrong. For a number in a spin box, see [TelamonSpinBox](telamon-spin-box.md). It is a Qt `QValidator`, so its results are Acceptable, Intermediate or Invalid as Qt defines them.

## Example

```qml
TelamonTextField {
    validator: TelamonNumberValidator { bottom: 1; top: 65535; decimals: 0 }
    invalidText: qsTr("Enter a port from 1 to 65535")
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `bottom` | `real` | negative infinity | The lowest accepted value. |
| `decimals` | `int` | `15` | The most decimals accepted, and at most 15. Set `0` for whole numbers. |
| `locale` | `string` | `""` | A locale name such as `"de_DE"`; empty is the application's locale. |
| `top` | `real` | positive infinity | The highest accepted value. |
