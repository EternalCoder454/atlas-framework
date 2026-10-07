pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import QtQml
import org.kde.kirigami as Kirigami

// A path bar: one button per segment with a chevron between them, the last
// one (where you are) in bold. When the path is wider than the bar, the
// middle collapses into a "…" button that opens a menu of the hidden
// segments; the first and the last always stay.
//
//   TelamonBreadcrumb {
//       segments: [
//           { title: qsTr("Home"), symbol: Symbols.Home },
//           { title: "Documents" },
//           { title: "Projects" },
//       ]
//       onActivated: index => goTo(index)
//   }
//
// A segment is an object with `title` and, optionally, `symbol`
// (Symbols.<Name>). `activated(index)` gives the segment's place in
// `segments`, whether it was clicked or chosen from the "…" menu. With the
// focus on the bar, Left and Right move between the buttons, Home and End
// jump to the ends, and Enter or Space presses the one in focus.
T.Control {
    id: control

    property var segments: []
    readonly property int count: control.segments ? control.segments.length : 0

    // See docs/reference/telamon-ui/telamon-breadcrumb.md.
    property string hiddenText: qsTr("Hidden folders")

    signal activated(int index)

    QtObject {
        id: priv
        readonly property font regular: Qt.font({ "family": TelamonStyle.fontFamily, "pointSize": TelamonStyle.fontSizeBody })
        // The default font in bold; `font.bold` cannot be set beside `font:`.
        readonly property font strong: {
            const f = Qt.font({ "family": TelamonStyle.fontFamily, "pointSize": TelamonStyle.fontSizeBody });
            const o = {
                "family": f.family,
                "bold": true
            };
            if (f.pixelSize > 0) {
                o.pixelSize = f.pixelSize;
            } else {
                o.pointSize = f.pointSize;
            }
            return Qt.font(o);
        }
        // Bumped when any segment's width changes, to lay out again.
        property int revision: 0
        // The segment the keyboard is on; -1 is the "…" button.
        property int current: -2
        property Item moreItem: null
        readonly property real chevronWidth: Math.round(Kirigami.Units.gridUnit * 1.1)
        readonly property real moreWidth: Math.round(Kirigami.Units.gridUnit * 2.2) + chevronWidth
        // The first segment that is shown after the "…"; 1 means none hidden.
        readonly property int firstTail: {
            priv.revision;
            const n = control.count;
            if (n < 3) {
                return Math.min(1, n);
            }
            const avail = control.availableWidth;
            let total = 0;
            for (let i = 0; i < n; ++i) {
                total += priv.widthOf(i);
            }
            if (total <= avail) {
                return 1;
            }
            let used = priv.widthOf(0) + priv.moreWidth + priv.widthOf(n - 1);
            let from = n - 1;
            while (from > 1 && used + priv.widthOf(from - 1) <= avail) {
                used += priv.widthOf(from - 1);
                --from;
            }
            return from;
        }
        readonly property bool collapsed: priv.firstTail > 1
        // What the arrow keys visit, in order.
        readonly property var stops: {
            const out = [];
            if (control.count === 0) {
                return out;
            }
            out.push(0);
            if (priv.collapsed) {
                out.push(-1);
            }
            for (let i = Math.max(1, priv.firstTail); i < control.count; ++i) {
                out.push(i);
            }
            return out;
        }
        readonly property int focused: priv.stops.indexOf(priv.current) >= 0 ? priv.current : priv.stops[priv.stops.length - 1] ?? -2

        function widthOf(i) {
            const item = items.itemAt(i);
            return item ? item.implicitWidth : 0;
        }
        function shown(i) {
            return i === 0 || i >= priv.firstTail;
        }
        function move(delta) {
            const at = priv.stops.indexOf(priv.focused);
            const to = Math.max(0, Math.min(priv.stops.length - 1, at + delta));
            priv.current = priv.stops[to];
        }
        // Tell screen readers which segment the keyboard moved to.
        function announceFocused() {
            const at = priv.focused;
            const title = at === -1 ? control.hiddenText : (control.segments[at]?.title ?? "");
            if (title.length > 0) {
                // On the control (an Item): a QtObject has no accessible to announce from.
                control.Accessible.announce(title);
            }
        }
        function press(stop) {
            if (stop === -1) {
                if (priv.moreItem) {
                    moreMenu.popup(priv.moreItem, 0, priv.moreItem.height);
                }
            } else if (stop >= 0) {
                control.activated(stop);
            }
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 24
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.9)
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.ToolBar
    //: Spoken name of a path bar (breadcrumb)
    Accessible.name: qsTr("Path")

    Keys.onPressed: event => {
        const dir = control.mirrored ? -1 : 1;
        let moved = false;
        switch (event.key) {
        case Qt.Key_Left:
            priv.move(-dir);
            moved = true;
            break;
        case Qt.Key_Right:
            priv.move(dir);
            moved = true;
            break;
        case Qt.Key_Home:
            priv.current = 0;
            moved = true;
            break;
        case Qt.Key_End:
            priv.current = control.count - 1;
            moved = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (event.isAutoRepeat) {
                break;
            }
            priv.press(priv.focused);
            break;
        default:
            return;
        }
        event.accepted = true;
        if (moved) {
            priv.announceFocused();
        }
    }

    background: null

    contentItem: Item {
        clip: true
        Row {
            id: row
            height: parent.height

            Repeater {
                id: items
                model: control.count
                // Widths are known only once a delegate exists, so measure again.
                onItemAdded: priv.revision++
                onItemRemoved: priv.revision++
                delegate: Item {
                    id: seg
                    required property int index
                    readonly property var info: control.segments[seg.index] ?? ({})
                    readonly property bool last: seg.index === control.count - 1
                    readonly property bool keyFocus: control.visualFocus && priv.focused === seg.index

                    visible: priv.shown(seg.index)
                    width: visible ? seg.implicitWidth + (moreSlot.active ? priv.moreWidth : 0) : 0
                    height: row.height
                    implicitWidth: Math.min(Math.round(Kirigami.Units.gridUnit * 16), button.implicitWidth) + (seg.last ? 0 : priv.chevronWidth)
                    onImplicitWidthChanged: priv.revision++

                    T.AbstractButton {
                        id: button
                        objectName: "segmentButton"
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, seg.implicitWidth - (seg.last ? 0 : priv.chevronWidth))
                        height: Math.round(Kirigami.Units.gridUnit * 1.6)
                        leftPadding: TelamonStyle.spacingLarge
                        rightPadding: TelamonStyle.spacingLarge
                        hoverEnabled: true
                        focusPolicy: Qt.NoFocus
                        text: seg.info.title ?? ""
                        Accessible.role: Accessible.Button
                        Accessible.focused: seg.keyFocus
                        Accessible.name: button.text
                        //: Spoken hint on the last segment of a path bar: it is where you are now
                        Accessible.description: seg.last ? qsTr("Current location") : ""
                        implicitWidth: Math.min(Math.round(Kirigami.Units.gridUnit * 16), label.implicitWidth + leftPadding + rightPadding)
                        onClicked: {
                            priv.current = seg.index;
                            control.activated(seg.index);
                        }
                        background: Item {
                            Rectangle {
                                id: pill
                                anchors.fill: parent
                                radius: TelamonStyle.radiusSmall
                                color: button.down ? TelamonStyle.pressed : button.hovered ? TelamonStyle.hover : "transparent"
                                Behavior on color {
                                    ColorAnimation {
                                        duration: TelamonStyle.durationShort
                                    }
                                }
                            }
                            TelamonFocusRing {
                                radius: pill.radius + gap
                                shown: seg.keyFocus
                            }
                        }
                        contentItem: RowLayout {
                            id: label
                            spacing: TelamonStyle.spacingSmall
                            Loader {
                                active: (seg.info.symbol ?? 0) !== 0
                                visible: active
                                sourceComponent: Symbol {
                                    icon: seg.info.symbol ?? 0
                                    size: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                                    color: seg.last ? TelamonStyle.text : TelamonStyle.textMuted
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: button.text
                                font: seg.last ? priv.strong : priv.regular
                                color: seg.last ? TelamonStyle.text : TelamonStyle.textMuted
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                            }
                        }
                    }
                    // Anchored, not placed by x, so it follows the button when mirrored.
                    Symbol {
                        objectName: "segmentChevron"
                        visible: !seg.last
                        anchors.left: button.right
                        anchors.leftMargin: Math.round((priv.chevronWidth - width) / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        icon: control.mirrored ? Symbols.ChevronLeft : Symbols.ChevronRight
                        size: Kirigami.Units.iconSizes.smallMedium
                        color: TelamonStyle.textMuted
                    }
                    // The "…" button, after the first segment.
                    Loader {
                        id: moreSlot
                        active: seg.index === 0 && priv.collapsed
                        anchors.left: parent.left
                        anchors.leftMargin: seg.implicitWidth
                        anchors.verticalCenter: parent.verticalCenter
                        sourceComponent: Item {
                            width: priv.moreWidth
                            height: Math.round(Kirigami.Units.gridUnit * 1.6)
                            Component.onCompleted: priv.moreItem = more
                            T.AbstractButton {
                                id: more
                                anchors.left: parent.left
                                width: priv.moreWidth - priv.chevronWidth
                                height: parent.height
                                hoverEnabled: true
                                focusPolicy: Qt.NoFocus
                                Accessible.role: Accessible.Button
                                Accessible.focused: control.visualFocus && priv.focused === -1
                                //: Spoken name of the "…" button of a path bar, which opens the folders that do not fit
                                Accessible.name: control.hiddenText
                                onClicked: {
                                    priv.current = -1;
                                    priv.press(-1);
                                }
                                background: Item {
                                    Rectangle {
                                        id: morePill
                                        anchors.fill: parent
                                        radius: TelamonStyle.radiusSmall
                                        color: more.down || moreMenu.visible ? TelamonStyle.pressed : more.hovered ? TelamonStyle.hover : "transparent"
                                    }
                                    TelamonFocusRing {
                                        radius: morePill.radius + gap
                                        shown: control.visualFocus && priv.focused === -1
                                    }
                                }
                                contentItem: Item {
                                    Symbol {
                                        anchors.centerIn: parent
                                        icon: Symbols.MoreHoriz
                                        size: Kirigami.Units.iconSizes.smallMedium
                                        color: TelamonStyle.textMuted
                                    }
                                }
                            }
                            Symbol {
                                anchors.left: more.right
                                anchors.leftMargin: Math.round((priv.chevronWidth - width) / 2)
                                anchors.verticalCenter: parent.verticalCenter
                                icon: control.mirrored ? Symbols.ChevronLeft : Symbols.ChevronRight
                                size: Kirigami.Units.iconSizes.smallMedium
                                color: TelamonStyle.textMuted
                            }
                        }
                    }
                }
            }
        }
    }

    ContextMenu {
        id: moreMenu
        title: control.hiddenText
        Instantiator {
            model: Math.max(0, priv.firstTail - 1)
            delegate: ContextMenuItem {
                required property int index
                text: control.segments[index + 1]?.title ?? ""
                symbol: control.segments[index + 1]?.symbol ?? 0
                onTriggered: control.activated(index + 1)
            }
            onObjectAdded: (index, object) => moreMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => moreMenu.removeItem(object)
        }
    }
}
