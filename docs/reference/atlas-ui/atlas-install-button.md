---
title: AtlasInstallButton
summary: An install button for apps with a progress bar inside it, a cancel press while installing, and states for install, update, open and retry.
section: Buttons
since: "1.3.0"
---

A button for installing an app, with its progress inside it: a thin bar along its bottom edge fills as the download goes. `installState` says what it offers and what a press means. Use it in a store's app card or detail page. See [AtlasButton](atlas-button.md) for an ordinary button.

AtlasInstallButton is a Qt Quick Controls [`AbstractButton`](https://doc.qt.io/qt-6/qml-qtquick-templates-abstractbutton.html); its inherited properties and `clicked` work as usual.

## Example

```qml
AtlasInstallButton {
    installState: app.state   // "install", "installing", ...
    progress: app.progress    // 0 to 1; below 0 when the size is unknown
    onClicked: app.act()
    onCancelRequested: app.cancel()
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `animated` | `bool` | `true` | `false` holds the progress shimmer still (for a screenshot). |
| `errorText` | `string` | `"Retry"` | The label in the `"error"` state. Translated. |
| `installState` | `string` | `"install"` | What the button offers: see the table below. Any other value is drawn as `"install"`. Item's own `state` stays free for an app's states. |
| `installText` | `string` | `"Install"` | The label in the `"install"` state. Translated. |
| `installedText` | `string` | `"Open"` | The label in the `"installed"` state. Replace it for an app that says "Launch". Translated. |
| `progress` | `real` | `-1` | 0 to 1 while installing. A negative value means no figure is known: the button shows "Installing…" and a bar that slides to and fro. |
| `updateText` | `string` | `"Update"` | The label in the `"update"` state. Translated. |

`installState` is one of:

| Value | Look | A press |
|---|---|---|
| `"install"` | Install, in the accent colour | `clicked` |
| `"installing"` | The fill and a percentage | `clicked`, then `cancelRequested` |
| `"installed"` | Open, in the soft style | `clicked` |
| `"update"` | Update, in the accent colour | `clicked` |
| `"error"` | Retry, in the negative colour | `clicked` |

## Signals

| Name | Description |
|---|---|
| `cancelRequested()` | The button was pressed while `installState` is `"installing"`. `clicked` fires for every press as for any button. |

## Accessibility

While installing, the accessible name is "Installing" and its description gives the percentage and says that a press cancels. Enter and Return press the button.
