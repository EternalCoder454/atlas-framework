---
title: TelamonWindowButtons
summary: The minimise, maximise or restore and close buttons of a frameless window, drawn like the Telamon OS window decoration.
section: Windows and pages
since: "1.4.0"
---

TelamonWindowButtons draws the window buttons as 32 px cells with a 26 px rounded square, as the Telamon OS KWin decoration does. Hover tints the square with the highlight colour and close turns red. [TelamonHeaderBar](telamon-header-bar.md) places two of these in KWin's left and right button layout; use one on its own to build a custom title bar. The colours come from the Header colour set, so a scheme other than Telamon OS's still works.

TelamonWindowButtons is a `Row`. A click minimises, maximises or restores, or closes the window the item is in.

## Example

```qml
TelamonWindowButtons { buttons: ["minimize", "maximize", "close"] }
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `active` | `bool` | `Window.active` | Whether the window is active; an inactive window draws fainter buttons. |
| `buttons` | `var` | `["minimize", "maximize", "close"]` | Which buttons to show, left to right: `"minimize"`, `"maximize"` and `"close"`. |
| `maximized` | `bool` (read-only) | — | True while the window is maximised; the maximise button then shows "restore". |

## Accessibility

The buttons never take keyboard focus (the header's window menu is the keyboard way) and carry accessible names.
