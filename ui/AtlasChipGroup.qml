import QtQuick
import QtQuick.Controls as QQC2

// A wrapping flow of AtlasChips. `spacing` defaults to AtlasStyle.spacing;
// `exclusive` makes the checkable chips one-of (like radio buttons).
//
//   AtlasChipGroup {
//       width: parent.width
//       exclusive: true
//       AtlasChip { text: qsTr("All"); checkable: true; checked: true }
//       AtlasChip { text: qsTr("Unread"); checkable: true }
//   }
//
// One Tab stop: Tab reaches one chip, and Left/Right (mirrored in right-to-left
// layouts), Up/Down, Home and End move between chips. When the focused chip is
// removed, focus moves to its neighbour. Give the group a `width`: it wraps to
// it and its height follows.
Item {
    id: control

    default property alias content: flow.data
    property real spacing: AtlasStyle.spacing
    property bool exclusive: false

    implicitWidth: flow.implicitWidth
    implicitHeight: flow.implicitHeight

    // Index of the chip that Tab reaches, and the chip that last had focus.
    property int _current: 0
    property bool _hadFocus: false

    function _chips() {
        const list = [];
        for (let i = 0; i < flow.children.length; ++i) {
            const c = flow.children[i];
            if (c && c.closable !== undefined && c.visible && c.enabled) {
                list.push(c);
            }
        }
        return list;
    }
    function _sync() {
        const chips = _chips();
        _current = Math.max(0, Math.min(chips.length - 1, _current));
        // Every chip tells the group when it is shown, hidden, enabled or
        // disabled, so the Tab stop never stays on a chip that cannot take it;
        // the ones out of the list are not Tab stops.
        for (let i = 0; i < flow.children.length; ++i) {
            const c = flow.children[i];
            if (c && c.closable !== undefined) {
                c._tabOwner = control;
                if (chips.indexOf(c) < 0) {
                    c.focusPolicy = Qt.ClickFocus;
                }
            }
        }
        for (let i = 0; i < chips.length; ++i) {
            // Only the current chip is a Tab stop; the others take focus by click or arrow.
            chips[i].focusPolicy = i === _current ? Qt.StrongFocus : Qt.ClickFocus;
        }
    }
    // Called by a chip whose `visible` or `enabled` changed.
    function _chipStateChanged() {
        Qt.callLater(_sync);
    }
    function _syncGroup() {
        group.syncButtons(_chips());
    }
    function _focusChip(i) {
        const chips = _chips();
        if (chips.length === 0) {
            return;
        }
        _current = Math.max(0, Math.min(chips.length - 1, i));
        chips[_current].forceActiveFocus(Qt.TabFocusReason);
        // After the move: Qt refuses to turn Tab off on the item that has focus.
        Qt.callLater(_sync);
    }
    function _indexOfFocused() {
        const chips = _chips();
        for (let i = 0; i < chips.length; ++i) {
            if (chips[i].activeFocus) {
                return i;
            }
        }
        return -1;
    }

    Keys.onPressed: event => {
        const i = _indexOfFocused();
        if (i < 0) {
            return;
        }
        const step = control.LayoutMirroring.enabled ? -1 : 1;
        switch (event.key) {
        case Qt.Key_Right:
        case Qt.Key_Down:
            _focusChip(i + (event.key === Qt.Key_Right ? step : 1));
            break;
        case Qt.Key_Left:
        case Qt.Key_Up:
            _focusChip(i - (event.key === Qt.Key_Left ? step : 1));
            break;
        case Qt.Key_Home:
            _focusChip(0);
            break;
        case Qt.Key_End:
            _focusChip(_chips().length - 1);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // Keeps the roving Tab stop on the chip that has focus, and gives focus
    // to a neighbour when the focused chip goes away.
    Connections {
        target: control.Window.window
        function onActiveFocusItemChanged() {
            const i = control._indexOfFocused();
            if (i >= 0) {
                control._current = i;
                control._hadFocus = true;
                Qt.callLater(control._sync);
            } else if (control._hadFocus) {
                control._hadFocus = false;
                Qt.callLater(control._restoreFocus);
            }
        }
    }
    function _restoreFocus() {
        const w = control.Window.window;
        // Nothing took the focus: the chip was removed. Another item that has
        // it is the user's choice, left alone.
        if (!w || (w.activeFocusItem && w.activeFocusItem !== w.contentItem)) {
            return;
        }
        _focusChip(_current);
    }

    Flow {
        id: flow
        width: control.width
        spacing: control.spacing
        onChildrenChanged: {
            Qt.callLater(control._sync);
            Qt.callLater(control._syncGroup);
        }
    }
    Component.onCompleted: {
        _sync();
        _syncGroup();
    }

    QQC2.ButtonGroup {
        id: group
        exclusive: control.exclusive
        function syncButtons(chips) {
            const old = [];
            for (let i = 0; i < group.buttons.length; ++i) {
                old.push(group.buttons[i]);
            }
            for (const b of old) {
                group.removeButton(b);
            }
            for (const c of chips) {
                if (c.checkable) {
                    group.addButton(c);
                }
            }
        }
    }
}
