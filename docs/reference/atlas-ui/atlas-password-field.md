---
title: AtlasPasswordField
summary: A rounded password field with an eye that shows the text, an error message, and automatic hiding when focus leaves.
section: Fields and pickers
since: "1.4.0"
---

A rounded single-line password field: [AtlasTextField](atlas-text-field.md)'s look, with the text masked and an eye at the trailing end that shows or hides it. The text goes back to hidden when the field loses the keyboard focus (to anything but the eye itself), when its window goes to the background, and when the field is hidden or disabled; the selection goes with it. Copy and cut do nothing while the text is hidden.

AtlasPasswordField is a Qt Quick Controls [`TextField`](https://doc.qt.io/qt-6/qml-qtquick-templates-textfield.html); its inherited properties and signals (`text`, `placeholderText`, `accepted`) work as usual.

## Example

```qml
AtlasPasswordField {
    placeholderText: qsTr("Password")
    errorText: text.length < 8 ? qsTr("Use at least 8 characters") : ""
    onAccepted: confirm.forceActiveFocus()
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `errorText` | `string` | `""` | The message under the field; empty for no error. |
| `hasError` | `bool` (read-only) | — | `true` when `errorText` is not empty. |
| `revealed` | `bool` (read-only) | — | `true` while the text is shown in clear. Only true while the field (or its eye) has the keyboard focus in the active window, whatever asked for it. |
| `rtl` | `bool` (read-only) | — | Whether the layout is mirrored. A `TextField` has no `mirrored` of its own. |

## Methods

| Signature | Description |
|---|---|
| `hide()` | Masks the text again. |
| `reveal()` | Shows the text in clear while the field (or its eye) has the keyboard focus. Does nothing when it hasn't, or while the field is disabled. |

> [!NOTE]
> Don't set `echoMode` or `inputMethodHints`: the field sets them itself, and setting either can show the password or let the keyboard remember it (`lint-app.sh` warns). There is no `clearable`. Keep the password itself out of `errorText`, which screen readers speak.
