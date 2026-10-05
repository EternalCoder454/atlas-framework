---
title: AtlasCard
summary: A padded card on the raised surface, with an optional header and footer, and optionally clickable.
section: Layout
since: "1.4.0"
---

AtlasCard has Section's look: rounded corners and a hairline border. It has an optional header (`title`, `subtitle` and `headerTrailing`, items at the far edge such as a button or a badge), then whatever you put inside, then an optional `footer` row. To list rows in a grouped card, see [Section](section.md).

AtlasCard is a Qt Quick Templates `Control`; its inherited properties work as usual. See <https://doc.qt.io/qt-6/qml-qtquick-controls-control.html>.

## Example

```qml
AtlasCard {
    title: qsTr("Backups")
    subtitle: qsTr("Last run yesterday")
    headerTrailing: [ SecondaryButton { text: qsTr("Run now") } ]
    AtlasLabel { text: qsTr("42 files protected.") }
    footer: [ TextButton { text: qsTr("Details") } ]
}
```

## Keyboard

With `clickable`, the whole card is a button and one Tab stop: Return, Enter and Space click it. Controls inside a clickable card keep their own clicks. A card that is not clickable takes no focus.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `clickable` | `bool` | `false` | The card reacts to the pointer, takes keyboard focus and emits `clicked()`. |
| `content` | `list<QtObject>` (default, read-only) | — | Items declared inside the card. |
| `footer` | `list<QtObject>` (read-only) | — | A row under the content, aligned to the trailing edge. |
| `headerTrailing` | `list<QtObject>` (read-only) | — | Items at the trailing edge of the header row. |
| `subtitle` | `string` | `""` | A line under the title. Also the accessible description. |
| `title` | `string` | `""` | The header's title. Also the accessible name. |

## Signals

| Name | Description |
|---|---|
| `clicked()` | A clickable card was pressed, or activated with the keyboard. |
