---
title: AtlasScreenshotCarousel
summary: A row of screenshots shown one at a time with previous and next buttons, dots and arrow keys, loading only the neighbours.
section: Lists and tables
since: "1.3.0"
---

A row of screenshots, one at a time: previous and next buttons over the picture, dots below (a "3 / 20" counter instead when there are more than 12; nothing for a single screenshot), and the arrow keys. Only the shown image and its two neighbours are loaded, asynchronously and at a bounded size. At most the first 50 sources are shown. With no sources it shows a short "No screenshots" message. Use it on an app's detail page, next to [AtlasInstallButton](atlas-install-button.md).

AtlasScreenshotCarousel is a Qt Quick Controls [`Control`](https://doc.qt.io/qt-6/qml-qtquick-templates-control.html); its inherited properties work as usual.

## Example

```qml
AtlasScreenshotCarousel {
    sources: [Qt.resolvedUrl("shots/a.png"), "qrc:/b.png"]
    Layout.fillWidth: true
    Layout.preferredHeight: width * 9 / 16
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `allowRemote` | `bool` | `false` | Lets `https:` sources load, for a trusted source. `http:` is refused either way. |
| `count` | `int` (read-only) | — | How many sources are shown: at most 50, and none for something that is not a list. |
| `currentIndex` | `int` | `0` | The screenshot shown. Kept within `count`. |
| `sources` | `var` | `[]` | A list of image urls (strings or `url` values). |

## Keyboard

The arrow keys go to the previous and next screenshot; Home and End go to the first and last.

## Where pictures may come from

Each source is resolved the way Qt reads it. Only local files (`file:`, no host), `qrc:` and `image:` (the app's own image providers) load. Anything else (`http:`, `ftp:`, `data:`, a `//host` url, control characters) is refused: the slide shows the broken-image state, and the first refusal is logged with its scheme only.

> [!NOTE]
> Pass absolute urls (`Qt.resolvedUrl("shots/a.png")` in the app's file): a relative one is read against Atlas.Ui's own files. An app that shows remote screenshots should download them itself and pass the local files, which is best. Otherwise set `allowRemote: true` for a trusted source. Qt logs the whole url of an image that fails to load, so a remote url must carry no secret (no token in its query). A `file:` source should come from the app's own download or cache, not straight from metadata.
