---
title: AtlasCopyButton
summary: A small icon button that copies its text to the clipboard and shows a check mark for a moment.
section: Buttons
since: "1.4.0"
---

AtlasCopyButton copies `text` to the clipboard through [AtlasClipboard](atlas-clipboard.md) and shows a check mark and the tooltip "Copied" for 1.5 seconds. It is a [ToolbarButton](toolbar-button.md), and Tab reaches it. Under reduced motion there is no fade: the symbol just swaps.

## Example

```qml
AtlasCopyButton { text: command.text }
AtlasCopyButton { text: token; onCopied: toast.show(qsTr("Token copied")) }
```

`text` is what is copied, so the button names itself "Copy" for screen readers, and says "Copied" after a copy. The properties below come from ToolbarButton.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `focusable` | `bool` | `true` | Lets Tab reach the button. (ToolbarButton defaults to `false`.) |
| `iconRotation` | `real` | `0` | Turns the icon, for a chevron that points down once opened. |
| `shortcutText` | `string` | `""` | The shortcut as shown to people, such as "Ctrl+B". |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `Symbols.ContentCopy`, `Symbols.Check` while done | The icon. The button sets it itself. |

## Signals

| Name | Description |
|---|---|
| `copied()` | Emitted after each copy. |
