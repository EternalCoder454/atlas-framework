---
title: AtlasToolbar
summary: A horizontal bar of actions that moves the ones that don't fit into a "more" menu.
section: Navigation
since: "1.4.0"
---

AtlasToolbar shows a list of `AtlasAction` or Qt `Action` items as [ToolbarButton](toolbar-button.md)s. Actions that don't fit move, in order, into a menu behind a "more" button and come back as the bar widens. Use it for the main tools of a window; [AtlasHeaderBar](atlas-header-bar.md) places one in the window header, and [AtlasFloatingToolbar](atlas-floating-toolbar.md) is the capsule that floats over content.

AtlasToolbar is an `Item`. The model is `actions`; there are no other children to place. A change of `AtlasAction.section` between two neighbours draws a divider between them (and a separator in the menu).

## Example

```qml
AtlasToolbar {
    width: parent.width
    actions: [saveAction, openAction, boldAction, italicAction]
    leading: QQC2.Label { text: qsTr("Notes") }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accessibleName` | `string` | `qsTr("Toolbar")` | The name of the bar for screen readers. |
| `actions` | `list<Action>` (read-only) | `[]` | The `AtlasAction` or Qt `Action` items, in order. Each button follows its action (symbol, tooltip, shortcut, checkable, enabled), and the same action fills the overflow menu. |
| `flat` | `bool` | `true` | True draws nothing behind the buttons; false draws a surface with rounded corners. |
| `focusable` | `bool` | `true` | Lets Tab reach the buttons; false keeps the keyboard focus where it is. |
| `leading` | `list<Item>` (read-only) | — | Items before the buttons (a title). Assign one item or a list; they stay visible when there is no room. |
| `moreMenu` | `ContextMenu` | — | The "more" menu, to open it from code. |
| `overflowCount` | `int` (read-only) | — | How many actions are in the "more" menu. |
| `trailing` | `list<Item>` (read-only) | — | Items after the "more" button (a search field). Assign one item or a list; they stay visible when there is no room. |
| `visibleCount` | `int` (read-only) | — | How many actions show as buttons; the rest are in the menu. |

## Notes

> [!NOTE]
> The fit is worked out once per change of the width or of the slots' implicit widths, from the size of one button, never from the laid-out result. Without room the bar shows only `leading`, `trailing` and the "more" button.
