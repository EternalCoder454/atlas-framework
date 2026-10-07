---
title: TelamonFocusRing
summary: The keyboard focus ring every Telamon control shows: a magenta-violet outline with a gap, only for keyboard focus.
section: Style and motion
---

TelamonFocusRing is a 2 px magenta-violet (`TelamonStyle.focus`) outline with a 2 px gap outside the control's shape, shown only when focus came from the keyboard. It fades in over `durationShort` and grows slightly into place; under reduced motion it only appears. Put it inside the control's `background` and give it the shape's radius plus the gap.

## Example

```qml
TelamonButton {
    id: control
    background: Rectangle {
        radius: TelamonStyle.radiusSmall
        TelamonFocusRing { radius: parent.radius + gap; shown: control.visualFocus }
    }
}
```

It is decorative: screen readers skip it. It is a `Rectangle`, so its other properties (`radius`) work as usual.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `gap` | `real` | `2` | How far outside the parent the ring sits. |
| `shown` | `bool` | `false` | Whether the ring shows. Usually the control's `visualFocus`. |
