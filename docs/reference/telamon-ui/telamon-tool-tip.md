---
title: TelamonToolTip
summary: A small rounded hint on a raised card, opened after the hover delay.
section: Menus, dialogs and popups
since: "1.3.0"
---

TelamonToolTip is the tool tip for Telamon apps. Declare it inside the item it describes, set `text`, and bind `shown` to the hover state of its parent. Bind it to the keyboard focus too, so keyboard users get the hint.

TelamonToolTip is a Qt Quick Templates `ToolTip` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-tooltip.html)); its inherited properties (`text`, `delay`, `timeout`) work as usual. It opens after the hover delay, closes at once when `shown` ends and goes by itself after a while. It sits above its item, or below it when there is no room above. With no `text` it draws nothing and `shown` does not open it.

## Example

```qml
TelamonButton {
    text: qsTr("Refresh")
    TelamonToolTip {
        text: qsTr("Check for updates")
        shown: parent.hovered || parent.visualFocus
    }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `shown` | `bool` | `false` | Opens the tip after the hover delay when it becomes true and closes it at once when it becomes false. Usually bound to the parent's hover state. |

> [!NOTE]
> Setting `visible` opens the tip at once, without the delay. The text is plain text.
