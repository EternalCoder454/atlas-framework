import QtQuick
import QtQuick.Shapes
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A busy indicator: an accent arc that turns. Show it while something loads;
// `running: false` hides it. It stands still (a fixed arc) while it is not
// visible, with `animated: false`, or when Plasma's animation speed is
// "Instant".
//
//   AtlasSpinner { running: model.loading }
T.BusyIndicator {
    id: control

    // Turn the arc. Off for a fixed arc, e.g. in screenshots.
    property bool animated: true

    QtObject {
        id: internals
        readonly property bool turning: control.animated && control.running && control.visible && Kirigami.Units.longDuration > 1
        readonly property real stroke: Math.max(2, Math.round(control.availableWidth / 9))
    }

    implicitWidth: Kirigami.Units.iconSizes.medium
    implicitHeight: implicitWidth
    padding: 0
    visible: running

    Accessible.role: Accessible.Indicator
    //: Spoken name of a busy indicator or loading skeleton: content is on its way
    Accessible.name: qsTr("Loading")

    contentItem: Item {
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: implicitWidth

        Shape {
            id: arc
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // Drawn once into a texture; turning it is then one transform per
            // frame, on the render thread, with nothing to re-tessellate.
            layer.enabled: true
            layer.smooth: true
            // The shape is a ring track and a quarter arc on it.
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(Kirigami.Theme.textColor, 0.12)
                strokeWidth: internals.stroke
                PathAngleArc {
                    centerX: arc.width / 2
                    centerY: arc.height / 2
                    radiusX: (arc.width - internals.stroke) / 2
                    radiusY: radiusX
                    startAngle: 0
                    sweepAngle: 360
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: Kirigami.Theme.highlightColor
                strokeWidth: internals.stroke
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: arc.width / 2
                    centerY: arc.height / 2
                    radiusX: (arc.width - internals.stroke) / 2
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: 100
                }
            }
            RotationAnimator on rotation {
                from: 0
                to: 360
                // One turn in about a second at normal speed.
                duration: Kirigami.Units.longDuration * 4
                loops: Animation.Infinite
                running: internals.turning
            }
        }
    }
}
