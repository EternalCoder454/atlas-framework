---
title: TelamonEmailValidator
summary: A validator for an email address field: one @, a dotted domain and a bounded length.
section: Validators
since: "1.4.0"
---

TelamonEmailValidator is a Qt `QValidator` for a field's `validator`, with Acceptable, Intermediate and Invalid as Qt defines them. It checks a pragmatic address: one `@`, a local part, and a domain with a dot, at most 254 characters. The local part is at most 64 characters, may not start or end with a dot or hold two dots in a row, and may not contain `,;<>"()[]\:?&%#` or format characters. The domain holds only letters, digits, `-` and `.`, and no label of it may be empty or start or end with a hyphen. Whitespace anywhere inside is Invalid. Text with spaces around it is Intermediate until `fixup()` trims it. It uses no regular expressions. Pair it with `TelamonTextField.invalidText`, see [TelamonTextField](telamon-text-field.md).

## Example

```qml
TelamonTextField {
    placeholderText: qsTr("Email")
    validator: TelamonEmailValidator {}
    invalidText: qsTr("Enter an address like name@example.com")
}
```

> [!NOTE]
> Acceptable text is still not safe to splice into a URL or header unencoded.

It has no properties of its own.
