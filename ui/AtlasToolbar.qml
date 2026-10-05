pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T

// A horizontal bar of actions. The actions that don't fit move, in order, into
// a menu behind a "more" button, and come back as the bar widens.
//
// The model is `actions`: a list of AtlasAction or Qt Action. Each one is a
// ToolbarButton that follows it (symbol, tooltip, shortcut, checkable,
// enabled), and the same action fills the overflow menu. A change of
// `AtlasAction.section` between two neighbours draws a divider between them
// (and a separator in the menu). There are no other children to place: put a
// title or a search field in `leading`, and anything for the far end in
// `trailing`; both stay visible. Without room the bar shows only those and the
// "more" button.
//
//   AtlasToolbar {
//       width: parent.width
//       actions: [saveAction, openAction, boldAction, italicAction]
//       leading: QQC2.Label { text: qsTr("Notes") }
//   }
//
// The buttons are reachable with Tab (`focusable`). The fit is a binding of
// the width and the slots' implicit widths: it is worked out once per change
// of either, from the size of one button, and never from the laid-out result.
Item {
    id: root

    // AtlasAction or Qt Action items, in order.
    property list<T.Action> actions
    // Items before the buttons (a title) and after the "more" button (a search
    // field). Assign one item or a list.
    property alias leading: leadingRow.data
    property alias trailing: trailingRow.data
    // True (the default) draws nothing behind the buttons; false a surface with
    // rounded corners.
    property bool flat: true
    // Lets Tab reach the buttons; false keeps the keyboard focus where it is.
    property bool focusable: true
    // The name of the bar for screen readers.
    property string accessibleName: qsTr("Toolbar")

    // How many actions show as buttons; the rest are in the menu.
    readonly property int visibleCount: _fitCount
    // Number of actions in the "more" menu.
    readonly property int overflowCount: actions.length - _fitCount
    // The "more" menu, to open it from code.
    readonly property ContextMenu moreMenu: menu

    readonly property real _pad: AtlasStyle.spacingSmall
    readonly property real _gap: AtlasStyle.spacingSmall
    readonly property real _buttonWidth: probe.implicitWidth
    readonly property real _dividerWidth: 1 + _gap * 2
    readonly property real _leadingWidth: leadingRow.children.length > 0 ? leadingRow.implicitWidth : 0
    readonly property real _trailingWidth: trailingRow.children.length > 0 ? trailingRow.implicitWidth : 0
    // The width of the first n actions as buttons, with the dividers between.
    function _widthOf(n) {
        let w = 0;
        for (let i = 0; i < n; ++i) {
            w += _buttonWidth + (i > 0 ? _gap + (_dividerBefore(i) ? _dividerWidth : 0) : 0);
        }
        return w;
    }
    function _sectionOf(i) {
        const s = actions[i].section;
        return s === undefined ? "" : String(s);
    }
    function _dividerBefore(i) {
        return i > 0 && _sectionOf(i) !== _sectionOf(i - 1);
    }
    // The count of buttons that fit, and the room they have.
    readonly property int _fitCount: {
        const n = root.actions.length;
        const room = root.width - _pad * 2 - (_leadingWidth > 0 ? _leadingWidth + _gap : 0) - (_trailingWidth > 0 ? _trailingWidth + _gap : 0) - _gap;
        if (_widthOf(n) <= room) {
            return n;
        }
        const more = _buttonWidth + _gap;
        let count = n;
        while (count > 0 && _widthOf(count) + more > room) {
            --count;
        }
        return count;
    }

    implicitWidth: _pad * 2 + (_leadingWidth > 0 ? _leadingWidth + _gap : 0) + _widthOf(actions.length) + _gap + (_trailingWidth > 0 ? _trailingWidth + _gap : 0)
    implicitHeight: probe.implicitHeight + _pad * 2

    Accessible.role: Accessible.ToolBar
    Accessible.name: root.accessibleName

    // The menu is rebuilt when the actions or the overflow change.
    onActionsChanged: _rebuildMenu()
    Component.onCompleted: _rebuildMenu()

    property bool _rebuildPending: false
    function _rebuildMenu() {
        // Not while the menu is open (its rows would vanish under the pointer);
        // it is rebuilt when it closes.
        if (menu.visible) {
            _rebuildPending = true;
            return;
        }
        _rebuildPending = false;
        while (menu.count > 0) {
            const item = menu.takeItem(0);
            if (item) {
                item.destroy();
            }
        }
        for (let i = _fitCount; i < actions.length; ++i) {
            if (i > _fitCount && _dividerBefore(i)) {
                menu.addItem(separatorComponent.createObject(null));
            }
            menu.addItem(itemComponent.createObject(null, {
                action: actions[i]
            }));
        }
    }
    on_FitCountChanged: _rebuildMenu()

    // Measures one button; never shown.
    ToolbarButton {
        id: probe
        visible: false
        symbol: Symbols.MoreHoriz
    }
    Component {
        id: itemComponent
        ContextMenuItem {}
    }
    Component {
        id: separatorComponent
        ContextMenuSeparator {}
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.flat
        radius: AtlasStyle.radius
        color: AtlasStyle.chromeBackground
        border.width: 1
        border.color: AtlasStyle.separator
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: root._pad
        spacing: root._gap

        RowLayout {
            id: leadingRow
            visible: children.length > 0
            spacing: root._gap
        }

        Row {
            spacing: root._gap
            Repeater {
                model: root._fitCount
                delegate: Row {
                    id: entry
                    required property int index
                    readonly property var action: root.actions[index]
                    spacing: root._gap
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Rectangle {
                        visible: root._dividerBefore(entry.index)
                        width: 1
                        height: Math.round(probe.implicitHeight * 0.6)
                        anchors.verticalCenter: parent.verticalCenter
                        color: AtlasStyle.separator
                    }
                    ToolbarButton {
                        action: entry.action
                        focusable: root.focusable
                    }
                }
            }
        }

        ToolbarButton {
            id: moreButton
            visible: root.overflowCount > 0
            symbol: Symbols.MoreHoriz
            text: qsTr("More")
            focusable: root.focusable
            checked: menu.visible
            onClicked: menu.popup(moreButton, 0, moreButton.height + root._gap)
            ContextMenu {
                id: menu
                onClosed: {
                    if (root._rebuildPending) {
                        root._rebuildMenu();
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        RowLayout {
            id: trailingRow
            visible: children.length > 0
            spacing: root._gap
        }
    }
}
