---
title: TelamonPasswordStrength
summary: A strength bar and label for a password, shown under a TelamonPasswordField; the scoring stays in the app.
section: Fields and pickers
since: "1.5.0"
---

TelamonPasswordStrength shows how strong a password is: a bar of four cells that fill with `score`, and a label beside it. It only shows a result; the app does the scoring (a length rule, zxcvbn, a server's verdict) and passes the number. Colour is not the only cue: the label and the number of filled cells say the same.

## Example

```qml
TelamonPasswordField { id: pw; placeholderText: qsTr("Password") }
TelamonPasswordStrength { score: app.strengthOf(pw.text) }
```

## Accessibility

Screen readers get a progress bar. Its accessible name is `label, score of 4` ("Good, 3 of 4"); with nothing typed it is "Password strength".

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `score` | `int` | `-1` | 0 (very weak) to 4 (strong). -1, or any value below 0 or not a whole number, means nothing typed: an empty bar and no label. A value above 4 counts as 4. Scores 0 and 1 are drawn in the error colour, 2 in the warning colour, 3 and 4 in the success colour. |
| `text` | `string` | `""` | Replaces the built-in label ("Very weak", "Weak", "Fair", "Good", "Strong"). Empty keeps it. |
