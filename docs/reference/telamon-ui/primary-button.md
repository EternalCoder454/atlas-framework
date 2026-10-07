---
title: PrimaryButton
summary: A TelamonButton preset as a filled accent button, for the main action.
section: Buttons
---

PrimaryButton is [TelamonButton](telamon-button.md) with `prominent: true`: an `accentStrong` button with `accentStrongText` text (white in Light, near-black in Dark) and 4 px corners, for the one main action of a view. The properties, states and enums are TelamonButton's; see its page. Use [SecondaryButton](secondary-button.md) for the other actions and [TextButton](text-button.md) for a link-style action.

PrimaryButton is a Qt Quick Templates `AbstractButton` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html)); its inherited properties (`text`, `icon`, `checkable`, `checked`, `clicked`) work as usual.

## Example

```qml
PrimaryButton { text: qsTr("Save"); onClicked: save() }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accent` | `color` (read-only) | `TelamonStyle.accent` | The accent colour, for custom content. |
| `busy` | `bool` | `false` | Something is in progress: shows a spinner in place of the symbol and takes no presses. |
| `prominent` | `bool` | `true` | The preset: the button is drawn prominent. Ignored when `variant` is not Default. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | A Material Symbol drawn instead of `icon.name`; 0 for none. |
| `textTint` | `color` (read-only) | the theme's text colour | The normal text colour, for custom content. |
| `variant` | `int` (TelamonButton.Variant) | `TelamonButton.Default` | The look. A variant other than Default wins over `prominent`. |

## Enums

### Variant

| Value | Description |
|---|---|
| `PrimaryButton.Default` | Control fill and a hairline border; `prominent` decides the look. |
| `PrimaryButton.Prominent` | Strong accent fill: the one main action of a view. |
| `PrimaryButton.Destructive` | Error-coloured text and border on a faint error fill. |
| `PrimaryButton.Ghost` | No fill and no border until hover. |

> [!NOTE]
> New code can use `TelamonButton` with `variant` directly; PrimaryButton, SecondaryButton and TextButton stay supported.
