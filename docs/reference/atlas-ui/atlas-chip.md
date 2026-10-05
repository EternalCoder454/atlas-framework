---
title: AtlasChip
summary: A small label for a tag, a filter or a value; plain, checkable or closable.
section: Buttons
since: "1.4.0"
---

AtlasChip is plain (just `text`), checkable, or closable, or a mix. A checkable chip is a filter: the checked chip has the selection fill, an accent border and a check mark instead of its symbol, and is fully round, while an unchecked one has 8 px corners. A plain (not checkable) chip is always fully round. A `closable` chip has an x button; the app removes the chip when `closeRequested()` fires. Put chips that belong together in an [AtlasChipGroup](atlas-chip-group.md).

AtlasChip is a Qt Quick Templates `AbstractButton`; its inherited properties (`text`, `checkable`, `checked`, `toggled`) work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html>.

## Example

```qml
AtlasChip { text: qsTr("Unread"); checkable: true; onToggled: app.filterUnread = checked }
AtlasChip { text: tag; closable: true; onCloseRequested: tags.remove(index) }
```

## Keyboard

A chip is a Tab stop (inside an AtlasChipGroup only one chip is). On a closable chip with focus, Delete or Backspace emits `closeRequested()`.

## Accessibility

The accessible name is the text. The close button's is "Remove" followed by the text.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `closable` | `bool` | `false` | Shows an x button; it, or Delete/Backspace, emits `closeRequested()`. |
| `showsCheck` | `bool` (read-only) | — | `true` when the chip is checkable and checked, so it shows a check mark. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | A Material Symbol before the text; 0 for none. |
| `tint` | `color` (read-only) | the theme's text colour | The chip's text colour, for custom content. |

## Signals

| Name | Description |
|---|---|
| `closeRequested()` | The user asked to remove the chip. The app removes it. |
