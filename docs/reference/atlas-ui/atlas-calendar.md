---
title: AtlasCalendar
summary: A month grid for choosing a day, with keyboard navigation and optional date limits.
section: Fields and pickers
since: "1.4.0"
---

AtlasCalendar names the month in a header with previous and next buttons, then shows the weekday names and six rows of days. The first day of the week and the names come from `locale`. Today is ringed, the selected day is filled with the accent, and days outside `minimumDate` to `maximumDate` are disabled. An invalid Date (`new Date(NaN)`) means "no date": no selection, no bound. For a field that opens a calendar, use [AtlasDatePicker](atlas-date-picker.md).

AtlasCalendar is a Qt Quick Templates `Control`; its inherited properties work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-control.html>.

## Example

```qml
AtlasCalendar {
    minimumDate: new Date()
    onActivated: date => booking.day = date
}
```

> [!NOTE]
> Dates the calendar makes, and hands to `activated`, are local noon of the day, so time zones and DST never move them.

## Keyboard

The calendar holds focus, not each day. Return or Space chooses the focused day.

- Left and Right: a day (swapped in right-to-left layouts).
- Up and Down: a week.
- Home and End: the start and end of the week.
- PageUp and PageDown: a month.

A move stops at the bounds.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `maximumDate` | `date` | invalid (no limit) | The latest day that can be chosen. |
| `minimumDate` | `date` | invalid (no limit) | The earliest day that can be chosen. |
| `month` | `int` | the selected date's month, else today's | The month shown (0 is January). |
| `selectedDate` | `date` | invalid (none) | The chosen day. |
| `today` | `date` | the current day | The day that is ringed. Set it only to make a picture or test repeatable. |
| `year` | `int` | the selected date's year, else today's | The year of the month shown. |

> [!NOTE]
> A user's edit does not end a binding on `selectedDate`, `month` or `year` (a day, the month buttons, PageUp and PageDown, the arrow keys). If `onActivated` stores the day, the binding follows the model; if the app ignores it, the property returns to the model's one turn of the event loop later. A new `selectedDate` from the app turns the month to it without holding anything, and `showDate()` called by the app turns it too. With the default `month` and `year`, both go on following the selection afterwards; if the app set `month` or `year` itself, `showDate()` writes them as it did in 1.4.0 (the app asked for it). A handler or `onXChanged` that reads it sees the new value at once. A literal value or no binding keeps the user's edit.

## Signals

| Name | Description |
|---|---|
| `activated(date date)` | A day was chosen by click, Return or Space. `selectedDate` is set too. |

## Methods

| Signature | Description |
|---|---|
| `showDate(QDateTime d): QVariant` | Turns to the month of `d` without selecting it. Does nothing for an invalid date. |
