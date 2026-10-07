---
title: StatusHero
summary: A big centred status: a round icon badge with an optional ring, a headline, a subtitle and action buttons.
section: Feedback and status
---

StatusHero is the large status of a page: "Everything is up to date", "Installing...", "Something went wrong". It shows a round icon badge (with a ring for busy or progress), a headline, a subtitle, an optional progress bar and the action buttons you put inside. For an empty list use [TelamonEmptyState](telamon-empty-state.md).

StatusHero is a `ColumnLayout`. Actions sit side by side when they fit and stack when they do not. Changing `headline` is announced to screen readers, so a banner need not repeat the state.

## Example

```qml
StatusHero {
    iconName: "update-none"
    headline: qsTr("Installing updates")
    subtitle: qsTr("Do not turn off your computer.")
    progress: 0.4
    showBar: true
    barText: qsTr("120 MB of 300 MB")
    PrimaryButton { text: qsTr("Pause") }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `actions` | `list<Item>` (read-only) | — | The default property: the buttons under the text. |
| `badgeUnits` | `real` | `5` | The badge's diameter in grid units. |
| `barText` | `string` | `""` | A line under the bar ("120 MB of 300 MB"); shown with `showBar`. |
| `busy` | `bool` | `false` | Draws a spinning ring around the badge while true (and no `progress`). |
| `cornerBadgeIcon` | `string` | `""` | An icon name for a small accent circle on the badge's bottom right corner (a check, say). Empty for none. |
| `headline` | `string` | `""` | The page's state, as a large heading. Announced when it changes. |
| `iconIsMask` | `bool` | `true` | Paints the icon in `tint` (a one-colour symbol). False shows it in its own colours, as a logo. |
| `iconName` | `string` | `""` | The theme icon in the badge. |
| `progress` | `real` | `-1` | 0 to 1 draws a progress ring, and fills the bar; negative means none (the bar slides). |
| `ringWidth` | `real` | `4` | The ring's stroke width in pixels. |
| `showBar` | `bool` | `false` | Shows a thin bar under the subtitle: filled to `progress`, or a sliding segment while `progress` is negative. |
| `showTintCircle` | `bool` | `true` | Shows the pale circle behind the icon. False lets the icon fill the badge. |
| `sideBySide` | `bool` (read-only) | — | True when the actions fit side by side in the width. |
| `subtitle` | `string` | `""` | A line of text under the headline. |
| `tint` | `color` | `TelamonStyle.accent` | The colour of the icon, ring and bar. |
| `wideWidth` | `real` (read-only) | — | The width the actions need side by side. |
