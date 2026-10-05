---
title: AtlasUrlValidator
summary: A validator for a text field that accepts a URL with one of a set of schemes.
section: Validators
since: "1.4.0"
---

AtlasUrlValidator is a `QValidator` for a field's `validator`. Acceptable text is a complete URL whose scheme is in `schemes`; `http` and `https` also need a host. Pair it with `AtlasTextField.invalidText` ([AtlasTextField](atlas-text-field.md)) so the field says what is wrong.

Like the other Atlas validators ([AtlasEmailValidator](atlas-email-validator.md), [AtlasPathValidator](atlas-path-validator.md), [AtlasNumberValidator](atlas-number-validator.md)) it rejects text over a fixed length, uses no regular expressions and rejects NUL and other control characters. Intermediate means the user can still type a valid URL.

## Example

```qml
AtlasTextField {
    validator: AtlasUrlValidator { schemes: ["https"] }
    invalidText: qsTr("Enter a web address starting with https://")
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `schemes` | `list<string>` | `["https"]` | The accepted URL schemes, without the colon. |

> [!NOTE]
> Acceptable text is still not safe to splice into a URL or header unencoded. `fixup()` trims surrounding whitespace.
