---
title: TelamonIcon
summary: A theme icon (Kirigami.Icon) that stays under the dialogs, popups and menus in front of it with Qt Quick's software renderer.
section: Icons
since: "2.0.5"
---

TelamonIcon is a `Kirigami.Icon` for icons from the icon theme or an image url (`source: "folder"`). Use it wherever an icon can end up under a dialog, popup or menu. With Qt Quick's software renderer, which Telamon apps use by default, a plain `Kirigami.Icon` draws as a render node, and when a repaint touches part of it (a blinking cursor, a list update) the whole icon is painted again over whatever covers it. TelamonIcon is a layer on the software renderer, an ordinary image node that stays in its place. With OpenGL and the other renderers it is the plain icon. Telamon.Ui's own controls use it for all their icons.

TelamonIcon is a `Kirigami.Icon`; all of its properties work as usual. For a Material Symbol, use [Symbol](symbol.md).

## Example

```qml
TelamonIcon {
    source: "folder"
    implicitWidth: Kirigami.Units.iconSizes.medium
    implicitHeight: Kirigami.Units.iconSizes.medium
}
```
