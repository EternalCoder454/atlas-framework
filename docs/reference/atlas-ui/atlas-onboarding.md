---
title: AtlasOnboarding
summary: A setup scaffold with a column of steps, one page at a time, and a footer with Back, Skip and Next or Finish.
section: Windows and pages
since: "1.4.0"
---

A setup or onboarding scaffold: a column of steps on the left, one page at a time on the right, and a footer with Back (hidden on the first page), Skip and Next (Finish on the last page). The pages are the items declared inside it. The step column hides when the window is narrow, and a "Step 2 of 3" line shows above the page instead.

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

For a first-run setup, `nextText`, `finishText` and `backText` set the button labels, `busy` shows a spinner on Next while the app works, `autoAdvance: false` lets the app decide when to move on (it calls `next()` after `advanceRequested`), `canGoBack: false` takes Back away, and `stepStyle: AtlasOnboarding.Dots` swaps the step column for a row of dots.

```qml
AtlasOnboarding {
    stepStyle: AtlasOnboarding.Dots
    autoAdvance: false
    busy: setup.working
    nextText: qsTr("Continue")
    onAdvanceRequested: index => setup.apply(index)   // then setup calls next()
}
```

## Dots

With `stepStyle: AtlasOnboarding.Dots` a centred row of dots shows above the page instead of the step column, at any window width (there is then no "Step 2 of 3" line). The current dot is wider and in the accent colour, past dots are the accent at 45 %, future dots the text colour at 20 % (the control border in high contrast). The width change is animated, not under reduced motion. Screen readers get one "Step 2 of 3" for the row. `showSteps: false` hides the dots, as it hides the column.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `autoAdvance` | `bool` | `true` | `false`: Next emits `advanceRequested(index)` and the control stays; the app calls `next()` itself. An app that answers later sets `busy` in its handler, so a second Next waits; a handler that refuses (a check failed) leaves Next free. Since 1.5.0. |
| `backText` | `string` | `""` | Replaces the built-in "Back". Empty keeps it. Since 1.5.0. |
| `busy` | `bool` | `false` | Next shows a spinner, ignores clicks and keys, and has the accessible description "Busy". Back, Skip and Alt+Left do nothing while it is set. Since 1.5.0. |
| `canGoBack` | `bool` | `true` | `false` hides Back and turns Alt+Left off. Alt+Left is KDE's standard Back, also in right-to-left layouts, so it is not mirrored; it works only in the active window, and with two onboardings in one window the shortcut is ambiguous. Since 1.5.0. |
| `count` | `int` (read-only) | — | The number of pages. |
| `currentIndex` | `int` | `0` | The page shown. It is kept within the pages. |
| `finishText` | `string` | `""` | Replaces the built-in "Finish" on the last page. Empty keeps it. Since 1.5.0. |
| `nextText` | `string` | `""` | Replaces the built-in "Next". Empty keeps it. Since 1.5.0. |
| `pages` | `list<Item>` (read-only) | — | The default property: the items declared inside, one per page. |
| `showSkip` | `bool` | `false` | Shows Skip on every page, not only on `skippable` ones. |
| `showSteps` | `bool` | `true` | Shows the step column or the dots. The column also hides when the window is narrow. |
| `stepStyle` | `enum` | `AtlasOnboarding.Column` | `AtlasOnboarding.Column`, the step column on the left, or `AtlasOnboarding.Dots`, a row of dots above the page. Since 1.5.0. |

## Signals

| Name | Description |
|---|---|
| `advanceRequested(int index)` | The Next (or Finish) button was used on page `index`, before the control moves; emitted on every use, also with `autoAdvance` off. `next()` called from code does not emit it. Since 1.5.0. |
| `finished()` | Next was used on the last page. |
| `skipped(int index)` | Skip was used on page `index`. |

## Methods

| Signature | Description |
|---|---|
| `back()` | Goes to the previous page; nothing on the first. |
| `next()` | Goes to the next page, or emits `finished()` on the last. Does nothing while the page's `canAdvance` is `false`. It does not emit `advanceRequested`. |
| `skip()` | Emits `skipped(index)` and moves on. On the last page only the signal fires. |

## Enums

### StepStyle

| Value | Description |
|---|---|
| `AtlasOnboarding.Column` | The step column on the left (hidden when the window is narrow). The default. |
| `AtlasOnboarding.Dots` | A row of dots above the page. |
