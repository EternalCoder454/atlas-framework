---
title: AtlasViewSwitcher
summary: Page tabs for the top of a window: a symbol and text per tab, the current one tinted, with an optional count badge.
section: Navigation
since: "1.4.0"
---

AtlasViewSwitcher is the page switcher after libadwaita's ViewSwitcher. Each tab is a symbol with its text beside it (or under it with `narrow`); the current tab is tinted with the accent and the tint slides to the new tab. For document tabs use [TabBar](tab-bar.md); for a small choice inside a page use [AtlasSegmentedControl](atlas-segmented-control.md).

AtlasViewSwitcher is a Qt Quick Templates `Control` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-control.html)); its inherited properties work as usual.

## Example

```qml
AtlasViewSwitcher {
    model: [
        { text: qsTr("Installed"), symbol: Symbols.CheckCircle },
        { text: qsTr("Updates"), symbol: Symbols.Update, badge: 3 }
    ]
    currentIndex: pages.currentIndex
    onActivated: index => pages.currentIndex = index
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `count` | `int` (read-only) | — | The number of tabs. |
| `currentIndex` | `int` | `-1` | The current tab; -1 means none. The switcher owns no state: change it in answer to `activated()`. |
| `model` | `var` | `[]` | A list of `{ text, symbol, badge }`. `symbol` is a [Symbols](symbols.md) value (0 or missing: text only); `badge` is a count (0 or missing: none). |
| `narrow` | `bool` | `false` | Puts the text under the symbol. |

## Signals

| Name | Description |
|---|---|
| `activated(int index)` | Emitted when the user picks a tab; `index` is its position. |

## Keyboard

One Tab stop. Left and Right (mirrored in a right-to-left layout), Home and End move between the tabs and activate them. Ctrl+PageUp and Ctrl+PageDown are left to the app.
