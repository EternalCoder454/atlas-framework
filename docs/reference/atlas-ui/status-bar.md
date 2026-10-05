---
title: StatusBar
summary: A slim bar along the bottom of a window for Ln/Col, encoding, zoom and similar cells.
section: Windows and pages
---

StatusBar is a slim bar along the bottom of a window. Put [StatusBarItem](status-bar-item.md) children inside it. A spacer is an `Item` with `Layout.fillWidth: true`, which pushes the cells after it to the far end. A thin separator is drawn between neighbouring visible cells, none next to a spacer.

StatusBar is an `Item`.

## Example

```qml
StatusBar {
    StatusBarItem { text: qsTr("Ln 3, Col 14") }
    Item { Layout.fillWidth: true }
    StatusBarItem { text: qsTr("UTF-8") }
    StatusBarItem { text: qsTr("100%"); clickable: true }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `content` | `list<Item>` (read-only) | — | The default property: the cells and spacers. |
| `density` | `int` | `AtlasStyle.density` | `AtlasStyle.Normal` or `AtlasStyle.Compact`; Compact shrinks the height to about 75%. |

## Methods

| Signature | Description |
|---|---|
| `refresh(): var` | Sets `leadingSeparator` on every visible cell that follows another one. Called when the children or their visibility change; call it yourself only after changing something it can't see. |
