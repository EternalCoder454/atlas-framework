---
title: TextButton
summary: A link-styled button: accent text, no fill.
section: Buttons
---

TextButton is a quiet button for an action that should read like a link, such as "Learn more" or "Skip". It shows accent text with a grey hover and press tint, never an accent fill. Use [AtlasButton](atlas-button.md) for an action that needs a stronger look.

TextButton is a Qt Quick Templates `AbstractButton` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html)); its inherited properties (`text`, `checkable`, `checked`, `clicked`) work as usual. It has no properties of its own.

## Example

```qml
TextButton { text: qsTr("Learn more"); onClicked: showHelp() }
```

## Keyboard

TextButton takes the keyboard focus with Tab and shows a focus ring; Return, Enter and Space click it.
