---
title: AtlasEmptyState
summary: What a list shows when it has nothing: a large symbol, a title, an explanation and an optional action button, centred.
section: Feedback and status
---

AtlasEmptyState has a large symbol, a title, a line of explanation, and an optional action button, all centred. Fill the list's area with it and show it when the list is empty. The button appears when `actionText` is set and emits `triggered()`.

## Example

```qml
AtlasEmptyState {
    anchors.fill: parent
    visible: list.count === 0
    symbol: Symbols.FolderOpen
    title: qsTr("No files")
    text: qsTr("Files you download will show up here.")
    actionText: qsTr("Open Downloads")
    actionSymbol: Symbols.FolderOpen
    onTriggered: openDownloads()
}
```

## Accessibility

It is a group: the title is its name and the text its description.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `actionSymbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | A symbol shown on the action button; 0 for none. |
| `actionText` | `string` | `""` | The button's label; empty for no button. |
| `iconName` | `string` | `""` | A theme icon by name, instead of `symbol`. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | The large Material Symbol. |
| `text` | `string` | `""` | The line of explanation. |
| `title` | `string` | `""` | The title, in bold. |

## Signals

| Name | Description |
|---|---|
| `triggered()` | The action button was used. |
