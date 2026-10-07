---
title: Symbols
summary: The singleton that holds every Material Symbol's value as Symbols.Name, and looks symbols up by name.
section: Icons
since: "1.3.0"
---

Symbols is a singleton with about 4,000 enum values, one per Material Symbol. A value is the symbol's codepoint in the fonts; pass it to [Symbol](symbol.md) as `icon:` or to a control's `symbol:` property. See the [symbols library](../symbols/index.md) for the fonts.

`Symbols.<Name>` is Google's name in PascalCase: `arrow_back` is `Symbols.ArrowBack`, and a leading number is spelled out (`10k` is `Symbols.TenK`). Because the values are an enum, the `<app>_qmllint` target flags a misspelled one. To find a name, search the Telamon Gallery (`telamon-symbols`: search, pick a style, then Copy QML) or `api/symbols.txt` in the telamon-framework repository, which lists every `Symbols.<Name>` value. The values are not listed on this page.

Use the outline for everything; only the selected item of a navigation control (sidebar entry, tab or view switcher tab) turns solid, with `Symbol.filled`.

## Example

```qml
Row {
    Symbol { icon: Symbols.Settings }
    TelamonButton { text: qsTr("Delete"); symbol: Symbols.Delete }
    Symbol { name: "arrow_back" }
}
```

## Methods

| Signature | Description |
|---|---|
| `available(int style): bool` | Returns whether the font of a `Symbol.Style` (0 Outlined, 1 Rounded, 2 Sharp) is installed. No warning if not. |
| `codepoint(string name): int` | Returns the codepoint for a name (`"arrow_back"`, `"arrow-back"`, `"ArrowBack"` or an older name such as `"check_circle_outline"`), in any case and with spaces or hyphens for underscores. Returns 0 with a warning for an unknown name, and 0 without one for an empty name. |
| `family(int style): string` | Returns the font family of a `Symbol.Style` (0 Outlined, 1 Rounded, 2 Sharp); an out-of-range style gives Rounded. It returns the name even when the font is not installed, and then logs one warning per style (Rounded warns when the fonts load). Use `available()` for a silent check. |
| `key(int codepoint): string` | Returns the QML name for a codepoint (`"ArrowBack"`, for `Symbols.ArrowBack`); empty for none. |
| `name(int codepoint): string` | Returns Google's name for a codepoint (`"arrow_back"`); empty for none. |
| `names(): list<string>` | Returns every symbol's name, sorted, without the older names. |

> [!NOTE]
> Removing or renaming a `Symbols.<Name>` value breaks apps, so the framework treats the set of names as a contract. Prefer `Symbols.<Name>` to `name:` strings: a misspelling is caught at build time, not at run time.
