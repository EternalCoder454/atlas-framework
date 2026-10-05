pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A titled horizontal row of cards for a store ("Editors' choice", "New
// apps"). It scrolls sideways, with a button at each end that hides when
// there is nothing more that way, and makes cards only for what is on screen
// (a horizontal ListView), so a model of thousands costs what a screenful
// does.
//
//   AtlasShelf {
//       title: qsTr("Editors' choice")
//       model: store.featured      // a list of objects, or an item model
//       onActivated: index => openPage(index)
//   }
//
// The default delegate is an AtlasAppCard that reads `name`, `summary`,
// `sizeText`, `rating`, `iconName`, `installState`, `progress` and `verified`
// from each model entry, and emits `activated(index)` when pressed. A custom
// `delegate` gets the usual `index`, `model` and `modelData` and sets its own
// width (`control.cardWidth` is the one the default card uses). The row is as
// high as the tallest card made so far.
//
// The cards are Tab stops, and the Left and Right arrows (Home, End) move
// between them and scroll the next one into view. In a right-to-left layout
// the row and its buttons are mirrored.
T.Control {
    id: control

    property string title
    property var model: null
    // The card for each entry; an AtlasAppCard by default.
    property Component delegate: defaultDelegate
    // The width of the default card.
    property real cardWidth: Kirigami.Units.gridUnit * 18
    // How many cards the model holds.
    readonly property int count: list.count

    // A default-delegate card was pressed.
    signal activated(int index)

    readonly property Component defaultDelegate: Component {
        AtlasAppCard {
            id: card
            required property int index
            required property var model
            // A list of objects arrives as `modelData`; an item model's roles
            // are read from `model`.
            readonly property var entry: card.model.modelData !== undefined ? card.model.modelData : card.model
            width: control.cardWidth
            name: String(card.entry.name ?? "")
            summary: String(card.entry.summary ?? "")
            sizeText: String(card.entry.sizeText ?? "")
            rating: Number(card.entry.rating ?? 0)
            icon.name: String(card.entry.iconName ?? "")
            installState: String(card.entry.installState ?? "install")
            progress: Number(card.entry.progress ?? -1)
            verified: card.entry.verified === true
            onClicked: control.activated(card.index)
        }
    }

    QtObject {
        id: priv
        // As high as the tallest card made so far.
        property real rowHeight: 0
        function measure() {
            let h = 0;
            for (const c of list.contentItem.children) {
                if (c.implicitHeight > h) {
                    h = c.implicitHeight;
                }
            }
            if (h > priv.rowHeight) {
                priv.rowHeight = h;
            }
        }
        // How far a button press scrolls: most of what is shown.
        readonly property real stepWidth: Math.max(control.cardWidth, list.width - control.cardWidth * 0.5)
        readonly property bool canScrollLeft: list.contentX > list.originX + 1
        readonly property bool canScrollRight: list.contentX < list.originX + list.contentWidth - list.width - 1
        // Scrolls toward the physical side: -1 left, 1 right (so mirrored
        // layouts, where "end" is on the left, need no case of their own).
        function scroll(direction) {
            const lo = list.originX;
            const hi = Math.max(lo, list.originX + list.contentWidth - list.width);
            scrollAnim.stop();
            scrollAnim.to = Math.max(lo, Math.min(hi, list.contentX + direction * priv.stepWidth));
            scrollAnim.start();
        }
        // The first Tab stop of a card's root item, or null.
        function focusTarget(root) {
            if (!root) {
                return null;
            }
            if (root.activeFocusOnTab) {
                return root;
            }
            const next = root.nextItemInFocusChain(true);
            return next && root.contains(root.mapFromItem(next, 0, 0)) && next !== root ? next : root;
        }
        function focusIndex(i) {
            if (i < 0 || i >= list.count) {
                return;
            }
            list.positionViewAtIndex(i, ListView.Contain);
            list.forceLayout();
            const target = priv.focusTarget(list.itemAtIndex(i));
            if (target) {
                target.forceActiveFocus(Qt.TabFocusReason);
            }
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 40
    implicitHeight: heading.height + list.height + AtlasStyle.spacing
    focusPolicy: Qt.NoFocus
    background: null

    Accessible.role: Accessible.Pane
    Accessible.name: control.title

    contentItem: FocusScope {
        id: scope

        Text {
            id: heading
            anchors.left: parent.left
            anchors.right: parent.right
            visible: control.title.length > 0
            height: visible ? implicitHeight : 0
            text: control.title
            font.family: AtlasStyle.fontFamily
            font.pointSize: AtlasStyle.fontSizeHeading
            font.bold: true
            color: Kirigami.Theme.textColor
            textFormat: Text.PlainText
            elide: Text.ElideRight
            horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
            Accessible.role: Accessible.Heading
        }

        ListView {
            id: list
            objectName: "list"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: heading.bottom
            anchors.topMargin: heading.visible ? AtlasStyle.spacing : 0
            height: priv.rowHeight
            orientation: ListView.Horizontal
            spacing: AtlasStyle.spacing
            clip: true
            model: control.model
            boundsBehavior: Flickable.StopAtBounds
            delegate: control.delegate
            // The row takes the height of the tallest card; cards come and
            // go as it scrolls, so measure again when the content changes.
            onContentWidthChanged: priv.measure()
            onCountChanged: priv.measure()
            onMovementEnded: priv.measure()
            Component.onCompleted: Qt.callLater(priv.measure)

            Keys.onPressed: event => {
                if (list.count === 0) {
                    return;
                }
                // Left and Right are physical; the mirrored row reads the other way.
                const toRight = event.key === Qt.Key_Right;
                let target = -1;
                switch (event.key) {
                case Qt.Key_Left:
                case Qt.Key_Right:
                    target = list.currentIndex + ((toRight !== control.mirrored) ? 1 : -1);
                    break;
                case Qt.Key_Home:
                    target = 0;
                    break;
                case Qt.Key_End:
                    target = list.count - 1;
                    break;
                default:
                    return;
                }
                priv.focusIndex(Math.max(0, Math.min(list.count - 1, target)));
                event.accepted = true;
            }
        }

        // Follows the focus: a card that takes it (Tab, an arrow) is
        // scrolled fully into view, and becomes the current one.
        Connections {
            target: scope.Window.window
            enabled: scope.activeFocus
            function onActiveFocusItemChanged() {
                let it = scope.Window.window.activeFocusItem;
                while (it && it.parent !== list.contentItem) {
                    it = it.parent;
                }
                if (!it) {
                    return;
                }
                const p = it.mapToItem(list.contentItem, 1, 1);
                const i = list.indexAt(p.x, p.y);
                if (i >= 0) {
                    list.currentIndex = i;
                    list.positionViewAtIndex(i, ListView.Contain);
                }
            }
        }

        NumberAnimation {
            id: scrollAnim
            target: list
            property: "contentX"
            duration: AtlasStyle.duration
            easing.type: Easing.OutCubic
        }

        Repeater {
            model: [-1, 1]
            delegate: T.AbstractButton {
                id: nav
                objectName: modelData < 0 ? "scrollLeft" : "scrollRight"
                required property int modelData
                // -1 is the left button, 1 the right one.
                readonly property bool available: nav.modelData < 0 ? priv.canScrollLeft : priv.canScrollRight
                // What the button means: the start or the end of the row.
                readonly property bool isStart: (nav.modelData < 0) !== control.mirrored
                x: nav.modelData < 0 ? AtlasStyle.spacing : list.width - width - AtlasStyle.spacing
                y: list.y + Math.round((list.height - height) / 2)
                width: Math.round(Kirigami.Units.gridUnit * 2)
                height: width
                visible: nav.available || opacity > 0
                opacity: nav.available ? (nav.hovered || control.hovered ? 1 : 0.8) : 0
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                Accessible.role: Accessible.Button
                //: Button that scrolls a row of cards back toward its start
                Accessible.name: nav.isStart ? qsTr("Scroll to start") : qsTr("Scroll to end")
                onClicked: priv.scroll(nav.modelData)
                Behavior on opacity {
                    NumberAnimation {
                        duration: AtlasStyle.durationShort
                    }
                }
                background: Rectangle {
                    radius: AtlasStyle.radiusPill
                    color: Qt.alpha(Kirigami.Theme.backgroundColor, nav.down ? 0.95 : 0.85) // floats over the cards, so it follows the window colour, not a token
                    border.width: 1
                    border.color: AtlasStyle.controlBorder
                }
                contentItem: Item {
                    Symbol {
                        anchors.centerIn: parent
                        icon: nav.modelData < 0 ? Symbols.ChevronLeft : Symbols.ChevronRight
                        size: Kirigami.Units.iconSizes.smallMedium
                    }
                }
            }
        }
    }
}
