---
title: NotesText
summary: Release notes shown from a safe HTML fragment, styled with Telamon colours and spacing.
section: Text and code
---

NotesText shows release notes. The backend sends a safe HTML fragment (no images, no styles, https links only); NotesText styles it with Telamon colours and spacing. Clicking a link emits `linkClicked`; the page decides, through the backend's `isSafeLink`, whether it opens. A leading heading that repeats "What's new in ..." is dropped, since the section title already says it.

NotesText is a Qt Quick `Text` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-text.html)); its inherited properties work as usual.

## Example

```qml
NotesText {
    html: backend.notesHtml
    plain: backend.notesPlain
    onLinkClicked: link => { if (backend.isSafeLink(link)) Qt.openUrlExternally(link) }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accent` | `color` (read-only) | the accent, lightened on a dark theme | The colour of links. |
| `body` | `string` (read-only) | — | `html` without a leading "What's new" heading. |
| `css` | `string` (read-only) | — | The style sheet that gives the HTML its Telamon look. |
| `darkTheme` | `bool` (read-only) | — | True when the theme's background is dark. |
| `html` | `string` | `""` | The safe HTML fragment to show. |
| `plain` | `string` | `""` | The same notes as plain text, used as the accessible name. |

## Signals

| Name | Description |
|---|---|
| `linkClicked(string link)` | Emitted when the user activates a link; `link` is its address. Nothing is opened by NotesText itself. |

> [!NOTE]
> NotesText renders rich text. Only give it HTML the backend has made safe, and open a link only after checking it.
