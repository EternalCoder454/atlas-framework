---
title: TelamonShortcutLabel
summary: A keyboard shortcut drawn as keycaps, one per key, in the platform's own spelling.
section: Text and code
since: "1.4.0"
---

A keyboard shortcut drawn as keycaps, one per key, in the platform's own spelling. A shortcut of several steps ("Ctrl+K, Ctrl+C") shows the steps one after the other with a comma between them. With no sequence it has no size and is hidden. It follows right-to-left layouts, and screen readers get the sequence as text.

## Example

```qml
TelamonShortcutLabel { sequence: "Ctrl+Shift+S" }
TelamonShortcutLabel { sequence: saveAction.shortcut }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `sequence` | `var` | `""` | The shortcut: a string (`"Ctrl+Shift+S"`) or a `StandardKey` number (`StandardKey.Save`), such as a `TelamonAction`'s `shortcut`. See [TelamonShortcuts](telamon-shortcuts.md). |
