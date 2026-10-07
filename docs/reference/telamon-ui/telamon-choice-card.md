---
title: TelamonChoiceCard
summary: One of a few choices shown as a picture with its name and a check circle; exclusive in a group.
section: Buttons
since: "1.5.0"
---

TelamonChoiceCard is one of a few choices, shown as a picture with its name under it and a check circle beside the name. The chosen card has a ring in the accent colour around the picture; hover and keyboard focus show a fainter ring. For a plain choice in a form, use [TelamonRadioButton](telamon-radio-button.md); for accent colours, [TelamonAccentPicker](telamon-accent-picker.md).

TelamonChoiceCard is a Qt Quick Templates `AbstractButton` and always `checkable`; its inherited properties (`text`, `checked`, `checkable`, `autoExclusive`, `toggled`) work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html>.

## Example

```qml
ButtonGroup { id: group }
TelamonChoiceCard {
    text: qsTr("Dark")
    source: "qrc:/themes/dark.png"
    ButtonGroup.group: group
    checked: app.theme === "dark"
    onToggled: if (checked) app.theme = "dark"
}
```

## Exclusive choice

Cards are not exclusive by themselves, as for any button. Put them in a `ButtonGroup`, or set `autoExclusive: true` on each card with the same parent.

## User edits and bindings

A user's choice does not end an app's binding on `checked`: the new value is held for one turn of the event loop, then the binding is restored. A binding that takes the edit in `onToggled` follows the app; one that refuses it springs back. With no binding the choice stays. See "User edits and app bindings" in the 1.5.0 notes.

## Keyboard

A card is a Tab stop; Space chooses it. Inside a `ButtonGroup`, the arrow keys follow the group's usual rules.

## Accessibility

Screen readers get a radio button named `text`, checked when chosen.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `aspectRatio` | `real` | `1.6` | The picture's width over its height (1.6 is 16:10). A value that is not a finite number above 0 uses 1.6. |
| `source` | `url` | empty | The picture, cropped to fill its frame with rounded corners. While it loads, and if it is missing or cannot be read, the empty frame shows. |
