---
title: TelamonColorField
summary: A colour chooser: a swatch and hex field that opens a palette, a hex field and the system colour dialog.
section: Fields and pickers
since: "1.4.0"
---

TelamonColorField shows a swatch and the colour as hex text (a colour with alpha shows as RGBA instead, such as `rgba(104, 88, 226, 0.5)`). Clicking it opens a card with a palette of swatches (the current colour first when it is not one of them), a hex field and, with `showMore`, a "More..." button for the system colour dialog.

The hex field takes `#rgb` and `#rrggbb` (and `#aarrggbb` with `showAlpha`; the `#` may be left out) and applies the colour as soon as what is typed is complete. `rgb(104, 88, 226)` and `rgba(104, 88, 226, 0.5)` are accepted too (alpha 0 to 1; the alpha form needs `showAlpha`).

TelamonColorField is a Qt Quick Templates `AbstractButton`; its inherited properties work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html>.

## Example

```qml
TelamonColorField {
    color: "#3daee9"
    onEdited: settings.accent = color
    Accessible.name: qsTr("Accent color")
}
```

## Accessibility

Name it with `Accessible.name` (what the colour is for). The default name is "Color". The hex value is spoken as the description.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `color` | `color` | `"#3daee9"` | The colour. |
| `hex` | `string` (read-only) | — | The colour as `#rrggbb`, or `#aarrggbb` when `showAlpha` is on and it is not opaque. |
| `showAlpha` | `bool` | `false` | Accept and show an alpha channel. |
| `showMore` | `bool` | `true` | Shows the "More..." button that opens the system colour dialog. |

> [!NOTE]
> A colour the user picks or types does not end a binding on `color`. If `onEdited` stores it, the binding follows the model; if the app ignores it, `color` returns to the model's one turn of the event loop later. A handler or `onXChanged` that reads it sees the new value at once. A literal value or no binding keeps the user's edit.

## Signals

| Name | Description |
|---|---|
| `edited()` | The user changed the colour. Not emitted when the app sets `color`. |
