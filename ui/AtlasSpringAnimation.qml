import QtQuick
import Atlas.Ui

// AtlasSpringAnimation: the Atlas spring for spatial movement, standard (no
// overshoot, settles quickly) or expressive (a small overshoot, for the
// signature moments only; see AtlasStyle). Use it in a Behavior on x, y,
// width, height or scale, never on colour or opacity. Under reduced motion
// the Behavior is turned off, so the value jumps; fade with an opacity
// animation where a jump would look abrupt.
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

    spring: expressive ? 4.5 : 6
    damping: expressive ? 0.3 : 0.55
    mass: 1
    epsilon: 0.25
}
