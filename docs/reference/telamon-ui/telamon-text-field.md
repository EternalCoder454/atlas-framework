---
title: TelamonTextField
summary: A single-line text field with an error message, a clear button, a prefix and suffix, a character counter and validation messages.
section: Fields and pickers
since: "1.3.0"
---

A single-line text field with small rounded corners, 28 px high (24 compact; it grows with large text). `placeholderText` shows while it is empty. A non-empty `errorText` turns the outline red, tints the field, puts an error symbol at the trailing edge and shows the message below the field. For a password, use [TelamonPasswordField](telamon-password-field.md); for several lines, [TelamonTextArea](telamon-text-area.md).

TelamonTextField is a Qt Quick Controls [`TextField`](https://doc.qt.io/qt-6/qml-qtquick-templates-textfield.html); `text`, `placeholderText`, `validator`, `maximumLength`, `accepted` and the rest work as usual.

## Example

```qml
TelamonTextField {
    placeholderText: qsTr("Name")
    clearable: true
    errorText: text.length === 0 ? qsTr("A name is required") : ""
}
TelamonTextField {
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
| `invalidText` | `string` | `""` | The message for a text the `validator` (or `inputMask`) does not accept. See below for when it shows. Since 1.4.0. |
| `prefix` | `string` | `""` | Fixed, muted text inside the field before what is typed (`"$"`). Since 1.4.0. |
| `rtl` | `bool` (read-only) | — | Whether the layout is mirrored. A `TextField` has no `mirrored` of its own. |
| `showCounter` | `bool` | `false` | Writes "length/max" under the field at its trailing end. Only when `maximumLength` is set. Since 1.4.0. |
| `suffix` | `string` | `""` | Fixed, muted text inside the field after what is typed (`"kg"`). Since 1.4.0. |
| `validateOn` | `string` | `"leaving"` | When `invalidText` first shows: `"leaving"` or `"typing"`. Since 1.4.0. |

## Validation messages

`invalidText` is not shown while the user types, because the unfinished text of an email or URL validator is not an error yet. With `validateOn: "leaving"` it appears once the focus has left the field or Return is pressed. With `validateOn: "typing"` it appears at once. After it has appeared it follows the text live and goes as soon as the text is acceptable. An `errorText` set by the app shows at once and wins.

The Telamon validators are made for this: [TelamonNumberValidator](telamon-number-validator.md) and [TelamonPathValidator](telamon-path-validator.md), plus [TelamonUrlValidator](telamon-url-validator.md) and [TelamonEmailValidator](telamon-email-validator.md).

## Accessibility

A new error message is announced to screen readers when it appears.
