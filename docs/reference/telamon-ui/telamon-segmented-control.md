---
title: TelamonSegmentedControl
summary: A row of joined segments with one selected, for a choice between a few views or modes.
section: Buttons
since: "1.4.0"
---

A row of joined segments, one selected: a choice between a few views or modes ("List | Grid", "Day | Week | Month"). Segments are all the same width, the widest one's, and text that does not fit is elided. The accent highlight slides to the chosen segment (not under reduced motion). For many options or a form choice, use [TelamonRadioButton](telamon-radio-button.md).

TelamonSegmentedControl is a Qt Quick Controls [`Control`](https://doc.qt.io/qt-6/qml-qtquick-templates-control.html); its inherited properties work as usual.

## Example

```qml
TelamonSegmentedControl {
    model: [qsTr("List"), { text: qsTr("Grid"), symbol: Symbols.GridView }]
    currentIndex: app.viewMode
    onActivated: index => app.viewMode = index
    Accessible.name: qsTr("View mode")
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `count` | `int` (read-only) | — | The number of segments. |
| `currentIndex` | `int` | `0` | The selected segment. |
| `model` | `var` | `[]` | A list of strings, or of objects `{ text, symbol, toolTip }`. `symbol` is a [Symbols](symbols.md) value. A segment with only a symbol takes its tooltip and accessible name from `toolTip`, else `text`. |

> [!NOTE]
> A user's choice does not end a binding on `currentIndex`. If `onActivated` stores it, the binding follows the model; if the app ignores it, `currentIndex` (and the highlight) returns to the model's one turn of the event loop later. A handler or `onXChanged` that reads it sees the new value at once. A literal value or no binding keeps the user's edit.

## Signals

| Name | Description |
|---|---|
| `activated(int index)` | The user chose segment `index`. Not emitted when `currentIndex` changes from code. |

## Keyboard

The control is one Tab stop. Left and Right move the selection (mirrored in right-to-left layouts), and Home and End jump to the ends.

## Accessibility

Screen readers get a tab list (`Accessible.PageTabList`) of page tabs, the selected one marked.

> [!NOTE]
> Give the control an `Accessible.name` ("View mode") for the screen reader's tab list.

Since 1.5.0: `model` may also be a ListModel or a number of segments, and a click gives the control the focus.
