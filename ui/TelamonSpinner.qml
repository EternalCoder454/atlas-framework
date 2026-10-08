import QtQuick
import QtQuick.Shapes
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A busy indicator: an accent arc that turns. Show it while something loads;
// `running: false` hides it. It stands still (a fixed arc) while it is not
// visible, with `animated: false`, or when Plasma's animation speed is
// "Instant".
//
//   TelamonSpinner { running: model.loading }
T.BusyIndicator {
    id: control

    // Turn the arc. Off for a fixed arc, e.g. in screenshots.
    property bool animated: true
    // The arc's colour: the accent, or a button's text colour on a filled button.
    property color color: TelamonStyle.accent

    QtObject {
        id: internals
        readonly property bool turning: control.animated && control.running && control.visible && TelamonStyle.duration > 1
        readonly property real stroke: Math.max(2, Math.round(control.availableWidth / 9))
        // The ring's radius leaves half a pixel at the edge: the stroke's
        // outside would otherwise touch the item's bounds exactly, and a
        // texture a pixel short (a fractional scale) cuts it off flat.
        readonly property real radius: Math.max(1, (control.availableWidth - stroke) / 2 - 0.5)
        // A third of the ring: a quarter of it is 10 px of 2 px line at 16 px,
        // too short to read as an arc.
        readonly property real sweep: 120
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
            // The shape is a ring track and an arc on it.
            ShapePath {
                fillColor: "transparent"
                strokeColor: TelamonStyle.alpha(Kirigami.Theme.textColor, 0.12)
                strokeWidth: internals.stroke
                PathAngleArc {
                    centerX: arc.width / 2
                    centerY: arc.height / 2
                    radiusX: internals.radius
                    radiusY: radiusX
                    startAngle: 0
                    sweepAngle: 360
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: control.color
                strokeWidth: internals.stroke
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: arc.width / 2
                    centerY: arc.height / 2
                    radiusX: internals.radius
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: internals.sweep
                }
            }
            RotationAnimator on rotation {
                from: 0
                to: 360
                // One turn in about a second at normal speed.
                duration: TelamonStyle.duration * 4
                loops: Animation.Infinite
                running: internals.turning && !TelamonStyle.softwareRendering
            }
            // In software rendering each turn repaints the spinner, so it
            // steps 30 degrees at about 12 frames a second instead.
            Timer {
                interval: 80
                repeat: true
                running: internals.turning && TelamonStyle.softwareRendering
                onTriggered: arc.rotation = (arc.rotation + 30) % 360
            }
        }
    }
}
