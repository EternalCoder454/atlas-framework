---
title: AtlasLabel
summary: Text in one of the Atlas looks (body, title, heading, caption, monospace) so an app never hard-codes sizes and weights.
section: Text and code
since: "1.4.0"
---

Text in one of the looks of Atlas apps, picked by `textStyle`. Use it instead of a bare `Label` so sizes, weights and colours come from [AtlasStyle](atlas-style.md). The text is plain unless `textFormat` is set.

AtlasLabel is a Qt Quick Controls [`Label`](https://doc.qt.io/qt-6/qml-qtquick-controls-label.html); wrapping, eliding, alignment and the rest work as usual.

## Example

```qml
AtlasLabel { text: qsTr("Downloads"); textStyle: AtlasLabel.Title }
AtlasLabel { text: path; textStyle: AtlasLabel.Mono; elide: Text.ElideMiddle }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `textStyle` | `int` (AtlasLabel.TextStyle) | `AtlasLabel.Body` | The look of the text. |

Title and Heading are headings for a screen reader; other styles are static text. Secondary information ("Step 2 of 2") is Caption, or [`AtlasStyle.textMuted`](atlas-style.md#properties).

## Enums

### TextStyle

| Value | Description |
|---|---|
| `AtlasLabel.Body` | The application font at body size. The default. |
| `AtlasLabel.Title` | A page title: large and bold. |
| `AtlasLabel.Heading` | A section heading: bold, in the full text colour. |
| `AtlasLabel.Caption` | Small and muted: footers and hints. |
| `AtlasLabel.Mono` | The fixed-width font: versions, paths, commands. |
| `AtlasLabel.WindowTitle` | A window's title: semibold, at body size. The header bar's title. |
| `AtlasLabel.Code` | The same as `Mono`. |
