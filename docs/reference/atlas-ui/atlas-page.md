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
| `busy` | `bool` | `false` | Shows a row with a spinner and `busyText` above the content, under the title row. It slides in and out with `AtlasStyle.duration` and takes no room when `false`. Becoming busy announces `busyText` to screen readers once. The content is not disabled: the app does that where it needs to. Under reduced motion the spinner is still and the row appears at once. `SectionRow.busy` is unchanged and covers one row. Since 1.5.0. |
| `busyText` | `string` | `""` | The label beside the spinner, and what is announced. Since 1.5.0. |
| `headerTrailing` | `list<QtObject>` (read-only) | — | Items at the trailing end of the title row (a button, a search field). The title elides before them. |
| `maxContentWidth` | `real` | 38 grid units | The widest the content grows. Writable since 1.4.0. |
| `subtitle` | `string` | `""` | One or two muted lines under the title, plain text, wrapped and elided after three lines; hidden when empty. Read by screen readers as the page's description; the title stays the only heading. Since 1.5.0. |
| `title` | `string` | `""` | The page's large bold title. Inside an [AtlasNavigationStack](atlas-navigation-stack.md) whose header shows, the header carries it and the page doesn't repeat it. |

## Methods

| Signature | Description |
|---|---|
| `ensureVisible(var item)` | Scrolls just enough to show `item`, a descendant of the content. The page calls it itself when the keyboard focus moves, and skips it for a click. |
