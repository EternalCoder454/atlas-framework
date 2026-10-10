---
title: TelamonButton
summary: The button every Telamon app uses, with four variants, an optional symbol and a busy state.
section: Buttons
---

TelamonButton is the shared base of `PrimaryButton` and `SecondaryButton` (and `MenuButton`, which builds on `SecondaryButton`), which are this button with a preset look. [TextButton](text-button.md) is not one of them: it is its own link-styled `AbstractButton` and has no `variant`. It has small rounded corners (4 px, 6 px while pressed), the standard control height, and grey hover and press states.

TelamonButton is a Qt Quick Templates `AbstractButton`; its inherited properties (`text`, `icon`, `checkable`, `checked`, `clicked`) work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html>.

## Example

```qml
TelamonButton { text: qsTr("Save"); variant: TelamonButton.Prominent }
TelamonButton { text: qsTr("Delete"); variant: TelamonButton.Destructive; symbol: Symbols.Delete }
TelamonButton { text: qsTr("Sync"); busy: model.syncing }
```

`variant` chooses the look. `prominent: true` is the same as `variant: Prominent` and stays supported. A variant other than Default wins; with Default, `prominent` decides.

States share one layer for every variant: hover and press lay a grey overlay over the fill, `checked` (with `checkable`) shows the selection fill with an accent border and accent text, a disabled button has readable disabled text, and the keyboard focus ring is drawn outside.

> [!NOTE]
> While `busy`, the button takes no mouse press and no Return, Enter or Space press, and describes itself as "Busy" to screen readers. A screen reader's press does not click it either. The busy spinner replaces the symbol, or comes before the text when there is no symbol, so the button grows a little.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accent` | `color` (read-only) | `TelamonStyle.accent` | The accent colour, for custom content. |
| `busy` | `bool` | `false` | Something is in progress: shows a spinner and takes no presses. |
| `maximumWidth` | `real` | `0` | The widest the button asks for; a longer text is elided. 0 means no limit. Since 1.5.0. |
| `prominent` | `bool` | `false` | Same as `variant: TelamonButton.Prominent`. Ignored when `variant` is not Default. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | A Material Symbol drawn instead of `icon.name`; 0 for none. |
| `textTint` | `color` (read-only) | the theme's text colour | The normal text colour, for custom content. |
| `variant` | `int` (TelamonButton.Variant) | `TelamonButton.Default` | The look. |

## Enums

### Variant

| Value | Description |
|---|---|
| `TelamonButton.Default` | Control fill and a hairline border. Leaves the choice to `prominent`. |
| `TelamonButton.Prominent` | Strong accent fill: the one main action of a view. |
| `TelamonButton.Destructive` | Error-coloured text and border on a faint error fill. |
| `TelamonButton.Ghost` | No fill and no border until hover. |
