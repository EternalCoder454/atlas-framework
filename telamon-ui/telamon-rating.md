---
title: TelamonRating
summary: Zero to five stars with halves drawn, read-only by default, or editable with hover preview, click and keyboard.
section: Fields and pickers
since: "1.4.0"
---

Zero to five stars. `value` is 0 to 5 and halves are drawn (4.5 shows four stars and a half). It is `readOnly` by default, a rating to look at. Set `readOnly: false` to let the user choose: the stars under the pointer preview the choice, and a click sets whole stars and emits `edited()`. `count` adds "(123)" after the stars, the number of ratings behind a value.

TelamonRating is a Qt Quick Controls [`Control`](https://doc.qt.io/qt-6/qml-qtquick-templates-control.html); its inherited properties work as usual.

## Example

```qml
TelamonRating { value: app.rating; count: app.ratingCount }
TelamonRating {
    readOnly: false
    value: review.stars
    onEdited: review.stars = value
    Accessible.name: qsTr("Your rating")
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `count` | `int` | `0` | The number of ratings behind the value. `0` or less shows none. |
| `readOnly` | `bool` | `true` | `false` lets the user choose. |
| `starSize` | `real` | a small-medium icon size | The size of a star. |
| `value` | `real` | `0` | The rating, 0 to 5. Held to that range and rounded to halves. |

> [!NOTE]
> A user's edit does not end a binding on `value`. `value: review.stars` stays bound: if `onEdited` stores the edit, it follows the model; if the app ignores the edit, `value` returns to the model's one turn of the event loop later. A handler or `onXChanged` that reads it sees the new value at once. A literal value or no binding keeps the user's edit.

## Signals

| Name | Description |
|---|---|
| `edited()` | The user changed `value` by click or keyboard. Not emitted for a change from code. |

## Keyboard

When editable, the control is a Tab stop. Left and Right change the value by one (mirrored in right-to-left layouts), Home clears it and End gives five.

## Accessibility

Read-only, screen readers get a static "4.5 out of 5". Editable, they get a slider that can increase and decrease; give it an `Accessible.name`.
