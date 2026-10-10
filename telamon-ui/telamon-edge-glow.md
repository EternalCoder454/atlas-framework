---
title: TelamonEdgeGlow
summary: A soft violet-to-sakura glow along the inside edges of its parent, meaning "the system is doing something for you now".
section: Feedback and status
since: "1.4.0"
---

TelamonEdgeGlow is the window-edge glow. The glow fades in, breathes slowly while `active`, and fades out. While inactive, nothing is drawn and no timer or animation runs. Under reduced motion, and in software rendering ([TelamonStyle.softwareRendering](telamon-style.md)), the glow is static: it still shows and hides, without the fade or the breathing, and no animation runs. It is drawn with stacked gradient rectangles (no shader), so it also works with the software renderer.

## Example

```qml
TelamonEdgeGlow { anchors.fill: parent; active: updater.applying }
```

> [!WARNING]
> The glow has one meaning only: the system or the app is doing something for you right now, such as an update being applied or an update that is ready. Never use it for decoration, hover, focus, selection or an error.

Size it to the parent and put it last in the window's content so that it draws above the rest. It takes no input and is hidden from screen readers: say what is happening in text as well (a label, a TelamonStatusHero).

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `active` | `bool` | `false` | `true` while the system or the app is working for the user. |
| `animated` | `bool` | `true` | `false` holds the breathing still (a screenshot); the glow stays visible. |
| `reach` | `real` | `TelamonStyle.spacingXXLarge * 1.5` | How far the glow reaches in from each edge, in pixels. The four edges overlap in the corners by design, so a corner is a little brighter. |
