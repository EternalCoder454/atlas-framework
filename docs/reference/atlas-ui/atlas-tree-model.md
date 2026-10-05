---
title: AtlasTreeModel
summary: A read-only tree model built from nested JavaScript objects, for AtlasTreeView.
section: Lists and tables
since: "1.4.0"
---

AtlasTreeModel builds a tree model from nested JS objects, because QML can't build a tree model itself. Use it for a small tree that is static or rebuilt as a whole; an app with a large or live tree writes its own `QAbstractItemModel`: the model has no cap on the number of nodes (only on depth, 64) and keeps the `items` list as well as the nodes built from it. Feed it to [AtlasTreeView](atlas-tree-view.md) or any Qt Quick `TreeView`.

The model has one column. Its roles are `display` (the text), `symbol` (a [Symbols](symbols.md) value, 0 if none) and `icon` (an icon name or image url, empty if none). Each item is `{ text, symbol, icon, children }`.

## Example

```qml
AtlasTreeModel {
    id: tree
    items: [
        { text: "Documents", symbol: Symbols.Folder, children: [
            { text: "Report.odt" }, { text: "Notes.md" } ] },
        { text: "Music" }
    ]
}
AtlasTreeView { model: tree; symbolRole: "symbol" }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `items` | `list<var>` | `[]` | The tree: a list of `{ text, symbol, icon, children }` objects. Setting it again replaces the whole tree (a view collapses). The depth is limited to 64 levels. |
