pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A grid of files or apps: an icon over a name, the current one in a rounded
// pill. It scrolls on its own and makes cells only for what is on screen, so
// a folder of ten thousand files costs what a screenful does.
//
//   AtlasIconGrid {
//       model: files                  // a QAbstractItemModel, or a JS array
//       textRole: "name"
//       iconRole: "icon"              // an icon name or an image url
//       symbolRole: "symbol"          // or a Symbols.<Name> value, if no icon
//       onActivated: index => open(index)
//       onContextMenuRequested: (index, x, y) => menu.popup(...)
//   }
//
// Each role is optional and names a role of the model (or a key of an
// array's objects); an array of plain strings shows the strings as names.
// A cell with neither an icon nor a symbol shows a generic file symbol.
// Click selects, double click or Enter activates, the arrow keys, Home, End
// and Page Up/Down move, and the Menu key or a right click asks for a
// context menu (`x` and `y` are in the grid, for ContextMenu.popup). Name
// the grid for screen readers with Accessible.name ("Files").
T.Control {
    id: control

    property var model
    property string textRole: "text"
    property string iconRole
    property string symbolRole
    property alias currentIndex: grid.currentIndex
    // The icon's side; cells grow with it.
    property real iconSize: Math.round(Kirigami.Units.gridUnit * 3.4)
    // Shown in the middle when there are no items ("This Folder Is Empty").
    property string placeholderText
    readonly property alias count: grid.count

    signal activated(int index)
    signal contextMenuRequested(int index, real x, real y)

    QtObject {
        id: priv
        readonly property real minCell: Math.round(control.iconSize + Kirigami.Units.gridUnit * 3.6)
        readonly property int columns: Math.max(1, Math.floor(grid.width / priv.minCell))
        readonly property real cellW: Math.floor(grid.width / priv.columns)
        readonly property real cellH: Math.round(control.iconSize + Kirigami.Units.gridUnit * 3.2)

        function move(to) {
            if (grid.count === 0) {
                return;
            }
            grid.currentIndex = Math.max(0, Math.min(grid.count - 1, to));
            grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
        }
        function menuAtCurrent() {
            const item = grid.itemAtIndex(grid.currentIndex);
            if (!item) {
                return;
            }
            const p = item.mapToItem(control, item.width / 2, item.height / 2);
            control.contextMenuRequested(grid.currentIndex, p.x, p.y);
        }
        // `role` of a delegate's model, or the model itself for a plain list
        // of strings.
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

    Keys.onPressed: event => {
        const page = Math.max(1, Math.floor(grid.height / priv.cellH) - 1) * priv.columns;
        const dir = control.mirrored ? -1 : 1;
        const at = Math.max(0, grid.currentIndex);
        switch (event.key) {
        case Qt.Key_Left:
            priv.move(at - dir);
            break;
        case Qt.Key_Right:
            priv.move(at + dir);
            break;
        case Qt.Key_Up:
            priv.move(at - priv.columns);
            break;
        case Qt.Key_Down:
            priv.move(at + priv.columns);
            break;
        case Qt.Key_PageUp:
            priv.move(at - page);
            break;
        case Qt.Key_PageDown:
            priv.move(at + page);
            break;
        case Qt.Key_Home:
            priv.move(0);
            break;
        case Qt.Key_End:
            priv.move(grid.count - 1);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (!event.isAutoRepeat && grid.currentIndex >= 0 && grid.currentIndex < grid.count) {
                control.activated(grid.currentIndex);
            }
            break;
        case Qt.Key_Menu:
            if (grid.currentIndex >= 0 && grid.currentIndex < grid.count) {
                priv.menuAtCurrent();
            }
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    background: null

    contentItem: Item {
        GridView {
            id: grid
            anchors.fill: parent
            model: control.model
            cellWidth: priv.cellW
            cellHeight: priv.cellH
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false
            activeFocusOnTab: false
            currentIndex: 0
            reuseItems: true
            cacheBuffer: 0
            highlightFollowsCurrentItem: false

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
                id: cell
                required property int index
                required property var model
                readonly property bool current: GridView.isCurrentItem
                readonly property string title: {
                    const t = priv.pick(cell.model, control.textRole);
                    return t !== undefined ? String(t) : typeof cell.model.modelData === "string" ? cell.model.modelData : "";
                }
                readonly property string iconName: String(priv.pick(cell.model, control.iconRole) ?? "")
                readonly property int symbolValue: Number(priv.pick(cell.model, control.symbolRole) ?? 0)

                width: grid.cellWidth
                height: grid.cellHeight
                Accessible.role: Accessible.ListItem
                Accessible.name: cell.title
                Accessible.selected: cell.current
                Accessible.focusable: true
                Accessible.onPressAction: control.activated(cell.index)

                Rectangle {
                    id: pill
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    radius: 12
                    color: cell.current ? Qt.alpha(Kirigami.Theme.highlightColor, control.activeFocus ? 0.22 : 0.14) : Qt.alpha(Kirigami.Theme.textColor, hover.hovered ? 0.06 : 0)
                    AtlasFocusRing {
                        radius: pill.radius + gap
                        shown: cell.current && control.visualFocus
                    }
                }

                Item {
                    id: iconBox
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Kirigami.Units.largeSpacing
                    width: control.iconSize
                    height: control.iconSize
                    Kirigami.Icon {
                        anchors.fill: parent
                        visible: cell.iconName.length > 0
                        source: cell.iconName
                        isMask: false
                    }
                    // Made only for cells that have no icon.
                    Loader {
                        anchors.centerIn: parent
                        active: cell.iconName.length === 0
                        sourceComponent: Symbol {
                            icon: cell.symbolValue !== 0 ? cell.symbolValue : Symbols.Description
                            size: Math.round(control.iconSize * 0.75)
                            color: Kirigami.Theme.highlightColor
                        }
                    }
                }
                Text {
                    anchors.top: iconBox.bottom
                    anchors.topMargin: Kirigami.Units.smallSpacing
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    text: cell.title
                    font: Kirigami.Theme.defaultFont
                    color: Kirigami.Theme.textColor
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                HoverHandler {
                    id: hover
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: {
                        control.forceActiveFocus(Qt.MouseFocusReason);
                        grid.currentIndex = cell.index;
                    }
                    onDoubleTapped: control.activated(cell.index)
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: point => {
                        control.forceActiveFocus(Qt.MouseFocusReason);
                        grid.currentIndex = cell.index;
                        const p = cell.mapToItem(control, point.position.x, point.position.y);
                        control.contextMenuRequested(cell.index, p.x, p.y);
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            visible: grid.count === 0 && control.placeholderText.length > 0
            Symbol {
                anchors.horizontalCenter: parent.horizontalCenter
                icon: Symbols.FolderOpen
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
