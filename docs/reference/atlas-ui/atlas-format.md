---
title: AtlasFormat
summary: A singleton that formats sizes, speeds, percentages, numbers, durations and dates alike in every Atlas app and in the user's language.
section: Services
since: "1.4.0"
---

AtlasFormat shows sizes, speeds, percentages, numbers, durations and dates one way, so every Atlas app spells them alike. Every function takes an optional last `locale` argument (`"de_DE"`, `"en"`); without one it uses the application's `QLocale`.

## Example

```qml
Column {
    Label { text: AtlasFormat.bytes(file.size) }                  // "1.5 MiB"
    Label { text: AtlasFormat.percent(progress) }                 // "42%"
    Label { text: AtlasFormat.duration(remaining) }               // "1 h 5 min"
    Label { text: AtlasFormat.date(modified, "relative") }        // "5 minutes ago"
}
```

> [!NOTE]
> The unit and wording strings belong to Atlas.Ui and are translated with its catalogue. A translation follows the application's language, not the `locale` argument: that one only decides digits, separators and date formats.

A value that is not a number (NaN, infinity), or a date that is invalid, gives `""`, never `"NaN"`. A negative size or duration keeps its sign. An unknown duration or date `style` is treated as the default one.

## Methods

Each method can be called with fewer arguments; the later ones take the defaults named below.

| Signature | Description |
|---|---|
| `bytes(double n): QString` | Formats a byte count with IEC units: `"0 B"`, `"512 B"`, `"1.5 KiB"`, `"3.2 GiB"`. `precision` is 0 to 10 (default 1); other values are clamped. |
| `bytes(double n, int precision): QString` | Same, with the extra argument set. |
| `bytes(double n, int precision, QString locale): QString` | Same, with the extra argument set. |
| `bytes(double n, int precision, QString locale, QString system): QString` | `system` is `"iec"` (default) or `"si"`. `"si"` counts in 1000 and writes `B`, `kB`, `MB`, `GB`, `TB`, `PB`: 1 200 000 000 is `"1.2 GB"`. Any other name is `"iec"`. |
| `bytesPerSecond(double n): QString` | Like `bytes`, as a speed: `"1.5 MiB/s"`. `precision` is clamped to 0 to 10 the same way. |
| `bytesPerSecond(double n, int precision): QString` | Same, with the extra argument set. |
| `bytesPerSecond(double n, int precision, QString locale): QString` | Same, with the extra argument set. |
| `bytesPerSecond(double n, int precision, QString locale, QString system): QString` | The same as `bytes`, with `/s`: `"2.5 MB/s"` for `"si"`. |
| `date(QDateTime d): QString` | Formats a date. `style` is `"short"` (default), `"long"`, `"dateTime"`, `"time"`, `"atTime"` ("today at 14:05"), `"relative"` ("just now", "3 hours ago", "yesterday", "in 5 minutes"; a date a week or more away shows its short form), `"longAtTime"` ("Thursday, 1 January 2099 at 03:00": the long date with the weekday, then the short time), `"atTimeSentence"` ("Today at 9:41") or `"relativeSentence"` ("Just now"); the two sentence styles are `atTime` and `relative` with the first letter in upper case by the locale's rules, for the start of a sentence. `atTime` gives "yesterday at 14:05" for the previous day and "the short date, then \"at\" and the time" for any other day. `atTime` and `relative` compare with `now` (default: the current time). An invalid date gives `""`. |
| `date(QDateTime d, QString style): QString` | Same, with the extra argument set. |
| `date(QDateTime d, QString style, QString locale): QString` | Same, with the extra argument set. |
| `date(QDateTime d, QString style, QString locale, QDateTime now): QString` | Same, with the extra argument set. |
| `duration(double seconds): QString` | Formats a number of seconds. `style` is `"short"` (default; "1 h 5 min"), `"long"` ("1 hour 5 minutes") or `"clock"` ("1:05:09", "05:09"). The largest non-zero unit is shown, plus the next one only when it is not zero, in both `short` and `long`: 3605 s gives "1 h" and 65 s gives "1 min 5 s". The input is clamped. A negative duration keeps its sign. |
| `duration(double seconds, QString style): QString` | Same, with the extra argument set. |
| `duration(double seconds, QString style, QString locale): QString` | Same, with the extra argument set. |
| `number(double n): QString` | Formats a number grouped by the locale. `precision` -1 (default; any negative value) is the shortest exact form, up to 6 decimals; otherwise 0 to 10, clamped. |
| `number(double n, int precision): QString` | Same, with the extra argument set. |
| `number(double n, int precision, QString locale): QString` | Same, with the extra argument set. |
| `percent(double fraction): QString` | Formats a fraction as a percentage: 0.423 gives `"42%"` (en) or `"42 %"` (de). `precision` defaults to 0 and is clamped to 0 to 10. |
| `percent(double fraction, int precision): QString` | Same, with the extra argument set. |
| `percent(double fraction, int precision, QString locale): QString` | Same, with the extra argument set. |
