pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// The merged header of a frameless Atlas window: the window menu and app
// icon, the title, the main tools and the window buttons in one 32 px row.
// Give it to an AtlasWindow as its `header`, and that window turns frameless
// (no KWin title bar; see AtlasWindow):
//
//   AtlasWindow {
//       header: AtlasHeaderBar {
//           actions: [saveAction, openAction, undoAction]
//           leading: AtlasAppMenu { menus: [...] }
//       }
//   }
//
// Left to right (KWin's own button layout, kwinrc, decides the sides; the
// AtlasOS default is the window menu on the left, minimise, maximise and
// close on the right): the window menu button, `leading`, the title, the
// `actions` in an AtlasToolbar (the ones that don't fit go behind its "more"
// button), `stretch` (a row that takes all the free width, for a TabBar),
// `trailing`, the window buttons. The title leads, left aligned; with
// `centerTitle` it is centred when the bar is wide (40 grid units), and leads
// again when it is narrower. The colours are the Header colour set, drawn over
// the window's blur at the window's own alpha, with a hairline below.
//
// Dragging the empty bar moves the window, a double click maximises or
// restores it, and a right click (or Alt+Space, or the window menu button)
// opens a menu with Minimize, Maximize or Restore, and Close: the
// compositor's own menu is out of reach of a frameless client. Buttons and
// anything else in the bar keep their clicks.
Item {
    id: root

    // The title; the window's title unless set.
    property string title: Window.window ? Window.window.title : ""
    // AtlasAction or Qt Action items for the toolbar.
    property alias actions: toolbar.actions
    // Items after the window menu button, before the title (an AtlasAppMenu),
    // and items before the window buttons (a search field).
    property alias leading: leadingRow.data
    property alias trailing: trailingRow.data
    // Items in a row that takes all the free width between the title and
    // `actions` on one side and `trailing` on the other: a child that sets
    // Layout.fillWidth (a TabBar) fills the bar. Its empty parts still drag the
    // window. With no free width the row is 0 wide and its items are hidden.
    property alias stretch: stretchRow.data
    // False leaves the title out, for a bar whose `stretch` row is the title.
    property bool showTitle: true
    // Centres the title when the bar is wide enough.
    property bool centerTitle: false
    // False leaves the window buttons out (the window has its own).
    property bool windowButtons: true
    // The icon name of the window menu button; the application's by default.
    property string iconName: Qt.application.name
    // Whether the window is active; an inactive window draws a quieter bar.
    property bool active: Window.active

    // True when the title is drawn centred.
    readonly property bool titleCentered: centerTitle && width >= Kirigami.Units.gridUnit * 40 && !root._hasStretch
    readonly property bool _hasStretch: stretchRow.children.length > 0

    // Opens the window menu below the left edge; for keyboard users.
    function openWindowMenu() {
        windowMenu.popup(root, root.LayoutMirroring.enabled ? root.width : 0, root.height);
    }

    // Test hooks: replace the call into the window system.
    property var _moveHook: null
    property var _toggleHook: null

    function _startMove() {
        if (_moveHook) {
            _moveHook();
        } else if (Window.window) {
            Window.window.startSystemMove();
        }
    }
    function _toggleMaximize() {
        if (root._kiosk) {
            return;
        }
        if (_toggleHook) {
            _toggleHook();
            return;
        }
        const w = Window.window;
        if (w) {
            if (w.visibility === Window.Maximized) {
                w.showNormal();
            } else {
                w.showMaximized();
            }
        }
    }
    function _minimize() {
        if (Window.window) {
            Window.window.showMinimized();
        }
    }
    // The window is a kiosk (AtlasWindow.kiosk): no way to close it from here.
    readonly property bool _kiosk: root._kioskOf(Window.window)
    // `w` is untyped: only an AtlasWindow has `kiosk`, and a plain Window does not.
    function _kioskOf(w: var): bool {
        return w ? w["kiosk"] === true : false;
    }
    function _close() {
        if (Window.window) {
            Window.window.close();
        }
    }

    readonly property bool _maximized: Window.window ? Window.window.visibility === Window.Maximized : false
    readonly property var _left: AtlasWindowChrome.buttonsOnLeft
    readonly property var _right: AtlasWindowChrome.buttonsOnRight
    function _windowButtonsOf(list) {
        return list.filter(name => name !== "menu");
    }

    implicitHeight: 32
    implicitWidth: Kirigami.Units.gridUnit * 30
    Kirigami.Theme.colorSet: Kirigami.Theme.Header
    Kirigami.Theme.colorGroup: root.active ? Kirigami.Theme.Active : Kirigami.Theme.Inactive
    Kirigami.Theme.inherit: false

    Accessible.role: Accessible.ToolBar
    Accessible.name: qsTr("Window header")

    Shortcut {
        sequence: "Alt+Space"
        onActivated: root.openWindowMenu()
    }

    // The bar: the Header colour at the window's alpha, a hairline below.
    Rectangle {
        anchors.fill: parent
        color: {
            return AtlasStyle.chromeBackground;
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: AtlasStyle.separator
        }
    }

    // Under everything: what no child takes moves, maximises or opens the menu.
    Item {
        id: dragArea
        anchors.fill: parent
        z: -1

        DragHandler {
            target: null
            acceptedButtons: Qt.LeftButton
            onActiveChanged: if (active) {
                root._startMove();
            }
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            // Two taps close in time and place: a double click. Judged by the
            // clock here, not by the tap count, so it needs nothing from the
            // event timestamps.
            property double _lastTime: 0
            property point _lastPoint
            onTapped: eventPoint => {
                const now = Date.now();
                const p = eventPoint.position;
                if (now - _lastTime <= Application.styleHints.mouseDoubleClickInterval && Math.abs(p.x - _lastPoint.x) <= 8 && Math.abs(p.y - _lastPoint.y) <= 8) {
                    _lastTime = 0;
                    root._toggleMaximize();
                } else {
                    _lastTime = now;
                    _lastPoint = p;
                }
            }
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: eventPoint => windowMenu.popup(dragArea, eventPoint.position.x, eventPoint.position.y)
        }
    }

    ContextMenu {
        id: windowMenu
        ContextMenuItem {
            text: qsTr("Minimize")
            onTriggered: root._minimize()
        }
        ContextMenuItem {
            visible: !root._kiosk
            text: root._maximized ? qsTr("Restore") : qsTr("Maximize")
            onTriggered: root._toggleMaximize()
        }
        ContextMenuSeparator {
            visible: !root._kiosk
        }
        ContextMenuItem {
            visible: !root._kiosk
            text: qsTr("Close")
            destructive: true
            onTriggered: root._close()
        }
    }

    Component {
        id: menuButtonComponent
        T.AbstractButton {
            id: menuButton
            implicitWidth: 32
            implicitHeight: 32
            focusPolicy: Qt.NoFocus
            hoverEnabled: true
            Accessible.role: Accessible.ButtonMenu
            Accessible.name: qsTr("Window menu")
            Accessible.onPressAction: clicked()
            onClicked: windowMenu.popup(menuButton, 0, menuButton.height)
            background: Rectangle {
                x: 3
                y: 3
                width: 26
                height: 26
                radius: 7
                color: menuButton.down ? Qt.alpha(Kirigami.Theme.highlightColor, 0.45) : menuButton.hovered ? Qt.alpha(Kirigami.Theme.highlightColor, 0.28) : "transparent"
            }
            contentItem: Item {
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    source: root.iconName.length > 0 ? root.iconName : "application-x-executable"
                    fallback: "application-x-executable"
                }
            }
        }
    }

    // The left group: the window menu button when KWin puts it left, then
    // window buttons KWin puts left, then `leading`.
    Row {
        id: leftRow
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        // At narrow widths each group gets at most half the bar, so they can't overlap.
        width: Math.min(implicitWidth, Math.max(0, (root.width - 13) / 2))
        clip: width < implicitWidth

        Loader {
            active: root._left.indexOf("menu") >= 0
            visible: active
            sourceComponent: menuButtonComponent
        }
        AtlasWindowButtons {
            readonly property var _names: root._windowButtonsOf(root._left)
            visible: root.windowButtons && _names.length > 0
            buttons: _names
            active: root.active
        }
        Row {
            id: leadingRow
            spacing: AtlasStyle.spacingSmall
        }
    }

    // The right group: `trailing`, then the window buttons KWin puts right.
    Row {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0, (root.width - 13) / 2))
        clip: width < implicitWidth
        spacing: 4

        Row {
            id: trailingRow
            spacing: AtlasStyle.spacingSmall
        }
        AtlasWindowButtons {
            readonly property var _names: root._windowButtonsOf(root._right)
            visible: root.windowButtons && _names.length > 0
            buttons: _names
            active: root.active
        }
        Loader {
            active: root._right.indexOf("menu") >= 0
            visible: active
            sourceComponent: menuButtonComponent
        }
    }

    // The title: leading after the left group, or centred when there is room.
    // Placed with anchors (not x), so it mirrors under LayoutMirroring.
    QQC2.Label {
        id: title
        readonly property real _free: Math.max(0, root.width - leftRow.width - rightRow.width - AtlasStyle.spacing * 2)
        // With no actions the title may take all the free width; otherwise 40% of it.
        readonly property real _maxWidth: root.titleCentered ? Math.max(0, root.width - 2 * Math.max(leftRow.width, rightRow.width) - AtlasStyle.spacing * 2) : (root.actions.length > 0 || root._hasStretch ? _free * 0.4 : _free)
        anchors.left: root.titleCentered ? undefined : leftRow.right
        anchors.leftMargin: root.showTitle ? AtlasStyle.spacing : 0
        anchors.horizontalCenter: root.titleCentered ? parent.horizontalCenter : undefined
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showTitle
        width: root.showTitle ? Math.max(0, Math.min(implicitWidth, _maxWidth)) : 0
        text: root.title
        elide: Text.ElideRight
        font.pointSize: AtlasStyle.fontSizeWindowTitle
        font.weight: AtlasStyle.fontWeightWindowTitle
        font.family: AtlasStyle.fontFamily
        color: AtlasStyle.text
        Accessible.ignored: true
    }

    // The tools fill what the title and the groups leave.
    AtlasToolbar {
        id: toolbar
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: root.titleCentered ? leftRow.right : title.right
        anchors.leftMargin: AtlasStyle.spacingSmall
        // With a stretch row the tools take only what they need.
        readonly property real _toolsRoom: root.titleCentered ? Math.max(0, (root.width - title.width) / 2 - leftRow.width - 4 - 2 * AtlasStyle.spacingSmall) : Math.max(0, root.width - leftRow.width - 4 - (root.showTitle ? AtlasStyle.spacing : 0) - title.width - rightRow.width - 9 - 3 * AtlasStyle.spacingSmall)
        width: root._hasStretch ? Math.min(implicitWidth, _toolsRoom) : _toolsRoom
        visible: actions.length > 0
        accessibleName: qsTr("Main tools")
    }

    // The stretch row: all the width the title, the tools and the groups leave.
    RowLayout {
        id: stretchRow
        anchors.left: toolbar.visible ? toolbar.right : title.right
        anchors.leftMargin: AtlasStyle.spacingSmall
        anchors.right: rightRow.left
        anchors.rightMargin: AtlasStyle.spacingSmall
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        // Hairline below: the row stops above it.
        anchors.bottomMargin: 1
        spacing: AtlasStyle.spacingSmall
        // No free width: nothing shows, nothing overlaps.
        visible: children.length > 0 && width >= 1
        clip: true
    }

    // Where the window's top resize handle must stop so it does not cover the
    // window buttons: the free span between the two groups, from the left edge.
    readonly property real _freeStart: root.LayoutMirroring.enabled ? rightRow.width + 9 : leftRow.width + 4
    readonly property real _freeEnd: root.LayoutMirroring.enabled ? leftRow.width + 4 : rightRow.width + 9
    // The groups' margins from the window's left and right edges.
    readonly property real _startMargin: root.LayoutMirroring.enabled ? 9 : 4
    readonly property real _endMargin: root.LayoutMirroring.enabled ? 4 : 9
}
