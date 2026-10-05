---
title: Motion
summary: How Atlas apps move: AtlasSpringAnimation standard and expressive, the duration tokens, reduced motion, the violet to sakura gradient rule and why nothing animates while idle.
section: Guides
order: 30
---

Motion in Atlas apps is quick and subtle. Colour and opacity fade with the duration tokens; things that move or change size use a spring.

## Durations

`AtlasStyle.durationShort` (100 ms), `duration` (150 ms) and `durationLong` (250 ms) are the only durations an app uses. Every one is 0 when `AtlasStyle.reducedMotion` is true.

```qml
Rectangle {
    color: mouse.containsMouse ? AtlasStyle.hover : "transparent"
    Behavior on color { ColorAnimation { duration: AtlasStyle.durationShort } }
}
```

## Springs

[AtlasSpringAnimation](atlas-spring-animation.md) is for spatial movement: a panel opening, a row expanding, a selection indicator sliding. Use it in a `Behavior` on `x`, `y`, `width`, `height` or `scale`, never on colour or opacity.

| Spring | Overshoot | Settles in | Use |
|---|---|---|---|
| Standard (default) | none | about 240 ms for a 100 px move | Everyday movement. |
| Expressive (`expressive: true`) | about 7% | about 350 ms | The signature moments only: sliding selection indicators, the focus ring growing in, the switch thumb, a drop zone accepting. |

```qml
Rectangle {
    id: indicator
    Behavior on x {
        enabled: !AtlasStyle.reducedMotion
        AtlasSpringAnimation { expressive: true }
    }
}
```

A value that moves less than about 2 units (a scale, a 0 to 1 progress) needs `fine: true`, or the spring ends in one frame.

## Reduced motion

`AtlasStyle.reducedMotion` follows `Appearance.reducedMotion`: Plasma's animation speed is "Instant" (`AnimationDurationFactor` is 0 in kdeglobals `[KDE]`), or the environment has `ATLAS_REDUCED_MOTION=1`. Then:

- the duration tokens are 0, so fades are instant;
- a spring is off (the value jumps), so put `enabled: !AtlasStyle.reducedMotion` on the `Behavior`; where a jump looks abrupt, fade with an opacity animation instead;
- an animation with no duration, such as a spinner, checks `reducedMotion` itself, and [AtlasEdgeGlow](atlas-edge-glow.md) stays still.

## The violet to sakura gradient

The signature gradient runs from violet (`AtlasStyle.accent`) to sakura (`AtlasStyle.sakura`). It has one meaning: the system or the app is doing something for the user right now. It is used in exactly three places:

1. the [edge glow](atlas-edge-glow.md);
2. the shimmer of an active [progress bar](atlas-progress-bar.md);
3. "update ready".

Never put it on buttons, selection, focus, errors, text or as decoration.

## Nothing animates while idle

An idle app uses no CPU. Animations stop when hidden, and a control that animates all the time (a spinner, the placeholder's sweep, the edge glow) draws nothing and runs nothing when it is off or hidden; `AtlasSpinner` and `AtlasPlaceholder` stay still with `animated: false`. An app's own timers should follow the same rule: poll or animate only while the window is visible, as the template's `shown` binding does.
