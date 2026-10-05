---
title: Symbol
summary: Draws one Material Symbol, tinted like text.
section: Icons
---

Symbol draws a Material Symbol. Pick one by value (`icon: Symbols.Settings`, checked at build time) or by Google's name (`name: "arrow_back"`). The default style is Rounded. Browse them all with the Atlas Gallery (`atlas-symbols`) or at fonts.google.com/icons; see [Symbols](symbols.md) and the [symbols library](../symbols/index.md).

Symbol is an `Item` and is decorative: screen readers skip it, so give the control around it the accessible name. Controls take a `symbol:` property for the common case, so use Symbol directly only for a free-standing icon.

## Example

```qml
Row {
    Symbol { icon: Symbols.Settings }
    Symbol { name: "arrow_back"; size: 24 }
    Symbol { icon: Symbols.Favorite; filled: liked; color: Kirigami.Theme.negativeTextColor }
    Symbol { icon: Symbols.Home; style: Symbol.Sharp; weight: 300 }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `codepoint` | `int` (read-only) | — | The codepoint drawn: `icon`, else the one for `name`, else 0 (nothing drawn). |
| `color` | `color` | `Kirigami.Theme.textColor` | The tint. |
| `fill` | `real` | `filled ? 1 : 0` | How solid the symbol is, 0 (outline) to 1 (solid). Changes animate, including ones set directly for anything in between. |
| `filled` | `bool` | `false` | The solid version of the symbol. |
| `grade` | `int` | `0` | A finer weight change that keeps the symbol's size, -50 to 200. Light symbols on a dark background look heavier: -25 evens them out. |
| `icon` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | The symbol to draw; 0 uses `name`. |
| `name` | `string` | `""` | Google's name ("arrow_back"), used when `icon` is 0. Warns at run time if there is no such symbol. |
| `size` | `real` | `Kirigami.Units.iconSizes.smallMedium` | The drawn size in pixels. The font's optical size follows it. |
| `style` | `int` (Symbol.Style) | `Symbol.Rounded` | The font style. |
| `weight` | `int` | `400` | The stroke weight, 100 (thin) to 700 (bold); 400 matches regular text. |

## Enums

### Style

| Value | Description |
|---|---|
| `Symbol.Outlined` | Outlined; installed by `atlas-symbols-fonts-extra`. |
| `Symbol.Rounded` | Rounded, the default; installed by `atlas-symbols-fonts`. |
| `Symbol.Sharp` | Sharp; installed by `atlas-symbols-fonts-extra`. |

> [!NOTE]
> A Symbol that asks for a style whose font is missing draws blank and logs one warning; `Symbols.available(style)` tells. Only the selected item of a navigation control (sidebar entry, tab or view switcher tab) uses `filled: true`; everything else uses the outline.
