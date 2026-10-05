---
title: AtlasAppCard
summary: A store card for one app: icon, name, short summary, rating and size, with an install button at the end.
section: Lists and tables
---

AtlasAppCard shows one app in a store. Pressing the card anywhere except on its action emits `clicked`: open the app's page. The action at the end is an [AtlasInstallButton](atlas-install-button.md) unless you give another through `actionComponent`.

AtlasAppCard is a Qt Quick Templates `AbstractButton`; its inherited properties (`icon.name`, `icon.source`, `clicked`) work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html>.

## Example

```qml
AtlasAppCard {
    name: "Atlas Notepad"
    summary: qsTr("Fast, plain text editing")
    icon.name: "accessories-text-editor"      // or icon.source: a url
    rating: 4.6                                // 0 hides it
    sizeText: "12 MB"
    installState: "installing"                 // see AtlasInstallButton
    progress: 0.4
    onClicked: openPage()
    onActionClicked: install()
    onCancelRequested: cancel()
}
```

`verified: true` puts a "Verified" badge after the name (since 1.5.0). `compact: true` lays the card out as one list row (icon, name, summary on one line, size, action) for an Installed or Updates list, with less padding and a smaller icon (since 1.5.0):

```qml
AtlasAppCard {
    compact: true
    verified: true
    name: "Atlas Notepad"
    summary: qsTr("Fast, plain text editing")
    sizeText: "12 MB"
    installState: "update"
}
```

Another action goes in `actionComponent`, a Component the card sizes and centres at its end:

```qml
AtlasAppCard {
    actionComponent: Component { TextButton { text: qsTr("Manage") } }
}
```

## Keyboard

The card is a Tab stop, and so is its action. Return or Enter on the focused card emits `clicked`; an action inside the card that has focus keeps its own Return.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `actionComponent` | `Component` | `defaultAction` | Replaces the AtlasInstallButton. Leave it alone to keep the default. |
| `defaultAction` | `Component` (read-only) | an AtlasInstallButton | The default action, bound to `installState` and `progress`. |
| `compact` | `bool` | `false` | A one-row list layout: icon, name, summary, size, action. The rating is not shown. Since 1.5.0. |
| `installState` | `string` | `"install"` | Forwarded to the default action; see [AtlasInstallButton](atlas-install-button.md). |
| `name` | `string` | `""` | The app's name, also its spoken name. |
| `progress` | `real` | `-1` | Forwarded to the default action; see AtlasInstallButton. |
| `rating` | `real` | `0` | Stars, 0 to 5. A value of 0 or less shows none. |
| `sizeText` | `string` | `""` | The download or installed size, already formatted ("12 MB"). |
| `summary` | `string` | `""` | A short description, up to two lines. |
| `verified` | `bool` | `false` | Adds a badge after the name. A screen reader hears "Verified" in the card's description. Since 1.5.0. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `0` | The icon for an app without `icon.name` or `icon.source`. 0 shows `Symbols.Apps`. |

## Signals

| Name | Description |
|---|---|
| `actionClicked()` | The default action was clicked (not while `installState` is `"installing"`, `"removing"` or `"queued"`). |
| `cancelRequested()` | The default action asked to cancel an install in progress. |
