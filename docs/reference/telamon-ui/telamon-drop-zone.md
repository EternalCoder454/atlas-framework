---
title: TelamonDropZone
summary: A dashed, rounded area that files can be dropped on, with a symbol, text and an optional Browse button.
section: Fields and pickers
since: "1.4.0"
---

TelamonDropZone shows a symbol, a line of text, a subtitle and an optional Browse button. A drag over it turns the border to the accent colour. A drag that carries nothing acceptable turns it to the error colour and says so. `dropped(urls)` carries only the accepted URLs: local files (`file://`), unless `allowRemote` is true, that match `nameFilters`. A drag that will be accepted also makes the zone swell slightly, and it settles back when the drag leaves; under reduced motion it does not scale.

## Example

```qml
TelamonDropZone {
    Layout.fillWidth: true
    text: qsTr("Drop images here")
    subtitle: qsTr("PNG or JPEG")
    nameFilters: ["*.png", "*.jpg"]
    browseText: qsTr("Browse…")
    onDropped: urls => model.addFiles(urls)
    onBrowseRequested: fileDialog.open()
}
```

> [!NOTE]
> The zone never opens or reads a file: the app does that with the URLs. Treat the URLs as untrusted input.

## Keyboard

The zone is a Tab stop. Return, Space (and a click) emit `browseRequested()`, so an app opens its file dialog there. The Browse button shows when `browseText` is set.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `acceptedKeys` | `list<string>` | `["text/uri-list"]` | MIME types a drag must offer to be considered. |
| `allowRemote` | `bool` | `false` | Also accepts URLs that are not local files (http, https, ...). |
| `browseText` | `string` | `""` | The Browse button's label; empty for no button. |
| `dragAccepted` | `bool` (read-only) | `false` | `true` while an acceptable drag is over the zone. |
| `dragRejected` | `bool` (read-only) | `false` | `true` while a drag with nothing acceptable is over the zone. |
| `nameFilters` | `list<string>` | `[]` | Globs the file names must match, such as `["*.png"]` (case-insensitive). Empty accepts all. |
| `subtitle` | `string` | `""` | A second line under the text. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `Symbols.UploadFile` | The large symbol. |
| `text` | `string` | `qsTr("Drop files here")` | The main line. Also the accessible name. |

## Signals

| Name | Description |
|---|---|
| `browseRequested()` | Return, Space, a click or the Browse button asked for a file dialog. |
| `dropped(list<url> urls)` | Files were dropped. Only the accepted URLs. |
