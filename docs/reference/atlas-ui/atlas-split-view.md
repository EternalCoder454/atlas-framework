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
| `stateKey` | `string` | `""` | Names the saved sizes. When set, the sizes are saved under `AtlasSplitView-<stateKey>` in the app's settings file ([AtlasSettings](atlas-settings.md)) a moment after a drag, and restored when the view is created. Empty keeps them for this run only. |

## Methods

| Signature | Description |
|---|---|
| `restoreSizes(string sizes): bool` | Applies sizes from `saveSizes()`. Returns `false` for a string that is empty or does not fit this view; nothing changes then. |
| `saveSizes(): string` | The pane sizes as a base64 string, for the app's own storage. |

Apps with their own storage use `saveSizes()` and `restoreSizes()` instead of `stateKey`.
