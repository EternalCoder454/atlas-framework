---
title: Accessibility
summary: Keyboard focus, the focus ring, accessible roles and names, right-to-left mirroring and the checks the framework runs on every control.
section: Guides
order: 50
---

Every Atlas.Ui control is usable with the keyboard and a screen reader, and right to left. An app built from Atlas.Ui's controls keeps that. The app's part is below.

## Keyboard focus

- Every control that acts takes keyboard focus; a disabled one does not (Tab skips it).
- Controls that hold several items follow the platform's pattern: one Tab stop and arrow keys inside a [segmented control](atlas-segmented-control.md), a [view switcher](atlas-view-switcher.md), a [chip group](atlas-chip-group.md) and radio groups. Each page lists its keys under Keyboard.
- Tab order is reading order: rows top to bottom, left to right (right to left under RTL), and Shift+Tab retraces it.
- A popup returns focus to what opened it when it closes.

## The focus ring

[AtlasFocusRing](atlas-focus-ring.md) is the outline every control shows: 2 px in `AtlasStyle.focus` with a 2 px gap. It appears only for keyboard focus, never after a click. A custom control puts it in its background:

```qml
QQC2.Control {
    id: control
    focusPolicy: Qt.StrongFocus
    background: Rectangle {
        radius: AtlasStyle.radiusSmall
        AtlasFocusRing { radius: parent.radius + gap; shown: control.visualFocus }
    }
}
```

The colour is 3:1 or better against the window in Light and Dark.

## Roles and names

Screen readers need a role and a name for everything the user can reach. Atlas.Ui's controls set both. When an app builds its own interactive item, or uses a control whose label is only an icon, it sets them:

```qml
AtlasSegmentedControl {
    Accessible.name: qsTr("Density")
    model: [qsTr("Normal"), qsTr("Compact")]
}
```

- [Symbol](symbol.md) is decorative and ignored by screen readers, so give the control around it a name (an icon-only button needs its `text` or `Accessible.name`).
- An error is announced through `Accessible.description` or an alert, not only coloured.
- A busy control says it is busy.
- [AccessibilityState](accessibility-state.md) tells whether a screen reader is listening. Controls use it, for example to keep a scroll bar drawn.
- Text a user reads goes through `qsTr()`.

## Right to left

Controls follow `Qt.RightToLeft`: their layouts mirror, and where a control shows a direction (a [breadcrumb](atlas-breadcrumb.md)'s chevrons, a [shortcut label](atlas-shortcut-label.md), a [tree view](atlas-tree-view.md)) it follows too. An app sets it once on its window, as the template does:

```qml
LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
LayoutMirroring.childrenInherit: true
```

A [Symbol](symbol.md) itself is never mirrored. Where an app picks a directional icon (a back arrow, a chevron), it picks the left or right one from `LayoutMirroring.enabled` or the control's `mirrored`.

## Text size, contrast and motion

Controls follow `Appearance.textScale`, `highContrast` and `reducedMotion`. See [Style and theming](style-and-theming.md) and [Motion](motion.md).

## What the framework's tests enforce

Built with `-DATLAS_UI_TESTS=ON`, the tests find every gallery demo (`ui/gallery/demos/<Type>Demo.qml`) at run time, so a new control with a demo is covered at once.

| Test | What it checks |
|---|---|
| Accessibility | Any visible, enabled item that Tab reaches must have an `Accessible.role` and `Accessible.name`. It walks every demo with Tab (200 presses at most, else it is a focus trap): each item must be visible and sized, the order must be reading order, and Shift+Tab must retrace it. |
| State | With a demo's root disabled, Tab reaches nothing and the picture changes. Each item Tab reaches looks different with keyboard focus than without. |
| Visual | A picture of every demo is compared with a golden in light, dark, the user's accent, opaque, high contrast, right to left, compact and 200% text. |
| Translation | With another language set, a default `SearchField` shows the translated string. |
| Frameless window | The header bar's drag and double click, the resize handles and the caption-button layout parsing. |

An app can use the same gallery-demo approach for its own pages, and runs `tools/lint-app.sh` and `tools/check-app-names.sh` in its CI. The lint fails on default Qt Quick buttons and warns on other default controls that Atlas.Ui replaces.
