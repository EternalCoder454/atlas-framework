pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T

// A bar of actions, horizontal or vertical. The actions that don't fit move,
// in order, into a menu behind a "more" button, and come back as the bar
// grows; or, with `overflow: AtlasToolbar.Scroll`, they scroll out of view one
// button at a time.
//
// The model is `actions`: a list of AtlasAction or Qt Action. Each one is a
// ToolbarButton that follows it (symbol, tooltip, shortcut, checkable,
// enabled), and the same action fills the overflow menu. A change of
// `AtlasAction.section` between two neighbours draws a divider between them
// (and a separator in the menu). An action with a `menu` or a `popover` is a
// button that opens it; in the overflow menu a `menu` is a submenu. There are
// no other children to place: put a title or a search field in `leading`, and
// anything for the far end in `trailing`; both stay visible. Without room the
// bar shows only those and the "more" button.
//
//   AtlasToolbar {
//       width: parent.width
//       actions: [saveAction, openAction, boldAction, italicAction]
//       leading: QQC2.Label { text: qsTr("Notes") }
//   }
//
// The buttons are reachable with Tab (`focusable`). The fit is a binding of
// the extent and the slots' implicit sizes: it is worked out once per change
// of either, from the size of one button, and never from the laid-out result.
Item {
    id: root

    enum Overflow {
        Menu = 0,
        Scroll = 1
    }

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
    // With `focusable`, false makes a click not take the focus.
    property bool focusOnClick: true
    // The name of the bar for screen readers.
    property string accessibleName: qsTr("Toolbar")
    // Qt.Horizontal or Qt.Vertical: the direction of the strip.
    property int orientation: Qt.Horizontal
    // What happens to buttons that do not fit: Menu or Scroll.
    property int overflow: AtlasToolbar.Menu

    // How many actions show as buttons (in Scroll mode, in view); the rest are
    // in the menu, or scrolled out of view.
    readonly property int visibleCount: _scroll ? _viewCount : _fitCount
    // Number of actions in the "more" menu, or out of view.
    readonly property int overflowCount: actions.length - visibleCount
    // The "more" menu, to open it from code.
    readonly property ContextMenu moreMenu: menu
    // True while Scroll mode has buttons out of view.
    readonly property bool scrolls: _scrolling

    readonly property bool _vertical: orientation === Qt.Vertical
    readonly property bool _scroll: overflow === AtlasToolbar.Scroll
    readonly property real _pad: AtlasStyle.spacingSmall
    readonly property real _gap: AtlasStyle.spacingSmall
    readonly property real _buttonLen: _vertical ? probe.implicitHeight : probe.implicitWidth
    readonly property real _dividerLen: 1 + _gap * 2
    readonly property real _leadingLen: leadingRow.children.length > 0 ? (_vertical ? leadingRow.implicitHeight : leadingRow.implicitWidth) : 0
    readonly property real _trailingLen: trailingRow.children.length > 0 ? (_vertical ? trailingRow.implicitHeight : trailingRow.implicitWidth) : 0
    readonly property int _align: _vertical ? (Qt.AlignHCenter | Qt.AlignTop) : (Qt.AlignVCenter | Qt.AlignLeft)
    // Buttons that hold a menu or popover that is open (the bar is "active").
    property int _openCount: 0
    readonly property bool _menuOpen: _openCount > 0 || menu.visible || (_morePopover !== null && _morePopover.visible)
    property var _morePopover: null

    // The length of the first n actions as buttons, with the dividers between.
    function _lenOf(n) {
        let w = 0;
        for (let i = 0; i < n; ++i) {
            w += _buttonLen + (i > 0 ? _gap + (_dividerBefore(i) ? _dividerLen : 0) : 0);
        }
        return w;
    }
    function _sectionOf(i) {
        const s = actions[i].section;
        return s === undefined ? "" : String(s);
    }
    // A scrolling strip has no dividers: a step is one button.
    function _dividerBefore(i) {
        return !_scroll && i > 0 && _sectionOf(i) !== _sectionOf(i - 1);
    }
    readonly property real _extent: _vertical ? height : width
    // The room for the buttons along the strip.
    readonly property real _room: _extent - _pad * 2 - (_leadingLen > 0 ? _leadingLen + _gap : 0) - (_trailingLen > 0 ? _trailingLen + _gap : 0) - _gap
    // Menu mode: the count of buttons that fit, and the room they have.
    readonly property int _fitCount: {
        const n = root.actions.length;
        if (_scroll || _lenOf(n) <= _room) {
            return n;
        }
        const more = _buttonLen + _gap;
        let count = n;
        while (count > 0 && _lenOf(count) + more > _room) {
            --count;
        }
        return count;
    }
    // Scroll mode: whole buttons in view, with a chevron's room kept at each end.
    readonly property bool _scrolling: _scroll && actions.length > 0 && _lenOf(actions.length) > _room
    readonly property int _viewCount: {
        const n = root.actions.length;
        if (!_scrolling) {
            return n;
        }
        const avail = _room - 2 * (_buttonLen + _gap);
        return Math.max(1, Math.min(n, Math.floor((avail + _gap) / (_buttonLen + _gap))));
    }
    readonly property real _viewLen: _viewCount * _buttonLen + Math.max(0, _viewCount - 1) * _gap
    readonly property int _maxIndex: Math.max(0, actions.length - _viewCount)
    // The first button in view (Scroll mode).
    property int _index: 0
    on_MaxIndexChanged: _index = Math.min(_index, _maxIndex)
    function _step(d) {
        _index = Math.max(0, Math.min(_maxIndex, _index + d));
    }
    // Scrolls so that button i is in view (Tab follows the focus).
    function _reveal(i) {
        if (!_scrolling) {
            return;
        }
        if (i < _index) {
            _index = i;
        } else if (i >= _index + _viewCount) {
            _index = i - _viewCount + 1;
        }
    }
    property real _wheel: 0
    property double _wheelAt: 0
    // Adds a wheel movement: a pause, or the other direction, starts the sum
    // again; every 120 steps one button.
    function _wheelBy(d: real): void {
        const now = Date.now();
        if (now - root._wheelAt > 300 || (root._wheel !== 0 && (d > 0) !== (root._wheel > 0))) {
            root._wheel = 0;
        }
        root._wheelAt = now;
        root._wheel += d;
        while (root._wheel >= 120) {
            root._step(-1);
            root._wheel -= 120;
        }
        while (root._wheel <= -120) {
            root._step(1);
            root._wheel += 120;
        }
    }

    readonly property real _alongImplicit: _pad * 2 + (_leadingLen > 0 ? _leadingLen + _gap : 0) + _lenOf(actions.length) + _gap + (_trailingLen > 0 ? _trailingLen + _gap : 0)
    implicitWidth: _vertical ? probe.implicitWidth + _pad * 2 : _alongImplicit
    implicitHeight: _vertical ? _alongImplicit : probe.implicitHeight + _pad * 2

    Accessible.role: Accessible.ToolBar
    Accessible.name: root.accessibleName

    // The menu is rebuilt when the actions or the overflow change.
    onActionsChanged: _rebuildMenu()
    Component.onCompleted: _rebuildMenu()

    property bool _rebuildPending: false
    // The first action in the menu: none in Scroll mode.
    readonly property int _menuStart: _scroll ? actions.length : _fitCount
    // Watches the overflow actions, so a row changes kind when an action gains
    // or loses its menu or popover.
    property var _watchers: []
    function _rebuildMenu() {
        // Not while the menu is open: its rows would vanish under the pointer,
        // and an action that came back as a button must not have its menu in
        // two places. Close it; it is rebuilt when it has closed.
        if (menu.visible) {
            _rebuildPending = true;
            menu.close();
            return;
        }
        _rebuildPending = false;
        for (const w of _watchers) {
            w.destroy();
        }
        _watchers = [];
        while (menu.count > 0) {
            // A submenu is the app's own: take it out, never destroy it.
            if (menu.menuAt(0)) {
                menu.takeMenu(0);
                continue;
            }
            const item = menu.takeItem(0);
            if (item) {
                item.destroy();
            }
        }
        for (let i = _menuStart; i < actions.length; ++i) {
            if (i > _menuStart && _dividerBefore(i)) {
                menu.addItem(separatorComponent.createObject(null));
            }
            const a = actions[i];
            _watchers.push(watcherComponent.createObject(root, {
                target: a
            }));
            if (a.menu) {
                menu.addMenu(a.menu);
                const entry = menu.itemAt(menu.count - 1);
                if (entry) {
                    // The entry follows the action; the app's menu is not touched.
                    entry.text = Qt.binding(() => String(a.text).replace(/&(.)/g, "$1"));
                    entry.enabled = Qt.binding(() => a.enabled);
                    entry.symbol = Qt.binding(() => a.symbol === undefined ? 0 : a.symbol);
                }
            } else if (a.popover) {
                const row = popoverItemComponent.createObject(null, {
                    act: a
                });
                row.text = Qt.binding(() => String(a.text).replace(/&(.)/g, "$1"));
                row.enabled = Qt.binding(() => a.enabled);
                row.symbol = Qt.binding(() => a.symbol === undefined ? 0 : a.symbol);
                menu.addItem(row);
            } else {
                menu.addItem(itemComponent.createObject(null, {
                    action: a
                }));
            }
        }
    }
    // A popover in the menu opens from the "more" button.
    function _openPopover(p) {
        _morePopover = p;
        if (p.target !== undefined) {
            p.target = moreButton;
        }
        p.open();
    }
    on_FitCountChanged: _rebuildMenu()
    on_ScrollChanged: _rebuildMenu()

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
        id: popoverItemComponent
        ContextMenuItem {
            id: popRow
            property var act
            onTriggered: if (popRow.act.popover) root._openPopover(popRow.act.popover)
        }
    }
    Component {
        id: watcherComponent
        Connections {
            ignoreUnknownSignals: true
            function onMenuChanged() {
                root._rebuildMenu();
            }
            function onPopoverChanged() {
                root._rebuildMenu();
            }
        }
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

    GridLayout {
        anchors.fill: parent
        anchors.margins: root._pad
        columns: root._vertical ? 1 : 7
        rowSpacing: root._gap
        columnSpacing: root._gap

        GridLayout {
            id: leadingRow
            visible: children.length > 0
            columns: root._vertical ? 1 : Math.max(1, children.length)
            rowSpacing: root._gap
            columnSpacing: root._gap
            Layout.alignment: root._align
        }

        // Scroll mode: the way back, with its room kept while the strip scrolls.
        ToolbarButton {
            visible: root._scrolling
            enabled: root._index > 0
            opacity: enabled ? 1 : 0
            symbol: root._vertical ? Symbols.ExpandLess : (root.LayoutMirroring.enabled ? Symbols.ChevronRight : Symbols.ChevronLeft)
            text: qsTr("Scroll back")
            onClicked: root._step(-1)
            Layout.alignment: root._align
        }

        Item {
            id: viewport
            readonly property real _along: root._scrolling ? root._viewLen : (root._vertical ? buttons.implicitHeight : buttons.implicitWidth)
            implicitWidth: root._vertical ? buttons.implicitWidth : _along
            implicitHeight: root._vertical ? _along : buttons.implicitHeight
            clip: root._scrolling
            Layout.alignment: root._align

            Grid {
                id: buttons
                readonly property real _offset: root._index * (root._buttonLen + root._gap)
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: root._vertical ? 0 : -_offset
                anchors.topMargin: root._vertical ? -_offset : 0
                columns: root._vertical ? 1 : Math.max(1, rep.count)
                spacing: root._gap
                Behavior on anchors.leftMargin {
                    NumberAnimation {
                        duration: AtlasStyle.durationShort
                    }
                }
                Behavior on anchors.topMargin {
                    NumberAnimation {
                        duration: AtlasStyle.durationShort
                    }
                }
                Repeater {
                    id: rep
                    model: root._scroll ? root.actions.length : root._fitCount
                    delegate: Item {
                        id: entry
                        required property int index
                        readonly property var action: root.actions[index]
                        // The divider before this button, and the room it takes.
                        readonly property bool _divider: root._dividerBefore(index)
                        readonly property real _lead: _divider ? 1 + root._gap : 0
                        width: root._vertical ? Math.max(button.width, probe.implicitWidth) : _lead + button.width
                        height: root._vertical ? _lead + button.height : button.height
                        Rectangle {
                            visible: entry._divider
                            anchors.left: root._vertical ? undefined : parent.left
                            anchors.verticalCenter: root._vertical ? undefined : parent.verticalCenter
                            anchors.top: root._vertical ? parent.top : undefined
                            anchors.horizontalCenter: root._vertical ? parent.horizontalCenter : undefined
                            width: root._vertical ? Math.round(probe.implicitWidth * 0.6) : 1
                            height: root._vertical ? 1 : Math.round(probe.implicitHeight * 0.6)
                            color: AtlasStyle.separator
                        }
                        ToolbarButton {
                            id: button
                            anchors.left: parent.left
                            anchors.leftMargin: root._vertical ? 0 : entry._lead
                            anchors.top: parent.top
                            anchors.topMargin: root._vertical ? entry._lead : 0
                            action: entry.action
                            focusable: root.focusable
                            focusOnClick: root.focusOnClick
                            _beside: root._vertical
                            onActiveFocusChanged: if (activeFocus) root._reveal(entry.index)
                            // Counted once per transition, so a delegate that is made
                            // with its popup open, or whose action is swapped, stays balanced.
                            property bool _counted: false
                            function _sync(): void {
                                if (button._opened !== button._counted) {
                                    button._counted = button._opened;
                                    root._openCount = Math.max(0, root._openCount + (button._counted ? 1 : -1));
                                }
                            }
                            on_OpenedChanged: _sync()
                            Component.onCompleted: _sync()
                            Component.onDestruction: if (_counted) root._openCount = Math.max(0, root._openCount - 1)
                        }
                    }
                }
            }

            // One button per notch; partial turns of a touchpad add up.
            WheelHandler {
                enabled: root._scrolling
                onWheel: event => {
                    root._wheelBy((event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x) * (event.inverted ? -1 : 1));
                }
            }
        }

        ToolbarButton {
            visible: root._scrolling
            enabled: root._index < root._maxIndex
            opacity: enabled ? 1 : 0
            symbol: root._vertical ? Symbols.ExpandMore : (root.LayoutMirroring.enabled ? Symbols.ChevronLeft : Symbols.ChevronRight)
            text: qsTr("Scroll forward")
            onClicked: root._step(1)
            Layout.alignment: root._align
        }

        ToolbarButton {
            id: moreButton
            visible: !root._scroll && root.overflowCount > 0
            symbol: root._vertical ? Symbols.MoreVert : Symbols.MoreHoriz
            text: qsTr("More")
            focusable: root.focusable
            focusOnClick: root.focusOnClick
            _beside: root._vertical
            checked: menu.visible
            Layout.alignment: root._align
            onClicked: _popup(menu)
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
            Layout.fillWidth: !root._vertical
            Layout.fillHeight: root._vertical
        }

        GridLayout {
            id: trailingRow
            visible: children.length > 0
            columns: root._vertical ? 1 : Math.max(1, children.length)
            rowSpacing: root._gap
            columnSpacing: root._gap
            Layout.alignment: root._align
        }
    }
}
