---
title: AtlasExpandableSection
summary: A header row that folds its content away, with an optional symbol, subtitle and chevron.
section: Layout
since: "1.4.0"
---

AtlasExpandableSection has a header row with an optional symbol, a title with an optional subtitle, and a chevron. A click, Space, Return or Enter on the header toggles `expanded` and emits `toggled(expanded)`. The content grows and shrinks over `AtlasStyle.duration`, and while it is folded nothing in it can take the keyboard focus. [Section](section.md) folds a card and leaves the state to the page; this one keeps its own.

## Example

```qml
AtlasExpandableSection {
    title: qsTr("Advanced")
    subtitle: qsTr("For experts")
    symbol: Symbols.Settings
    onToggled: expanded => settings.advancedOpen = expanded
    AtlasCheckBox { text: qsTr("Verbose log") }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `content` | `list<QtObject>` (default, read-only) | — | Items declared inside: the folding content. |
| `expanded` | `bool` | `false` | Whether the content is open. |
| `subtitle` | `string` | `""` | A line under the title. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | A Material Symbol in front of the title; 0 for none. |
| `title` | `string` | `""` | The header's title. |

## Signals

| Name | Description |
|---|---|
| `toggled(bool expanded)` | The header was used. `expanded` is the new state. |
