---
title: TelamonNavigationStack
summary: Drill-down navigation with pages pushed over each other, a header with a Back button and the page title, and Alt+Left to go back.
section: Navigation
since: "1.4.0"
---

Pages pushed one over another, with a header row holding a Back button (disabled on the first page) and the current page's title. Pages slide sideways (instantly under reduced motion). Use it for list-to-detail flows inside one window; use [TelamonSidebar](telamon-sidebar.md) for the top-level places of an app.

A page is any `Item`, or a `Component` or URL of one. Its `title` property (a string, if it has one) shows in the header. A [TelamonPage](telamon-page.md) then hides its own title row while the header shows (its `headerTrailing` items stay), so the title appears once; with `showHeader: false` the page shows its own title again.

A page change (push, pop or replace) announces the new page's title to screen readers (since 1.5.0); the first page is not announced, and a page without a title announces nothing.

## Example

```qml
component ListPage: TelamonPage {
    title: qsTr("Items")
    signal opened
    onOpened: stack.push(detailComponent, { title: qsTr("Details") })
}
Component {
    id: detailComponent
    TelamonPage { }
}
TelamonNavigationStack {
    id: stack
    initialItem: ListPage { }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `canGoBack` | `bool` (read-only) | — | `true` when more than one page is on the stack. |
| `currentItem` | `Item` (read-only) | — | The page on top. |
| `depth` | `int` (read-only) | — | The number of pages on the stack. |
| `initialItem` | `var` | `null` | The page shown first: an `Item`, `Component` or URL. |
| `showHeader` | `bool` | `true` | Shows the Back button and the title row. |

## Signals

| Name | Description |
|---|---|
| `wentBack()` | The stack popped, by `pop()`, `popToRoot()`, the Back button, Alt+Left or the mouse Back button. |

## Methods

| Signature | Description |
|---|---|
| `pop()` | Goes back one page and returns the page that was removed, or `null` at the first page. |
| `popToRoot()` | Goes back to the first page. |
| `push(var page, var properties)` | Shows a page on top and returns it. `page` is an `Item`, `Component` or URL; `properties` are set on it and may be left out. |

## Keyboard

Alt+Left and the mouse Back button go back.

> [!NOTE]
> Escape does not go back: it belongs to dialogs and search.
