---
title: TelamonBreadcrumb
summary: A path bar with one button per segment; a long path collapses its middle into a menu.
section: Navigation
---

TelamonBreadcrumb shows one button per segment with a chevron between them, the last one (where you are) in bold. When the path is wider than the bar, the middle collapses into a "…" button that opens a menu of the hidden segments. The first and the last always stay.

## Example

```qml
TelamonBreadcrumb {
    segments: [
        { title: qsTr("Home"), symbol: Symbols.Home },
        { title: "Documents" },
        { title: "Projects" },
    ]
    onActivated: index => goTo(index)
}
```

A segment is an object with `title` and, optionally, `symbol` (a `Symbols.<Name>` value, see [Symbols](symbols.md)).

TelamonBreadcrumb is a Qt Quick Templates `Control`; its inherited properties work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-control.html>.

## Keyboard

The bar is one Tab stop. With the focus on the bar:

- Left and Right move between the buttons.
- Home and End jump to the ends.
- Enter or Space presses the one in focus.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `count` | `int` (read-only) | `0` | The number of segments. |
| `hiddenText` | `string` | `qsTr("Hidden folders")` | The title of the menu behind the "…" crumb, and its accessible name. |
| `segments` | `var` | `[]` | The path: a list of `{title, symbol}` objects. |

## Signals

| Name | Description |
|---|---|
| `activated(int index)` | A segment was chosen, by click or from the "…" menu. `index` is its place in `segments`. |
