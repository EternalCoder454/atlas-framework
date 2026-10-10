---
title: TelamonLabel
summary: Text in one of the Telamon looks (body, title, heading, caption, monospace) so an app never hard-codes sizes and weights.
section: Text and code
since: "1.4.0"
---

Text in one of the looks of Telamon apps, picked by `textStyle`. Use it instead of a bare `Label` so sizes, weights and colours come from [TelamonStyle](telamon-style.md). The text is plain unless `textFormat` is set.

TelamonLabel is a Qt Quick Controls [`Label`](https://doc.qt.io/qt-6/qml-qtquick-controls-label.html); wrapping, eliding, alignment and the rest work as usual.

## Example

```qml
TelamonLabel { text: qsTr("Downloads"); textStyle: TelamonLabel.Title }
TelamonLabel { text: path; textStyle: TelamonLabel.Mono; elide: Text.ElideMiddle }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `textStyle` | `int` (TelamonLabel.TextStyle) | `TelamonLabel.Body` | The look of the text. |

Title and Heading are headings for a screen reader; other styles are static text. Secondary information ("Step 2 of 2") is Caption, or [`TelamonStyle.textMuted`](telamon-style.md#properties).

## Enums

### TextStyle

| Value | Description |
|---|---|
| `TelamonLabel.Body` | The application font at body size. The default. |
| `TelamonLabel.Title` | A page title: large and bold. |
| `TelamonLabel.Heading` | A section heading: bold, in the full text colour. |
| `TelamonLabel.Caption` | Small and muted: footers and hints. |
| `TelamonLabel.Mono` | The fixed-width font: versions, paths, commands. |
| `TelamonLabel.WindowTitle` | A window's title: semibold, at body size. The header bar's title. |
| `TelamonLabel.Code` | The same as `Mono`. |
