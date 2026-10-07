---
title: TelamonHeaderBar
summary: The merged header of a frameless Telamon window: window menu, title, main tools and window buttons in one row.
section: Windows and pages
since: "1.4.0"
---

TelamonHeaderBar is the window menu and app icon, the title, the main tools and the window buttons in one 32 px row. Give it to a [TelamonWindow](telamon-window.md) as its `header`, and that window turns frameless (no KWin title bar).

Left to right: the window menu button, `leading`, the title, the `actions` in a [TelamonToolbar](telamon-toolbar.md) (the ones that don't fit go behind its "more" button), `stretch`, `trailing`, the window buttons. KWin's own button layout (`kwinrc`) decides the sides; the Telamon OS default is the window menu on the left, and minimise, maximise and close on the right. The title leads, left aligned. With `centerTitle` it is centred when the bar is wide (40 grid units), and leads again when it is narrower. The bar is filled with `TelamonStyle.chromeBackground` (lightly see-through over the window's blur, solid without blur), with a `TelamonStyle.separator` hairline below; text and icons use the Header colour set.

The `stretch` row takes all the free width between the title and `actions` on one side and `trailing` on the other. It is a `RowLayout`: a child that sets `Layout.fillWidth` takes the rest, so a [TabBar](tab-bar.md) fills the bar. Empty parts of the row still drag the window and still maximise on double click; items in it keep their clicks. With no free width the row is 0 wide and its items are hidden, not overlapped. While `stretch` has items the `actions` take only the width they need, and `titleCentered` is `false`. Set `showTitle: false` for a bar whose stretch row is the title.

## Example

```qml
TelamonWindow {
    header: TelamonHeaderBar {
        actions: [saveAction, openAction, undoAction]
        leading: TelamonAppMenu {
            menus: [{ title: qsTr("File"), actions: [openAction, null, quitAction] }]
        }
    }

    TelamonAction { id: saveAction; text: qsTr("&Save") }
    TelamonAction { id: openAction; text: qsTr("&Open") }
    TelamonAction { id: undoAction; text: qsTr("&Undo") }
    TelamonAction { id: quitAction; text: qsTr("&Quit") }
}
```

## Mouse and keyboard

Dragging the empty bar moves the window, and a double click maximises or restores it. A right click, Alt+Space or the window menu button opens a menu with Minimize, Maximize or Restore, and Close: the compositor's own menu is out of reach of a frameless client. Buttons and anything else in the bar keep their clicks.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `actions` | `list<Action>` (read-only) | `[]` | [TelamonAction](telamon-action.md) or Qt `Action` items for the toolbar. |
| `active` | `bool` | the window's `active` | Whether the window is active. An inactive window draws a quieter bar. |
| `centerTitle` | `bool` | `false` | Centres the title when the bar is wide enough. |
| `iconName` | `string` | `Qt.application.name` | The icon name of the window menu button. |
| `leading` | `list<QtObject>` (read-only) | — | Items after the window menu button, before the title (a [TelamonAppMenu](telamon-app-menu.md)). |
| `showTitle` | `bool` | `true` | `false` leaves the title out, for a bar whose `stretch` row is the title. |
| `stretch` | `list<QtObject>` (read-only) | — | Items in a row that takes all the free width between the title and `actions` on one side and `trailing` on the other. |
| `title` | `string` | the window's title | The title. |
| `titleCentered` | `bool` (read-only) | — | `true` when the title is drawn centred. |
| `trailing` | `list<QtObject>` (read-only) | — | Items before the window buttons (a search field). |
| `windowButtons` | `bool` | `true` | `false` leaves the window buttons out (the window has its own). |

## Methods

| Signature | Description |
|---|---|
| `openWindowMenu(): QVariant` | Opens the window menu below the leading edge, for keyboard users. |
