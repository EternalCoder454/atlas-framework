---
title: TelamonToolbar
summary: A horizontal or vertical bar of actions that moves the ones that don't fit into a "more" menu.
section: Navigation
since: "1.4.0"
---

TelamonToolbar shows a list of `TelamonAction` or Qt `Action` items as [ToolbarButton](toolbar-button.md)s. Actions that don't fit move, in order, into a menu behind a "more" button and come back as the bar widens. Use it for the main tools of a window; [TelamonHeaderBar](telamon-header-bar.md) places one in the window header, and [TelamonFloatingToolbar](telamon-floating-toolbar.md) is the capsule that floats over content.

TelamonToolbar is an `Item`. The model is `actions`; there are no other children to place. A change of `TelamonAction.section` between two neighbours draws a divider between them (and a separator in the menu).

A bar can be `Qt.Vertical`: buttons run top to bottom, `leading` is at the top, `trailing` at the bottom and the "more" button is last. The fit then uses the height, dividers are horizontal lines, and a right-to-left layout does not change it. Menus of the strip's buttons open beside it, on the side with more room.

With `overflow: TelamonToolbar.Scroll` buttons that do not fit are not moved to a menu: the strip shows whole buttons, one button per step, with a chevron at each end (shown only while there is more in that direction; its room is kept while the strip scrolls). Dividers are left out while it scrolls. The mouse wheel steps one button per notch, with partial turns of a touchpad added up. The chevrons ("Scroll back", "Scroll forward") are mouse targets and not Tab stops: Tab moves through the buttons and the strip follows the focus, so a button out of view is still reachable. The step is instant under reduced motion. There is no "more" menu in this mode.

An action with no symbol and no icon draws the first letter of its text (its tooltip and spoken name stay the whole text). An action with a `menu` or `popover` ([TelamonAction](telamon-action.md)) is a button that opens it. In the "more" menu a `menu` is a submenu with the same title (set from the action's text when empty) and symbol, and a `popover` is an item that opens the popover from the "more" button. While such a menu or popover is open, [TelamonFloatingToolbar](telamon-floating-toolbar.md) counts the bar as active.

## Example

```qml
TelamonToolbar {
    width: parent.width
    actions: [saveAction, openAction, boldAction, italicAction]
    leading: QQC2.Label { text: qsTr("Notes") }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accessibleName` | `string` | `qsTr("Toolbar")` | The name of the bar for screen readers. |
| `actions` | `list<Action>` (read-only) | `[]` | The `TelamonAction` or Qt `Action` items, in order. Each button follows its action (symbol, tooltip, shortcut, checkable, enabled), and the same action fills the overflow menu. Its overflow row follows the action's `text`, `enabled`, `symbol` and `menu` or `popover`; the app's own menu is never changed (its `title` stays). |
| `focusOnClick` | `bool` | `true` | With `focusable`, `false` makes a click not take the focus. Passed to every button. |
| `flat` | `bool` | `true` | True draws nothing behind the buttons; false draws a surface with rounded corners. |
| `focusable` | `bool` | `true` | Lets Tab reach the buttons; false keeps the keyboard focus where it is. |
| `leading` | `list<Item>` (read-only) | — | Items before the buttons (a title). Assign one item or a list; they stay visible when there is no room. |
| `moreMenu` | `ContextMenu` | — | The "more" menu, to open it from code. |
| `orientation` | `int` (`Qt.Horizontal` or `Qt.Vertical`) | `Qt.Horizontal` | The direction of the strip. |
| `overflow` | `int` (`TelamonToolbar.Overflow`) | `TelamonToolbar.Menu` | What happens to buttons that do not fit: moved into the "more" menu, or scrolled. |
| `overflowCount` | `int` (read-only) | — | How many actions are in the "more" menu (in `Scroll` mode, out of view). |
| `scrolls` | `bool` (read-only) | — | `true` while `Scroll` mode has buttons out of view. |
| `trailing` | `list<Item>` (read-only) | — | Items after the "more" button (a search field). Assign one item or a list; they stay visible when there is no room. |
| `visibleCount` | `int` (read-only) | — | How many actions show as buttons; the rest are in the menu. |

## Enums

### Overflow

| Value | Description |
|---|---|
| `TelamonToolbar.Menu` | Buttons that do not fit move into the "more" menu. |
| `TelamonToolbar.Scroll` | Buttons that do not fit scroll out of view, one button per step. |

## Notes

> [!NOTE]
> The fit is worked out once per change of the width or of the slots' implicit widths, from the size of one button, never from the laid-out result. Without room the bar shows only `leading`, `trailing` and the "more" button.
