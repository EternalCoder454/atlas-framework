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
// inside it (a drop-down, a colour swatch) follow the buttons. `orientation:
// Qt.Vertical` makes a tall capsule; `autoDim` keeps it quiet until the
// pointer is near. Escape on a button emits `escaped()` and gives the focus
// back to `returnFocus`, else to the item that had it before Tab came in.
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
    // Qt.Horizontal or Qt.Vertical (a tall capsule).
    property int orientation: Qt.Horizontal
    // What happens to buttons that do not fit: see AtlasToolbar.
    property int overflow: AtlasToolbar.Menu
    // With `focusable`, false makes a click not take the focus from the editor.
    property bool focusOnClick: true
    // True keeps the capsule quiet (at `dimOpacity`) until the pointer is within
    // `nearDistance` of it, a button has focus, a menu or popover from it is
    // open, `keepActive` is set or a press is down. Always full under high contrast.
    property bool autoDim: false
    property real dimOpacity: 0.35
    // How close the pointer must be, in px, to bring the capsule to full strength.
    property real nearDistance: 80
    // Holds full strength, for an app popover the toolbar cannot see.
    property bool keepActive: false
    // True at full strength.
    readonly property bool near: !autoDim || AtlasStyle.highContrast || keepActive || _pointerNear || _focusInside || bar._menuOpen || _pressed
    // Where Escape sends the focus.
    property Item returnFocus: null

    // Escape was pressed on a button.
    signal escaped

    // The inner toolbar, e.g. for its "more" menu.
    readonly property AtlasToolbar toolbar: bar

    property bool _pointerNear: false
    property bool _pressed: false
    // The item that had the focus before Tab came into the strip.
    property Item _last: null
    readonly property Item _focusItem: root.Window.window ? root.Window.window.activeFocusItem : null
    function _isInside(item): bool {
        for (let i = item; i; i = i.parent) {
            if (i === bar) {
                return true;
            }
        }
        return false;
    }
    readonly property bool _focusInside: _isInside(_focusItem)
    on_FocusItemChanged: if (_focusItem && !_isInside(_focusItem)) _last = _focusItem
    Component.onCompleted: if (_focusItem && !_isInside(_focusItem)) _last = _focusItem
    readonly property real _shadow: 6
    // The slide: it moves up by this much as it appears.
    readonly property real _slide: AtlasStyle.spacingLarge
    readonly property bool _vertical: orientation === Qt.Vertical
    // A vertical capsule slides sideways, away from the edge nearest it.
    readonly property real _slideSign: parent && x + width / 2 < parent.width / 2 ? -1 : 1

    implicitWidth: bar.implicitWidth
    implicitHeight: bar.implicitHeight
    width: _vertical ? implicitWidth : Math.min(implicitWidth, parent ? Math.max(0, parent.width - margin * 2) : implicitWidth)
    height: _vertical ? Math.min(implicitHeight, parent ? Math.max(0, parent.height - margin * 2) : implicitHeight) : implicitHeight
    opacity: shown ? (near ? 1 : dimOpacity) : 0
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

    // The pointer is read on the parent with one handler: no timer, nothing
    // runs while it is still, and a hidden capsule tracks nothing.
    HoverHandler {
        parent: root.parent
        enabled: root.shown && root.autoDim
        onPointChanged: root._track(point.position)
        onHoveredChanged: if (!hovered) root._pointerNear = false
    }
    function _track(p: point): void {
        const rx = root.x + root._dx;
        const ry = root.y + root._dy;
        const dx = Math.max(rx - p.x, 0, p.x - (rx + root.width));
        const dy = Math.max(ry - p.y, 0, p.y - (ry + root.height));
        root._pointerNear = Math.hypot(dx, dy) <= root.nearDistance;
    }

    Item {
        id: slider
        width: root.width
        height: root.height
        x: root._dx + (root._vertical ? slideOffset * root._slideSign : 0)
        y: root._dy + (root._vertical ? 0 : slideOffset)
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
                radius: Math.min(Math.min(width, height) / 2, AtlasStyle.radiusPill)
                color: Qt.rgba(0, 0, 0, 0.07)
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: Math.min(Math.min(width, height) / 2, AtlasStyle.radiusPill)
            color: AtlasStyle.chromeBackground
            border.width: 1
            border.color: AtlasStyle.controlBorder
        }
        AtlasToolbar {
            id: bar
            anchors.fill: parent
            flat: true
            actions: root.actions
            focusable: root.focusable
            focusOnClick: root.focusOnClick
            orientation: root.orientation
            overflow: root.overflow
            accessibleName: root.accessibleName
            Keys.onEscapePressed: event => {
                root.escaped();
                const to = root.returnFocus ? root.returnFocus : root._last;
                // Taken only when focus moves; otherwise Escape goes on to the app.
                if (to && to.visible && !to.activeFocus) {
                    to.forceActiveFocus(Qt.OtherFocusReason);
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }
        }
        // A press holds full strength (a tap on a touch screen has no hover).
        TapHandler {
            enabled: root.shown && root.autoDim
            grabPermissions: PointerHandler.TakeOverForbidden
            onPressedChanged: root._pressed = pressed
        }
    }
}
