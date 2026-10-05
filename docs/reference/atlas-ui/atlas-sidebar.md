---
title: AtlasSidebar
summary: A scrolling sidebar for SidebarItem and SidebarGroup entries with filtering, a placeholder, context menus and drop targets.
section: Navigation
since: "1.4.0"
---

A scrolling sidebar column for `SidebarItem` and `SidebarGroup` entries. Put them inside (give each `Layout.fillWidth: true`), or set `model` and a `delegate` whose root is a `SidebarItem` or `SidebarGroup`. Its background follows `AtlasWindow.sidebarColor()`. For pages pushed over each other, use [AtlasNavigationStack](atlas-navigation-stack.md).

It also:
- scrolls the selected entry into view when `currentIndex` or an entry's `selected` changes, and any entry that gets keyboard focus;
- filters entries by title with `filterText` (a case-insensitive "contains"; a group stays while it or one of its entries matches), with a search field on top when `showFilter` is `true`;
- shows `placeholderText` and `placeholderSymbol` when nothing is visible;
- emits `contextMenuRequested(item, pos)` for a right click and for the Menu key or Shift+F10 on the focused entry;
- with `dropEnabled`, highlights the entry a drag hovers over and emits `dropped(item, drop)`.

## Example

```qml
AtlasSidebar {
    width: compact ? 64 : 240
    compact: window.sidebarCollapsed
    showFilter: true
    placeholderText: qsTr("No matches")
    onContextMenuRequested: (item, pos) => menu.popup(item)
    SidebarItem { Layout.fillWidth: true; text: qsTr("Overview"); symbol: Symbols.Home; selected: true }
    SidebarGroup {
        text: qsTr("Disk")
        SidebarItem { sub: true; Layout.fillWidth: true; text: qsTr("sda") }
    }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `baseColor` | `color` | `AtlasStyle.base` | The base colour, made see-through by the window's blur like any sidebar. |
| `compact` | `bool` | `false` | Shows icon-only entries. Bind it to the window's `sidebarCollapsed`. |
| `content` | `list<QtObject>` (read-only) | — | The default property: the entries declared inside. |
| `currentIndex` | `int` | `-1` | The selected entry. It counts the `SidebarItem`s in order (sub-entries included, group headers not); `-1` means none. |
| `delegate` | `Component` | `null` | The delegate for `model`; its root is a `SidebarItem` or `SidebarGroup`. |
| `dropEnabled` | `bool` | `false` | Highlights the entry a drag hovers over and emits `dropped`. |
| `filterText` | `string` | `""` | Shows only entries whose title contains this text, case-insensitively. |
| `model` | `var` | `null` | A model of entries, with `delegate`. |
| `padding` | `int` | `AtlasStyle.spacingSmall` | The inner margin round the entries. |
| `placeholderSymbol` | `int` (a `Symbols.<Name>` value) | `0` | The symbol shown above `placeholderText` when nothing is visible. See [Symbols](symbols.md). |
| `placeholderText` | `string` | `""` | Shown when no entry is visible. |
| `showFilter` | `bool` | `false` | Shows a search field on top that sets `filterText`. |
| `spacing` | `int` | `AtlasStyle.spacingXSmall` | The gap between entries. |
| `win` | `var` (read-only) | — | The window the sidebar is in. |

> [!NOTE]
> Filtering and `compact` set the entries' `visible` and `compact` themselves, so don't bind those on `SidebarItem` or `SidebarGroup`.

## Signals

| Name | Description |
|---|---|
| `contextMenuRequested(Item item, point pos)` | A right click, or the Menu key or Shift+F10 on the focused entry. `item` is the `SidebarItem`, or the `SidebarGroup` for its header; `pos` is in the sidebar's coordinates. |
| `dropped(Item item, var drop)` | With `dropEnabled`, something was dropped on `item`. `drop` is the `DragEvent`. |

## Keyboard

Tab lands on the selected entry.
