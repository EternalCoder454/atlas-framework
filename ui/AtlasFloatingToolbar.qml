pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A capsule of icon buttons that floats over content, such as the formatting
// tools over an editor: a rounded surface with a soft shadow. It is an
// AtlasToolbar inside, so it has the same `actions` (AtlasAction or Qt Action,
// dividers between sections) and its "more" menu when the parent is too narrow.
// Its buttons never take the keyboard focus (`focusable: false`), so the
// editor keeps typing; set `focusable: true` to let Tab reach them. Items put
// inside it (a drop-down, a colour swatch) follow the buttons.
//
// `shown` fades it in and out with a short slide; hidden, it takes no input
// and is not visible. It stays inside its parent: it is drawn at least
// `margin` from the edges whatever `x` and `y` say (they are not changed), and
// it is never wider than the parent less the margins.
//
//   AtlasFloatingToolbar {
//       actions: [boldAction, italicAction, linkAction]
//       shown: editor.hasSelection
//       x: Math.round((parent.width - width) / 2)
//       y: parent.height - height - 16
//   }
Item {
    id: root

    property list<T.Action> actions
    // Extra items after the buttons.
    default property alias content: bar.trailing
    // True shows the capsule; false fades it away.
    property bool shown: true
    // Lets Tab reach the buttons. False keeps the focus in the editor.
    property bool focusable: false
    // Room kept free between the capsule and the parent's edges.
    property real margin: AtlasStyle.spacingLarge
    // The name for screen readers.
    property string accessibleName: qsTr("Tools")

    // The inner toolbar, e.g. for its "more" menu.
    readonly property AtlasToolbar toolbar: bar

    readonly property real _shadow: 6
    // The slide: it moves up by this much as it appears.
    readonly property real _slide: AtlasStyle.spacingLarge

    implicitWidth: bar.implicitWidth
    implicitHeight: bar.implicitHeight
    width: Math.min(implicitWidth, parent ? Math.max(0, parent.width - margin * 2) : implicitWidth)
    height: implicitHeight
    opacity: shown ? 1 : 0
    visible: opacity > 0
    // Hidden: no clicks reach the buttons beneath the fade.
    enabled: shown

    Behavior on opacity {
        NumberAnimation {
            duration: AtlasStyle.duration
            easing.type: Easing.OutCubic
        }
    }

    // How far the capsule is drawn from its x and y to stay `margin` inside
    // the parent. Nothing is assigned to x or y, so a binding on them lives.
    readonly property real _dx: parent && parent.width > 0 ? Math.max(margin, Math.min(x, Math.max(margin, parent.width - width - margin))) - x : 0
    readonly property real _dy: parent && parent.height > 0 ? Math.max(margin, Math.min(y, Math.max(margin, parent.height - height - margin))) - y : 0

    Item {
        id: slider
        width: root.width
        height: root.height
        x: root._dx
        y: root._dy + slideOffset
        property real slideOffset: root.shown ? 0 : root._slide
        Behavior on slideOffset {
            NumberAnimation {
                duration: AtlasStyle.duration
                easing.type: Easing.OutCubic
            }
        }

        // A soft shadow from stacked translucent rounded rectangles: cheap and
        // the same on every renderer.
        Repeater {
            model: 3
            delegate: Rectangle {
                required property int index
                readonly property real grow: (index + 1) * root._shadow / 3
                x: -grow
                y: -grow + root._shadow / 2
                width: slider.width + grow * 2
                height: slider.height + grow * 2
                radius: Math.min(height / 2, AtlasStyle.radiusPill)
                color: Qt.rgba(0, 0, 0, 0.07)
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: Math.min(height / 2, AtlasStyle.radiusPill)
            color: AtlasStyle.surface
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.18)
        }
        AtlasToolbar {
            id: bar
            anchors.fill: parent
            flat: true
            actions: root.actions
            focusable: root.focusable
            accessibleName: root.accessibleName
        }
    }
}
