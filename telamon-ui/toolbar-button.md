---
title: ToolbarButton
summary: A small icon button for toolbars that never takes the editor's focus.
section: Buttons
---

ToolbarButton is a small icon button for formatting toolbars (Bold, Italic, ...). It never takes the keyboard focus from the editor, unless `focusable` is set. `checkable` makes it a toggle, drawn with the selection fill, an accent border and an accent icon while checked. The tooltip is the text plus the optional `shortcutText`: "Bold (Ctrl+B)".

ToolbarButton is a Qt Quick Templates `AbstractButton` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html)); its inherited properties (`text`, `icon`, `action`, `checkable`, `checked`, `clicked`) work as usual. With an `action` (a [TelamonAction](telamon-action.md) or a plain Qt `Action`) the button follows it: the tooltip is `action.toolTip`, else `action.text`, else `text`; `action.symbol` is the symbol when it has one; and the action's shortcut is shown when `shortcutText` is empty. [TelamonToolbar](telamon-toolbar.md) builds a bar of these from a list of actions.

`round` draws a circle: width equals height and the corners are half of it; the hover, press and checked layers and the focus ring follow it. `tipSide` puts the tooltip beside the button (`Start` or `End`), flipping to the other side when there is no room and swapping under a right-to-left layout; it shows for hover and for keyboard focus. `toolTipText` changes only the tooltip's name part: the spoken name stays the action's or the `text`, and the shortcut still appends ("Bold (Ctrl+B)"). `focusOnClick: false` with `focusable: true` makes the button a Tab stop that a click does not focus.

An action with a `menu` or a `popover` (see [TelamonAction](telamon-action.md)) makes a button that opens it instead of triggering: the click never emits the action's `triggered()`, the button is a `ButtonMenu` for screen readers and is drawn checked while the menu or popover is open. A menu opens below the button (beside it in a vertical strip); a popover gets the button as its `target`. When a menu closes, a button that had the keyboard focus gets it back, unless the user clicked into something else.

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
| `focusOnClick` | `bool` | `true` | With `focusable`, `false` makes the button a Tab stop that a click does not focus. With `focusable: false` it has no effect. |
| `iconRotation` | `real` | `0` | Turns the icon by this many degrees, for a chevron that points down once opened. |
| `round` | `bool` | `false` | A circle: width equals height and the corner radius is half. |
| `shortcutText` | `string` | `""` | The shortcut as shown to people ("Ctrl+B"). It only describes. When empty, the action's shortcut is shown. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | the action's `symbol`, else `0` | A Material Symbol drawn instead of `icon.name`. |
| `tipSide` | `int` (`ToolbarButton.TipSide`) | `ToolbarButton.Below` | Where the tooltip opens. |
| `toolTipText` | `string` | `""` | The tooltip's name part, in place of the action's or the button's text. It does not change the accessible name. |

## Enums

### TipSide

| Value | Description |
|---|---|
| `ToolbarButton.Below` | Below the button (the default tooltip). |
| `ToolbarButton.Start` | Beside the button, at its leading side. |
| `ToolbarButton.End` | Beside the button, at its trailing side. |
