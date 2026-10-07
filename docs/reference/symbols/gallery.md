---
title: Telamon Gallery
summary: The Telamon Gallery app (telamon-symbols) shows every Telamon.Ui control live and every Material Symbol, and copies the QML for either.
order: 10
---

The Telamon Gallery is an app that shows what Telamon.Ui can do. It has two pages, Symbols and Controls, and builds from the same controls it shows, so it is also a sample of a Telamon app.

Install it with `sudo dnf install telamon-symbols` and start it with `telamon-symbols` or from the app menu. The package recommends `telamon-symbols-fonts-extra`, so the Outlined and Sharp styles show too; without it the page says so.

## Symbols

Every Material Symbol in a grid, with:

- a search field (it shows how many symbols match);
- a style choice: Outlined, Rounded or Sharp;
- a Filled switch;
- a weight slider (100 to 700);
- a large preview of the selected symbol with its Google name and its `Symbols.<Name>` name;
- **Copy QML**, which copies a ready `Symbol { ... }` snippet for the selected symbol, style, fill and weight.

See [Symbols](index.md) for how to use the result.

## Controls

Every Telamon.Ui control with a demo, grouped (Buttons, Inputs, Pickers, Selection, Lists and tables, Navigation and layout, Windows and dialogs, Feedback and status, Data display, Text, Style and services). Pick one to see it live, with:

- **Copy QML**, which copies the demo's snippet, taken from the usage example in the control's header comment;
- a **Disabled** switch that shows the control disabled;
- **Open the window** for the controls that are windows or dialogs.

## Theme and density

The header has two toggles that apply to the whole gallery at once, so you can see a control in every setting an app will meet:

| Toggle | Choices |
|---|---|
| Colour scheme | System, Light, Dark |
| Density | Normal, Compact (`TelamonStyle.density`) |

The gallery also runs on the user's accent colour, transparency setting and text size like any Telamon app. Its demos are what the framework's visual and accessibility tests run on, so a control that shows here is covered by them. See [Accessibility](../telamon-ui/accessibility.md).
