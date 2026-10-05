---
title: StatusBarItem
summary: One cell of a StatusBar: a short text, optionally clickable, with a symbol, a tooltip and a menu.
section: Windows and pages
---

StatusBarItem is a cell of a [StatusBar](status-bar.md): a short text such as "Ln 3, Col 14". With `clickable` it gets a hover background and emits `clicked()`; with a `menu` (a `QQC2.Menu` or [ContextMenu](context-menu.md)) a click pops it up above the cell, from its leading edge (the trailing one when mirrored) and moved to stay inside the window. The StatusBar sets `leadingSeparator` to draw the thin line before the cell.

StatusBarItem is a Qt Quick Templates `AbstractButton` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html)); its inherited properties (`text`, `clicked`) work as usual.

## Example

```qml
StatusBarItem { text: qsTr("UTF-8"); clickable: true; menu: encodingMenu }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `clickable` | `bool` | `false` | Gives the cell a hover and press background and makes it a button for screen readers. |
| `leadingSeparator` | `bool` | `false` | Draws the thin separator before the cell. Set by the `StatusBar`; don't set it yourself. |
| `menu` | `QtObject` | `null` | A `QQC2.Menu` or `ContextMenu` opened above the cell on a click (needs `clickable`); unset for none. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | A Material Symbol shown before the text. |
| `toolTip` | `string` | `""` | A tooltip shown on hover; also the accessible description. |

> [!NOTE]
> A clickable cell is reached with Tab (with a focus ring; Space and Return press it), and a click does not take the focus. A cell that is not clickable never takes it. The text elides when the cell is narrower than the text.
