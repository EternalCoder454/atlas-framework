---
title: AtlasAutocompleteField
summary: A text field that suggests completions from a list or model while you type.
section: Fields and pickers
since: "1.4.0"
---

AtlasAutocompleteField is an [AtlasTextField](atlas-text-field.md) with a suggestion popup. `model` is a list of strings or a model with `textRole`. The popup lists up to `maxSuggestions` choices that contain what was typed (`filter: "contains"`, the default) or start with it (`"startsWith"`), in any case, with the matching part in bold. The focus stays in the field. A model of ten thousand strings works: filtering waits 60 ms after the last key and stops at `maxSuggestions`.

## Example

```qml
AtlasAutocompleteField {
    model: ["Berlin", "Bern", "Bergen", "Paris"]
    placeholderText: qsTr("City")
    onAccepted: text => search(text)
}
```

## Keyboard

- Up and Down move among the suggestions. Nothing is highlighted until you do.
- Return or Tab takes the highlighted suggestion.
- Escape closes the list; a second Escape goes on to whoever is behind.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `clearable` | `bool` | `false` | A small cross empties the field. Passed to the inner text field. |
| `errorText` | `string` | `""` | A non-empty text turns the outline red and shows the message. Passed to the inner text field. |
| `filter` | `string` | `"contains"` | `"contains"` or `"startsWith"`. |
| `maxSuggestions` | `int` | `8` | The most choices the popup lists. |
| `model` | `var` | `[]` | A list of strings, or a model; with a model, `textRole` names the role. |
| `placeholderText` | `string` | `""` | Hint shown while the field is empty. |
| `popupOpen` | `bool` (read-only) | `false` | `true` while the suggestion list is open. |
| `readOnly` | `bool` | `false` | The text can't be edited. |
| `text` | `string` | `""` | What the user typed or took. |
| `textRole` | `string` | `""` | The model role that holds the text. |

## Signals

| Name | Description |
|---|---|
| `accepted(string text)` | A suggestion was taken, or Return was pressed with no list open. |
