import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A slider: a thin pill track filled with the accent up to a white knob.
// `from`, `to`, `value`, `stepSize` and `onMoved` work as in any Slider; it
// can be vertical.
//
//   AtlasSlider { from: 0; to: 100; value: 40; onMoved: volume = value }
T.Slider {
    id: control

    implicitWidth: control.horizontal ? Kirigami.Units.gridUnit * 12 : implicitHandleWidth + leftPadding + rightPadding
    implicitHeight: control.horizontal ? implicitHandleHeight + topPadding + bottomPadding : Kirigami.Units.gridUnit * 12
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.Slider
    Accessible.name: qsTr("Slider")
    Accessible.description: String(Math.round(control.value * 100) / 100)

    background: Rectangle {
        readonly property real thickness: 4
        x: control.leftPadding + (control.horizontal ? 0 : (control.availableWidth - width) / 2)
        y: control.topPadding + (control.horizontal ? (control.availableHeight - height) / 2 : 0)
        width: control.horizontal ? control.availableWidth : thickness
        height: control.horizontal ? thickness : control.availableHeight
        radius: thickness / 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.2)

        Rectangle {
            // The filled part runs from the start to the knob's centre.
            x: control.horizontal && control.mirrored ? parent.width - width : 0
            y: control.horizontal ? 0 : parent.height - height
            width: control.horizontal ? control.position * parent.width : parent.width
            height: control.horizontal ? parent.height : control.position * parent.height
            radius: parent.radius
            color: control.enabled ? Kirigami.Theme.highlightColor : control.palette.active.highlight
        }
    }

    handle: Rectangle {
        implicitWidth: 20
        implicitHeight: 20
        x: control.leftPadding + (control.horizontal ? control.visualPosition * (control.availableWidth - width) : (control.availableWidth - width) / 2)
        y: control.topPadding + (control.horizontal ? (control.availableHeight - height) / 2 : control.visualPosition * (control.availableHeight - height))
        radius: width / 2
        color: "white"
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.highlightColor, control.pressed ? 0.7 : 0.45)
        scale: control.pressed ? 1.1 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Kirigami.Units.shortDuration
                easing.type: Easing.OutCubic
            }
        }
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }
}
