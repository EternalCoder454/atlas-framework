---
title: AtlasSearchResults
summary: A launcher's results list with section headings, icons, subtitles and shortcut hints, driven by keys passed on from the search field.
section: Lists and tables
since: "1.3.0"
---

The results list of a launcher: rows grouped under section headings, each with an icon (or symbol), a title, a subtitle and a shortcut hint. It scrolls on its own and makes rows only for what is on screen. The search field keeps the keyboard focus and hands the list the keys it doesn't use with `handleKey()`. The mouse moves the highlight and a click activates.

AtlasSearchResults is a Qt Quick Controls [`Control`](https://doc.qt.io/qt-6/qml-qtquick-templates-control.html); its inherited properties work as usual.

## Example

```qml
SearchField { id: field; Keys.onPressed: event => results.handleKey(event) }
AtlasSearchResults {
    id: results
    model: hits                    // a QAbstractItemModel, or a JS array
    textRole: "title"
    subtitleRole: "subtitle"
    iconRole: "icon"               // an icon name or an image url
    symbolRole: "symbol"           // or Symbols.<Name>, if no icon
    sectionRole: "kind"            // rows with the same value group
    shortcutRole: "shortcut"       // "Ctrl+1": a hint, not a binding
    placeholderText: qsTr("No Results")
    onActivated: index => run(index)
}
```

Every role is optional. A role names a role of the model, or a key of an array's objects.

> [!NOTE]
> The model must keep rows of one section together. A shortcut role shows a hint only; it does not bind the key.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `count` | `int` (read-only) | — | The number of rows. |
| `currentIndex` | `int` | `0` | The highlighted row. `-1` for none. |
| `iconRole` | `string` | `""` | The model role holding an icon name or an image url. |
| `model` | `var` | `undefined` | A `QAbstractItemModel` or a JS array. |
| `placeholderText` | `string` | `""` | Shown in the middle when there are no rows. |
| `sectionRole` | `string` | `""` | The model role whose value groups rows under a heading. |
| `shortcutRole` | `string` | `""` | The model role holding a shortcut hint such as `"Ctrl+1"`. |
| `subtitleRole` | `string` | `""` | The model role holding the second line. |
| `symbolRole` | `string` | `""` | The model role holding a [Symbols](symbols.md) value (`int`), used when the row has no icon. |
| `textRole` | `string` | `"text"` | The model role holding the title. |

## Signals

| Name | Description |
|---|---|
| `activated(int index)` | A row was clicked, or Enter was pressed on the highlighted row. |

## Methods

| Signature | Description |
|---|---|
| `activateCurrent()` | Emits `activated()` for the highlighted row, if there is one. |
| `handleKey(var event): bool` | Takes Up, Down, Page Up, Page Down and Enter from a key event, and returns `true` if it used the key. Returns `false` for Shift+Enter and Ctrl+Enter, which are the app's, and for the movement keys when there are no rows. |
| `moveCurrent(var delta)` | Moves the highlight by `delta` rows, staying on the first or last row. With no highlight yet, forward goes to the first row and backward to the last. |
