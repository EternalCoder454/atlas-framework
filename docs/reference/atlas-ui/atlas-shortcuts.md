---
title: AtlasShortcuts
summary: A singleton registry of the app's actions that reports shortcut conflicts and turns shortcuts into readable text.
section: Services
since: "1.4.0"
---

`AtlasShortcuts` is a singleton: the registry of the app's actions. Every `AtlasAction` adds itself on completion and removes itself on destruction. The registry watches each one's `shortcut`, `text` and `enabled`, keeps the list for [AtlasShortcutsDialog](atlas-shortcuts-dialog.md) and [AtlasCommandPalette](atlas-command-palette.md), and reports conflicts: one shortcut on two actions that are both enabled. Two actions conflict when they live in the same window (actions outside any Item or window share the app level). An action whose Item is not in a window yet takes part in no comparison until it is. Each new conflict is logged once with `qWarning`, naming the shortcut and the action texts.

It also has the helpers [AtlasShortcutLabel](atlas-shortcut-label.md) uses to turn a shortcut (a string such as `"Ctrl+S"` or a `StandardKey` number) into text.

## Example

```qml
Text {
    text: AtlasShortcuts.readable(saveAction.shortcut)   // "Ctrl+S"
}
Connections {
    target: AtlasShortcuts
    function onConflictsChanged() { console.log(JSON.stringify(AtlasShortcuts.conflicts)) }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `actions` | `list<QtObject>` (read-only) | — | Every registered `AtlasAction`, in the order they were added. |
| `conflicts` | `list` (read-only) | — | The conflicts, as `[{ shortcut: "Ctrl+S", texts: ["Save", "Sort"] }]`, by shortcut. `conflictsChanged()` fires when they change. |

## Methods

| Signature | Description |
|---|---|
| `add(QtObject action)` | Registers an action. `AtlasAction` does this itself; an app doesn't call it. |
| `keys(var sequence): list` | The sequence as keycap labels: one list per chord, one string per key. |
| `plainText(string text): string` | An action's text without its `&` mnemonic markers (`&&` is one `&`). |
| `portable(var sequence): string` | The portable text (`"Ctrl+S"`, English names): what `conflicts` reports. |
| `readable(var sequence): string` | The sequence in the platform's own spelling (`"Ctrl+Shift+S"`). Empty when it is no shortcut. |
| `remove(QtObject action)` | Unregisters an action. `AtlasAction` does this itself; an app doesn't call it. |

`sequence` is a string or a `StandardKey` number in all of these.
