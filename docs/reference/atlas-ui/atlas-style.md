---
title: AtlasStyle
summary: A singleton of design tokens: colours by role, spacing, radii, fonts, durations and density, so no app hard-codes a number.
section: Style and motion
since: "1.4.0"
---

`AtlasStyle` is a singleton holding the design tokens of Atlas apps in one place. A control or an app reads `AtlasStyle.radius` instead of a bare 6, so the look can change in one file and every app follows. Everything is read-only except `density`.

Colours follow the system colour scheme, light or dark, with the neutrals tinted slightly toward Atlas violet (not under high contrast). Light and Dark are tuned separately. The accent is the user's Plasma accent when they chose one.

## Example

```qml
Rectangle {
    color: AtlasStyle.surface
    radius: AtlasStyle.radius
    border.color: AtlasStyle.separator
    Behavior on color { ColorAnimation { duration: AtlasStyle.durationShort } }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accent` | `color` (read-only) | — | Atlas violet (`#6858E2` Light, `#8A7AF4` Dark); the user's Plasma accent wins. For selection, indicators and checked states. |
| `accentStrong` | `color` (read-only) | — | The prominent (primary) button fill: `#5B4BD6` in Light (6:1 with white), `#A396F7` in Dark. The user's Plasma accent wins when they picked one. |
| `accentStrongText` | `color` (read-only) | — | Text on `accentStrong` (4.5:1 or more); the Plasma highlighted-text colour with a user accent. |
| `accentText` | `color` (read-only) | — | Text readable on `accent`. |
| `base` | `color` (read-only) | — | The window background (tonal step 0), tinted slightly toward violet (not under high contrast). |
| `chromeBackground` | `color` (read-only) | — | Header bars, sidebars and floating toolbars: lightly blurred (94%), solid without blur. |
| `codeSurface` | `color` (read-only) | — | A code view's own background. |
| `compact` | `bool` (read-only) | — | `true` when `density` is Compact. |
| `control` | `color` (read-only) | — | The fill of fields and default buttons (step 3). |
| `controlBorder` | `color` (read-only) | — | Control edges, stronger than `separator`. |
| `controlHeight` | `real` (read-only) | — | The height of a button, field or combo box: 28 px, or 24 px when compact. A control grows when its text needs more. |
| `density` | `int` (AtlasStyle.Density) | `AtlasStyle.Normal` | `AtlasStyle.Normal` or `AtlasStyle.Compact`, set by the app. The only writable property. |
| `duration` | `int` (read-only) | — | The everyday animation duration: 150 ms, or 0 under reduced motion. |
| `durationLong` | `int` (read-only) | — | The long animation duration: 250 ms, or 0 under reduced motion. |
| `durationShort` | `int` (read-only) | — | The short animation duration: 100 ms, or 0 under reduced motion. |
| `error` | `color` (read-only) | — | The colour scheme's negative text colour. |
| `errorFill` | `color` (read-only) | — | The faint fill of an invalid field. |
| `floatingBackground` | `color` (read-only) | — | Menus, popovers, notifications and the launcher: `surfaceRaised` at 85% over the blur, solid without it. |
| `focus` | `color` (read-only) | — | The keyboard focus ring: magenta-violet (`#A62A8C` Light, `#E28BE0` Dark); the user's Plasma accent wins. |
| `fontFamily` | `string` (read-only) | — | The application font's family: IBM Plex Sans when installed, else the system font. |
| `fontSizeBody` | `real` (read-only) | — | The body size in points: the application font's size. |
| `fontSizeCaption` | `real` (read-only) | — | Footers and hints: 0.92 of body. |
| `fontSizeCode` | `real` (read-only) | — | Code: the body size (in `monoFamily`). |
| `fontSizeHeading` | `real` (read-only) | — | Dialog titles: 1.15 of body. |
| `fontSizeTitle` | `real` (read-only) | — | Page titles: 1.6 of body. |
| `fontSizeWindowTitle` | `real` (read-only) | — | A header bar's title: the body size. |
| `fontWeightWindowTitle` | `int` (read-only) | — | The weight of a window title: `Font.DemiBold`. |
| `highContrast` | `bool` (read-only) | — | Passes `Appearance.highContrast` through. |
| `hover` | `color` (read-only) | — | A grey overlay for hover, never the accent, so hover never looks like selection. |
| `monoFamily` | `string` (read-only) | — | The fixed-width family: JetBrains Mono when installed, else the system fixed font. Set `font.family: AtlasStyle.monoFamily` on code. |
| `pressed` | `color` (read-only) | — | A grey overlay for a pressed control. |
| `radius` | `real` (read-only) | — | 6: menus, cards, popovers, tooltips and code views. |
| `radiusLarge` | `real` (read-only) | — | 8: dialogs, the command palette, drop zones and the segmented control's track. |
| `radiusPill` | `real` (read-only) | — | 1000: fully round shapes at any height: switch tracks, the radio button, progress and usage bars, toasts, and a chip that is checked or not checkable. |
| `radiusSmall` | `real` (read-only) | — | 4: controls (buttons, fields, combo boxes, menu items, sidebar and list selections). |
| `softwareRendering` | `bool` (read-only) | `false` | `true` when rendering is in software: the Qt Quick software adaptation, or the RHI on a software rasterizer (`GL_RENDERER` or the Vulkan device is llvmpipe, softpipe, SwiftShader or lavapipe). Known once the first window's scene graph is up, so it changes at most once, from `false` to `true`. `ATLAS_SOFTWARE_RENDERING=1` or `0` forces it (any other value is logged and ignored). Atlas controls go static or slow under it (the edge glow, shimmers, the skeleton sweep) or step at 20 frames a second or fewer where motion carries meaning (spinners, indeterminate bars). An animated or shader effect of your own should check it. Since 1.5.0. |
| `reducedMotion` | `bool` (read-only) | — | Follows `Appearance.reducedMotion` (Plasma's animation speed set to instant, or `ATLAS_REDUCED_MOTION=1`). An animation with no duration, such as a spinner, checks this. |
| `rowHeight` | `real` (read-only) | — | The height of a list or `SectionRow` row: 2.5 grid units, or 75% of that when compact. |
| `sakura` | `color` (read-only) | — | The second end of the signature gradient, which runs from `accent` to sakura. Only for the edge glow, an active progress shimmer and "update ready": never on buttons, selection or text. |
| `selection` | `color` (read-only) | — | A selected row or item: a quiet accent tint. |
| `selectionInactive` | `color` (read-only) | — | A selected row or item when the view has no focus. |
| `separator` | `color` (read-only) | — | Decorative hairlines and card borders (light). |
| `spacing` | `real` (read-only) | — | 8: the middle step of the spacing scale. |
| `spacingLarge` | `real` (read-only) | — | 12. |
| `spacingSmall` | `real` (read-only) | — | 4. |
| `spacingXLarge` | `real` (read-only) | — | 16. |
| `spacingXSmall` | `real` (read-only) | — | 2. |
| `spacingXXLarge` | `real` (read-only) | — | 24. |
| `success` | `color` (read-only) | — | The colour scheme's positive text colour. |
| `surface` | `color` (read-only) | — | A card over the page (a `Section`'s card, step 1). |
| `surfaceAlt` | `color` (read-only) | — | The alternate row colour of the colour scheme. |
| `surfaceRaised` | `color` (read-only) | — | Menus, popovers, dialogs and tooltips (step 2). |
| `text` | `color` (read-only) | — | Body text. |
| `textDisabled` | `color` (read-only) | — | Disabled text, still readable: 55% of `text`. |
| `textMuted` | `color` (read-only) | — | Secondary information ("Step 2 of 2"), captions and units: 65% of `text`. |
| `textScale` | `real` (read-only) | — | Passes `Appearance.textScale` through. |
| `warning` | `color` (read-only) | — | The colour scheme's neutral text colour. |

Spacing steps are 2, 4, 8, 12, 16 and 24 pixels.

## Enums

### Density

| Value | Description |
|---|---|
| `AtlasStyle.Normal` | The default density (0). Rows are 2.5 grid units and controls 28 px high. |
| `AtlasStyle.Compact` | Denser rows (75% of normal) and 24 px controls (1). |

## Motion and springs

The durations are quick and subtle, and all 0 when `reducedMotion` is `true`. A running animation or `Behavior` reads one of them. Spatial movement (a panel opening, a row expanding, a selection indicator sliding) uses [AtlasSpringAnimation](atlas-spring-animation.md): standard by default, and `expressive: true` only for signature moments. Colour and opacity never spring: they fade with the durations.

> [!NOTE]
> The sakura colour is only for the edge glow, an active progress shimmer and "update ready". Never use it on buttons, selection or text.
