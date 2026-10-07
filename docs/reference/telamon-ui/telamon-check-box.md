---
title: TelamonCheckBox
summary: A rounded check box with a label and an optional partly-checked state.
section: Buttons
---

TelamonCheckBox is a Qt Quick Controls `CheckBox` with the Telamon look. With `tristate: true` it also has a partly-checked state (`checkState === Qt.PartiallyChecked`), drawn as a dash; a click then cycles unchecked, partly, checked. All its properties are inherited: `text`, `checked`, `checkState`, `tristate`, `toggled()`. See <https://doc.qt.io/qt-6/qml-qtquick-controls-checkbox.html>.

## Example

```qml
TelamonCheckBox { text: qsTr("Remember me"); checked: true }
TelamonCheckBox { text: qsTr("Select all"); tristate: true; checkState: Qt.PartiallyChecked }
```

## Accessibility

The check box is one Tab stop. A screen reader gets `text` as its name. Without `text`, name it with `Accessible.name`. A partly-checked box reports a mixed state.
