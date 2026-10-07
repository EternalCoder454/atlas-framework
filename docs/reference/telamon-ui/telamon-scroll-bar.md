---
title: TelamonScrollBar
summary: A thin, rounded scroll bar whose thumb widens on hover and fades out when nothing is scrolling.
section: Layout
since: "1.4.0"
---

A thin, rounded scroll bar. The thumb widens when the pointer is over the bar and fades out when nothing is scrolling (policy `AsNeeded`). It stays drawn while hovered or pressed, and always when a screen reader is active ([AccessibilityState](accessibility-state.md)). Under reduced motion nothing fades or grows slowly: it shows and hides at once.

TelamonScrollBar is a Qt Quick Controls [`ScrollBar`](https://doc.qt.io/qt-6/qml-qtquick-templates-scrollbar.html); its inherited properties work as usual.

## Example

```qml
Flickable {
    ScrollBar.vertical: TelamonScrollBar {}
}
```
