pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// The results list of a launcher: rows grouped under section headings, each
// with an icon (or symbol), a title, a subtitle and a shortcut hint. It
// scrolls on its own and makes rows only for what is on screen. The search
// field keeps the keyboard focus; it hands the list the keys it doesn't use:
//
//   SearchField { id: field; Keys.onPressed: event => results.handleKey(event) }
//   AtlasSearchResults {
//       id: results
//       model: hits                    // a QAbstractItemModel, or a JS array
//       textRole: "title"
//       subtitleRole: "subtitle"
//       iconRole: "icon"               // an icon name or an image url
//       symbolRole: "symbol"           // or Symbols.<Name>, if no icon
//       sectionRole: "kind"            // rows with the same value group
//       shortcutRole: "shortcut"       // "Ctrl+1": a hint, not a binding
//       placeholderText: qsTr("No Results")
//       onActivated: index => run(index)
//   }
//
// Every role is optional. `handleKey(event)` takes Up, Down, Page Up,
// Page Down and Enter and returns true if it used the key; or call
// `moveCurrent(delta)` and `activateCurrent()` yourself. The model must
// keep rows of one section together. The mouse moves the highlight and a
// click activates.
T.Control {
    id: control

    property var model
    property string textRole: "text"
    property string subtitleRole
    property string iconRole
    property string symbolRole
    property string sectionRole
    property string shortcutRole
    property alias currentIndex: list.currentIndex
    // Shown in the middle when there are no rows.
    property string placeholderText
    readonly property alias count: list.count

    signal activated(int index)

    // Moves the highlight by `delta` rows, staying on the first or last row.
    function moveCurrent(delta) {
        if (list.count === 0) {
            return;
        }
        list.currentIndex = Math.max(0, Math.min(list.count - 1, Math.max(0, list.currentIndex) + delta));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }
    // Emits activated() for the highlighted row, if there is one.
    function activateCurrent() {
        if (list.currentIndex >= 0 && list.currentIndex < list.count) {
            control.activated(list.currentIndex);
        }
    }
    // Lets a search field pass on its keys: true if the key was used.
    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Up:
            control.moveCurrent(-1);
            break;
        case Qt.Key_Down:
            control.moveCurrent(1);
            break;
        case Qt.Key_PageUp:
            control.moveCurrent(-priv.page);
            break;
        case Qt.Key_PageDown:
            control.moveCurrent(priv.page);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (event.isAutoRepeat) {
                break;
            }
            control.activateCurrent();
            break;
        default:
            return false;
        }
        event.accepted = true;
        return true;
    }

    QtObject {
        id: priv
        // The small font in bold; `font.bold` cannot be set beside `font:`.
        readonly property font strong: {
            const f = Kirigami.Theme.smallFont;
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
        readonly property real rowHeight: Math.round(Kirigami.Units.gridUnit * 2.9)
        readonly property real headerHeight: Math.round(Kirigami.Units.gridUnit * 1.8)
        readonly property int page: Math.max(1, Math.floor(list.height / priv.rowHeight) - 1)
        function pick(model, role) {
            if (role.length > 0) {
                return model[role] ?? model.modelData?.[role];
            }
            return undefined;
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: Kirigami.Units.gridUnit * 20
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.List
    Accessible.focusable: true

    Keys.onPressed: event => control.handleKey(event)

    background: null

    contentItem: Item {
        ListView {
            id: list
            anchors.fill: parent
            model: control.model
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false
            activeFocusOnTab: false
            currentIndex: 0
            reuseItems: true
            cacheBuffer: 0
            highlightMoveDuration: Kirigami.Units.shortDuration
            highlightMoveVelocity: -1
            highlightResizeDuration: 0

            section.property: control.sectionRole
            section.criteria: ViewSection.FullString
            section.delegate: Item {
                required property string section
                width: ListView.view.width
                height: priv.headerHeight
                Accessible.role: Accessible.StaticText
                Accessible.name: section
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Kirigami.Units.largeSpacing * 2
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Kirigami.Units.smallSpacing
                    text: parent.section
                    font: priv.strong
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                    textFormat: Text.PlainText
                }
            }

            highlight: Item {
                z: 0
                Rectangle {
                    id: pill
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    radius: 10
                    color: Qt.alpha(Kirigami.Theme.highlightColor, 0.2)
                    AtlasFocusRing {
                        radius: pill.radius + gap
                        shown: control.visualFocus
                    }
                }
            }

            T.ScrollBar.vertical: T.ScrollBar {
                id: bar
                policy: T.ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: Math.round(Kirigami.Units.smallSpacing * 1.5)
                    radius: width / 2
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.3)
                    opacity: bar.active ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Kirigami.Units.shortDuration
                        }
                    }
                }
                background: null
            }

            delegate: Item {
                id: row
                required property int index
                required property var model
                readonly property bool current: ListView.isCurrentItem
                readonly property string title: {
                    const t = priv.pick(row.model, control.textRole);
                    return t !== undefined ? String(t) : typeof row.model.modelData === "string" ? row.model.modelData : "";
                }
                readonly property string subtitle: String(priv.pick(row.model, control.subtitleRole) ?? "")
                readonly property string iconName: String(priv.pick(row.model, control.iconRole) ?? "")
                readonly property int symbolValue: Number(priv.pick(row.model, control.symbolRole) ?? 0)
                readonly property string shortcut: String(priv.pick(row.model, control.shortcutRole) ?? "")

                width: ListView.view.width
                height: priv.rowHeight
                Accessible.role: Accessible.ListItem
                Accessible.name: row.title
                Accessible.description: row.subtitle
                Accessible.selected: row.current
                Accessible.focusable: true
                Accessible.onPressAction: control.activated(row.index)

                Item {
                    id: iconBox
                    anchors.left: parent.left
                    anchors.leftMargin: Kirigami.Units.largeSpacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.iconSizes.medium
                    height: width
                    Kirigami.Icon {
                        anchors.fill: parent
                        visible: row.iconName.length > 0
                        source: row.iconName
                        isMask: false
                    }
                    // Made only for rows that have no icon.
                    Loader {
                        anchors.centerIn: parent
                        active: row.iconName.length === 0 && row.symbolValue !== 0
                        sourceComponent: Symbol {
                            icon: row.symbolValue
                            size: Math.round(iconBox.width * 0.8)
                            color: Kirigami.Theme.highlightColor
                        }
                    }
                }
                Column {
                    anchors.left: iconBox.right
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.right: hint.visible ? hint.left : parent.right
                    anchors.rightMargin: Kirigami.Units.largeSpacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width
                        text: row.title
                        font: Kirigami.Theme.defaultFont
                        color: Kirigami.Theme.textColor
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: row.subtitle.length > 0
                        width: parent.width
                        text: row.subtitle
                        font: Kirigami.Theme.smallFont
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                }
                Text {
                    id: hint
                    visible: row.shortcut.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: Kirigami.Units.largeSpacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.shortcut
                    font: Kirigami.Theme.smallFont
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                    textFormat: Text.PlainText
                }

                HoverHandler {
                    // Only a moving pointer takes the highlight, so a list
                    // scrolling under a still pointer doesn't.
                    onPointChanged: {
                        if (hovered && list.currentIndex !== row.index) {
                            list.currentIndex = row.index;
                        }
                    }
                }
                TapHandler {
                    onTapped: {
                        list.currentIndex = row.index;
                        control.activated(row.index);
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            visible: list.count === 0 && control.placeholderText.length > 0
            Symbol {
                anchors.horizontalCenter: parent.horizontalCenter
                icon: Symbols.SearchOff
                size: Kirigami.Units.iconSizes.large
                color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
            }
            Text {
                text: control.placeholderText
                font: Kirigami.Theme.defaultFont
                color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                textFormat: Text.PlainText
            }
        }
    }
}
