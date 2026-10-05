---
title: AtlasWindowChrome
summary: A singleton with KWin's caption button layout and whether the desktop has a global menu.
section: Windows and pages
since: "1.4.0"
---

AtlasWindowChrome tells a frameless [AtlasWindow](atlas-window.md) what the desktop says about window decoration. [AtlasHeaderBar](atlas-header-bar.md) and [AtlasAppMenu](atlas-app-menu.md) use it; an app rarely needs it directly. It is a singleton and follows `kwinrc` and the D-Bus name live.

## Example

```qml
Component.onCompleted: console.log(AtlasWindowChrome.buttonsOnRight, AtlasWindowChrome.globalMenu)
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `buttonsOnLeft` | `list<string>` (read-only) | `["menu"]` | KWin's left caption buttons (`ButtonsOnLeft` in `kwinrc`), as `"menu"`, `"minimize"`, `"maximize"` and `"close"`, in KWin's order. Other KWin buttons are dropped. |
| `buttonsOnRight` | `list<string>` (read-only) | `["minimize", "maximize", "close"]` | KWin's right caption buttons (`ButtonsOnRight` in `kwinrc`), in the same form. |
| `globalMenu` | `bool` (read-only) | `false` | True when the desktop has a global menu (an owner of the D-Bus name `com.canonical.AppMenu.Registrar`) and the Qt platform theme is KDE's, so the native menu export can work. False until the first answer arrives, which is asynchronous. |

> [!NOTE]
> A layout with none of minimise, maximise and close falls back to the default, so a window can always be closed. A stalled bus never blocks the UI: the global-menu check has a one second timeout.
