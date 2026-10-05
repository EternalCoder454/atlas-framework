---
title: AtlasDatePicker
summary: A date field that shows the chosen date and opens a calendar in a raised card.
section: Fields and pickers
since: "1.4.0"
---

AtlasDatePicker is a field like [AtlasComboBox](atlas-combo-box.md) that shows the chosen date and opens an [AtlasCalendar](atlas-calendar.md). An invalid Date (`new Date(NaN)`) means "no date": the field shows `placeholderText`. Choosing a day sets `selectedDate`, emits `edited` and closes the card. Escape closes it too, and focus returns to the field.

AtlasDatePicker is a Qt Quick Templates `Control`; its inherited properties work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-control.html>.

## Example

```qml
AtlasDatePicker {
    selectedDate: new Date(2026, 2, 15)
    minimumDate: new Date(2026, 0, 1)
    clearable: true
    onEdited: task.due = selectedDate
}
```

## Keyboard

On the field, Alt+Down, Return or Space open the card. With `clearable` and a date set, Delete or Backspace clears it.

## Accessibility

Name it with `Accessible.name` (what the date is for). The date itself is spoken as the description.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `clearable` | `bool` | `false` | A clear button on the field (and Delete or Backspace) while a date is set. |
| `format` | `var` | `Locale.ShortFormat` | How the date reads in the field: a `Locale` format, or a format string. |
| `maximumDate` | `date` | invalid (no limit) | The latest day that can be chosen. |
| `minimumDate` | `date` | invalid (no limit) | The earliest day that can be chosen. |
| `opened` | `bool` (read-only) | `false` | The calendar card is open. |
| `placeholderText` | `string` | `qsTr("Pick a date")` | Shown while there is no date. |
| `selectedDate` | `date` | invalid (none) | The chosen day. |
| `today` | `date` | the current day | The day that is ringed in the calendar. |

> [!NOTE]
> A day chosen or cleared by the user does not end a binding on `selectedDate`. If `onEdited` stores it, the binding follows the model; if the app ignores it, `selectedDate` returns to the model's one turn of the event loop later. A handler or `onXChanged` that reads it sees the new value at once. A literal value or no binding keeps the user's edit.

## Signals

| Name | Description |
|---|---|
| `edited()` | The user changed `selectedDate` (a day chosen or cleared). Not emitted when the app sets it. |

## Methods

| Signature | Description |
|---|---|
| `close(): QVariant` | Closes the calendar card. |
| `open(): QVariant` | Opens the calendar card. |
