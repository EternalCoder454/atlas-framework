---
title: Symbols
summary: Google's Material Symbols as fonts, drawn with the Symbol type and named with Symbols.<Name>: styles, filled and outline, size, colour and how to find a name.
order: 2
---

Atlas apps draw their icons with Google's Material Symbols: about 4,000 icons in three styles (Outlined, Rounded and Sharp), each as a variable font. [Symbol](../atlas-ui/symbol.md) draws one, tinted like text, and [Symbols](../atlas-ui/symbols.md) is the singleton that holds every icon's value. Buttons, sidebar items and menu items take a `symbol:` property that is a `Symbols.<Name>`.

## Example

```qml
import QtQuick
import Atlas.Ui

Row {
    Symbol { icon: Symbols.Settings }
    Symbol { icon: Symbols.Favorite; filled: true; color: AtlasStyle.error }
    Symbol { name: "arrow_back"; style: Symbol.Sharp; size: 24; weight: 300 }
    PrimaryButton { text: qsTr("Share"); symbol: Symbols.Share }
}
```

## Naming

`Symbols.<Name>` is Google's name in PascalCase: `arrow_back` is `ArrowBack`, and a leading number is spelled out (`10k` is `TenK`). It is an enum, so a misspelled one is caught at build time by the app's `<app>_qmllint` target. `Symbol { name: "arrow_back" }` takes Google's name as a string instead (`arrow_back`, `arrow-back` and `ArrowBack` all work, and so do older Google names kept as aliases) and logs a warning at run time when there is none. Prefer `icon:`, which is checked when the app is built.

`Symbols.codepoint(name)`, `Symbols.name(codepoint)`, `Symbols.key(codepoint)` and `Symbols.names()` convert between the forms.

## Finding a symbol

There are thousands, so look one up rather than guess:

- Run the [Atlas Gallery](gallery.md): search, pick a style, fill and weight, then press Copy QML.
- Browse <https://fonts.google.com/icons> and convert the name as above.
- Search `api/symbols.txt` in the atlas-framework repository, which lists every `Symbols.<Name>` value.

## Fonts and licence

The fonts are Google's Material Symbols, under the Apache License 2.0 (the rest of Atlas Framework is MIT). Two packages carry them, both installed to `/usr/share/fonts/atlas-symbols` and found through fontconfig:

| Package | Contents |
|---|---|
| `atlas-symbols-fonts` | Rounded, the default and the only style Atlas.Ui's own controls use. `atlas-ui` requires it. |
| `atlas-symbols-fonts-extra` | Outlined and Sharp. The gallery recommends it. |

A Symbol that asks for a style that is not installed draws blank and logs one warning. `Symbols.available(style)` tells whether a style is installed, without a warning. Unused styles cost no memory: a font is only mapped once something draws with it.

## Properties of a Symbol

| Property | Meaning |
|---|---|
| `icon` | A `Symbols.<Name>` value; 0 means use `name`. |
| `name` | Google's name, used when `icon` is 0. |
| `style` | `Symbol.Outlined`, `Symbol.Rounded` (default) or `Symbol.Sharp`. |
| `filled`, `fill` | Solid or outline. `fill` runs 0 to 1 for anything between, and a change animates. |
| `weight` | Stroke weight, 100 (thin) to 700 (bold); 400 matches regular text. |
| `grade` | A finer weight change that keeps the size, -50 to 200. Light symbols on a dark background look heavier, so -25 evens them out. |
| `size` | Width and height in pixels; the default is `Kirigami.Units.iconSizes.smallMedium`. |
| `color` | The tint; the default is the theme's text colour. |

See the [Symbol](../atlas-ui/symbol.md) page for the full list.

## Filled or outline

Only the selected item of a navigation control (a sidebar entry, tab bar or view switcher tab) turns solid with `filled`. Everything else, selected or not, uses the outline. Controls from Atlas.Ui do this already; follow the same rule in an app's own navigation.

## Size, colour and weight

- Size: the optical size follows the drawn size (between 20 and 48), so small symbols get the sturdier strokes the font draws for them. Use the default for inline icons and `Kirigami.Units.iconSizes` values for others, not arbitrary pixels.
- Colour: a Symbol is tinted like text. Use `AtlasStyle` colours or `Kirigami.Theme` colours and never hard-code one, so light, dark and the user's accent all work.
- Accessibility: a Symbol is decorative and screen readers skip it, so give the control around it an accessible name. See [Accessibility](../atlas-ui/accessibility.md).

## Right to left

A Symbol is never mirrored by itself. Where an app picks a directional icon (a back arrow, a chevron), it chooses the left or right one from `LayoutMirroring.enabled` or the control's `mirrored`, as [AtlasBreadcrumb](../atlas-ui/atlas-breadcrumb.md) does for its chevrons.

## Updating the fonts

`ui/symbols/generate.py` rewrites the name table from a download from fonts.google.com. Google sometimes renames or removes an icon; the script keeps the older names as aliases for `name:`, but a removed `Symbols.<Name>` value is an API break (see [Compatibility](../atlas-ui/compatibility.md)).
