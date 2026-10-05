---
title: AtlasSpringAnimation
summary: The Atlas spring for movement and size, standard or with a small overshoot, for use in a Behavior.
section: Style and motion
since: "1.4.0"
---

The Atlas spring for spatial movement: standard (no overshoot, settles quickly) or expressive (a small overshoot, for the signature moments only; see [AtlasStyle](atlas-style.md)). Use it in a `Behavior` on `x`, `y`, `width`, `height` or `scale`, never on colour or opacity. Under reduced motion, turn the `Behavior` off so the value jumps, and fade with an opacity animation where a jump would look abrupt.

AtlasSpringAnimation is a Qt Quick [`SpringAnimation`](https://doc.qt.io/qt-6/qml-qtquick-springanimation.html); its inherited properties work as usual.

## Example

```qml
Rectangle {
    id: indicator
    Behavior on x {
        enabled: !AtlasStyle.reducedMotion
        AtlasSpringAnimation { expressive: true }
    }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `expressive` | `bool` | `false` | A small overshoot, for signature moments. `false` is the everyday spring. |
| `fine` | `bool` | `false` | For values that move less than about 2 units (scale, a 0 to 1 progress): stops at 0.001 instead of 0.25. |

## Timing

Measured in Qt 6.11 for a 100 px move, within 1 px of the target:

| Spring | Overshoot | Settled in |
|---|---|---|
| standard | none | about 240 ms (within 5 px at 160 ms) |
| expressive | about 7 px (7%) | about 350 ms |

The spring stops once it is within `epsilon` of the target, `0.25` by default, which suits pixels. For a value that moves less than about 2 units, set `fine: true`, or the spring ends in one frame:

```qml
Behavior on scale { AtlasSpringAnimation { expressive: true; fine: true } }
```

A fine spring keeps stepping a little longer (a 0.04 scale move: standard about 210 ms, expressive about 340 ms; a 100 px move about 510 ms and 1 s), and the extra frames are sub-pixel.

Qt steps the spring once per 16 ms frame. It is a damped oscillator of unit mass, so a shell can match it:

| Spring | Natural frequency | Stiffness | Damping ratio | Damping coefficient |
|---|---|---|---|---|
| standard | 25 rad/s | 645 /s² | 0.98 | 49 /s (critical) |
| expressive | 17 rad/s | 299 /s² | 0.64 | 22 /s |
