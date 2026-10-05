---
title: AtlasComboBox
summary: A drop-down list with the current choice in a field and the choices in a raised card, optionally filterable.
section: Fields and pickers
---

AtlasComboBox shows the current choice in a field with a chevron, and the choices in a raised card like ContextMenu's. `model`, `textRole`, `currentIndex` and `activated` work as in any Qt Quick Controls `ComboBox`; see <https://doc.qt.io/qt-6/qml-qtquick-controls-combobox.html>. With `filterable: true`, the list opens with a filter field on top, which suits long lists.

## Example

```qml
AtlasComboBox {
    model: [qsTr("Light"), qsTr("Dark"), qsTr("Automatic")]
    currentIndex: 2
    onActivated: index => settings.theme = index
}
```

## Keyboard

In a filterable list, typing narrows the choices (any part of the text, in any case), Up and Down move among the ones left, and Return chooses. The filter clears when the list closes.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `filterable` | `bool` | `false` | Opens the list with a filter field at the top. |
| `placeholderText` | `string` | `""` | Shown while nothing is chosen (`currentIndex` is -1). |
