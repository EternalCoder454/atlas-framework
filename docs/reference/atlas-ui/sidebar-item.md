---
title: SidebarItem
summary: A sidebar entry: accent icon and label with a soft selection and an optional live value or badge.
section: Navigation
---

SidebarItem is an entry of an [AtlasSidebar](atlas-sidebar.md): an accent icon plus a label, with a softly rounded selection, and optionally a live value on the right ("42%", "1.2 MB/s"). A `sub` entry is indented under a [SidebarGroup](sidebar-group.md)'s header; a `disclosure` entry is that header. A `badge` icon flags something on the entry's page that needs attention: after the label, or on the icon's corner when compact.

SidebarItem is a Qt Quick Templates `AbstractButton` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html)); its inherited properties (`text`, `icon`, `clicked`) work as usual.

## Example

```qml
SidebarItem {
    text: qsTr("Processor")
    symbol: Symbols.Memory
    value: Math.round(cpu.usage) + "%"
    selected: page === "cpu"
    onClicked: page = "cpu"
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `badge` | `string` | `""` | An icon name such as `"dialog-warning"`; empty for none. Drawn in its own colours. |
| `badgeText` | `string` | `""` | What the badge means, for screen readers ("2 problems"). |
| `compact` | `bool` | `false` | Icon only (narrow windows); the text becomes the tooltip and accessible name. Hover or keyboard focus shows the title, value and `badgeText` (when a `badge` is set) as a tooltip. |
| `density` | `int` | `AtlasStyle.density` | `AtlasStyle.Normal` or `AtlasStyle.Compact`; Compact shrinks the height and padding to about 75%. |
| `disclosure` | `bool` | `false` | Makes the entry a group header with a chevron that turns down when `expanded`. |
| `expanded` | `bool` | `false` | Whether a disclosure entry is open. |
| `selected` | `bool` | `false` | Draws the entry as the selected one. |
| `sub` | `bool` | `false` | Indents the entry under a group header. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | A Material Symbol drawn instead of `icon.name`. It is solid while the entry is selected. |
| `tintIcon` | `bool` | `true` | Tints a monochrome icon with the accent; false keeps a coloured icon as is. |
| `value` | `string` | `""` | A live value shown dimmed at the right edge; hidden when compact. |

## Keyboard

The entry takes Tab focus and Return, Enter and Space click it.
