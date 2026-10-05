pragma ComponentBehavior: Bound
import QtQuick
import org.kde.kirigami as Kirigami

// A skeleton block shown where content is still loading: soft rounded bars
// with a light sweep over them. `lines` is the number of bars (the last of
// several is shorter, like the end of a paragraph); each is `lineHeight`
// tall. Size it with `width`, or let it fill a layout. The sweep stops while
// the item is not visible, with `animated: false`, or when Plasma's
// animation speed is "Instant".
//
//   AtlasPlaceholder { width: 240; lines: 3 }
//   AtlasPlaceholder { width: 64; height: 64; lines: 1; lineHeight: 64 }
Item {
    id: control

    property int lines: 1
    property real lineHeight: Kirigami.Units.gridUnit
    // Sweep the light across. Off for still bars, e.g. in screenshots.
    property bool animated: true

    QtObject {
        id: internals
        readonly property int count: Math.max(1, control.lines)
        readonly property bool sweeping: control.animated && control.visible && control.opacity > 0 && AtlasStyle.duration > 1 && !AtlasStyle.softwareRendering
        // 0 to 1 across the sweep.
        property real phase: 0
    }

    implicitWidth: Kirigami.Units.gridUnit * 12
    implicitHeight: internals.count * control.lineHeight + (internals.count - 1) * AtlasStyle.spacingSmall

    Accessible.role: Accessible.Indicator
    //: Spoken name of a busy indicator or loading skeleton: content is on its way
    Accessible.name: qsTr("Loading")

    NumberAnimation {
        target: internals
        property: "phase"
        from: 0
        to: 1
        duration: AtlasStyle.durationLong * 4
        loops: Animation.Infinite
        running: internals.sweeping
    }

    Column {
        width: parent.width
        spacing: AtlasStyle.spacingSmall
        Repeater {
            model: internals.count
            delegate: Rectangle {
                id: bar
                required property int index
                width: internals.count > 1 && index === internals.count - 1 ? Math.round(parent.width * 0.6) : parent.width
                height: control.lineHeight
                radius: Math.min(8, height / 2)
                color: AtlasStyle.alpha(Kirigami.Theme.textColor, 0.08)
                clip: true
                Accessible.ignored: true

                Rectangle {
                    visible: internals.sweeping
                    width: Math.round(parent.width * 0.4)
                    height: parent.height
                    x: -width + internals.phase * (parent.width + width)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: AtlasStyle.alpha(Kirigami.Theme.textColor, 0)
                        }
                        GradientStop {
                            position: 0.5
                            color: AtlasStyle.alpha(Kirigami.Theme.textColor, 0.08)
                        }
                        GradientStop {
                            position: 1
                            color: AtlasStyle.alpha(Kirigami.Theme.textColor, 0)
                        }
                    }
                }
            }
        }
    }
}
