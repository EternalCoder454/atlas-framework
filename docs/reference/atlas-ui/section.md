---
title: Section
summary: A rounded card that groups SectionRows, or any items, on a raised background.
section: Layout
---

Section is the settings card of Atlas apps: an optional title above, a raised card with 6 px corners with the rows inside and an optional footer under it. Put [SectionRow](section-row.md)s in it, or any items. A `foldable` section's title is a button that folds the card away.

Section is a `ColumnLayout`; its children go into the card.

## Example

```qml
Section {
    id: cores
    title: qsTr("Each Processor")
    foldable: true
    folded: settings.folded.includes("cores")
    onFoldRequested: fold => settings.setFolded("cores", fold)
    MiniBars { values: cores.folded ? [] : cpu.coreUsage }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `content` | `list<Item>` (read-only) | — | The default property: the items inside the card. |
| `foldable` | `bool` | `false` | Makes the title a button that folds the card away. |
| `folded` | `bool` | `false` | Whether the card is folded (not drawn). Set it from a saved setting. |
| `footer` | `string` | `""` | A small note under the card. |
| `title` | `string` | `""` | The heading above the card; no heading when empty. |

## Signals

| Name | Description |
|---|---|
| `foldRequested(bool fold)` | Emitted when the title is clicked (or Return, Enter or Space is pressed on it); `fold` is the state asked for. |

> [!NOTE]
> A section doesn't keep its folded state: it asks with `foldRequested` and the page sets `folded`. A binding that reads `folded` first can stop feeding what is inside while it is folded.

## Accessibility

A foldable title is a button whose description is "Expanded" or "Collapsed"; a plain title is a heading.
