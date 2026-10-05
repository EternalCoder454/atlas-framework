---
title: AtlasFloatingToolbar
summary: A capsule of icon buttons that floats over content, such as formatting tools over an editor.
section: Navigation
since: "1.4.0"
---

AtlasFloatingToolbar is a rounded surface with a soft shadow. It is an [AtlasToolbar](atlas-toolbar.md) inside, so it has the same `actions` ([AtlasAction](atlas-action.md) or Qt `Action`, with dividers between sections) and its "more" menu when the parent is too narrow. Items put inside it (a drop-down, a colour swatch) follow the buttons.

`shown` fades it in and out with a short slide. While hidden, it takes no input and is not visible. It stays inside its parent: it is drawn at least `margin` from the edges whatever `x` and `y` say (they are not changed), and it is never wider than the parent less the margins.

## Example

```qml
AtlasFloatingToolbar {
    actions: [boldAction, italicAction, linkAction]
    shown: editor.hasSelection
    x: Math.round((parent.width - width) / 2)
    y: parent.height - height - 16
}
```

> [!NOTE]
> Its buttons never take the keyboard focus by default (`focusable: false`), so the editor keeps typing. Set `focusable: true` to let Tab reach them.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accessibleName` | `string` | `qsTr("Tools")` | The name for screen readers. |
| `actions` | `list<Action>` (read-only) | `[]` | The actions shown as buttons. |
| `content` | `list<QtObject>` (default, read-only) | — | Extra items after the buttons. |
| `focusable` | `bool` | `false` | Lets Tab reach the buttons. `false` keeps the focus in the editor. |
| `margin` | `real` | `AtlasStyle.spacingLarge` | Room kept free between the capsule and the parent's edges. |
| `shown` | `bool` | `true` | `true` shows the capsule; `false` fades it away. |
| `toolbar` | [AtlasToolbar](atlas-toolbar.md) (read-only) | the inner toolbar | The inner toolbar, for example for its "more" menu. |
