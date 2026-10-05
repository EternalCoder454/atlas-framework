pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A tree of rows on Qt Quick's TreeView, in the Atlas list look: rows as tall
// as AtlasStyle.rowHeight, a hover tint, the selected rows as an accent-tint
// rounded selection (radiusSmall), a chevron to expand (mirrored in right-to-left layouts) and one
// indent per level. Only the rows on screen are made. The model is any
// QAbstractItemModel; AtlasTreeModel builds one from nested JS objects:
//
//   AtlasTreeModel { id: files; items: [ { text: "Docs", symbol: Symbols.Folder,
//       children: [ { text: "Report.odt" } ] } ] }
//   AtlasTreeView {
//       model: files
//       textRole: "display"            // the default
//       symbolRole: "symbol"           // or iconRole: "icon"; empty = none
//       selectionMode: AtlasTreeView.MultiSelection
//       onActivated: index => open(index)
//       onContextMenuRequested: (index, pos) => menu.popup()
//       Accessible.name: qsTr("Files")
//   }
//
// Keys: Up, Down, Home, End, Page Up and Page Down move; Right expands or
// enters the first child and Left collapses or goes to the parent (swapped
// when mirrored); Return activates; Space selects (toggles, in multi
// selection); Menu or Shift+F10 asks for the context menu; letters jump to
// the next row whose text starts with what was typed in the last 500 ms. In
// multi selection Shift+Up/Down extend the selection, Ctrl+A selects all and
// Ctrl+Up/Down move without selecting; with NoSelection only the current row
// moves. Collapsing a row that hides the current one moves current to the
// collapsed row. Clicks: Ctrl toggles and Shift extends (multi),
// double-click activates, right-click asks for the context menu.
T.Control {
    id: control

    enum SelectionMode {
        SingleSelection,
        MultiSelection,
        NoSelection
    }

    property var model
    property string textRole: "display"
    // Role names for a Symbols.<Name> value / an icon name or url; empty = none.
    property string symbolRole
    property string iconRole
    property int selectionMode: AtlasTreeView.SingleSelection
    // What the tree shows in place of its rows (an AtlasStatus value) and the
    // content of that: the heading, the explanation, a Symbols value (0 for
    // the status's own) and one action.
    property int status: AtlasStatus.Ready
    property string statusTitle
    property string statusText
    property int statusSymbol: 0
    property AtlasAction statusAction: null
    // The QModelIndex of the current row (invalid when there is none).
    readonly property var currentIndex: selection.currentIndex
    // Which rows are selected: an ItemSelectionModel for the app to read.
    readonly property ItemSelectionModel selectionModel: selection
    readonly property alias count: view.rows

    signal activated(var index)
    signal contextMenuRequested(var index, point pos)

    function expand(index) {
        const r = view.rowAtIndex(index);
        if (r >= 0)
            view.expand(r);
    }
    function collapse(index) {
        const r = view.rowAtIndex(index);
        if (r >= 0)
            priv.collapseRow(r);
    }
    function isExpanded(index) {
        const r = view.rowAtIndex(index);
        return r >= 0 && view.isExpanded(r);
    }
    function expandAll() {
        view.expandRecursively();
    }
    function collapseAll() {
        view.collapseRecursively();
        priv.fixCurrent();
    }
    // Selects every row that is shown (MultiSelection only).
    function selectAll() {
        if (priv.multi && view.rows > 0)
            priv.selectRange(0, view.rows - 1);
    }
    function clearSelection() {
        selection.clearSelection();
        priv.anchorRow = -1;
    }

    // Not a Tab stop under a status: there is no row to show focus on, and the
    // status's action button is the stop.
    focusPolicy: control.status === AtlasStatus.Ready ? Qt.StrongFocus : Qt.ClickFocus
    implicitWidth: Kirigami.Units.gridUnit * 16
    implicitHeight: Kirigami.Units.gridUnit * 12
    background: null

    Accessible.role: Accessible.Tree
    Accessible.focusable: true

    onActiveFocusChanged: {
        if (activeFocus && !selection.currentIndex.valid && view.rows > 0)
            selection.setCurrentIndex(view.index(0, 0), ItemSelectionModel.Current);
    }

    onSelectionModeChanged: {
        if (selectionMode === AtlasTreeView.NoSelection)
            clearSelection();
    }
    onModelChanged: priv.anchorRow = -1

    ItemSelectionModel {
        id: selection
        model: control.model ?? null
    }

    // A reset (AtlasTreeModel.items set again) drops the rows the anchor meant.
    Connections {
        target: control.model ?? null
        ignoreUnknownSignals: true
        function onModelReset() {
            priv.anchorRow = -1;
        }
    }

    QtObject {
        id: priv
        readonly property bool multi: control.selectionMode === AtlasTreeView.MultiSelection
        readonly property bool selectable: control.selectionMode !== AtlasTreeView.NoSelection
        readonly property var app: Qt.application
        property int anchorRow: -1
        property string typed

        function pick(m, role) {
            return role.length > 0 && m ? m[role] : undefined;
        }
        function currentRow() {
            return selection.currentIndex.valid ? view.rowAtIndex(selection.currentIndex) : -1;
        }
        function textAt(row) {
            const m = control.model;
            const idx = view.index(row, 0);
            if (!m || !idx.valid)
                return "";
            let role = Qt.DisplayRole;
            if (control.textRole !== "display") {
                const names = m.roleNames ? m.roleNames() : undefined;
                role = -1;
                for (const k in names) {
                    if (String(names[k]) === control.textRole)
                        role = Number(k);
                }
                if (role < 0)
                    return "";
            }
            return String(m.data(idx, role) ?? "");
        }
        // Selects rows a..b (inclusive, in view order) and nothing else, in
        // one call: one QItemSelection when the model can build it.
        function selectRange(a, b) {
            const lo = Math.max(0, Math.min(a, b));
            const hi = Math.min(view.rows - 1, Math.max(a, b));
            const m = control.model;
            if (m && typeof m._selectionOf === "function") {
                const list = [];
                for (let r = lo; r <= hi; ++r)
                    list.push(view.index(r, 0));
                selection.select(m._selectionOf(list), ItemSelectionModel.ClearAndSelect);
                return;
            }
            selection.clearSelection();
            for (let r = lo; r <= hi; ++r)
                selection.select(view.index(r, 0), ItemSelectionModel.Select);
        }
        // After rows were hidden: if the current row is gone, move current
        // (and, outside multi selection, the selection) to its nearest shown
        // ancestor.
        function fixCurrent() {
            const m = control.model;
            let i = selection.currentIndex;
            if (!m || !i.valid || view.rowAtIndex(i) >= 0)
                return;
            while (i.valid && view.rowAtIndex(i) < 0)
                i = m.parent(i);
            if (!i.valid)
                return;
            const flag = priv.selectable && !priv.multi ? ItemSelectionModel.ClearAndSelect : ItemSelectionModel.Current;
            selection.setCurrentIndex(i, flag);
            anchorRow = view.rowAtIndex(i);
        }
        function collapseRow(row) {
            view.collapse(row);
            fixCurrent();
        }
        function toggleRow(row) {
            if (view.isExpanded(row))
                collapseRow(row);
            else
                view.expand(row);
        }
        // Moves the current row to `row`. extend: Shift (range from the
        // anchor); keep: Ctrl (move only, leave the selection).
        function goTo(row, extend, keep) {
            if (view.rows === 0)
                return;
            row = Math.max(0, Math.min(view.rows - 1, row));
            const idx = view.index(row, 0);
            if (!priv.selectable || (priv.multi && keep)) {
                selection.setCurrentIndex(idx, ItemSelectionModel.Current);
            } else if (priv.multi && extend) {
                if (anchorRow < 0)
                    anchorRow = Math.max(0, currentRow());
                selectRange(anchorRow, row);
                selection.setCurrentIndex(idx, ItemSelectionModel.Current);
            } else {
                anchorRow = row;
                selection.setCurrentIndex(idx, ItemSelectionModel.ClearAndSelect);
            }
            view.positionViewAtRow(row, TableView.Contain);
        }
        function toggle(row) {
            const idx = view.index(row, 0);
            anchorRow = row;
            selection.setCurrentIndex(idx, ItemSelectionModel.Current);
            if (priv.selectable)
                selection.select(idx, ItemSelectionModel.Toggle);
        }
        function menuFor(row, pos) {
            control.contextMenuRequested(view.index(row, 0), pos);
        }
        function typeAhead(ch) {
            typed += ch.toLowerCase();
            typedTimer.restart();
            const n = view.rows;
            const cur = Math.max(0, currentRow());
            // One repeated letter cycles through rows; a longer word stays
            // on the current row while it still matches.
            const start = typed.length === 1 ? cur + 1 : cur;
            for (let i = 0; i < n; ++i) {
                const r = (start + i) % n;
                if (textAt(r).toLowerCase().startsWith(typed)) {
                    goTo(r, false, false);
                    return;
                }
            }
        }
    }

    Timer {
        id: typedTimer
        interval: 500
        onTriggered: priv.typed = ""
    }

    Keys.onPressed: event => {
        if (control.status !== AtlasStatus.Ready) {
            return;
        }
        const row = priv.currentRow();
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const alt = (event.modifiers & Qt.AltModifier) !== 0;
        const page = Math.max(1, Math.floor(view.height / Math.max(1, AtlasStyle.rowHeight)) - 1);
        let used = true;
        switch (event.key) {
        case Qt.Key_Up:
            priv.goTo(row < 0 ? view.rows - 1 : row - 1, shift, ctrl);
            break;
        case Qt.Key_Down:
            priv.goTo(row < 0 ? 0 : row + 1, shift, ctrl);
            break;
        case Qt.Key_PageUp:
            priv.goTo(row - page, shift, false);
            break;
        case Qt.Key_PageDown:
            priv.goTo(row + page, shift, false);
            break;
        case Qt.Key_Home:
            priv.goTo(0, shift, false);
            break;
        case Qt.Key_End:
            priv.goTo(view.rows - 1, shift, false);
            break;
        case Qt.Key_Right:
        case Qt.Key_Left:
            {
                if (row < 0)
                    break;
                const forward = (event.key === Qt.Key_Right) !== control.mirrored;
                const idx = view.index(row, 0);
                if (forward) {
                    if (control.model.hasChildren(idx)) {
                        if (!view.isExpanded(row))
                            view.expand(row);
                        else
                            priv.goTo(row + 1, false, false);
                    }
                } else if (view.isExpanded(row)) {
                    priv.collapseRow(row);
                } else {
                    const p = view.rowAtIndex(control.model.parent(idx));
                    if (p >= 0)
                        priv.goTo(p, false, false);
                }
                break;
            }
        case Qt.Key_A:
            if (ctrl && !shift && !alt) {
                control.selectAll();
            } else {
                used = false;
                if (!ctrl && !alt && event.text.length === 1) {
                    priv.typeAhead(event.text);
                    used = true;
                }
            }
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (row >= 0)
                control.activated(view.index(row, 0));
            break;
        case Qt.Key_Space:
            if (row < 0)
                break;
            if (priv.multi)
                priv.toggle(row);
            else
                priv.goTo(row, false, false);
            break;
        case Qt.Key_Menu:
            if (row >= 0)
                priv.menuFor(row, Qt.point(control.width / 2, (row + 0.5) * AtlasStyle.rowHeight - view.contentY));
            break;
        case Qt.Key_F10:
            if (shift && row >= 0)
                priv.menuFor(row, Qt.point(control.width / 2, (row + 0.5) * AtlasStyle.rowHeight - view.contentY));
            else
                used = false;
            break;
        default:
            used = false;
            if (!ctrl && !alt && event.text.length === 1 && event.text.charCodeAt(0) > 32) {
                priv.typeAhead(event.text);
                used = true;
            }
        }
        event.accepted = used;
    }

    contentItem: TreeView {
        id: view
        clip: true
        visible: control.status === AtlasStatus.Ready
        model: control.model
        selectionModel: selection
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: false
        pointerNavigationEnabled: false
        keyNavigationEnabled: false
        selectionBehavior: TableView.SelectRows
        opacity: control.enabled ? 1 : 0.6
        reuseItems: true
        columnWidthProvider: () => view.width
        rowHeightProvider: () => AtlasStyle.rowHeight

        T.ScrollBar.vertical: T.ScrollBar {
            id: bar
            policy: T.ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: Math.round(Kirigami.Units.smallSpacing * 1.5)
                radius: width / 2
                color: AtlasStyle.alpha(Kirigami.Theme.textColor, 0.3)
                opacity: bar.active ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: AtlasStyle.durationShort
                    }
                }
            }
            background: null
        }

        delegate: Item {
            id: row
            required property TreeView treeView
            required property bool isTreeNode
            required property bool expanded
            required property bool hasChildren
            required property int depth
            required property int row
            required property int column
            required property bool current
            required property bool selected
            required property var model

            readonly property string title: String(priv.pick(row.model, control.textRole) ?? "")
            readonly property string iconName: String(priv.pick(row.model, control.iconRole) ?? "")
            readonly property int symbolValue: Number(priv.pick(row.model, control.symbolRole) ?? 0)
            readonly property real indent: Kirigami.Units.iconSizes.smallMedium

            implicitWidth: view.width
            implicitHeight: AtlasStyle.rowHeight
            LayoutMirroring.enabled: control.mirrored
            LayoutMirroring.childrenInherit: true

            Accessible.role: Accessible.TreeItem
            Accessible.name: row.title
            Accessible.selected: row.selected
            Accessible.focusable: true
            Accessible.description: row.hasChildren ? (row.expanded ? qsTr("Expanded") : qsTr("Collapsed")) : ""
            Accessible.onPressAction: control.activated(view.index(row.row, 0))
            Accessible.onToggleAction: priv.toggleRow(row.row)

            Rectangle {
                id: pill
                anchors.fill: parent
                anchors.leftMargin: AtlasStyle.spacingSmall
                anchors.rightMargin: AtlasStyle.spacingSmall
                radius: AtlasStyle.radiusSmall
                color: row.selected ? (control.activeFocus ? AtlasStyle.selection : AtlasStyle.selectionInactive) : hover.hovered ? AtlasStyle.hover : "transparent"
                AtlasFocusRing {
                    radius: pill.radius + gap
                    shown: control.visualFocus && row.current
                }
            }

            Item {
                id: chevron
                objectName: "chevron"
                // Set by hand, so mirrored by hand: from the right edge in RTL.
                readonly property real _offset: AtlasStyle.spacingSmall + AtlasStyle.spacing + row.depth * row.indent
                x: control.mirrored ? row.width - _offset - width : _offset
                anchors.verticalCenter: parent.verticalCenter
                width: row.indent
                height: row.indent
                // Mirrored layouts put the chevron on the right.
                Symbol {
                    anchors.centerIn: parent
                    visible: row.hasChildren
                    icon: Symbols.ChevronRight
                    size: Math.round(parent.width * 0.9)
                    color: AtlasStyle.textMuted
                    rotation: row.expanded ? 90 : control.mirrored ? 180 : 0
                    Behavior on rotation {
                        NumberAnimation {
                            duration: AtlasStyle.durationShort
                        }
                    }
                }
            }
            Item {
                id: iconBox
                anchors.left: chevron.right
                anchors.leftMargin: AtlasStyle.spacingSmall
                anchors.verticalCenter: parent.verticalCenter
                width: row.iconName.length > 0 || row.symbolValue !== 0 ? Kirigami.Units.iconSizes.smallMedium : 0
                height: width
                Kirigami.Icon {
                    anchors.fill: parent
                    visible: row.iconName.length > 0
                    source: row.iconName
                    isMask: false
                }
                Loader {
                    anchors.centerIn: parent
                    active: row.iconName.length === 0 && row.symbolValue !== 0
                    sourceComponent: Symbol {
                        icon: row.symbolValue
                        size: Math.round(iconBox.width * 0.9)
                        color: row.selected ? AtlasStyle.accent : AtlasStyle.textMuted
                    }
                }
            }
            Text {
                anchors.left: iconBox.right
                anchors.leftMargin: AtlasStyle.spacingSmall
                anchors.right: parent.right
                anchors.rightMargin: AtlasStyle.spacing
                anchors.verticalCenter: parent.verticalCenter
                Accessible.ignored: true
                text: row.title
                font.family: AtlasStyle.fontFamily
                font.pointSize: AtlasStyle.fontSizeBody
                color: AtlasStyle.text
                textFormat: Text.PlainText
                elide: Text.ElideRight
                // AlignLeft is the start edge: the mirrored row flips it.
                horizontalAlignment: Text.AlignLeft
            }

            HoverHandler {
                id: hover
                enabled: control.enabled
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (point, button) => {
                    control.forceActiveFocus(Qt.MouseFocusReason);
                    const mods = priv.app.keyboardModifiers;
                    if (button === Qt.RightButton) {
                        if (!row.selected)
                            priv.goTo(row.row, false, false);
                        priv.menuFor(row.row, row.mapToItem(control, point.position));
                        return;
                    }
                    if (row.hasChildren && chevron.contains(chevron.mapFromItem(row, point.position))) {
                        priv.toggleRow(row.row);
                        return;
                    }
                    if (priv.multi && (mods & Qt.ControlModifier))
                        priv.toggle(row.row);
                    else if (!priv.selectable)
                        priv.goTo(row.row, false, false);
                    else
                        priv.goTo(row.row, (mods & Qt.ShiftModifier) !== 0, false);
                }
                onDoubleTapped: (point, button) => {
                    if (button === Qt.LeftButton && !(row.hasChildren && chevron.contains(chevron.mapFromItem(row, point.position))))
                        control.activated(view.index(row.row, 0));
                }
            }
        }
    }

    AtlasStatusView {
        parent: control
        anchors.fill: parent
        status: control.status
        title: control.statusTitle
        text: control.statusText
        symbol: control.statusSymbol
        action: control.statusAction
    }
}
