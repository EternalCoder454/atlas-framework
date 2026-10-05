---
title: AtlasSplitView
summary: Panes side by side or stacked with a thin draggable Atlas divider that can remember the pane sizes between runs.
section: Layout
since: "1.4.0"
---

Panes side by side (or stacked) with a draggable divider in the Atlas look: a thin separator line inside a wider invisible grab area, tinted on hover and while dragged. Put the panes inside as children and size them with `SplitView.preferredWidth`, `SplitView.minimumWidth` and `SplitView.fillWidth` (the attached properties of Qt's own `SplitView`).

AtlasSplitView is a Qt Quick Controls [`SplitView`](https://doc.qt.io/qt-6/qml-qtquick-controls-splitview.html); its inherited properties work as usual.

## Example

```qml
AtlasSplitView {
    stateKey: "main"          // remember the sizes between runs
    Rectangle { SplitView.preferredWidth: 220; SplitView.minimumWidth: 140 }
    Rectangle { SplitView.fillWidth: true }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `collapsed` | `bool` (read-only) | — | `true` while the view shows one pane at a time: `collapsible` is on, the orientation is horizontal and the width is below `collapseWidth`. Since 1.5.0. |
| `collapseWidth` | `real` | 40 grid units | The width below which a `collapsible` view shows one pane at a time. Since 1.5.0. |
| `collapsible` | `bool` | `false` | Below `collapseWidth`, show one pane at a time. Horizontal views only. Since 1.5.0. |
| `currentPane` | `int` | `0` | The pane shown while collapsed (an index; one out of range shows the nearest pane). It is kept across a resize, and can be set directly as well as with `showPane()`. Since 1.5.0. |
| `stateKey` | `string` | `""` | Names the saved sizes. When set, the sizes are saved under `AtlasSplitView-<stateKey>` in the app's settings file ([AtlasSettings](atlas-settings.md)) a moment after a drag, and restored when the view is created. Empty keeps them for this run only. |

## Methods

| Signature | Description |
|---|---|
| `restoreSizes(string sizes): bool` | Applies sizes from `saveSizes()`. Returns `false` for a string that is empty or does not fit this view; nothing changes then. |
| `saveSizes(): string` | The pane sizes as a base64 string, for the app's own storage. |
| `showPane(int i)` | Moves to pane `i` and makes it `currentPane`; an index out of range is ignored. While collapsed the pane slides in from the end, with no motion under reduced motion. Since 1.5.0. |

Apps with their own storage use `saveSizes()` and `restoreSizes()` instead of `stateKey`.

## Collapsing

With `collapsible`, a horizontal view narrower than `collapseWidth` shows one pane at a time, the one `currentPane` names; the others are hidden (the view sets their `visible`, and sets it back when it expands). A pane other than the first gets a Back row at the top with a Back button; Alt+Left and the mouse Back button go back too, as in [AtlasNavigationStack](atlas-navigation-stack.md). Alt+Left works while focus is inside the view. Inside an AtlasNavigationStack page the innermost goes first: the view goes back a pane, and once it is on its first pane Alt+Left and the mouse Back button pop the page. Back returns to the pane shown before, or to the one before in order. While collapsed, `topPadding` makes room for the Back row (it is `padding` plus the row), so set `padding` rather than `topPadding`; the view clips a pane that is sliding in, and focus that was in a pane that hid moves to the one shown. A pane's own `visible` binding is kept: the view hides it with a binding of its own and gives it back on expanding. Moving to a pane slides it in from the end of the view (from the left in a right-to-left layout); under reduced motion it appears at once.

The sizes the user dragged, and the ones saved under `stateKey`, are kept: nothing is saved while the view is collapsed, and the panes return to those sizes when it expands. Together with the sidebar's `compact`, this is the adaptive scaffold; there is no separate type.

```qml
AtlasSplitView {
    collapsible: true
    stateKey: "main"
    Rectangle { SplitView.preferredWidth: 260; SplitView.minimumWidth: 160 }   // the list
    Rectangle { SplitView.fillWidth: true }                                    // the details
    // showPane(1) when the user opens an item; the Back row returns to the list
}
```
