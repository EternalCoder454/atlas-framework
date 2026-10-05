---
title: AtlasWindow
summary: The application window of an Atlas app: blur or opaque, a width class, saved size and an optional frameless header.
section: Windows and pages
---

AtlasWindow is the window of every Atlas app. With "Transparency and blur" on and a compositor that blurs, the background is the theme's background at `blurAlpha` over the blurred desktop; otherwise it is plain and opaque. Put `sidebarColor(base)` on a sidebar so it is a little more see-through.

AtlasWindow is a Qt Quick Controls `ApplicationWindow` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-applicationwindow.html)); its inherited properties work as usual.

`widthClass` says how roomy the window is: Compact below 30 grid units wide, Wide from 60, Medium between. `sidebarCollapsed` is true in Compact, so every app folds its sidebar to icons at the same width. `stateKey` saves the window's width, height and maximised state under `Window-<stateKey>` in the app's settings file and restores them when the window first shows, clamped to the screen.

## Example

```qml
AtlasWindow {
    stateKey: "main"
    AtlasSidebar {
        compact: window.sidebarCollapsed
        // ...
    }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `blurAlpha` | `real` | `0.80` | The window background's alpha over the blur. |
| `blurred` | `bool` (read-only) | — | True while the window is drawn over blur (`Appearance.effective`). |
| `frameless` | `bool` (read-only) | — | True when `header` is an [AtlasHeaderBar](atlas-header-bar.md): the window then draws its own title row. |
| `sidebarCollapsed` | `bool` (read-only) | — | True when `widthClass` is `Compact`; bind `AtlasSidebar.compact` to it. |
| `sidebarFactor` | `real` | `0.8` | How much more see-through the sidebar is, as a factor on `blurAlpha`. |
| `stateKey` | `string` | `""` | Names the saved window state; empty keeps none. |
| `widthClass` | `int` (read-only) | — | How roomy the window is (`AtlasWindow.WidthClass`). |

## Methods

| Signature | Description |
|---|---|
| `sidebarColor(color base): color` | Returns `base` with the sidebar's alpha (`blurAlpha` times `sidebarFactor`), or `base` unchanged when there is no blur. |
| `syncBlur(): var` | Asks the compositor to blur behind the window or stops it, following `Appearance`. Called when the window shows, gets focus or `blurred` changes. |
| `tinted(color base, real factor): color` | Returns `base` with the alpha `blurAlpha` times `factor`, or `base` unchanged when there is no blur. |

## Enums

### WidthClass

| Value | Description |
|---|---|
| `AtlasWindow.Compact` | Narrower than 30 grid units. |
| `AtlasWindow.Medium` | From 30 up to 60 grid units. |
| `AtlasWindow.Wide` | 60 grid units or wider. |

## Frameless mode

Give the window an [AtlasHeaderBar](atlas-header-bar.md) as its `header` and it draws its own title row (title, main tools and the window buttons) instead of KWin's title bar:

```qml
AtlasWindow {
    header: AtlasHeaderBar { actions: [saveAction, openAction] }
}
```

The window then has `Qt.FramelessWindowHint`, a hairline border (none when maximised or full screen) and 4 px invisible handles around it that resize it through the compositor. Without an `AtlasHeaderBar` nothing changes and KWin decorates the window.

> [!NOTE]
> A second launch of an app started with `atlas_app_run` raises this window and exits; nothing is needed in QML.
