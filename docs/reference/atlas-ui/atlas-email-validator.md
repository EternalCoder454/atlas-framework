---
title: AtlasEmailValidator
summary: A validator for an email address field: one @, a dotted domain and a bounded length.
section: Validators
since: "1.4.0"
---

AtlasEmailValidator is a Qt `QValidator` for a field's `validator`, with Acceptable, Intermediate and Invalid as Qt defines them. It checks a pragmatic address: one `@`, a local part, and a domain with a dot, at most 254 characters. The local part may not contain `,;<>"()[]\:?&%#` or format characters. It uses no regular expressions. Pair it with `AtlasTextField.invalidText`, see [AtlasTextField](atlas-text-field.md).

## Example

```qml
AtlasTextField {
    placeholderText: qsTr("Email")
    validator: AtlasEmailValidator {}
    invalidText: qsTr("Enter an address like name@example.com")
}
```

> [!NOTE]
> Acceptable text is still not safe to splice into a URL or header unencoded.

It has no properties of its own.
