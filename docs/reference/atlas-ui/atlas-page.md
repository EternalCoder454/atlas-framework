---
title: AtlasPage
summary: A scrolling page with a large bold title, generous centred margins and a place for buttons at the end of the title row.
section: Windows and pages
---

A scrolling page with a large bold title and centred margins. Items declared inside it become its content, in a column. Use it as the body of each page of an app's window.

## Example

```qml
AtlasPage {
    title: qsTr("Settings")
    headerTrailing: AtlasButton { text: qsTr("Reset") }
    AtlasLabel { text: qsTr("Appearance"); textStyle: AtlasLabel.Heading }
    // ...more content
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `content` | `list<QtObject>` (read-only) | — | The default property: items declared inside are placed in the page's column. |
| `headerTrailing` | `list<QtObject>` (read-only) | — | Items at the trailing end of the title row (a button, a search field). The title elides before them. |
| `maxContentWidth` | `real` | 38 grid units | The widest the content grows. Writable since 1.4.0. |
| `title` | `string` | `""` | The page's large bold title. |

## Methods

| Signature | Description |
|---|---|
| `ensureVisible(var item)` | Scrolls just enough to show `item`, a descendant of the content. The page calls it itself when the keyboard focus moves, and skips it for a click. |
