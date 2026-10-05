import QtQuick
import Atlas.Ui

// AtlasSpringAnimation: the Atlas spring for spatial movement, standard (no
// overshoot, settles quickly) or expressive (a small overshoot, for the
// signature moments only; see AtlasStyle). Use it in a Behavior on x, y,
// width, height or scale, never on colour or opacity. Under reduced motion
// the Behavior is turned off, so the value jumps; fade with an opacity
// animation where a jump would look abrupt.
//
// Measured in Qt 6.11 (a 100 px move, frames of about 16 ms, within 1 px of
// the target):
//   standard    no overshoot, settled in about 240 ms (within 5 px at 160 ms)
//   expressive  overshoots by about 7 px (7%), settled in about 350 ms
// Qt steps the spring once per 16 ms frame: velocity = velocity * (1 - damping)
// + spring * 0.016 * (target - value), then value += velocity. That is a damped
// oscillator of unit mass (stiffness k = natural frequency squared, damping
// coefficient c = 2 * zeta * omega), so the AtlasOS shell can match it:
//   standard    omega 25 rad/s (k 645 /s^2), zeta 0.98, c 49 /s (critical)
//   expressive  omega 17 rad/s (k 299 /s^2), zeta 0.64, c 22 /s
//
//   Rectangle {
//       id: indicator
//       Behavior on x {
//           enabled: !AtlasStyle.reducedMotion
//           AtlasSpringAnimation { expressive: true }
//       }
//   }
SpringAnimation {
    // A small overshoot for signature moments; false is the everyday spring.
    property bool expressive: false

    spring: expressive ? 4 : 7
    damping: expressive ? 0.3 : 0.55
    mass: 1
    epsilon: 0.25
}
