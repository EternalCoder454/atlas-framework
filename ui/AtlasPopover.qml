import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// A raised card that opens next to a control: surface colour, rounded
// corners, a soft shadow and a hairline border, with an optional arrow that
// points at `target`. It opens below the target, or above when there is no
// room below, lines up with the target's leading edge (trailing in a
// right-to-left layout) and is kept inside the window. Escape and a click
// outside close it, and the focus goes back to the target. Put anything in it.
//
//   AtlasButton { id: more; text: qsTr("More"); onClicked: info.open() }
//   AtlasPopover {
//       id: info
//       target: more
//       AtlasLabel { text: qsTr("Details go here.") }
//   }
T.Popup {
    id: control

    // floatingBackground is tinted translucent over the blurred window, solid without it.
    readonly property color _surface: AtlasStyle.floatingBackground

    // The item the popover belongs to and points at; set it before opening.
    property Item target
    property bool showArrow: true
    default property alias content: column.data

    // True when the popover sits above the target.
    readonly property bool above: control._above
    property bool _above: false
    // Where the arrow's tip is, in the popover's own coordinates.
    property real _arrowX: width / 2

    readonly property real _arrowSize: control.showArrow ? Kirigami.Units.smallSpacing * 2 : 0
    readonly property real _gap: Kirigami.Units.smallSpacing
    readonly property real _edge: Kirigami.Units.smallSpacing * 2

    parent: QQC2.Overlay.overlay
    modal: false
    focus: true
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutside
    padding: AtlasStyle.spacingLarge * 2
    // The arrow's room is inside the popover's box, outside its card.
    topInset: control._above ? 0 : control._arrowSize
    bottomInset: control._above ? control._arrowSize : 0
    topPadding: padding + topInset
    bottomPadding: padding + bottomInset
    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset, contentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset, contentHeight + topPadding + bottomPadding)

    // Below the target when it fits, else above when that fits, else on the
    // side with more room; then lined up and clamped.
    function _place(): void {
        const t = control.target;
        const p = control.parent;
        if (!t || !p) {
            return;
        }
        const origin = t.mapToItem(p, 0, 0);
        const w = control.implicitWidth;
        const h = control.implicitHeight;
        const below = p.height - (origin.y + t.height) - control._gap;
        const over = origin.y - control._gap;
        control._above = h > below && over > below;
        const rawY = control._above ? origin.y - control._gap - h : origin.y + t.height + control._gap;
        control.y = Math.max(0, Math.min(rawY, p.height - h));
        const rawX = control.mirrored ? origin.x + t.width - w : origin.x;
        control.x = Math.max(0, Math.min(rawX, p.width - w));
        const centre = origin.x + t.width / 2 - control.x;
        // Keep the arrow on the straight part of the card, off the rounded corners.
        const lo = AtlasStyle.radius + control._arrowSize;
        control._arrowX = Math.max(lo, Math.min(centre, w - lo));
    }

    onAboutToShow: control._place()
    onImplicitHeightChanged: if (visible) control._place()
    onImplicitWidthChanged: if (visible) control._place()
    onClosed: {
        const t = control.target;
        const focused = t ? t.Window.window?.activeFocusItem : null;
        let inside = !focused;
        for (let i = focused; i && !inside; i = i.parent) {
            inside = i === control.contentItem || i === control.background;
        }
        // A click into another field keeps its caret.
        if (t && t.visible && t.enabled && inside) {
            t.forceActiveFocus(Qt.PopupFocusReason);
        }
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: AtlasStyle.durationShort
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: AtlasStyle.durationShort
        }
    }

    background: Item {
        // A soft shadow made of a few faint outlines: no shader, so it also draws with the software renderer.
        Rectangle {
            anchors.fill: card
            anchors.margins: -1
            anchors.topMargin: 1
            anchors.bottomMargin: -3
            radius: AtlasStyle.radius + 1
            color: Qt.alpha("black", 0.05)
        }
        Rectangle {
            anchors.fill: card
            anchors.margins: -2
            anchors.topMargin: 0
            anchors.bottomMargin: -4
            radius: AtlasStyle.radius + 2
            color: Qt.alpha("black", 0.035)
        }
        Rectangle {
            anchors.fill: card
            anchors.margins: -3
            anchors.topMargin: -1
            anchors.bottomMargin: -5
            radius: AtlasStyle.radius + 3
            color: Qt.alpha("black", 0.02)
        }
        Rectangle {
            id: card
            x: 0
            y: control.topInset
            width: parent.width
            height: parent.height - control.topInset - control.bottomInset
            radius: AtlasStyle.radius
            color: control._surface
            border.width: 1
            border.color: AtlasStyle.separator
        }
        // The arrow: a square turned 45 degrees, cut off at the card's edge.
        Item {
            visible: control.showArrow
            x: control._arrowX - control._arrowSize
            width: control._arrowSize * 2
            y: control._above ? card.y + card.height - 1 : 0
            height: control._arrowSize + 1
            clip: true
            Rectangle {
                width: control._arrowSize * Math.SQRT2
                height: width
                x: control._arrowSize - width / 2
                y: (control._above ? 1 : control._arrowSize) - height / 2
                rotation: 45
                color: control._surface
                border.width: 1
                border.color: AtlasStyle.separator
            }
        }
    }

    contentItem: ColumnLayout {
        id: column
        spacing: AtlasStyle.spacing
        Accessible.role: Accessible.Pane
    }
}
