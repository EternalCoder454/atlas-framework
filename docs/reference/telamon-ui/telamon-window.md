---
title: TelamonWindow
summary: The application window of a Telamon app: blur or opaque, a width class, saved size and an optional frameless header.
section: Windows and pages
---

TelamonWindow is the window of every Telamon app. With "Transparency and blur" on and a compositor that blurs, the background is `TelamonStyle.base` at `blurAlpha` over the blurred desktop; otherwise it is plain, opaque `TelamonStyle.base`. Put `sidebarColor(base)` on a sidebar so it is a little more see-through.

TelamonWindow is a Qt Quick Controls `ApplicationWindow` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-applicationwindow.html)); its inherited properties work as usual.

`widthClass` says how roomy the window is: Compact below 30 grid units wide, Wide from 60, Medium between. `sidebarCollapsed` is true in Compact, so every app folds its sidebar to icons at the same width. `stateKey` saves the window's width, height and maximised state under `Window-<stateKey>` in the app's settings file and restores them when the window first shows, clamped to the screen.

## Example

```qml
TelamonWindow {
    stateKey: "main"
    TelamonSidebar {
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
| `compactBreakpoint` | `real` | `30` | Below this width, in grid units, `widthClass` is `Compact` (and `sidebarCollapsed` is true). A value that is not a finite number above 0 uses the default. Since 1.5.0. |
| `frameless` | `bool` (read-only) | — | True when `header` is a [TelamonHeaderBar](telamon-header-bar.md): the window then draws its own title row. |
| `kiosk` | `bool` | `false` | Full screen, no close button (the window buttons and the header's window menu leave Close out), and a close request (Alt+F4, the compositor) is refused. `Qt.quit()` asks every window to close, so a kiosk window stops it too: to end the app, set `kiosk` to `false` first, or call `Qt.exit()`. Maximize and Restore are left out too, and if the window leaves full screen anyway (KWin's F11, a menu) it is put back, unless it is minimized. Set on a hidden window, it takes effect when the window is shown, also when set again after hiding; set back to `false`, the window leaves the full screen kiosk put it in (a full screen the app chose itself stays; a minimized window leaves it when it comes back) (to Maximized if `stateKey` saved it so). Applied one turn after the change, because `flags` change with it and on Wayland that can recreate the window; this is verified only on the offscreen platform. See "Kiosk windows". Since 1.5.0. |
| `sidebarCollapsed` | `bool` (read-only) | — | True when `widthClass` is `Compact`; bind `TelamonSidebar.compact` to it. |
| `sidebarFactor` | `real` | `0.8` | How much more see-through the sidebar is, as a factor on `blurAlpha`. |
| `stateKey` | `string` | `""` | Names the saved window state; empty keeps none. |
| `wideBreakpoint` | `real` | `60` | From this width, in grid units, `widthClass` is `Wide`. When `compactBreakpoint` is not below it there is no `Medium`. A value that is not a finite number above 0 uses the default. Since 1.5.0. |
| `widthClass` | `int` (read-only) | — | How roomy the window is (`TelamonWindow.WidthClass`), from `compactBreakpoint` and `wideBreakpoint`. |

## Methods

| Signature | Description |
|---|---|
| `confirm(var options, var done): var` | Opens a [ConfirmDialog](confirm-dialog.md) with `options.title`, `text`, `acceptText`, `rejectText` and `destructive` (a destructive dialog starts on Cancel), and calls `done(true)` or `done(false)` exactly once: `true` for the accept button, `false` for Cancel, Escape, a click outside, or the window being hidden or destroyed (a window whose `onClosing` vetoes the close keeps its dialogs), or the caller destroying the returned dialog. A second `confirm()` while one is open opens a second dialog, each answered once. On a window that is not visible there is nothing to open the dialog in: `done(false)` is called at once and `confirm()` returns `null`. Otherwise it returns the dialog. Use `done` for the answer: the return value can be `null`. Since 1.5.0. |
| `sidebarColor(color base): color` | Returns `base` with the sidebar's alpha (`blurAlpha` times `sidebarFactor`), or `base` unchanged when there is no blur. |
| `syncBlur(): var` | Asks the compositor to blur behind the window or stops it, following `Appearance`. Called when the window shows, gets focus or `blurred` changes. |
| `toast(string text, var options)` | Queues a toast at the bottom of the window. Toasts show one at a time, in order, and are announced to screen readers; the same text and action twice in a row is shown once (`onAction` is compared by identity, so pass the same function object; two inline arrow functions are two actions), and at most 20 wait (the oldest waiting toast is dropped first). `options`: `actionText` (a button label), `onAction` (a function called when it is clicked), `timeout` (ms, default 2500; 5000 for an error; rounded and kept between 1 and 60000) and `kind` (`"info"`, the default, or `"error"`). The host item is made on first use. Since 1.5.0. |
| `tinted(color base, real factor): color` | Returns `base` with the alpha `blurAlpha` times `factor`, or `base` unchanged when there is no blur. |

## Enums

### WidthClass

| Value | Description |
|---|---|
| `TelamonWindow.Compact` | Narrower than `compactBreakpoint` (30 grid units). |
| `TelamonWindow.Medium` | From 30 up to 60 grid units. |
| `TelamonWindow.Wide` | `wideBreakpoint` (60 grid units) or wider. |

## Frameless mode

Give the window a [TelamonHeaderBar](telamon-header-bar.md) as its `header` and it draws its own title row (title, main tools and the window buttons) instead of KWin's title bar:

```qml
TelamonWindow {
    header: TelamonHeaderBar { actions: [saveAction, openAction] }
}
```

The window then has `Qt.FramelessWindowHint`, top corners rounded like the Telamon OS decoration's (`TelamonStyle.radiusLarge`; the surface is always see-through so the corners show what is behind, and the blur leaves them out), a hairline border (no border and square corners when maximised or full screen) and invisible handles along its edges (6 px deep, with 16 px L-shaped corners; along the top edge a corner stops where the header's buttons begin) that resize it through the compositor. Without a `TelamonHeaderBar` nothing changes and KWin decorates the window.

> [!NOTE]
> A second launch of an app started with `telamon_app_run` raises this window and exits; nothing is needed in QML.

## Kiosk windows

- An app's own `onClosing` handles the same close request, and the handler that runs last decides. Do not set `close.accepted = true` while `kiosk` is on, or the window may close.
- Logout and shutdown ask windows to close too, and a kiosk window refuses them: it can delay the session's logout until the app sets `kiosk` to `false` or exits (`Qt.exit()`).
