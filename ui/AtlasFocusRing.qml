import QtQuick
import org.kde.kirigami as Kirigami

// The keyboard focus ring every Atlas control shows: an accent outline just
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
    border.color: Qt.alpha(Kirigami.Theme.highlightColor, 0.6)
    visible: shown
    z: 1
    Accessible.ignored: true
}
