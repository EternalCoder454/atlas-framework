---
title: SecondaryButton
summary: An AtlasButton preset as a soft tinted pill with a hairline border.
section: Buttons
---

SecondaryButton is [AtlasButton](atlas-button.md) with `prominent: false`: a soft pill with a hairline border for the actions beside the main one ([PrimaryButton](primary-button.md)). The properties, states and enums are AtlasButton's; see its page.

SecondaryButton is a Qt Quick Templates `AbstractButton` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html)); its inherited properties (`text`, `icon`, `checkable`, `checked`, `clicked`) work as usual.

## Example

```qml
SecondaryButton { text: qsTr("Cancel"); onClicked: close() }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accent` | `color` (read-only) | `AtlasStyle.accent` | The accent colour, for custom content. |
| `busy` | `bool` | `false` | Something is in progress: shows a spinner in place of the symbol and takes no presses. |
| `prominent` | `bool` | `false` | Same as `variant: AtlasButton.Prominent`. Ignored when `variant` is not Default. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | A Material Symbol drawn instead of `icon.name`; 0 for none. |
| `textTint` | `color` (read-only) | the theme's text colour | The normal text colour, for custom content. |
| `variant` | `int` (AtlasButton.Variant) | `AtlasButton.Default` | The look. A variant other than Default wins over `prominent`. |

## Enums

### Variant

| Value | Description |
|---|---|
| `SecondaryButton.Default` | Control fill and a hairline border; `prominent` decides the look. |
| `SecondaryButton.Prominent` | Strong accent fill: the one main action of a view. |
| `SecondaryButton.Destructive` | Error-coloured text and border on a faint error fill. |
| `SecondaryButton.Ghost` | No fill and no border until hover. |

> [!NOTE]
> New code can use `AtlasButton` with `variant` directly; PrimaryButton, SecondaryButton and TextButton stay supported.
