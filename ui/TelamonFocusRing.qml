import QtQuick
import Telamon.Ui

// The keyboard focus ring every Telamon control shows: a 2 px accent
// (TelamonStyle.focus) outline with a 2 px gap outside the control's shape, only
// when focus came from the keyboard. It fades in with durationShort and grows
// slightly into place (scale 0.96 to 1, the expressive spring); under reduced
// motion it only appears. Put it inside the control's background and give it
// the shape's radius plus the gap:
//
//   background: Rectangle {
//       radius: TelamonStyle.radiusSmall
//       TelamonFocusRing { radius: parent.radius + gap; shown: control.visualFocus }
//   }
//
// Decorative: screen readers skip it.
Rectangle {
    // Usually the control's visualFocus.
    property bool shown: false
    // How far outside the parent the ring sits.
    property real gap: 2

    anchors.fill: parent
    anchors.margins: -gap
    radius: 0
    color: "transparent"
    border.width: 2
    border.color: TelamonStyle.focus
    // Fades out before it is hidden; nothing runs while it is off.
    visible: shown || opacity > 0
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.96
    Behavior on opacity {
        NumberAnimation {
            duration: TelamonStyle.durationShort
        }
    }
    Behavior on scale {
        enabled: !TelamonStyle.reducedMotion
        TelamonSpringAnimation {
            expressive: true
            fine: true
        }
    }
    z: 1
    Accessible.ignored: true
}
