---
title: AtlasTimePicker
summary: A time of day as hours and minutes number fields, with AM/PM in 12-hour mode and an optional day-of-week drop-down.
section: Fields and pickers
since: "1.4.0"
---

A time of day: hours and minutes as two number fields (Up and Down, the wheel, or type a number and press Return; both wrap round), and in 12-hour mode an AM/PM button. With `showDay: true` a drop-down with the days of the week comes first, for a weekly schedule. Minutes snap to `minuteStep` (7 with a step of 5 becomes 5; the last allowed value below 60 is the largest multiple). An out-of-range `hours` or `minutes` is clamped.

AtlasTimePicker is a Qt Quick Controls [`Control`](https://doc.qt.io/qt-6/qml-qtquick-templates-control.html); its inherited properties work as usual.

## Example

```qml
AtlasTimePicker {
    hours: 7; minutes: 30
    minuteStep: 5
    onEdited: alarm.set(hours, minutes)
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `day` | `int` (`Qt.Monday` to `Qt.Sunday`) | `Qt.Monday` | The day of the week. Used with `showDay`. |
| `hours` | `int` | `0` | The hour, 0 to 23, also in 12-hour mode. |
| `minuteStep` | `int` | `1` | The step minutes snap to, 1 to 59. |
| `minutes` | `int` | `0` | The minute, 0 to 59, a multiple of `minuteStep`. |
| `showDay` | `bool` | `false` | Shows a day-of-week drop-down before the time. |
| `use24Hour` | `bool` | from the locale | Shows a 24-hour clock. The default follows the locale's short time format. |

> [!NOTE]
> An out-of-range `hours` or `minutes` is replaced by the corrected value, so a binding to either is broken by it.

## Signals

| Name | Description |
|---|---|
| `edited()` | The user changed the hours, minutes, AM/PM or day. |

## Accessibility

Each part has its own accessible name: hours, minutes, AM or PM, and day.
