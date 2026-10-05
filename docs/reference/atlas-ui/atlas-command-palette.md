---
title: AtlasCommandPalette
summary: A searchable popup list of the app's actions, opened with a shortcut such as Ctrl+K.
section: Menus, dialogs and popups
since: "1.4.0"
---

AtlasCommandPalette is a search field over a list of the app's actions. Typing filters the actions: every word of the query must appear in the action's text or section, in any case, and names that start with the query come first. Only enabled actions are listed. With an empty query, the actions run most recently come first (kept in memory only). Each row shows the symbol, text, section and shortcut of the action.

It is a Qt Quick Controls `Popup`: declare it anywhere and call `open()`. See <https://doc.qt.io/qt-6/qml-qtquick-controls-popup.html>. Actions are [AtlasAction](atlas-action.md) items.

## Example

```qml
AtlasCommandPalette { id: palette }
AtlasAction {
    text: qsTr("Command Palette")
    shortcut: "Ctrl+K"
    onTriggered: palette.open()
}
```

## Keyboard

- Up and Down move the highlight.
- Return runs the highlighted action and closes the palette.
- Escape closes it.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `actions` | `list<QtObject>` | `AtlasShortcuts.actions` (every AtlasAction of the app), or the actions of `collection` | The actions on offer: anything with `text`, `enabled` and `trigger()`, and optionally `symbol`, `category`, `section` and `shortcut`. Give a list to offer fewer; a list that is not empty wins over the collection. |
| `collection` | `AtlasActionCollection` | `null` | The app's [AtlasActionCollection](atlas-action-collection.md): its actions are offered when `actions` is empty, and the user's changed shortcuts show. Each row's subtitle is the action's `category`. |
| `placeholderText` | `string` | `qsTr("Type a command")` | Hint in the empty search field. |
| `query` | `string` | `""` | The text in the search field. |
| `recentCount` | `int` | `5` | How many recently run actions lead the empty list. |

## Signals

| Name | Description |
|---|---|
| `triggered(QtObject action)` | Emitted after the palette closed and the action ran. |
