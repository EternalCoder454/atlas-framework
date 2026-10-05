import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import Atlas.Ui

// A thin, rounded scroll bar. The thumb widens when the pointer is over the
// bar and fades out when nothing is scrolling (policy AsNeeded). It stays
// drawn while hovered or pressed, and always when a screen reader is active.
// Under reduced motion nothing fades or grows slowly: it shows and hides at
// once.
//
//   Flickable {
//       ScrollBar.vertical: AtlasScrollBar {}
//   }
T.ScrollBar {
    id: control

    // Shown steadily rather than only while scrolling.
    readonly property bool _steady: control.hovered || control.pressed || AccessibilityState.active

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset, implicitContentHeight + topPadding + bottomPadding)
    // The bar is as thick as the widened thumb, so hovering it is easy; the
    // thumb inside is thin until then.
    padding: AtlasStyle.spacingXSmall + 1
    hoverEnabled: true
    policy: T.ScrollBar.AsNeeded
    minimumSize: Math.min(1, (Kirigami.Units.gridUnit * 2) / Math.max(1, control.horizontal ? control.width : control.height))

    Accessible.role: Accessible.ScrollBar
    //: Accessible name of a scroll bar
    Accessible.name: qsTr("Scroll bar")

    contentItem: Item {
        id: handle
        // Laid out by the bar: a vertical bar sets x, y, width and height of its handle.
        implicitWidth: control.vertical ? Kirigami.Units.smallSpacing * 2 + 2 : 0
        implicitHeight: control.horizontal ? Kirigami.Units.smallSpacing * 2 + 2 : 0
        opacity: 0

        readonly property bool _shown: control.policy === T.ScrollBar.AlwaysOn || (control.size < 1 && (control.active || control._steady))
        states: State {
            name: "shown"
            when: handle._shown
            PropertyChanges {
                handle.opacity: 1
            }
        }
        transitions: [
            Transition {
                from: "shown"
                to: ""
                SequentialAnimation {
                    PauseAnimation {
                        duration: AtlasStyle.reducedMotion ? 0 : AtlasStyle.durationLong
                    }
                    NumberAnimation {
                        property: "opacity"
                        duration: AtlasStyle.durationLong
                    }
                }
            },
            Transition {
                from: ""
                to: "shown"
                NumberAnimation {
                    property: "opacity"
                    duration: AtlasStyle.durationShort
                }
            }
        ]

        Rectangle {
            id: thumb
            // Thin at rest, wider under the pointer; the bar's padding keeps it a little off the edge.
            property real thickness: control._steady ? Kirigami.Units.smallSpacing * 2 : Math.max(4, Kirigami.Units.smallSpacing)
            width: control.vertical ? thickness : parent.width
            height: control.horizontal ? thickness : parent.height
            x: control.vertical ? (control.mirrored ? 0 : parent.width - width) : 0
            y: control.horizontal ? parent.height - height : 0
            radius: Math.min(width, height) / 2
            color: control.pressed ? AtlasStyle.text : control.hovered ? Qt.alpha(AtlasStyle.text, 0.75) : AtlasStyle.textMuted
            Behavior on thickness {
                NumberAnimation {
                    duration: AtlasStyle.durationShort
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: AtlasStyle.durationShort
                }
            }
        }
    }
}
