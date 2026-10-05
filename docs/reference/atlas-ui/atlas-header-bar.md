---
title: AtlasHeaderBar
summary: The merged header of a frameless Atlas window: window menu, title, main tools and window buttons in one row.
section: Windows and pages
since: "1.4.0"
---

AtlasHeaderBar is the window menu and app icon, the title, the main tools and the window buttons in one 32 px row. Give it to an [AtlasWindow](atlas-window.md) as its `header`, and that window turns frameless (no KWin title bar).

Left to right: the window menu button, `leading`, the title, the `actions` in an [AtlasToolbar](atlas-toolbar.md) (the ones that don't fit go behind its "more" button), `trailing`, the window buttons. KWin's own button layout (`kwinrc`) decides the sides; the AtlasOS default is the window menu on the left, and minimise, maximise and close on the right. The title leads, left aligned. With `centerTitle` it is centred when the bar is wide (40 grid units), and leads again when it is narrower. The bar is filled with `AtlasStyle.chromeBackground` (lightly see-through over the window's blur, solid without blur), with an `AtlasStyle.separator` hairline below; text and icons use the Header colour set.

## Example

```qml
AtlasWindow {
    header: AtlasHeaderBar {
        actions: [saveAction, openAction, undoAction]
        leading: AtlasAppMenu {
            menus: [{ title: qsTr("File"), actions: [openAction, null, quitAction] }]
        }
    }

    AtlasAction { id: saveAction; text: qsTr("&Save") }
    AtlasAction { id: openAction; text: qsTr("&Open") }
    AtlasAction { id: undoAction; text: qsTr("&Undo") }
    AtlasAction { id: quitAction; text: qsTr("&Quit") }
}
```

## Mouse and keyboard

Dragging the empty bar moves the window, and a double click maximises or restores it. A right click, Alt+Space or the window menu button opens a menu with Minimize, Maximize or Restore, and Close: the compositor's own menu is out of reach of a frameless client. Buttons and anything else in the bar keep their clicks.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `actions` | `list<Action>` (read-only) | `[]` | [AtlasAction](atlas-action.md) or Qt `Action` items for the toolbar. |
| `active` | `bool` | the window's `active` | Whether the window is active. An inactive window draws a quieter bar. |
| `centerTitle` | `bool` | `false` | Centres the title when the bar is wide enough. |
| `iconName` | `string` | `Qt.application.name` | The icon name of the window menu button. |
| `leading` | `list<QtObject>` (read-only) | — | Items after the window menu button, before the title (an [AtlasAppMenu](atlas-app-menu.md)). |
| `title` | `string` | the window's title | The title. |
| `titleCentered` | `bool` (read-only) | — | `true` when the title is drawn centred. |
| `trailing` | `list<QtObject>` (read-only) | — | Items before the window buttons (a search field). |
| `windowButtons` | `bool` | `true` | `false` leaves the window buttons out (the window has its own). |

## Methods

| Signature | Description |
|---|---|
| `openWindowMenu(): QVariant` | Opens the window menu below the leading edge, for keyboard users. |
