---
title: TelamonBadge
summary: A small pill label for a status or count, or a dot meaning "something is new here".
section: Feedback and status
since: "1.4.0"
---

TelamonBadge shows a short text such as "New", "3" or "Beta". `type` picks the tint. `symbol` adds a Material Symbol before the text. With no text and no symbol it is a small dot (`dot`).

## Example

```qml
TelamonBadge { text: qsTr("Beta"); type: "accent" }
TelamonBadge { text: "3"; type: "error" }
TelamonBadge { type: "success" }          // a dot
```

## Accessibility

A badge is not interactive and has no Tab stop. A screen reader gets the text. A dot or a symbol with no text gets the name of its type ("Warning"), or `accessibleName` when the app sets it ("Update available"). Give a dot an accessible name where the dot is the only sign.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accessibleName` | `string` | `text`, or the type's name when there is no text | What a screen reader says. |
| `dot` | `bool` | `true` when there is no text and no symbol | Shows the badge as a small dot. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | A Material Symbol before the text; 0 for none. |
| `text` | `string` | `""` | The label. |
| `type` | `string` | `"neutral"` | The tint: `"neutral"`, `"accent"`, `"success"`, `"warning"` or `"error"`. |
