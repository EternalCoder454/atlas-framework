pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import QtQuick.Controls as QQC2
import QtQml
import org.kde.kirigami as Kirigami
import Atlas.Ui

// A raised card that opens next to a control: surface colour, rounded
// corners, a soft shadow and a hairline border, with an optional arrow that
// points at `target`. It opens below the target, or above when there is no
// room below (`side` picks another side: Above, Start or End, and flips to
// the opposite one when there is no room), lines up with the target's leading
// edge (trailing in a right-to-left layout) and is kept inside the window. Escape and a click
// outside close it, and the focus goes back to the target. It is placed again
// when the window is resized or the target (or anything it sits in) moves. With
// no target it opens in the middle of the window, with no arrow. Put anything in it.
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

    // Where the popover opens: Auto is below, else above. Start and End are
    // logical: End is the right of the target in a left-to-right layout.
    enum Side {
        Auto = 0,
        Below = 1,
        Above = 2,
        Start = 3,
        End = 4
    }
    property int side: AtlasPopover.Auto
    // The side in use after fitting (never Auto).
    readonly property int placedSide: control._phys === 3 ? (control.mirrored ? AtlasPopover.End : AtlasPopover.Start) : control._phys === 4 ? (control.mirrored ? AtlasPopover.Start : AtlasPopover.End) : control._phys

    // True when the popover sits above the target.
    readonly property bool above: control._above
    // The side in use as the screen sees it: 1 below, 2 above, 3 left, 4 right of the target.
    property int _phys: 1
    readonly property bool _above: control._phys === 2
    // Where the arrow's tip is, in the popover's own coordinates.
    property real _arrowX: width / 2
    property real _arrowY: height / 2

    readonly property real _arrowSize: control.showArrow && control.target ? Kirigami.Units.smallSpacing * 2 : 0
    readonly property real _gap: Kirigami.Units.smallSpacing
    readonly property real _edge: Kirigami.Units.smallSpacing * 2

    parent: QQC2.Overlay.overlay
    modal: false
    focus: true
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutside
    padding: AtlasStyle.spacingLarge * 2
    // The arrow's room is inside the popover's box, outside its card.
    topInset: control._phys === 1 ? control._arrowSize : 0
    bottomInset: control._phys === 2 ? control._arrowSize : 0
    leftInset: control._phys === 4 ? control._arrowSize : 0
    rightInset: control._phys === 3 ? control._arrowSize : 0
    topPadding: padding + topInset
    bottomPadding: padding + bottomInset
    leftPadding: padding + leftInset
    rightPadding: padding + rightInset
    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset, contentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset, contentHeight + topPadding + bottomPadding)

    // On the chosen side when it fits, else the opposite side when that fits,
    // else the side with more room; then lined up (or centred, for Start and
    // End) and clamped into the parent.
    function _place(): void {
        const t = control.target;
        const p = control.parent;
        if (!p) {
            return;
        }
        if (!t) {
            control.x = Math.max(0, Math.round((p.width - control.implicitWidth) / 2));
            control.y = Math.max(0, Math.round((p.height - control.implicitHeight) / 2));
            return;
        }
        const origin = t.mapToItem(p, 0, 0);
        // The card's own size: the arrow's room is added on the facing side.
        const bw = control.implicitWidth - control.leftInset - control.rightInset;
        const bh = control.implicitHeight - control.topInset - control.bottomInset;
        const room = [0, p.height - (origin.y + t.height) - control._gap, origin.y - control._gap, origin.x - control._gap, p.width - (origin.x + t.width) - control._gap];
        const need = [0, bh + control._arrowSize, bh + control._arrowSize, bw + control._arrowSize, bw + control._arrowSize];
        let first = 1;
        if (control.side === AtlasPopover.Above) {
            first = 2;
        } else if (control.side === AtlasPopover.Start) {
            first = control.mirrored ? 4 : 3;
        } else if (control.side === AtlasPopover.End) {
            first = control.mirrored ? 3 : 4;
        }
        // 1 and 2, 3 and 4 are opposites.
        const other = first + (first % 2 === 1 ? 1 : -1);
        let phys = first;
        if (need[first] > room[first]) {
            phys = need[other] <= room[other] || room[other] > room[first] ? other : first;
        }
        control._phys = phys;
        const horizontal = phys >= 3;
        const w = bw + (horizontal ? control._arrowSize : 0);
        const h = bh + (horizontal ? 0 : control._arrowSize);
        let rawX;
        let rawY;
        if (horizontal) {
            rawY = origin.y + t.height / 2 - h / 2;
            rawX = phys === 3 ? origin.x - control._gap - w : origin.x + t.width + control._gap;
        } else {
            rawY = phys === 2 ? origin.y - control._gap - h : origin.y + t.height + control._gap;
            rawX = control.mirrored ? origin.x + t.width - w : origin.x;
        }
        control.y = Math.max(0, Math.min(rawY, p.height - h));
        control.x = Math.max(0, Math.min(rawX, p.width - w));
        // Keep the arrow on the straight part of the card, off the rounded corners.
        const lo = AtlasStyle.radius + control._arrowSize;
        control._arrowX = Math.max(lo, Math.min(origin.x + t.width / 2 - control.x, w - lo));
        control._arrowY = Math.max(lo, Math.min(origin.y + t.height / 2 - control.y, h - lo));
    }

    // The target and everything it sits in: when one moves, the popover follows.
    property var _chain: []
    // Rebuilds the chain, then places. Run when the popover shows, when the
    // target changes and when an item of the chain gets a new parent.
    function _track(): void {
        const chain = [];
        for (let i = control.target; i; i = i.parent) {
            chain.push(i);
        }
        control._chain = chain;
        control._place();
    }
    onAboutToShow: control._track()
    onTargetChanged: if (visible) control._track()
    onParentChanged: if (visible) control._place()
    // In a list property of its own, not the default one (the column).
    readonly property list<QtObject> _watchers: [
        Connections {
            target: control.parent
            function onWidthChanged() { if (control.visible) control._place(); }
            function onHeightChanged() { if (control.visible) control._place(); }
        },
        Instantiator {
            model: control._chain
            delegate: Connections {
                required property var modelData
                target: modelData
                function onXChanged() { if (control.visible) control._place(); }
                function onYChanged() { if (control.visible) control._place(); }
                function onWidthChanged() { if (control.visible) control._place(); }
                function onHeightChanged() { if (control.visible) control._place(); }
                // Not rebuilt here: this delegate would be destroyed inside its own signal.
                function onParentChanged() { if (control.visible) Qt.callLater(control._track); }
            }
        }
    ]
    onImplicitHeightChanged: if (visible) control._place()
    onImplicitWidthChanged: if (visible) control._place()
    onClosed: {
        control._chain = [];
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
            color: AtlasStyle.alpha("black", 0.05)
        }
        Rectangle {
            anchors.fill: card
            anchors.margins: -2
            anchors.topMargin: 0
            anchors.bottomMargin: -4
            radius: AtlasStyle.radius + 2
            color: AtlasStyle.alpha("black", 0.035)
        }
        Rectangle {
            anchors.fill: card
            anchors.margins: -3
            anchors.topMargin: -1
            anchors.bottomMargin: -5
            radius: AtlasStyle.radius + 3
            color: AtlasStyle.alpha("black", 0.02)
        }
        Rectangle {
            id: card
            x: control.leftInset
            y: control.topInset
            width: parent.width - control.leftInset - control.rightInset
            height: parent.height - control.topInset - control.bottomInset
            radius: AtlasStyle.radius
            color: control._surface
            border.width: 1
            border.color: AtlasStyle.separator
        }
        // The arrow: a square turned 45 degrees, cut off at the card's edge.
        Item {
            visible: control.showArrow && control._phys <= 2
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
        // The same arrow on a side edge, for Start and End.
        Item {
            visible: control.showArrow && control._phys >= 3
            x: control._phys === 3 ? card.x + card.width - 1 : 0
            width: control._arrowSize + 1
            y: control._arrowY - control._arrowSize
            height: control._arrowSize * 2
            clip: true
            Rectangle {
                width: control._arrowSize * Math.SQRT2
                height: width
                x: (control._phys === 3 ? 1 : control._arrowSize) - width / 2
                y: control._arrowSize - height / 2
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
