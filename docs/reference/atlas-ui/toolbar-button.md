---
title: ToolbarButton
summary: A small icon button for toolbars that never takes the editor's focus.
section: Buttons
---

ToolbarButton is a small icon button for formatting toolbars (Bold, Italic, ...). It never takes the keyboard focus from the editor, unless `focusable` is set. `checkable` makes it a toggle, drawn with the selection fill, an accent border and an accent icon while checked. The tooltip is the text plus the optional `shortcutText`: "Bold (Ctrl+B)".

ToolbarButton is a Qt Quick Templates `AbstractButton` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html)); its inherited properties (`text`, `icon`, `action`, `checkable`, `checked`, `clicked`) work as usual. With an `action` (an [AtlasAction](atlas-action.md) or a plain Qt `Action`) the button follows it: the tooltip is `action.toolTip`, else `action.text`, else `text`; `action.symbol` is the symbol when it has one; and the action's shortcut is shown when `shortcutText` is empty. [AtlasToolbar](atlas-toolbar.md) builds a bar of these from a list of actions.

## Example

```qml
ToolbarButton {
    symbol: Symbols.FormatBold
    text: qsTr("Bold")
    shortcutText: "Ctrl+B"
    checkable: true
    onClicked: editor.toggleBold()
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `focusable` | `bool` | `false` | True lets Tab reach the button (with the focus ring; Space and Return press it); false keeps the editor's focus. |
| `iconRotation` | `real` | `0` | Turns the icon by this many degrees, for a chevron that points down once opened. |
| `shortcutText` | `string` | `""` | The shortcut as shown to people ("Ctrl+B"). It only describes. When empty, the action's shortcut is shown. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | the action's `symbol`, else `0` | A Material Symbol drawn instead of `icon.name`. |
