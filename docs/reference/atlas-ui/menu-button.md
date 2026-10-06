---
title: MenuButton
summary: A SecondaryButton with a chevron that opens a menu of the items inside it.
section: Buttons
---

MenuButton is a [SecondaryButton](secondary-button.md) with a chevron that opens a menu on a click; a second click on the button closes it. Put `QQC2.MenuItem` children inside it; they become the menu's items. With an `action` it shows the action's text and, when it has one, its symbol. For a main action joined to a menu use [AtlasSplitButton](atlas-split-button.md).

MenuButton is a Qt Quick Templates `AbstractButton` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html)); the properties it shares with [AtlasButton](atlas-button.md) are described there.

## Example

```qml
MenuButton {
    text: qsTr("Sort")
    QQC2.MenuItem { text: qsTr("By name"); onTriggered: sortByName() }
    QQC2.MenuItem { text: qsTr("By size"); onTriggered: sortBySize() }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accent` | `color` (read-only) | `AtlasStyle.accent` | The accent colour, for custom content. |
| `busy` | `bool` | `false` | Something is in progress: shows a spinner in place of the symbol and takes no presses. |
| `items` | `list<Item>` (read-only) | — | The default property: the `QQC2.MenuItem` children shown in the menu. |
| `prominent` | `bool` | `false` | Same as `variant: AtlasButton.Prominent`. Ignored when `variant` is not Default. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | A Material Symbol drawn instead of `icon.name`; 0 for none. |
| `textTint` | `color` (read-only) | the theme's text colour | The normal text colour, for custom content. |
| `variant` | `int` (AtlasButton.Variant) | `AtlasButton.Default` | The look. A variant other than Default wins over `prominent`. |

## Enums

### Variant

| Value | Description |
|---|---|
| `MenuButton.Default` | Control fill and a hairline border; `prominent` decides the look. |
| `MenuButton.Prominent` | Strong accent fill: the one main action of a view. |
| `MenuButton.Destructive` | Error-coloured text and border on a faint error fill. |
| `MenuButton.Ghost` | No fill and no border until hover. |

## Accessibility

The button is a menu button for screen readers. Its description is "Expanded" or "Collapsed", and a change of it is announced when the menu opens or closes.
