---
title: AtlasClipboard
summary: A singleton for the system clipboard: copy and read text, rich text and images without a hidden TextEdit.
section: Services
since: "1.4.0"
---

AtlasClipboard puts clipboard access for QML in one place. The app asks for everything: nothing is read until `text()` is called, and no content is ever logged. `hasText` and `hasImage` look at the formats on offer, not at the content, and update when the clipboard changes in any app.

## Example

```qml
Item {
    function demo() {
        AtlasClipboard.setText("hello")
        AtlasClipboard.setRichText("<b>hello</b>", "hello")   // html + plain text
        AtlasClipboard.setImage(grabResult.image)             // a QImage ...
        AtlasClipboard.setImage("file:///home/me/shot.png")   // ... or a local file
        if (AtlasClipboard.hasText) { field.text = AtlasClipboard.text() }
    }
}
```

> [!NOTE]
> An image from a file must be a local file of at most 64 MB (and at most 64 MB of pixels once decoded). Anything else is refused and `setImage()` returns `false`.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `hasImage` | `bool` (read-only) | — | The clipboard offers an image format. |
| `hasText` | `bool` (read-only) | — | The clipboard offers a text format. |

## Signals

| Name | Description |
|---|---|
| `changed()` | The clipboard's content changed, in this or any other app. `hasText` and `hasImage` are re-read. |

## Methods

| Signature | Description |
|---|---|
| `setImage(QVariant image): bool` | Puts an image on the clipboard: a `QImage` (a grab result's `image`), or the url or path of a local image file. Returns `false` when refused or unreadable. |
| `setRichText(QString html, QString plainFallback): void` | Puts `html` (text/html) and `plainFallback` (text/plain) on the clipboard. |
| `setText(QString text): void` | Puts plain text on the clipboard. |
| `text(): QString` | The clipboard's text, or an empty string. |
