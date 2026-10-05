---
title: AtlasTextField
summary: A single-line text field with an error message, a clear button, a prefix and suffix, a character counter and validation messages.
section: Fields and pickers
since: "1.3.0"
---

A single-line text field with small rounded corners, 28 px high (24 compact; it grows with large text). `placeholderText` shows while it is empty. A non-empty `errorText` turns the outline red, tints the field, puts an error symbol at the trailing edge and shows the message below the field. For a password, use [AtlasPasswordField](atlas-password-field.md); for several lines, [AtlasTextArea](atlas-text-area.md).

AtlasTextField is a Qt Quick Controls [`TextField`](https://doc.qt.io/qt-6/qml-qtquick-templates-textfield.html); `text`, `placeholderText`, `validator`, `maximumLength`, `accepted` and the rest work as usual.

## Example

```qml
AtlasTextField {
    placeholderText: qsTr("Name")
    clearable: true
    errorText: text.length === 0 ? qsTr("A name is required") : ""
}
AtlasTextField {
    maximumLength: 40; showCounter: true
    validator: RegularExpressionValidator { regularExpression: /[a-z]+/ }
    invalidText: qsTr("Use lowercase letters only")
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `clearable` | `bool` | `false` | Shows a small cross that empties the field once there is text. |
| `errorText` | `string` | `""` | The message under the field; empty for no error. Shows at once and wins over `invalidText`. |
| `hasError` | `bool` (read-only) | — | `true` while `errorText` or `invalidText` shows. |
| `invalidText` | `string` | `""` | The message for a text the `validator` (or `inputMask`) does not accept. See below for when it shows. |
| `prefix` | `string` | `""` | Fixed, muted text inside the field before what is typed (`"$"`). |
| `rtl` | `bool` (read-only) | — | Whether the layout is mirrored. A `TextField` has no `mirrored` of its own. |
| `showCounter` | `bool` | `false` | Writes "length/max" under the field at its trailing end. Only when `maximumLength` is set. |
| `suffix` | `string` | `""` | Fixed, muted text inside the field after what is typed (`"kg"`). |
| `validateOn` | `string` | `"leaving"` | When `invalidText` first shows: `"leaving"` or `"typing"`. |

## Validation messages

`invalidText` is not shown while the user types, because the unfinished text of an email or URL validator is not an error yet. With `validateOn: "leaving"` it appears once the focus has left the field or Return is pressed. With `validateOn: "typing"` it appears at once. After it has appeared it follows the text live and goes as soon as the text is acceptable. An `errorText` set by the app shows at once and wins.

The Atlas validators are made for this: [AtlasNumberValidator](atlas-number-validator.md) and [AtlasPathValidator](atlas-path-validator.md), plus [AtlasUrlValidator](atlas-url-validator.md) and [AtlasEmailValidator](atlas-email-validator.md).

## Accessibility

A new error message is announced to screen readers when it appears.
