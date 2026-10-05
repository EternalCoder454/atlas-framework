---
title: AtlasChipGroup
summary: A wrapping flow of chips, optionally one-of like radio buttons, with one Tab stop.
section: Buttons
since: "1.4.0"
---

AtlasChipGroup lays out [AtlasChip](atlas-chip.md) items in a flow that wraps. `exclusive` makes the checkable chips one-of, like radio buttons. Give the group a `width`: it wraps to it and its height follows.

## Example

```qml
AtlasChipGroup {
    width: parent.width
    exclusive: true
    AtlasChip { text: qsTr("All"); checkable: true; checked: true }
    AtlasChip { text: qsTr("Unread"); checkable: true }
}
```

## Keyboard

The group is one Tab stop: Tab reaches one chip. Left and Right (mirrored in right-to-left layouts), Up and Down, Home and End move between chips. When the focused chip is removed, focus moves to its neighbour.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `content` | `list<QtObject>` (default, read-only) | — | The chips declared inside the group. |
| `exclusive` | `bool` | `false` | Checkable chips are one-of. |
| `spacing` | `real` | `AtlasStyle.spacing` | The gap between chips, and between rows. |
