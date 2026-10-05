---
title: AccessibilityState
summary: A singleton that says whether a screen reader or other assistive technology is listening.
section: Services
---

AccessibilityState wraps Qt's accessibility activation. A component can use `active` to leave out text that only a screen reader would read. Qt keeps the answer and emits `activeChanged` when it changes.

Since 1.5.0 it also reports what the platform asks for: Qt's accessibility contrast preference and the desktop portal's `org.freedesktop.appearance` settings (`contrast`, `reduced-motion`, `accent-color`), read once and followed when they change. Without a portal they keep their defaults. [Appearance](appearance.md) and [AtlasStyle](atlas-style.md) include these and Plasma's own settings, so a control normally reads those.

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
| `highContrast` | `bool` (read-only) | `false` | The system asks for more contrast: Qt's contrast preference is high, or the portal's `contrast` is 1. Since 1.5.0. |
| `reducedMotion` | `bool` (read-only) | `false` | The portal's `reduced-motion` is 1, or `ATLAS_REDUCED_MOTION=1`. Since 1.5.0. |
| `accentColor` | `color` (read-only) | invalid | The accent colour the portal reports, or an invalid colour when there is none. Plumbing for apps; Atlas.Ui's own accent still follows Plasma's. Since 1.5.0. |

## Signals

| Name | Description |
|---|---|
| `activeChanged()` | `active` changed. |
| `highContrastChanged()` | `highContrast` changed. |
| `reducedMotionChanged()` | `reducedMotion` changed. |
| `accentColorChanged()` | `accentColor` changed. |
