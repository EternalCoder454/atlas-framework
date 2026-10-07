---
title: TelamonShelf
summary: A titled horizontal row of cards for a store, with scroll buttons at each end and cards made only for what is on screen.
section: Lists and tables
since: "1.5.0"
---

TelamonShelf is a titled row of cards that scrolls sideways ("Editors' choice", "New apps"). A button at each end scrolls by most of a screenful and hides when there is nothing more that way. Inside is a horizontal `ListView`, so only the visible cards exist and a model of thousands costs what a screenful does. For one column of rows, use [TelamonListView](telamon-list-view.md).

TelamonShelf is a Qt Quick Controls [`Control`](https://doc.qt.io/qt-6/qml-qtquick-templates-control.html); its inherited properties work as usual.

## Example

```qml
TelamonShelf {
    title: qsTr("Editors' choice")
    model: [
        { name: "Telamon Notepad", summary: qsTr("Fast, plain text editing"), sizeText: "12 MB", rating: 4.6, verified: true },
        { name: "Telamon Monitor", summary: qsTr("Processes, memory and disks"), sizeText: "8 MB" }
    ]
    onActivated: index => openPage(index)
}
```

The default delegate is a [TelamonAppCard](telamon-app-card.md). It reads `name`, `summary`, `sizeText`, `rating`, `iconName`, `installState`, `progress` and `verified` from each entry (a list of objects, or the roles of an item model) and emits `activated(index)` when pressed. A custom `delegate` gets the usual `index`, `model` and `modelData`, and sets its own width; `cardWidth` is the width the default card uses. The row is as high as the tallest card made so far (its implicit or its set height), and is measured again when the model changes; the default cards all take the row's height, so a row is even. A delegate must not size its height from the list, or the row could never shrink.

## Keyboard

The cards are Tab stops, and Tab and Shift+Tab go through them in index order (each card's own stops, such as its install button, in between), then on out of the row. Left and Right move to the previous and next card (swapped in a right-to-left layout), Home and End go to the first and last. A card that takes focus is scrolled fully into view.

## Right-to-left and motion

In a right-to-left layout the row, its first card and its buttons are mirrored: the start button is on the right. Under reduced motion a button press scrolls at once. In high contrast the buttons get the strong border.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `cardWidth` | `real` | 18 grid units | The width of the default card. |
| `count` | `int` (read-only) | — | How many cards the model holds. |
| `defaultDelegate` | `Component` (read-only) | a TelamonAppCard | The default card. |
| `delegate` | `Component` | `defaultDelegate` | The card for each entry. |
| `model` | `var` | `null` | A list, a number or an item model. |
| `title` | `string` | `""` | The heading above the row, also the shelf's spoken name. |

## Signals

| Name | Description |
|---|---|
| `activated(int index)` | A card of the default delegate was pressed. |

## Accessibility

The title is a heading and the shelf's accessible name. The two scroll buttons are named "Scroll to start" and "Scroll to end"; they take no Tab stop, since the cards scroll themselves into view.
