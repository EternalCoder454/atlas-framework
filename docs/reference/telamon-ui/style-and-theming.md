---
title: Style and theming
summary: TelamonStyle's colour, spacing, radius, size and density tokens, how the Plasma accent, light and dark, blur, high contrast and text scale reach an app.
section: Guides
order: 20
---

[TelamonStyle](telamon-style.md) is a singleton of design tokens. A control or an app reads `TelamonStyle.radius` instead of a bare 6 and `TelamonStyle.surface` instead of a hex colour, so the look can change in one file and every app follows. Everything is read-only except `density`. [Appearance](appearance.md) holds the switches the user controls (transparency, colour scheme, motion, text scale).

```qml
import QtQuick
import Telamon.Ui

Rectangle {
    color: TelamonStyle.surface
    radius: TelamonStyle.radius
    border.color: TelamonStyle.separator
    Behavior on color { ColorAnimation { duration: TelamonStyle.durationShort } }
}
```

## Colours

Colours follow the system colour scheme, light or dark. The neutrals are tinted slightly toward Telamon violet, except under high contrast. Light and Dark are tuned separately, so never compute one from the other.

| Token | Use |
|---|---|
| `accent` | Selection, indicators and checked states: Telamon violet (`#6858E2` in Light, `#8A7AF4` in Dark) unless the user chose an accent in Plasma. |
| `accentText` | Text readable on `accent`. |
| `accentStrong`, `accentStrongText` | The prominent (primary) button fill and its text (4.5:1 or more). |
| `focus` | The keyboard focus ring: a magenta-violet (`#A62A8C` Light, `#E28BE0` Dark), or the user's Plasma accent. |
| `base` | The window background (tonal step 0). |
| `surface` | A card over the page, such as a Section (step 1). |
| `surfaceRaised` | Menus, popovers, dialogs and tooltips (step 2). |
| `control` | The fill of fields and default buttons (step 3). |
| `codeSurface`, `surfaceAlt` | A code view's background; the colour scheme's alternate row colour. |
| `hover`, `pressed` | Grey overlays for hover and press, never the accent, so hover never looks like selection. |
| `selection`, `selectionInactive` | A selected row or item (a quiet accent tint); the same when the view has no focus. |
| `text`, `textMuted`, `textDisabled` | Body text; secondary text and units (65% of text); disabled text (55%, still readable). |
| `separator`, `controlBorder` | Decorative hairlines and card borders; control edges (stronger). |
| `success`, `warning`, `error`, `errorFill` | The scheme's positive, neutral and negative text colours; the faint fill of an invalid field. |
| `sakura` | The end of the violet to sakura gradient. Only for the edge glow, an active progress shimmer and "update ready". See [Motion](motion.md). |
| `floatingBackground` | Menus, popovers, notifications and the launcher: tinted over the blur (85%), solid without it. |
| `chromeBackground` | Header bars, sidebars and floating toolbars: lightly blurred (94%), solid without it. |

Tables, text fields, code views and dense forms stay solid.

### The Plasma accent wins

`Appearance.accentFromSystem` is true when the user chose an accent colour in Plasma (`AccentColor` in kdeglobals `[General]`). Then `accent`, `accentStrong` and `focus` all take that colour, as in other KDE apps. Otherwise the Telamon violet is used, and Telamon.Ui puts it in the application palette, so `Kirigami.Theme.highlightColor` is the accent too. An app never branches on this: it reads `TelamonStyle.accent`.

## Light and dark

Telamon.Ui follows the system colour scheme live. `Appearance.colorScheme` and `Appearance.darkMode` report it, and bindings on them update when the user switches. An app reads colours from TelamonStyle and `Kirigami.Theme` and has no mode of its own. The framework tests every control in light, dark, the user's accent, high contrast, right-to-left, compact density and 200% text.

## Spacing, radii and sizes

| Token | Value |
|---|---|
| `spacingXSmall`, `spacingSmall`, `spacing` | 2, 4, 8 |
| `spacingLarge`, `spacingXLarge`, `spacingXXLarge` | 12, 16, 24 |
| `radiusSmall` | 4: buttons, text and search fields, combo boxes, spin boxes, pickers, tabs, sidebar items, menu items and list selections. A button goes to 6 while pressed. |
| `radius` | 6: cards, Sections, popovers, tooltips, menus and code views |
| `radiusLarge` | 8: dialogs, the command palette, drop zones, the segmented control's track, the find bar, and an unchecked checkable chip |
| `radiusPill` | 1000, fully round: switch tracks, progress and usage bars, the floating toolbar, toasts, the find bar's fields and a checked chip. Badges use half their height. |
| `controlHeight` | 28 px, or 24 px when compact. A control grows when its text needs more. |

## Fonts and sizes

`fontFamily` is IBM Plex Sans and `monoFamily` is JetBrains Mono when installed, else the system font and the system fixed font. Telamon apps already use `fontFamily` as the application font, so set `font.family: TelamonStyle.monoFamily` only on code. Sizes are in points, from the application font: `fontSizeCaption` (0.92 of body), `fontSizeBody`, `fontSizeHeading` (1.15) and `fontSizeTitle` (1.6). Use [TelamonLabel](telamon-label.md) with a `textStyle` rather than setting them by hand.

## Density

`TelamonStyle.density` is `TelamonStyle.Normal` (0) or `TelamonStyle.Compact` (1), set by the app. `compact` is the same as a bool, and `rowHeight` is the height of a list or SectionRow row for the density (Normal 2.5 grid units, Compact 75% of that). Controls follow `density`; `SectionRow`, `TabBar`, `StatusBar` and `SidebarItem` also have a local `density`.

```qml
Component.onCompleted: TelamonStyle.density = TelamonStyle.Compact
```

## Blur with a solid fallback

The window is blurred only when `Appearance.effective` is true: the user's "Transparency and blur" switch is on and the compositor offers blur. Software rendering, many virtual machines and a disabled KWin blur effect do not. `floatingBackground` and `chromeBackground` already do the right thing in both cases, translucent over the blur and solid without it. Use them for chrome, and never set a window's opacity yourself.

```qml
Rectangle {
    color: TelamonStyle.floatingBackground
    radius: TelamonStyle.radius
}
```

The switch is `Transparency` under `[Appearance]` in `~/.config/telamonrc`, shared by every Telamon app. [TelamonTransparencySwitch](telamon-transparency-switch.md) is a settings row for it.

## High contrast and text scale

- `TelamonStyle.highContrast` passes `Appearance.highContrast` through: the system asks for high contrast. Separators and control borders become much stronger (alpha 0.4 and 0.8) and the violet tint of the neutrals is dropped.
- `TelamonStyle.textScale` passes `Appearance.textScale` through: the application font's point size over 10, so 1.0 is Plasma's default and 1.2 is 20% larger. Controls grow with their text; an app should lay out with `Layout` and `implicitHeight`, not fixed pixel heights.
- `TelamonStyle.reducedMotion` follows Plasma's animation speed. See [Motion](motion.md).
