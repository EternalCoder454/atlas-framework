import QtQuick
import Telamon.Ui

// TelamonSpringAnimation: the Telamon spring for spatial movement, standard (no
// overshoot, settles quickly) or expressive (a small overshoot, for the
// signature moments only; see TelamonStyle). Use it in a Behavior on x, y,
// width, height or scale, never on colour or opacity. Under reduced motion
// the Behavior is turned off, so the value jumps; fade with an opacity
// animation where a jump would look abrupt.
//
// Measured in Qt 6.11 (a 100 px move, frames of about 16 ms, within 1 px of
// the target):
//   standard    no overshoot, settled in about 240 ms (within 5 px at 160 ms)
//   expressive  overshoots by about 7 px (7%), settled in about 350 ms
// The spring stops once it is within `epsilon` of the target, 0.25 by default,
// which suits pixels. For a value that moves less than about 2 units (scale,
// a 0 to 1 progress) set `fine: true`, or the spring ends in one frame:
//   Behavior on scale { TelamonSpringAnimation { expressive: true; fine: true } }
// A fine spring keeps stepping a little longer (a 0.04 scale move: standard
// about 210 ms, expressive about 340 ms; a 100 px move about 510 ms and 1 s),
// and the extra frames are sub-pixel.
// Qt steps the spring once per 16 ms frame: velocity = velocity * (1 - damping)
// + spring * 0.016 * (target - value), then value += velocity. That is a damped
// oscillator of unit mass (stiffness k = natural frequency squared, damping
// coefficient c = 2 * zeta * omega), so the Telamon OS shell can match it:
//   standard    omega 25 rad/s (k 645 /s^2), zeta 0.98, c 49 /s (critical)
//   expressive  omega 17 rad/s (k 299 /s^2), zeta 0.64, c 22 /s
//
//   Rectangle {
//       id: indicator
//       Behavior on x {
//           enabled: !TelamonStyle.reducedMotion
//           TelamonSpringAnimation { expressive: true }
//       }
//   }
SpringAnimation {
    // A small overshoot for signature moments; false is the everyday spring.
    property bool expressive: false
    // For values that move less than about 2 units (scale, 0 to 1): stops at
    // 0.001 instead of 0.25.
    property bool fine: false

    spring: expressive ? 4 : 7
    damping: expressive ? 0.3 : 0.55
    mass: 1
    epsilon: fine ? 0.001 : 0.25
}
