---
title: TelamonTextArea
summary: A multi-line text field with small rounded corners that wraps long lines and lets Tab move focus on.
section: Fields and pickers
since: "1.3.0"
---

A multi-line text field with small rounded corners. `placeholderText` shows while it is empty. It wraps long lines; put it in a `ScrollView` or give it a height for long text. With `wrapMode: TextEdit.NoWrap` (a log or code view) it is as wide as its longest line, so a `ScrollView` around it scrolls sideways. For one line, use [TelamonTextField](telamon-text-field.md).

TelamonTextArea is a Qt Quick Controls [`TextArea`](https://doc.qt.io/qt-6/qml-qtquick-templates-textarea.html); `text`, `placeholderText`, `wrapMode` and the rest work as usual. The text is always plain: `textFormat` is `TextEdit.PlainText`, so text that looks like HTML is shown and kept as typed (rich text would draw its tags and load the pictures it names).

## Example

```qml
TelamonTextArea {
    placeholderText: qsTr("Notes")
    implicitHeight: Kirigami.Units.gridUnit * 8
}
```

## Keyboard

Tab and Shift+Tab move the focus on, as in a form. A plain `TextArea` would type a tab character.
