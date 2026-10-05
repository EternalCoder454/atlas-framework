---
title: SidebarGroup
summary: A sidebar entry that folds out into sub-entries.
section: Navigation
---

SidebarGroup is a [SidebarItem](sidebar-item.md) header with sub-entries below it: Disk and its drives, Network and its interfaces. Put `SidebarItem`s with `sub: true` inside. The header toggles the group; while folded it shows as selected if one of its entries is, so the sidebar still says where you are.

In a compact sidebar (icons only) there is no room for sub-entries: the group is its header's icon alone, and a click on it emits `activated` for the app to open the group's first entry. SidebarGroup is a `ColumnLayout`.

## Example

```qml
SidebarGroup {
    text: qsTr("Disk")
    iconName: "drive-harddisk-symbolic"
    Repeater {
        model: disks
        SidebarItem { sub: true; text: model.label; value: model.rate }
    }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `compact` | `bool` | `false` | Icon only; follows `AtlasSidebar.compact` when inside an `AtlasSidebar`. |
| `expanded` | `bool` | `true` | Whether the sub-entries are shown. |
| `holdsSelection` | `bool` (read-only) | — | True when one of the entries is selected. |
| `iconName` | `string` | `""` | The header's icon name. |
| `items` | `list<Item>` (read-only) | — | The default property: the sub-entries. |
| `text` | `string` | `""` | The header's title. |
| `tintIcon` | `bool` | `true` | Tints a monochrome icon with the accent; false keeps a coloured icon as is. |
| `value` | `string` | `""` | A live value shown dimmed at the right of the header; hidden when compact. |

## Signals

| Name | Description |
|---|---|
| `activated()` | Emitted when the header is clicked in a compact sidebar. |
| `toggled()` | Emitted when the user folds or unfolds the group. |
