import QtQuick
import Atlas.Ui

// The keyboard focus ring every Atlas control shows: a pink (AtlasStyle.focus) outline just
// outside the control's shape, only when focus came from the keyboard. Put
// it inside the control's background and give it the shape's radius:
//
//   background: Rectangle {
//       radius: height / 2
//       AtlasFocusRing { radius: parent.radius; shown: control.visualFocus }
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
    border.color: Qt.alpha(AtlasStyle.focus, 0.85)
    visible: shown
    z: 1
    Accessible.ignored: true
}
