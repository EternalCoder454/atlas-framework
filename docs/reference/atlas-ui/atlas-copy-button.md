---
title: AtlasCopyButton
summary: A small icon button that copies its text to the clipboard and shows a check mark for a moment.
section: Buttons
since: "1.4.0"
---

AtlasCopyButton copies `text` to the clipboard through [AtlasClipboard](atlas-clipboard.md) and shows a check mark and the tooltip "Copied" for 1.5 seconds. It is a [ToolbarButton](toolbar-button.md), and Tab reaches it. Under reduced motion there is no fade: the symbol just swaps. With `label` set it is a text button ("Copy Details") that swaps its text to `copiedLabel` after a copy.

## Example

```qml
AtlasCopyButton { text: command.text }
AtlasCopyButton { text: token; onCopied: toast.show(qsTr("Token copied")) }
AtlasCopyButton { text: details; label: qsTr("Copy Details") }
```

`text` is what is copied, so the button names itself "Copy" (or `label`) for screen readers, and says "Copied" (or `copiedLabel`) after a copy. In text mode the tooltip is dropped, since the label says it, and the button keeps the width of the wider of the two texts so nothing jumps. The properties below come from ToolbarButton.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `copiedLabel` | `string` | `qsTr("Copied")` | The text shown for 1.5 seconds after a copy in text mode; also what the screen reader announces. |
| `focusable` | `bool` | `true` | Lets Tab reach the button. (ToolbarButton defaults to `false`.) |
| `iconRotation` | `real` | `0` | Turns the icon, for a chevron that points down once opened. |
| `shortcutText` | `string` | `""` | The shortcut as shown to people, such as "Ctrl+B". |
| `label` | `string` | `""` | Text beside the icon ("Copy Details"). Empty keeps the icon-only button. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `Symbols.ContentCopy`, `Symbols.Check` while done | The icon. The button sets it itself. |

## Signals

| Name | Description |
|---|---|
| `copied()` | Emitted after each copy. |
