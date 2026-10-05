---
title: Appearance
summary: A singleton with the look switches every Atlas app shares: transparency and blur, colour scheme, motion, text scale and the brand fonts.
section: Style and motion
---

Appearance holds the shared "Transparency and blur" setting (`Transparency` under `[Appearance]` in `atlasrc`, default on) and follows the desktop's preferences live. A `KConfigWatcher` keeps every open Atlas app in step when one of them, or the user, changes the file. Most apps read it through [AtlasStyle](atlas-style.md) and [AtlasWindow](atlas-window.md) rather than directly.

## Example

```qml
import QtQuick
import Atlas.Ui

Rectangle {
    color: Appearance.darkMode ? "#202020" : "#f5f5f5"
    Behavior on color {
        enabled: !Appearance.reducedMotion
        ColorAnimation { duration: 150 }
    }
}
```

> [!NOTE]
> `effective` is what a window acts on: `transparency` is on AND the compositor offers blur. Blur is missing in software rendering, many VMs, and when KWin's blur effect is off. Nothing signals a change in the compositor, so call `refresh()` when a window is shown or activated (`AtlasWindow` does).

The read-only system preferences each have a change signal, so a binding on them updates when the user changes the setting. The brand properties are `CONSTANT` but computed on each read. Separately, once when Atlas.Ui loads, `atlasUiApplyBrand()` sets the application font's family to IBM Plex Sans (when installed) and puts the violet highlight in the application palette unless the user chose a Plasma accent; it applies the palette again when the colour scheme changes.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accentFromSystem` | `bool` (read-only) | — | `true` when the user chose an accent colour in Plasma (`AccentColor` in kdeglobals `[General]`). Then that accent is used; otherwise the Atlas violet (and the magenta-violet focus ring) is. Constant. Since 1.4.0. |
| `blurAvailable` | `bool` (read-only) | `false` until read | Whether the compositor offers blur. Updated by `refresh()`. |
| `colorScheme` | `int` (read-only) (Appearance.ColorScheme) | `Appearance.UnknownScheme` | The system colour scheme, from `QStyleHints`. |
| `darkMode` | `bool` (read-only) | `false` | `true` when `colorScheme` is dark. When it is unknown, whether the palette's window colour is dark. |
| `effective` | `bool` (read-only) | — | `transparency && blurAvailable`: whether windows should be translucent over blur. |
| `fontFamily` | `string` (read-only) | — | `"IBM Plex Sans"` when installed, else the system font's family. It is the application font's family only when IBM Plex Sans is installed. Constant, but computed on each read. Since 1.4.0. |
| `highContrast` | `bool` (read-only) | `false` | The system asks for high contrast (`QStyleHints` accessibility, Qt 6.10+). |
| `monoFamily` | `string` (read-only) | — | `"JetBrains Mono"` when installed, else the system fixed font. Constant, but computed on each read. Since 1.4.0. |
| `reducedMotion` | `bool` (read-only) | `false` | `true` when Plasma's `AnimationDurationFactor` in kdeglobals `[KDE]` is 0 (animations off), or the environment has `ATLAS_REDUCED_MOTION=1`. A missing kdeglobals means `false`. |
| `textScale` | `real` (read-only) | `1.0` | The application font's point size over 10 (Plasma's default). 1.0 is the default size, 1.2 is 20% larger. |
| `transparency` | `bool` | `true` | The shared "Transparency and blur" setting. Writable; the change is saved to `atlasrc` and reaches every open Atlas app. |

## Methods

| Signature | Description |
|---|---|
| `applyBlur(QWindow* window): void` | Blurs (or stops blurring) everything behind the whole window, following `effective`. The window must exist: call it once it is visible. |
| `refresh(): void` | Asks the compositor again whether blur is on. |

## Enums

### ColorScheme

| Value | Description |
|---|---|
| `Appearance.UnknownScheme` | The system does not say. |
| `Appearance.LightScheme` | The light colour scheme. |
| `Appearance.DarkScheme` | The dark colour scheme. |
