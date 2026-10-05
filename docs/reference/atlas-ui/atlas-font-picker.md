---
title: AtlasFontPicker
summary: A font chooser: a pill showing the family in its own face and the size, opening a searchable list of installed families.
section: Fields and pickers
since: "1.4.0"
---

AtlasFontPicker is a pill with the family drawn in its own face and the size. Clicking it opens a card with a search field, the list of installed families (each in its own face, drawn only while visible) and a size spin box. `font` is the chosen font (its `family` and `pointSize`); the other parts of `font` are left as they are. With `fixedOnly`, the list holds monospace families only, found a few at a time after the first opening, so the list fills in.

AtlasFontPicker is a Qt Quick Templates `AbstractButton`; its inherited `font` property holds the choice. See <https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html>.

## Example

```qml
AtlasFontPicker {
    font.family: "Noto Sans Mono"
    font.pointSize: 11
    fixedOnly: true
    onEdited: terminal.font = font
    Accessible.name: qsTr("Terminal font")
}
```

## Accessibility

Name it with `Accessible.name` (what the font is for). The family and size are spoken as the description.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `fixedOnly` | `bool` | `false` | Lists only monospace families. |

## Signals

| Name | Description |
|---|---|
| `edited()` | The user chose a family or a size. Not emitted when the app sets them. |
