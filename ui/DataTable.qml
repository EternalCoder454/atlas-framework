pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// A table in the Section style: a rounded card with a header that sorts and
// inset rows below it, scrolling on its own and making rows only for what is
// on screen, so a list of a thousand processes costs what twenty do.
//
// The table doesn't sort: a header click sets sortRole and sortOrder, and the
// model follows them (a Rust QAbstractItemModel that moves rows, not one that
// resets). While the pointer is over the rows `pointerInside` is true; a live
// model holds its order still then, so the row under the pointer stays put.
// Hold it while a context menu opened on a row is up, too: the pointer has
// left the rows for the menu, but the row it acts on must not move.
//
//   DataTable {
//       model: apps
//       columns: [
//           { title: qsTr("Name"), role: "name", fill: true, iconRole: "icon" },
//           { title: qsTr("CPU"), role: "cpu", width: 5, align: Qt.AlignRight,
//             heat: 100, text: v => v.toFixed(1) + "%" },
//       ]
//       onActivated: row => ...
//       onContextMenuRequested: (row, x, y) => menu.popup(...)
//       onHeaderMenuRequested: (x, y) => columnsMenu.popup(...)
//   }
//
// A column is an object with:
//   title, role       the header and the model role it shows
//   width             in grid units; or `fill: true` for the column that
//                     takes what is left (the first one, if none says so;
//                     a second `fill` is sized by its width like the rest)
//   align             Qt.AlignLeft (default) or Qt.AlignRight for figures
//   text(value, row)  formats the value; `row` is the delegate's model object
//   heat              shade the cell by value / heat (load columns, as in the
//                     Windows Task Manager); 0 or absent for none
//   iconRole          a role holding an icon name, drawn before the text
//   cell              a Component for anything else (a status dot, a switch);
//                     it gets `value`, `row` and `column` set. Rows are
//                     reused as the list scrolls, so a cell shows only what
//                     those three say and keeps no state of its own.
//   sortable          false to keep its header from sorting (default true)
//
// The header stays at the top of the table while the rows scroll under it
// (the table scrolls its own rows; only they move), wherever the table sits.
//
// Resize: `resizableColumns: true` lets the user drag the boundary between
// two columns (a double click fits the column to its widest visible cell).
// The fill column takes what the others leave, so a drag changes the column
// beside the boundary, never the table's width. `columnWidths` holds every
// column's width in pixels once the user has resized (empty: automatic, as
// before) and is writable: save it from `columnResized(column, width)` and
// restore it on start. The fill column's entry is informational only.
//
// Show and hide: `columnsMenu: true` opens a menu of checkable column titles
// on a right click of the header; `hiddenColumns` lists the hidden column
// indexes and is writable. At least one column always stays visible.
//
// Selection: `selectionMode` is DataTable.SingleSelection (the default: the
// current row is the selection), DataTable.MultiSelection (Ctrl click toggles,
// Shift click and Shift+arrows extend, Ctrl+A selects all, Space toggles the
// current row) or DataTable.NoSelection. `selectedRows` lists the selected
// row numbers, ascending. Selection is by row number: a live model that moves
// rows leaves it where it was, and a change of `model` clears it.
// selectRows(rows), selectAll() and clearSelection() set it from code.
//
// Right click (which selects the row first, unless it is already part of a
// selection) and the Menu key or Shift+F10 on the current row emit
// rowContextMenuRequested(row, pos) as well as contextMenuRequested.
//
// `density` follows AtlasStyle.density: Compact makes the rows about 75% as
// tall.
//
// Name the table for screen readers with Accessible.name ("Apps").
//
// A tree (an app and its processes) is the model's to flatten: give
// `depthRole`, `expandableRole` and `expandedRole`, and the first column
// indents and shows a chevron that emits toggleRequested(row).
FocusScope {
    id: root

    enum SelectionMode {
        SingleSelection,
        MultiSelection,
        NoSelection
    }

    property var model
    property var columns: []
    property int selectionMode: DataTable.SingleSelection
    readonly property list<int> selectedRows: {
        if (selectionMode === DataTable.SingleSelection) {
            return list.currentIndex >= 0 ? [list.currentIndex] : [];
        }
        if (selectionMode === DataTable.MultiSelection) {
            return Object.keys(_sel).map(Number).sort((a, b) => a - b);
        }
        return [];
    }
    property bool resizableColumns: false
    property list<real> columnWidths
    property bool columnsMenu: false
    property list<int> hiddenColumns
    property int density: AtlasStyle.density
    property string sortRole
    property int sortOrder: Qt.DescendingOrder
    property alias currentIndex: list.currentIndex
    property string depthRole
    property string expandableRole
    property string expandedRole
    // Shown in the middle when there are no rows ("No Apps Match").
    property string placeholderText
    readonly property bool pointerInside: hover.hovered
    readonly property real rowHeight: Math.round(Kirigami.Units.gridUnit * 1.9 * (density === AtlasStyle.Compact ? 0.75 : 1))
    readonly property alias count: list.count

    signal activated(int row)
    signal contextMenuRequested(int row, real x, real y)
    // The same request with the position as a point in the table.
    signal rowContextMenuRequested(int row, point pos)
    // The user resized a column (also while dragging); `width` is in pixels.
    signal columnResized(int column, real width)
    // A right click on the header, at x, y in the table: for a menu of
    // the columns to show.
    signal headerMenuRequested(real x, real y)
    signal deleteRequested(int row)
    signal toggleRequested(int row)

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: Kirigami.Units.gridUnit * 20
    Layout.fillWidth: true
    activeFocusOnTab: true

    Accessible.role: Accessible.Table
    Accessible.focusable: true
    // Mirror every cell and the header with the table, even when the app
    // mirrors only the table itself.
    LayoutMirroring.childrenInherit: true

    readonly property real padding: AtlasStyle.spacingSmall
    readonly property real cellPadding: AtlasStyle.spacingLarge
    readonly property real _minColumnWidth: Kirigami.Units.gridUnit * 3
    // Hidden columns as a set of indexes; the first column stays if the app
    // hides them all.
    readonly property var _hidden: {
        const set = {};
        for (const h of hiddenColumns) {
            if (h >= 0 && h < columns.length) {
                set[h] = true;
            }
        }
        if (columns.length > 0 && Object.keys(set).length >= columns.length) {
            delete set[0];
        }
        return set;
    }
    // The column that takes the space the others leave: the first visible one
    // saying `fill`, else the first visible one.
    readonly property int _fillIndex: {
        let first = -1;
        for (let i = 0; i < columns.length; ++i) {
            if (_hidden[i]) {
                continue;
            }
            if (columns[i].fill === true) {
                return i;
            }
            if (first < 0) {
                first = i;
            }
        }
        return first;
    }
    // Pixel widths, the fill column taking what the others leave. A column
    // without a width (or a second fill) gets a few grid units rather than
    // NaN; if the fixed columns don't fit, the header and rows clip.
    readonly property var widths: {
        const avail = Math.max(0, width - 2 * padding);
        const gu = Kirigami.Units.gridUnit;
        const fill = _fillIndex;
        const w = columns.map((c, i) => _hidden[i] || i === fill ? 0 : columnWidths[i] > 0 ? Math.round(Math.max(_minColumnWidth, columnWidths[i])) : Math.round((c.width ?? 4) * gu));
        const fixed = w.reduce((a, b) => a + b, 0);
        if (columns.length > 0) {
            w[fill] = Math.max(gu * 4, avail - fixed);
        }
        return w;
    }

    function sortBy(i) {
        const c = columns[i];
        if (c.sortable === false) {
            return;
        }
        if (sortRole === c.role) {
            sortOrder = sortOrder === Qt.AscendingOrder ? Qt.DescendingOrder : Qt.AscendingOrder;
        } else {
            sortRole = c.role;
            // Figures start biggest first, names A to Z.
            sortOrder = c.align === Qt.AlignRight ? Qt.DescendingOrder : Qt.AscendingOrder;
        }
    }

    // Selected rows in Multi mode, row number -> true. Replaced, never edited,
    // so bindings see the change.
    readonly property var _columnsMenu: columnsMenuLoader.item
    property var _sel: ({})
    property int _anchor: -1
    readonly property bool _multi: selectionMode === DataTable.MultiSelection

    onModelChanged: {
        _sel = ({});
        _anchor = -1;
    }

    function selectRows(rows) {
        if (!_multi) {
            if (selectionMode === DataTable.SingleSelection && rows.length > 0 && rows[0] >= 0 && rows[0] < list.count) {
                list.currentIndex = rows[0];
            }
            return;
        }
        const set = {};
        for (const r of rows) {
            if (r >= 0 && r < list.count) {
                set[r] = true;
            }
        }
        _sel = set;
        _anchor = rows.length > 0 ? rows[rows.length - 1] : -1;
    }
    function selectAll() {
        if (!_multi) {
            return;
        }
        const set = {};
        for (let i = 0; i < list.count; ++i) {
            set[i] = true;
        }
        _sel = set;
    }
    function clearSelection() {
        if (_multi) {
            _sel = ({});
        }
    }
    function _selectRange(a, b, add) {
        const set = add ? Object.assign({}, _sel) : {};
        const hi = Math.min(list.count - 1, Math.max(a, b));
        for (let i = Math.max(0, Math.min(a, b)); i <= hi; ++i) {
            set[i] = true;
        }
        _sel = set;
    }
    // A press or key moved the current row from `from` to `to`.
    function _select(from, to, shift, ctrl) {
        if (!_multi || to < 0) {
            return;
        }
        if (shift) {
            if (_anchor < 0) {
                _anchor = from >= 0 ? from : to;
            }
            _selectRange(_anchor, to, ctrl);
        } else if (ctrl) {
            const set = Object.assign({}, _sel);
            if (set[to]) {
                delete set[to];
            } else {
                set[to] = true;
            }
            _sel = set;
            _anchor = to;
        } else {
            const set = {};
            set[to] = true;
            _sel = set;
            _anchor = to;
        }
    }
    function _pruneSelection() {
        const keys = Object.keys(_sel);
        if (keys.some(k => Number(k) >= list.count)) {
            const set = {};
            keys.forEach(k => {
                if (Number(k) < list.count) {
                    set[k] = true;
                }
            });
            _sel = set;
        }
        if (_anchor >= list.count) {
            _anchor = -1;
        }
    }

    function _nextVisible(i) {
        for (let j = i + 1; j < columns.length; ++j) {
            if (!_hidden[j]) {
                return j;
            }
        }
        return -1;
    }
    // Sets a column's pixel width, within what the fill column can give up.
    function _setColumnWidth(i, w) {
        const fill = _fillIndex;
        if (i < 0 || i >= columns.length || i === fill || _hidden[i] || !isFinite(w)) {
            return;
        }
        const room = Math.max(0, widths[fill] - Kirigami.Units.gridUnit * 4);
        w = Math.round(Math.max(_minColumnWidth, Math.min(w, widths[i] + room)));
        if (w === widths[i]) {
            return;
        }
        const all = columns.map((c, k) => _hidden[k] ? (columnWidths[k] ?? 0) : widths[k]);
        all[i] = w;
        columnWidths = all;
        columnResized(i, w);
    }
    // The delegate of row r, or null when it isn't on screen.
    function _delegate(r) {
        return list.itemAtIndex(r);
    }
    // The widest the visible cells of column i are, plus the header.
    function _fitColumn(i) {
        const c = columns[i];
        if (!c) {
            return;
        }
        const icon = Kirigami.Units.iconSizes.small + AtlasStyle.spacingSmall;
        const pad = 2 * cellPadding + 2;
        metrics.text = String(c.title ?? "");
        let best = metrics.advanceWidth + pad + icon;
        const first = Math.max(0, list.indexAt(1, list.contentY + 1));
        let last = list.indexAt(1, list.contentY + list.height - 2);
        if (last < 0) {
            last = list.count - 1;
        }
        const firstVisible = _nextVisible(-1);
        for (let r = first; r <= last; ++r) {
            const item = _delegate(r);
            if (!item || c.cell !== undefined) {
                continue;
            }
            const v = item.model[c.role];
            metrics.text = String(c.text ? c.text(v, item.model) : (v ?? ""));
            let w = metrics.advanceWidth + pad + (c.iconRole !== undefined ? icon : 0);
            if (i === firstVisible && (expandableRole || item.depth > 0)) {
                w += Kirigami.Units.iconSizes.small + item.indent;
            }
            best = Math.max(best, w);
        }
        _setColumnWidth(i, Math.ceil(best));
    }
    function _toggleColumn(i) {
        const hidden = Object.keys(_hidden).map(Number);
        const at = hidden.indexOf(i);
        if (at >= 0) {
            hidden.splice(at, 1);
        } else if (hidden.length < columns.length - 1) {
            hidden.push(i);
        } else {
            return;
        }
        hiddenColumns = hidden.sort((a, b) => a - b);
    }
    function _openColumnsMenu(x, y) {
        columnsMenuLoader.active = true;
        (columnsMenuLoader.item as ContextMenu).popup(root, x, y);
    }
    function _requestRowMenu(row, x, y) {
        if (_multi && !_sel[row]) {
            _select(list.currentIndex, row, false, false);
        }
        contextMenuRequested(row, x, y);
        rowContextMenuRequested(row, Qt.point(x, y));
    }

    TextMetrics {
        id: metrics
        font: Kirigami.Theme.defaultFont
    }

    Loader {
        id: columnsMenuLoader
        active: false
        sourceComponent: ContextMenu {
            Repeater {
                model: root.columns.length

                ContextMenuItem {
                    id: entry
                    required property int index
                    text: root.columns[index].title
                    checkable: true
                    // The last visible column can't be hidden.
                    enabled: !(checked && root.columns.length - Object.keys(root._hidden).length <= 1)
                    onTriggered: root._toggleColumn(index)

                    Binding {
                        target: entry
                        property: "checked"
                        value: !root._hidden[entry.index]
                    }
                }
            }
        }
    }

    Keys.onPressed: event => {
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const from = list.currentIndex;
        const page = Math.max(1, Math.floor(list.height / root.rowHeight) - 1);
        let to = list.currentIndex;
        switch (event.key) {
        case Qt.Key_Up:
            to = Math.max(0, to - 1);
            break;
        case Qt.Key_Down:
            to = Math.min(list.count - 1, to + 1);
            break;
        case Qt.Key_PageUp:
            to = Math.max(0, to - page);
            break;
        case Qt.Key_PageDown:
            to = Math.min(list.count - 1, to + page);
            break;
        case Qt.Key_A:
            if (ctrl && root._multi) {
                root.selectAll();
                event.accepted = true;
            }
            return;
        case Qt.Key_Space:
            if (root._multi && to >= 0 && !event.isAutoRepeat) {
                root._select(from, to, false, true);
                event.accepted = true;
            }
            return;
        case Qt.Key_Home:
            to = 0;
            break;
        case Qt.Key_End:
            to = list.count - 1;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (to >= 0) {
                if (!event.isAutoRepeat) {
                    root.activated(to);
                }
                event.accepted = true;
            }
            return;
        case Qt.Key_Delete:
            if (to >= 0) {
                if (!event.isAutoRepeat) {
                    root.deleteRequested(to);
                }
                event.accepted = true;
            }
            return;
        case Qt.Key_Menu:
            event.accepted = root.openMenuAtCurrent();
            return;
        case Qt.Key_F10:
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = root.openMenuAtCurrent();
            }
            return;
        case Qt.Key_Left:
        case Qt.Key_Right:
            // Fold or unfold a tree row, the way a file manager does.
            if (to >= 0 && root.expandableRole && list.currentItem && list.currentItem.expandable) {
                const open = (event.key === Qt.Key_Right) !== root.mirrored;
                if (open !== list.currentItem.expanded) {
                    root.toggleRequested(to);
                    event.accepted = true;
                }
            }
            return;
        default:
            return;
        }
        if (to !== list.currentIndex && to >= 0) {
            list.currentIndex = to;
            list.positionViewAtIndex(to, ListView.Contain);
        }
        root._select(from, to, shift, false);
        event.accepted = true;
    }
    readonly property bool mirrored: LayoutMirroring.enabled
    // Translated once: qsTr looks its file up in Qt's resources on every
    // call, and the rows re-evaluate whenever the model changes.
    readonly property string expandedText: qsTr("Expanded")
    readonly property string collapsedText: qsTr("Collapsed")

    function openMenuAtCurrent() {
        // Bring the row on screen first: off screen it has no item.
        if (list.currentIndex >= 0 && list.currentIndex < list.count) {
            list.positionViewAtIndex(list.currentIndex, ListView.Contain);
        }
        const item = list.currentItem;
        if (!item) {
            return false;
        }
        const p = item.mapToItem(root, root.mirrored ? item.width - Kirigami.Units.gridUnit * 2 : Kirigami.Units.gridUnit * 2, item.height / 2);
        root._requestRowMenu(list.currentIndex, p.x, p.y);
        return true;
    }

    // The card, drawn like Section's.
    Rectangle {
        anchors.fill: parent
        radius: AtlasStyle.radiusLarge
        color: Qt.alpha(Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.5) : Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(1, 1, 1, 0.06)), root.Window.window && root.Window.window.blurred === true ? 0.94 : 1)
        border.width: 1
        border.color: root.activeFocus ? Qt.alpha(AtlasStyle.focus, 0.85) : Qt.alpha(Kirigami.Theme.textColor, 0.12)
    }

    Row {
        id: header
        x: root.padding
        y: root.padding
        width: root.width - 2 * root.padding
        height: Math.round(Kirigami.Units.gridUnit * 1.8)
        clip: true

        // Right clicks only, over every column and the space after them; a
        // handler, so left clicks and the resize grips below get theirs.
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: eventPoint => {
                const p = header.mapToItem(root, eventPoint.position);
                root.headerMenuRequested(p.x, p.y);
                if (root.columnsMenu) {
                    root._openColumnsMenu(p.x, p.y);
                }
            }
        }

        Repeater {
            model: root.columns.length

            Item {
                id: head
                required property int index
                readonly property var column: root.columns[index]
                readonly property bool sorted: column.role === root.sortRole
                readonly property bool alignRight: column.align === Qt.AlignRight

                visible: !root._hidden[index]
                width: root.widths[index] ?? 0
                height: header.height
                Accessible.role: Accessible.ColumnHeader
                Accessible.name: column.title
                Accessible.onPressAction: root.sortBy(index)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: AtlasStyle.radiusSmall
                    color: Qt.alpha(Kirigami.Theme.textColor, headMouse.pressed ? 0.1 : headMouse.containsMouse ? 0.05 : 0)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.cellPadding
                    anchors.rightMargin: root.cellPadding
                    spacing: Kirigami.Units.smallSpacing
                    // Mirrored with the table, so figures' titles sit at
                    // the end either way.
                    layoutDirection: head.alignRight ? Qt.RightToLeft : Qt.LeftToRight

                    QQC2.Label {
                        text: head.column.title
                        font.weight: head.sorted ? Font.DemiBold : Font.Normal
                        opacity: head.sorted ? 0.9 : 0.6
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        Layout.maximumWidth: head.width - root.cellPadding * 2 - Kirigami.Units.iconSizes.small
                    }
                    Kirigami.Icon {
                        visible: head.sorted
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        source: root.sortOrder === Qt.AscendingOrder ? "arrow-up" : "arrow-down"
                        isMask: true
                        color: Kirigami.Theme.textColor
                        opacity: 0.6
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    id: headMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: head.column.sortable !== false
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.sortBy(head.index)
                }

                // The boundary to the next visible column. Only the fill
                // column gives or takes space, so with it at or before the
                // boundary the columns after the boundary change (the other
                // way round from the pointer), else the column before it.
                MouseArea {
                    id: grip
                    readonly property int _next: root._nextVisible(head.index)
                    readonly property bool _after: head.index >= root._fillIndex
                    readonly property int _target: _after ? _next : head.index
                    property real _startX
                    property real _startWidth

                    // Anchors mirror with the table, so this is the end edge.
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: Kirigami.Units.smallSpacing * 3
                    visible: root.resizableColumns && _next >= 0
                    hoverEnabled: true
                    cursorShape: Qt.SplitHCursor
                    onPressed: mouse => {
                        _startX = mapToItem(root, mouse.x, 0).x;
                        _startWidth = root.widths[_target] ?? 0;
                    }
                    onPositionChanged: mouse => {
                        if (!pressed) {
                            return;
                        }
                        const dx = (mapToItem(root, mouse.x, 0).x - _startX) * (root.mirrored ? -1 : 1);
                        root._setColumnWidth(_target, _startWidth + (_after ? -dx : dx));
                    }
                    onDoubleClicked: root._fitColumn(_target)

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        width: grip.pressed || grip.containsMouse ? 2 : 1
                        height: parent.height * 0.5
                        radius: width / 2
                        color: grip.pressed || grip.containsMouse ? AtlasStyle.accent : Qt.alpha(Kirigami.Theme.textColor, 0.18)
                    }
                }
            }
        }
    }

    Rectangle {
        id: rule
        x: root.padding + root.cellPadding / 2
        y: header.y + header.height
        width: root.width - 2 * x
        height: 1
        color: Qt.alpha(Kirigami.Theme.textColor, 0.1)
    }

    Item {
        id: rows
        x: root.padding
        y: rule.y + rule.height + root.padding / 2
        width: root.width - 2 * root.padding
        // Stop short of the bottom corners' curve.
        height: root.height - y - root.padding * 2
    }

    ListView {
        id: list
        anchors.fill: rows
        clip: true
        model: root.model
        reuseItems: true
        onCountChanged: root._pruneSelection()
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: -1
        highlightMoveDuration: 0
        keyNavigationEnabled: false
        activeFocusOnTab: false

        // Over the rows only: pointing at the header doesn't hold the order.
        // An ancestor of the rows, since their MouseAreas take the hover.
        HoverHandler {
            id: hover
        }
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            policy: QQC2.ScrollBar.AsNeeded
            implicitWidth: 10
            padding: 2
            contentItem: Rectangle {
                implicitWidth: 6
                radius: width / 2
                color: Qt.alpha(Kirigami.Theme.textColor, parent.pressed ? 0.45 : parent.hovered ? 0.35 : 0.22)
                opacity: parent.active ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: AtlasStyle.duration
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
            readonly property bool selected: root.selectionMode === DataTable.SingleSelection ? current : root._multi ? root._sel[index] === true : false
            readonly property int depth: root.depthRole ? (model[root.depthRole] ?? 0) : 0
            readonly property bool expandable: root.expandableRole ? model[root.expandableRole] === true : false
            readonly property bool expanded: root.expandedRole ? model[root.expandedRole] === true : false
            readonly property real indent: depth * Kirigami.Units.gridUnit * 1.2

            width: ListView.view.width
            height: root.rowHeight
            Accessible.role: Accessible.Row
            Accessible.selected: selected
            Accessible.focusable: true
            Accessible.focused: selected && root.activeFocus
            // Qt's Accessible has no expandable or expanded state to set;
            // say it in the description.
            Accessible.description: expandable ? (expanded ? root.expandedText : root.collapsedText) : ""
            Accessible.onPressAction: root.activated(index)
            Accessible.onToggleAction: {
                if (expandable) {
                    root.toggleRequested(index);
                }
            }
            // Every column, for the current row and for every row while a
            // screen reader is listening; otherwise the first only.
            // Formatting every cell twice on each change doubled a busy
            // table's work.
            Accessible.name: {
                const parts = [];
                const all = selected || AccessibilityState.active;
                for (let i = 0; i < (all ? root.columns.length : Math.min(1, root.columns.length)); ++i) {
                    const c = root.columns[i];
                    const v = row.model[c.role];
                    parts.push(c.title + " " + (c.text ? c.text(v, row.model) : v));
                }
                return parts.join(", ");
            }

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 1
                anchors.bottomMargin: 1
                radius: AtlasStyle.radiusSmall
                color: row.selected ? Qt.alpha(AtlasStyle.accent, root.activeFocus ? 0.22 : 0.14) : Qt.alpha(Kirigami.Theme.textColor, rowMouse.pressed ? 0.08 : rowMouse.containsMouse ? 0.045 : 0)
                // The current row of a multi-selection when it isn't selected
                // (Ctrl+Space off), so the keyboard position stays visible.
                border.width: root._multi && row.current && !row.selected && root.activeFocus ? 1 : 0
                border.color: Qt.alpha(AtlasStyle.focus, 0.85)
            }

            Row {
                anchors.fill: parent

                Repeater {
                    model: root.columns.length

                    Item {
                        id: cell
                        required property int index
                        readonly property var column: root.columns[index]
                        readonly property var value: row.model[column.role]
                        // A value the machine doesn't report (NaN) is cold.
                        readonly property real heat: column.heat > 0 && Number(value) > 0 ? Math.min(1, Number(value) / column.heat) : 0
                        readonly property real indent: index === 0 ? row.indent : 0

                        visible: !root._hidden[index]
                        width: root.widths[index] ?? 0
                        height: row.height

                        // Heat: the busier, the warmer. Faint at idle so a
                        // quiet list stays quiet.
                        Rectangle {
                            visible: cell.heat > 0.02
                            anchors.fill: parent
                            anchors.topMargin: 1
                            anchors.bottomMargin: 1
                            color: Qt.alpha(Kirigami.Theme.neutralTextColor, 0.06 + 0.32 * cell.heat)
                        }

                        Loader {
                            id: custom
                            active: cell.column.cell !== undefined && cell.visible
                            anchors.fill: parent
                            anchors.leftMargin: root.cellPadding
                            anchors.rightMargin: root.cellPadding
                            sourceComponent: cell.column.cell
                            onLoaded: {
                                item.value = Qt.binding(() => cell.value);
                                item.row = Qt.binding(() => row.model);
                                item.column = Qt.binding(() => cell.column);
                            }
                        }

                        RowLayout {
                            visible: !custom.active
                            anchors.fill: parent
                            anchors.leftMargin: root.cellPadding + (cell.index === 0 && (root.expandableRole || row.depth > 0) ? Kirigami.Units.iconSizes.small + cell.indent : 0)
                            anchors.rightMargin: root.cellPadding
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                visible: cell.column.iconRole !== undefined
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                source: cell.column.iconRole ? (row.model[cell.column.iconRole] || "application-x-executable") : ""
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: cell.column.text ? cell.column.text(cell.value, row.model) : (cell.value ?? "")
                                horizontalAlignment: cell.column.align === Qt.AlignRight ? Text.AlignRight : Text.AlignLeft
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                font.features: cell.column.align === Qt.AlignRight ? { "tnum": 1 } : {}
                            }
                        }
                    }
                }
            }

            // The tree's chevron, one per row and only in a tree, at the
            // start of the first column (its right edge when mirrored).
            Loader {
                active: root.expandableRole.length > 0 && row.expandable
                x: root.mirrored ? row.width - width - root.cellPadding / 2 - row.indent : root.cellPadding / 2 + row.indent
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.small
                height: width
                sourceComponent: Kirigami.Icon {
                    source: root.mirrored ? "arrow-left" : "arrow-right"
                    isMask: true
                    color: Kirigami.Theme.textColor
                    opacity: 0.45
                    rotation: row.expanded ? (root.mirrored ? -90 : 90) : 0

                    TapHandler {
                        onTapped: root.toggleRequested(row.index)
                    }
                }
            }

            // Over the cells: a changed figure repaints the row as one
            // rectangle (see repaintarea.h). Keyed on the values, not the
            // texts: that repaints rows whose text held ("0 B/s" from a
            // rate that moved), but the busy table then goes as one
            // rectangle, and painting through a clip of many costs more
            // than painting it all (measured: 22 against 25.7 ms/s).
            RepaintArea {
                anchors.fill: parent
                content: root.columns.map(c => row.model[c.role])
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                // Under the cells' own controls (a switch) and the chevron.
                z: -1
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: mouse => {
                    const from = list.currentIndex;
                    list.currentIndex = row.index;
                    root.forceActiveFocus(Qt.MouseFocusReason);
                    if (mouse.button === Qt.LeftButton) {
                        root._select(from, row.index, (mouse.modifiers & Qt.ShiftModifier) !== 0, (mouse.modifiers & Qt.ControlModifier) !== 0);
                    }
                }
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        const p = mapToItem(root, mouse.x, mouse.y);
                        root._requestRowMenu(row.index, p.x, p.y);
                    }
                }
                onDoubleClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        root.activated(row.index);
                    }
                }
            }
        }
    }

    QQC2.Label {
        visible: list.count === 0 && root.placeholderText.length > 0
        anchors.centerIn: rows
        width: list.width - Kirigami.Units.gridUnit * 2
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.placeholderText
        opacity: 0.6
        textFormat: Text.PlainText
    }
}
