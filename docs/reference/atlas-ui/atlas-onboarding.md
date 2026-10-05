---
title: AtlasOnboarding
summary: A setup scaffold with a column of steps, one page at a time, and a footer with Back, Skip and Next or Finish.
section: Windows and pages
since: "1.4.0"
---

A setup or onboarding scaffold: a column of steps on the left, one page at a time on the right, and a footer with Back, Skip and Next (Finish on the last page). The pages are the items declared inside it. The step column hides when the window is narrow, and a "Step 2 of 3" line shows above the page instead.

A page may declare these plain properties; all are optional:

| Page property | Type | Meaning |
|---|---|---|
| `title` | `string` | The step's name in the column. |
| `canAdvance` | `bool` | Default `true`. `false` disables Next. |
| `skippable` | `bool` | Default `false`. `true` shows Skip on this page. |

## Example

```qml
AtlasOnboarding {
    anchors.fill: parent
    onFinished: window.close()
    Item { property string title: qsTr("Welcome"); /* ... */ }
    Item { property string title: qsTr("Account"); property bool canAdvance: nameField.text.length > 0 }
    Item { property string title: qsTr("Done") }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `count` | `int` (read-only) | — | The number of pages. |
| `currentIndex` | `int` | `0` | The page shown. It is kept within the pages. |
| `pages` | `list<Item>` (read-only) | — | The default property: the items declared inside, one per page. |
| `showSkip` | `bool` | `false` | Shows Skip on every page, not only on `skippable` ones. |
| `showSteps` | `bool` | `true` | Shows the step column. It also hides when the window is narrow. |

## Signals

| Name | Description |
|---|---|
| `finished()` | Next was used on the last page. |
| `skipped(int index)` | Skip was used on page `index`. |

## Methods

| Signature | Description |
|---|---|
| `back()` | Goes to the previous page; nothing on the first. |
| `next()` | Goes to the next page, or emits `finished()` on the last. Does nothing while the page's `canAdvance` is `false`. |
| `skip()` | Emits `skipped(index)` and moves on. On the last page only the signal fires. |
