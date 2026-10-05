---
title: AccessibilityState
summary: A singleton that says whether a screen reader or other assistive technology is listening.
section: Services
---

AccessibilityState wraps Qt's accessibility activation. A component can use `active` to leave out text that only a screen reader would read. Qt keeps the answer and emits `activeChanged` when it changes.

## Example

```qml
import QtQuick.Controls
import Atlas.Ui

Label {
    // Spoken hint, visible only while a screen reader is listening.
    visible: AccessibilityState.active
    text: qsTr("Press Enter to open")
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `active` | `bool` (read-only) | — | `true` while an assistive technology is listening. A binding on it updates when that changes. |
