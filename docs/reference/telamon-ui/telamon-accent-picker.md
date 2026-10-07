---
title: TelamonAccentPicker
summary: A row of round colour swatches, one chosen, for an accent colour.
section: Buttons
since: "1.5.0"
---

TelamonAccentPicker is a row of round colour swatches with one chosen. The chosen swatch has a ring in the text colour and a check mark; hover shows a fainter ring. For a colour typed or picked freely, use [TelamonColorField](telamon-color-field.md).

TelamonAccentPicker is a Qt Quick Controls [`Control`](https://doc.qt.io/qt-6/qml-qtquick-templates-control.html); its inherited properties work as usual.

## Example

```qml
TelamonAccentPicker {
    model: [{ color: "#3584e4", name: qsTr("Blue") }, { color: "#e5487a", name: qsTr("Pink") }]
    currentIndex: app.accentIndex
    onActivated: index => app.accentIndex = index
    Accessible.name: qsTr("Accent color")
}
```

## User edits and bindings

A user's choice does not end an app's binding on `currentIndex`: the new index is held for one turn of the event loop, then the binding is restored. A binding that takes the edit in `onActivated` follows the app; one that refuses it springs back. With no binding the choice stays.

## Keyboard

One Tab stop. Left and Right move the choice (mirrored in right-to-left layouts), Home and End jump to the first and last swatch.

## Accessibility

The picker is a group; give it an `Accessible.name` ("Accent color"). Each swatch is a radio button, the chosen one checked. Its name is the entry's `name`, or "Accent color N" (N counts from 1) when it has none; the same text is its tooltip.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `count` | `int` (read-only) | — | The number of swatches. |
| `currentColor` | `color` (read-only) | — | The chosen swatch's colour; fully transparent when `currentIndex` is out of range. |
| `currentIndex` | `int` | `0` | The chosen swatch. |
| `model` | `var` | `[]` | A list of colours, or of objects `{ color, name }`. An entry that is not a colour is drawn as nothing. |

## Signals

| Name | Description |
|---|---|
| `activated(int index)` | The user chose swatch `index` (not a change of `currentIndex` from code, and not the swatch already chosen). |
