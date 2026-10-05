pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A list in the Atlas look: rows of AtlasStyle.rowHeight, a hover tint, the
// selected rows in an accent-tint rounded selection (radiusSmall), and a focus ring on the current row when
// the keyboard moved there. It is a ListView, so `model`, `delegate`,
// `currentIndex`, `count` and the rest work as usual, and it makes rows only
// for what is on screen: ten thousand rows cost what a screenful does.
//
//   AtlasListView {
//       model: files                   // a QAbstractItemModel, or a JS array
//       textRole: "name"
//       subtitleRole: "path"
//       symbolRole: "symbol"           // a Symbols.<Name> value
//       selectionMode: AtlasListView.MultiSelection
//       placeholderText: qsTr("No files")
//       placeholderSymbol: Symbols.FolderOpen
//       Accessible.name: qsTr("Files")
//       onActivated: index => open(index)
//       onContextMenuRequested: (index, pos) => menu.popup(this, pos.x, pos.y)
//   }
//
// Without a `delegate` each row shows the symbol, the text and the subtitle
// from the model's roles (keys of an array's objects; an array of plain
// strings shows the strings). With your own delegate, the view still does the
// clicking, selecting, the keyboard and the context menu; draw the selection
// with `list.isSelected(index)` (it re-evaluates when the selection changes).
//
// Selection works by row index; it is cleared when `model` changes, resets or
// moves rows, and follows the rows when a QAbstractItemModel or ListModel
// inserts or removes some (a JS array just drops indexes past its end).
// selectedRows (the same as selectedIndexes), select(), selectRows(list),
// selectAll() and clearSelection() read and set it from code. Click selects; Ctrl-click toggles and
// Shift-click extends (MultiSelection); Shift+arrows extend, Ctrl+A selects
// all, Space toggles. Double click or Return emits `activated`; a right
// click (it selects an unselected row first), the Menu key or Shift+F10
// emits `contextMenuRequested` with a position in the list. Typing jumps to
// the next row whose text starts with what was typed (an array, a ListModel,
// or a model's "display" role; the buffer clears after 500 ms).
//
// With `reorderable`, the default rows show a grip to drag and Alt+Up/Down
// moves the current row: the list emits `moveRequested(from, to)` and the app
// moves the model's row to `to` at once, in the handler; the list then
// selects it. Name the list for screen readers with Accessible.name.
//
// `status` (an AtlasStatus value) shows Loading, Empty, NoResults or Error
// in place of the rows, below the list's `header` if it has one; see
// docs/reference/atlas-ui/atlas-status.md.
ListView {
    id: control

    enum SelectionMode {
        SingleSelection,
        MultiSelection,
        NoSelection
    }

    property string textRole: "text"
    property string subtitleRole
    property string symbolRole
    property int selectionMode: AtlasListView.SingleSelection
    property bool reorderable: false
    // Shown in the middle when there are no rows.
    property string placeholderText
    property int placeholderSymbol: 0
    // What the list shows in place of its rows (an AtlasStatus value) and the
    // content of that: the heading, the explanation, a Symbols value (0 for
    // the status's own) and one action button.
    property int status: AtlasStatus.Ready
    property string statusTitle
    property string statusText
    property int statusSymbol: 0
    property AtlasAction statusAction: null
    // The selected row indexes, ascending.
    readonly property list<int> selectedIndexes: {
        control._rev;
        return Object.keys(control._sel).map(Number).sort((a, b) => a - b);
    }
    // The same list, named as in DataTable.
    readonly property list<int> selectedRows: control.selectedIndexes

    signal activated(int index)
    signal contextMenuRequested(int index, point pos)
    signal moveRequested(int from, int to)

    function select(index: int): void {
        if (control.selectionMode === AtlasListView.NoSelection || index < 0 || index >= control.count) {
            return;
        }
        control.currentIndex = index;
        control._setOnly(index);
    }
    // Multi selection: selects every row. Other modes: no effect.
    function selectAll(): void {
        if (!control._multi) {
            return;
        }
        const s = {};
        for (let i = 0; i < control.count; ++i) {
            s[i] = true;
        }
        control._sel = s;
        control._rev++;
    }
    // Selects exactly these rows (out-of-range ones are ignored). Single
    // selection takes the first valid one; NoSelection ignores the call.
    function selectRows(rows: list<int>): void {
        if (!control._selectable) {
            return;
        }
        if (!control._multi) {
            for (const r of rows) {
                if (r >= 0 && r < control.count) {
                    control.select(r);
                    return;
                }
            }
            return;
        }
        const s = {};
        let last = -1;
        for (const r of rows) {
            if (r >= 0 && r < control.count) {
                s[r] = true;
                last = r;
            }
        }
        control._sel = s;
        control._anchor = last;
        control._rev++;
    }
    function clearSelection(): void {
        control._sel = ({});
        control._anchor = -1;
        control._rev++;
    }
    function isSelected(index: int): bool {
        control._rev; // the revision is what makes a binding on this re-run
        return control._sel[index] === true;
    }

    // Internal: the selection lives in a plain object and a revision counter,
    // so a row's binding does not depend on the whole selection.
    // The default font a little smaller; a pixel-sized theme font has
    // pointSize -1, so it scales its pixel size instead.
    readonly property font _captionFont: {
        const f = Qt.font({ "family": AtlasStyle.fontFamily, "pointSize": AtlasStyle.fontSizeBody });
        const o = {
            "family": f.family
        };
        if (f.pixelSize > 0) {
            o.pixelSize = Math.round(f.pixelSize * 0.92);
        } else {
            o.pointSize = f.pointSize * 0.92;
        }
        return Qt.font(o);
    }
    property var _sel: ({})
    property int _rev: 0
    property int _anchor: -1
    property int _hover: -1
    property bool _mouseFocus: false
    property string _typed: ""
    property int _dragFrom: -1
    property real _dragDelta: 0
    readonly property real _rowH: control.subtitleRole.length > 0 ? Math.round(AtlasStyle.rowHeight * 1.4) : AtlasStyle.rowHeight
    readonly property bool _multi: control.selectionMode === AtlasListView.MultiSelection
    readonly property bool _selectable: control.selectionMode !== AtlasListView.NoSelection
    // Selection follows a model that reports its row changes.
    readonly property bool _tracked: control.model !== null && control.model !== undefined && control.model.rowsInserted !== undefined
    readonly property int _dropIndex: control._dragFrom < 0 ? -1 : Math.max(0, Math.min(control.count - 1, Math.floor((control._dragFrom + 0.5) + control._dragDelta / control._rowH)))

    function _setOnly(index: int): void {
        const s = {};
        s[index] = true;
        control._sel = s;
        control._anchor = index;
        control._rev++;
    }
    function _toggle(index: int): void {
        if (!control._multi) {
            control._setOnly(index);
            return;
        }
        const s = control._sel;
        if (s[index] === true) {
            delete s[index];
        } else {
            s[index] = true;
        }
        control._anchor = index;
        control._rev++;
    }
    // The rows from the anchor to `index`; `add` keeps the selection too.
    function _extend(index: int, add: bool): void {
        if (!control._multi) {
            control._setOnly(index);
            return;
        }
        const from = control._anchor >= 0 ? control._anchor : Math.max(0, control.currentIndex);
        const s = add ? Object.assign({}, control._sel) : {};
        for (let i = Math.min(from, index); i <= Math.max(from, index); ++i) {
            s[i] = true;
        }
        control._sel = s;
        control._anchor = from;
        control._rev++;
    }
    // Moves the current row; Shift extends the selection, Ctrl only moves.
    function _moveTo(index: int, modifiers: int): void {
        if (control.count === 0) {
            return;
        }
        const i = Math.max(0, Math.min(control.count - 1, index));
        control.currentIndex = i;
        if (!control._selectable || (modifiers & Qt.ControlModifier)) {
            return;
        }
        if (modifiers & Qt.ShiftModifier) {
            control._extend(i, false);
        } else {
            control._setOnly(i);
        }
    }
    function _clickAt(index: int, modifiers: int): void {
        control.forceActiveFocus(Qt.MouseFocusReason);
        control._mouseFocus = true;
        if (index < 0) {
            return;
        }
        control.currentIndex = index;
        if (!control._selectable) {
            return;
        }
        if (modifiers & Qt.ShiftModifier) {
            control._extend(index, (modifiers & Qt.ControlModifier) !== 0);
        } else if (modifiers & Qt.ControlModifier) {
            control._toggle(index);
        } else {
            control._setOnly(index);
        }
    }
    function _menuAt(index: int, x: real, y: real): void {
        const p = control.contentItem.mapToItem(control, x, y);
        control.contextMenuRequested(index, Qt.point(p.x, p.y));
    }
    function _menuAtCurrent(): void {
        const i = control.currentIndex;
        if (i < 0 || i >= control.count) {
            return;
        }
        // From the row's place: its delegate may not be made after a jump.
        const it = control.itemAtIndex(i);
        const p = it ? it.mapToItem(control, control.width / 2, it.height / 2) : control.contentItem.mapToItem(control, control.width / 2, i * control._rowH + control._rowH / 2);
        control.contextMenuRequested(i, Qt.point(p.x, Math.max(0, Math.min(control.height, p.y))));
    }
    function _move(delta: int): void {
        const i = control.currentIndex;
        const to = i + delta;
        if (!control.reorderable || i < 0 || to < 0 || to >= control.count) {
            return;
        }
        control._moved(i, to);
    }
    function _moved(from: int, to: int): void {
        control.moveRequested(from, to);
        control.currentIndex = to;
        if (control._selectable) {
            control._setOnly(to);
        }
    }
    // `role` of a delegate's model, or undefined; a plain string array has no roles.
    function _pick(model, role: string) {
        if (role.length > 0) {
            return model[role] ?? model.modelData?.[role];
        }
        return undefined;
    }
    // The text of any row, made or not, for type-ahead.
    function _textAt(i: int): string {
        const m = control.model;
        let v;
        if (m && typeof m.get === "function") {
            v = m.get(i)?.[control.textRole];
        } else if (m && typeof m.data === "function" && typeof m.index === "function") {
            v = m.data(m.index(i, 0), Qt.DisplayRole);
        } else if (m && typeof m.length === "number") {
            // A JS array reaches the view as an array-like list.
            v = m[i];
            if (v !== null && typeof v === "object") {
                v = v[control.textRole];
            }
        }
        return v === undefined || v === null ? "" : String(v);
    }
    function _typeAhead(ch: string): void {
        const first = control._typed.length === 0;
        control._typed += ch.toLowerCase();
        typeTimer.restart();
        // One letter again and again steps on; a longer word stays on a match.
        const start = control.currentIndex < 0 ? 0 : first || control._typed.length === 1 ? control.currentIndex + 1 : control.currentIndex;
        for (let n = 0; n < control.count; ++n) {
            const i = (start + n) % control.count;
            if (control._textAt(i).toLowerCase().startsWith(control._typed)) {
                control._moveTo(i, 0);
                return;
            }
        }
    }

    Timer {
        id: typeTimer
        interval: 500
        onTriggered: control._typed = ""
    }

    function _shiftSelection(first: int, delta: int, last: int): void {
        // delta > 0: rows inserted at `first`; delta < 0: rows first..last removed.
        const s = {};
        for (const k of Object.keys(control._sel)) {
            const n = Number(k);
            if (delta < 0 && n >= first && n <= last) {
                continue;
            }
            s[n >= first ? n + delta : n] = true;
        }
        control._sel = s;
        control._anchor = control._anchor >= first ? (delta < 0 && control._anchor <= last ? -1 : control._anchor + delta) : control._anchor;
        control._rev++;
    }
    onModelChanged: control.clearSelection()

    Connections {
        target: control._tracked ? control.model : null
        ignoreUnknownSignals: true
        function onRowsInserted(parent, first, last) {
            if (!parent.valid) {
                control._shiftSelection(first, last - first + 1, last);
            }
        }
        function onRowsRemoved(parent, first, last) {
            if (!parent.valid) {
                control._shiftSelection(first, -(last - first + 1), last);
            }
        }
        function onModelReset() {
            control.clearSelection();
        }
        function onRowsMoved() {
            control.clearSelection();
        }
        function onLayoutChanged() {
            control.clearSelection();
        }
    }

    onCountChanged: {
        // Rows that are gone drop out of the selection (a tracked model
        // shifts it itself, and does so before the count is final).
        if (control._tracked) {
            return;
        }
        let changed = false;
        for (const k of Object.keys(control._sel)) {
            if (Number(k) >= control.count) {
                delete control._sel[k];
                changed = true;
            }
        }
        if (control.count === 0) {
            control._anchor = -1;
        }
        if (changed) {
            control._rev++;
        }
    }
    onCurrentIndexChanged: {
        if (control.currentIndex >= 0 && control.currentIndex < control.count) {
            control.positionViewAtIndex(control.currentIndex, ListView.Contain);
        }
    }
    onActiveFocusChanged: {
        if (!control.activeFocus) {
            control._mouseFocus = false;
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 20
    implicitHeight: Kirigami.Units.gridUnit * 14
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    keyNavigationEnabled: false
    // An empty list has no row to show focus on.
    activeFocusOnTab: control.count > 0
    currentIndex: 0
    reuseItems: true
    highlightFollowsCurrentItem: false
    delegate: rowDelegate

    Accessible.role: Accessible.List
    Accessible.focusable: true

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
                    duration: AtlasStyle.durationShort
                }
            }
        }
        background: null
    }

    Keys.onPressed: event => {
        if (control._statusActive) {
            return;
        }
        control._mouseFocus = false;
        const mods = event.modifiers;
        const at = control.currentIndex;
        const page = Math.max(1, Math.floor(control.height / control._rowH) - 1);
        const plain = mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods & Qt.AltModifier && !(mods & (Qt.ControlModifier | Qt.MetaModifier))) {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                control._move(event.key === Qt.Key_Up ? -1 : 1);
                event.accepted = true;
            }
            return;
        }
        switch (event.key) {
        case Qt.Key_Up:
            control._moveTo(at < 0 ? control.count - 1 : at - 1, mods);
            break;
        case Qt.Key_Down:
            control._moveTo(at < 0 ? 0 : at + 1, mods);
            break;
        case Qt.Key_PageUp:
            control._moveTo(at < 0 ? control.count - 1 : at - page, mods);
            break;
        case Qt.Key_PageDown:
            control._moveTo(at < 0 ? 0 : at + page, mods);
            break;
        case Qt.Key_Home:
            control._moveTo(0, mods);
            break;
        case Qt.Key_End:
            control._moveTo(control.count - 1, mods);
            break;
        case Qt.Key_A:
            if (mods & Qt.ControlModifier) {
                control.selectAll();
                break;
            }
            if (!control._typeKey(event)) {
                return;
            }
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (!event.isAutoRepeat && at >= 0 && at < control.count) {
                control.activated(at);
            }
            break;
        case Qt.Key_Space:
            if (control._typed.length > 0) {
                control._typeAhead(" ");
            } else if (at >= 0 && at < control.count && control._selectable) {
                control._toggle(at);
            }
            break;
        case Qt.Key_F10: // Shift+F10 is the Menu key's twin
            if (!(mods & Qt.ShiftModifier)) {
                return;
            }
            control._menuAtCurrent();
            break;
        case Qt.Key_Menu:
            control._menuAtCurrent();
            break;
        default:
            if (plain || !control._typeKey(event)) {
                return;
            }
        }
        event.accepted = true;
    }
    function _typeKey(event): bool {
        const t = event.text;
        if (t.length !== 1 || t < " " || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            return false;
        }
        control._typeAhead(t);
        return true;
    }

    // Input for every row, made by the view so a custom delegate gets it too.
    // These are children of the content item: positions are content positions.
    HoverHandler {
        enabled: !control._statusActive
        onPointChanged: control._hover = control.indexAt(point.position.x, point.position.y)
        onHoveredChanged: {
            if (!hovered) {
                control._hover = -1;
            }
        }
    }
    TapHandler {
        enabled: !control._statusActive
        acceptedModifiers: Qt.NoModifier
        onTapped: point => control._clickAt(control.indexAt(point.position.x, point.position.y), 0)
        onDoubleTapped: point => {
            const i = control.indexAt(point.position.x, point.position.y);
            if (i >= 0) {
                control.activated(i);
            }
        }
    }
    TapHandler {
        enabled: !control._statusActive
        acceptedModifiers: Qt.ControlModifier
        onTapped: point => control._clickAt(control.indexAt(point.position.x, point.position.y), Qt.ControlModifier)
    }
    TapHandler {
        enabled: !control._statusActive
        acceptedModifiers: Qt.ShiftModifier
        onTapped: point => control._clickAt(control.indexAt(point.position.x, point.position.y), Qt.ShiftModifier)
    }
    TapHandler {
        enabled: !control._statusActive
        acceptedModifiers: Qt.ControlModifier | Qt.ShiftModifier
        onTapped: point => control._clickAt(control.indexAt(point.position.x, point.position.y), Qt.ControlModifier | Qt.ShiftModifier)
    }
    TapHandler {
        enabled: !control._statusActive
        acceptedButtons: Qt.RightButton
        acceptedModifiers: Qt.KeyboardModifierMask
        onTapped: point => {
            const i = control.indexAt(point.position.x, point.position.y);
            control.forceActiveFocus(Qt.MouseFocusReason);
            control._mouseFocus = true;
            if (i < 0) {
                return;
            }
            control.currentIndex = i;
            if (control._selectable && !control.isSelected(i)) {
                control._setOnly(i);
            }
            control._menuAt(i, point.position.x, point.position.y);
        }
    }

    // Where a dragged row would land.
    Rectangle {
        parent: control.contentItem
        visible: control._dragFrom >= 0 && control._dropIndex !== control._dragFrom
        x: AtlasStyle.spacing
        width: control.contentItem.width - 2 * AtlasStyle.spacing
        y: {
            const it = control.itemAtIndex(control._dropIndex);
            const below = control._dropIndex > control._dragFrom;
            if (it) {
                return (below ? it.y + it.height : it.y) - 1;
            }
            return (below ? control._dropIndex + 1 : control._dropIndex) * control._rowH - 1;
        }
        height: 2
        radius: 1
        color: AtlasStyle.accent
        z: 3
        Accessible.ignored: true
    }

    // The rows are hidden while a status shows; the header stays.
    readonly property bool _statusActive: control.status !== AtlasStatus.Ready
    on_StatusActiveChanged: control._hookRows()
    // Rows are hidden by a Binding on each one's `visible`, so an app's own
    // `visible` binding on a delegate is kept and comes back with Ready.
    property var _hooked: null
    Component {
        id: hiderComp
        Binding {
            property: "visible"
            value: false
            restoreMode: Binding.RestoreBindingOrValue
        }
    }
    function _hookRows(): void {
        if (!control.contentItem) {
            return;
        }
        if (control._hooked === null) {
            control._hooked = new WeakSet();
        }
        const kids = control.contentItem.children;
        for (let i = 0; i < kids.length; ++i) {
            const k = kids[i];
            if (k.ListView.view === control && !control._hooked.has(k)) {
                control._hooked.add(k);
                hiderComp.createObject(k, {
                    "target": k,
                    "when": Qt.binding(() => control._statusActive)
                });
            }
        }
    }
    Connections {
        target: control.contentItem
        enabled: control._statusActive
        function onChildrenChanged() {
            control._hookRows();
            // The view's own bookkeeping of a new row may come a moment later.
            Qt.callLater(control._hookRows);
        }
    }
    AtlasStatusView {
        parent: control
        x: 0
        y: control.headerItem ? Math.max(0, control.headerItem.y + control.headerItem.height - control.contentY) : 0
        width: control.width
        height: Math.max(0, control.height - y)
        z: 2
        status: control.status
        title: control.statusTitle
        text: control.statusText
        symbol: control.statusSymbol
        action: control.statusAction
    }

    AtlasEmptyState {
        parent: control
        anchors.fill: parent
        visible: control.status === AtlasStatus.Ready && control.count === 0 && (control.placeholderText.length > 0 || control.placeholderSymbol !== 0)
        symbol: control.placeholderSymbol
        title: control.placeholderText
    }

    Component {
        id: rowDelegate
        Item {
            id: row
            required property int index
            required property var model
            readonly property bool current: ListView.isCurrentItem
            readonly property bool selected: control.isSelected(row.index)
            readonly property string title: {
                const t = control._pick(row.model, control.textRole);
                return t !== undefined ? String(t) : typeof row.model.modelData === "string" ? row.model.modelData : "";
            }
            readonly property string subtitle: String(control._pick(row.model, control.subtitleRole) ?? "")
            readonly property int symbolValue: Number(control._pick(row.model, control.symbolRole) ?? 0)
            readonly property bool dragging: control._dragFrom === row.index

            width: control.width
            height: control._rowH
            z: row.dragging ? 2 : 0
            transform: Translate {
                y: row.dragging ? control._dragDelta : 0
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: row.subtitle.length > 0 ? row.title + ", " + row.subtitle : row.title
            Accessible.selected: row.selected
            Accessible.focusable: true
            Accessible.onPressAction: control.activated(row.index)

            Rectangle {
                id: pill
                anchors.fill: parent
                anchors.leftMargin: AtlasStyle.spacing
                anchors.rightMargin: AtlasStyle.spacing
                anchors.topMargin: AtlasStyle.spacingXSmall
                anchors.bottomMargin: AtlasStyle.spacingXSmall
                radius: AtlasStyle.radiusSmall
                color: row.dragging ? AtlasStyle.selection : row.selected ? (control.activeFocus ? AtlasStyle.selection : AtlasStyle.selectionInactive) : control._hover === row.index ? AtlasStyle.hover : "transparent"
                AtlasFocusRing {
                    gap: 1
                    radius: pill.radius + gap
                    shown: row.current && control.activeFocus && !control._mouseFocus
                }
            }

            RowLayout {
                anchors.fill: pill
                anchors.leftMargin: AtlasStyle.spacing
                anchors.rightMargin: AtlasStyle.spacing
                spacing: AtlasStyle.spacing

                Item {
                    id: grip
                    visible: control.reorderable
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    Accessible.ignored: true
                    Symbol {
                        anchors.centerIn: parent
                        icon: Symbols.DragIndicator
                        size: Kirigami.Units.iconSizes.smallMedium
                        color: AtlasStyle.textMuted
                    }
                    DragHandler {
                        target: null
                        xAxis.enabled: false
                        cursorShape: Qt.SizeVerCursor
                        onActiveChanged: {
                            if (active) {
                                control.forceActiveFocus(Qt.MouseFocusReason);
                                control._mouseFocus = true;
                                control.currentIndex = row.index;
                                control._dragDelta = 0;
                                control._dragFrom = row.index;
                            } else {
                                const from = control._dragFrom;
                                const to = control._dropIndex;
                                control._dragFrom = -1;
                                control._dragDelta = 0;
                                if (from >= 0 && to >= 0 && to !== from) {
                                    control._moved(from, to);
                                }
                            }
                        }
                        onActiveTranslationChanged: {
                            if (active) {
                                control._dragDelta = activeTranslation.y;
                            }
                        }
                    }
                }
                Loader {
                    active: row.symbolValue !== 0
                    visible: active
                    sourceComponent: Symbol {
                        icon: row.symbolValue
                        size: Kirigami.Units.iconSizes.smallMedium
                        color: AtlasStyle.accent
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: row.title
                        font.family: AtlasStyle.fontFamily
                        font.pointSize: AtlasStyle.fontSizeBody
                        color: AtlasStyle.text
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        Accessible.ignored: true // the row carries the name
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: row.subtitle.length > 0
                        text: row.subtitle
                        font: control._captionFont
                        color: AtlasStyle.textMuted
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        Accessible.ignored: true
                    }
                }
            }
        }
    }
}
