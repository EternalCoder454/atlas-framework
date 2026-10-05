pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// A scrolling sidebar column for SidebarItem and SidebarGroup entries. Put
// them inside (give each Layout.fillWidth: true), or set `model` and a
// `delegate` whose root is a SidebarItem or SidebarGroup. It
//  - scrolls the selected entry into view when `currentIndex` or an entry's
//    `selected` changes, and any entry that gets keyboard focus;
//  - filters entries by title with `filterText` (a case-insensitive
//    "contains"; a group stays while it or one of its entries matches), with a
//    SearchField on top when `showFilter` is true. Filtering and `compact`
//    set the entries' `visible` and `compact` themselves, so don't bind those;
//  - shows `placeholderText` and `placeholderSymbol` when nothing is visible;
//  - emits `contextMenuRequested(item, pos)` for a right click and for the Menu
//    key or Shift+F10 on the focused entry (`item` is the SidebarItem, or the
//    SidebarGroup for its header; `pos` is in the sidebar's coordinates);
//  - with `dropEnabled`, highlights the entry a drag hovers over and emits
//    `dropped(item, drop)`;
//  - puts the keyboard focus on the selected entry when you Tab into it.
// `currentIndex` counts the SidebarItems in order (sub-entries included, group
// headers not); -1 means none. Its background follows AtlasWindow.sidebarColor().
// Bind `compact` to the window's `sidebarCollapsed`:
//
//   AtlasSidebar {
//       width: compact ? 64 : 240
//       compact: window.sidebarCollapsed
//       showFilter: true
//       placeholderText: qsTr("No matches")
//       onContextMenuRequested: (item, pos) => menu.popup(item)
//       SidebarItem { Layout.fillWidth: true; text: qsTr("Overview"); symbol: Symbols.Home; selected: true }
//       SidebarGroup {
//           text: qsTr("Disk")
//           SidebarItem { sub: true; Layout.fillWidth: true; text: qsTr("sda") }
//       }
//   }
FocusScope {
    id: control

    default property alias content: column.data
    property alias model: repeater.model
    property alias delegate: repeater.delegate
    property int currentIndex: -1
    property string filterText
    property bool showFilter: false
    property string placeholderText
    property int placeholderSymbol: 0
    property bool compact: false
    property bool dropEnabled: false
    // Inner margin round the entries.
    property int padding: AtlasStyle.spacingSmall
    // Gap between entries.
    property int spacing: AtlasStyle.spacingXSmall
    // The base colour, made see-through by the window's blur like any sidebar.
    property color baseColor: AtlasStyle.base

    signal contextMenuRequested(Item item, point pos)
    signal dropped(Item item, var drop)

    implicitWidth: compact ? Kirigami.Units.gridUnit * 4 : Kirigami.Units.gridUnit * 14
    implicitHeight: Kirigami.Units.gridUnit * 20

    Accessible.role: Accessible.List
    Accessible.name: qsTr("Sidebar")

    QtObject {
        id: priv
        property var watched: []
        property bool filtered: false
        property int visibleCount: 1
        property var dropItem: null
        // The entry (or group header) the shared selection highlight sits on.
        property Item target: null
        // How far the highlight still lags behind the target, in px. A selection
        // change sets it to the old position minus the new one and springs it
        // back to 0; layout changes (groups opening, filtering, text scale) move
        // the highlight with the target directly, with no spring.
        property real slideY: 0
        property real slideHeight: 0
        // Off while the lag is set, on while it springs back to 0.
        property bool springing: false
        Behavior on slideY {
            enabled: priv.springing && !AtlasStyle.reducedMotion
            AtlasSpringAnimation {
                expressive: true
            }
        }
        Behavior on slideHeight {
            enabled: priv.springing && !AtlasStyle.reducedMotion
            AtlasSpringAnimation {
                expressive: true
            }
        }
        readonly property bool hasTarget: target !== null && target.visible && target.height > 0
        // The target's rectangle in column coordinates. Sums the positions up
        // the parent chain, so it follows any layout change above the target.
        readonly property rect targetRect: {
            const t = target;
            if (!t) {
                return Qt.rect(0, 0, 0, 0);
            }
            let x = 0;
            let y = 0;
            for (let it = t; it && it !== column; it = it.parent) {
                x += it.x;
                y += it.y;
            }
            return Qt.rect(x, y, t.width, t.height);
        }
        // Moves the highlight to the selected entry. Moving the selection
        // deselects the old entry before it selects the new one, so "nothing
        // selected" is only believed once the change has settled.
        function updateTarget() {
            const found = findSelected();
            if (found === null) {
                if (target !== null) {
                    Qt.callLater(clearTarget);
                }
                return;
            }
            setTarget(found);
        }
        function clearTarget() {
            if (findSelected() === null && target !== null) {
                springing = false;
                slideY = 0;
                slideHeight = 0;
                target = null;
            }
        }
        function findSelected(): var {
            for (const e of entries()) {
                const c = isGroup(e) ? e._header : e;
                if (c.selected === true && (isGroup(e) || e.visible)) {
                    return c;
                }
            }
            return null;
        }
        function setTarget(found: var) {
            if (found === target) {
                return;
            }
            // Slide only from a highlight that is showing and laid out.
            const from = hasTarget && control.visible && highlightReady;
            const oldY = selectionHighlight.y;
            const oldH = selectionHighlight.height;
            springing = false;
            slideY = 0;
            slideHeight = 0;
            target = found;
            if (from && hasTarget) {
                slideY = oldY - (targetRect.y + column.y);
                slideHeight = oldH - targetRect.height;
                springing = true;
                slideY = 0;
                slideHeight = 0;
            }
        }
        // True once the first layout is done, so the first selection never slides.
        property bool highlightReady: false
        readonly property var win: control.Window.window
        // A leaf entry (SidebarItem) or a group (SidebarGroup).
        function isGroup(c: var): bool {
            return c && c._entries !== undefined;
        }
        function isLeaf(c: var): bool {
            return c && c._entries === undefined && typeof c.text === "string" && c.selected !== undefined;
        }
        // Every entry: leaves, groups, and a group's leaves, in order.
        function entries(): var {
            const out = [];
            const top = column.children;
            for (let i = 0; i < top.length; ++i) {
                const c = top[i];
                if (isGroup(c)) {
                    out.push(c);
                    const subs = c._entries.children;
                    for (let j = 0; j < subs.length; ++j) {
                        if (isLeaf(subs[j])) {
                            out.push(subs[j]);
                        }
                    }
                } else if (isLeaf(c)) {
                    out.push(c);
                }
            }
            return out;
        }
        function matches(c: var, f: string): bool {
            return f.length === 0 || c.text.toLowerCase().indexOf(f) >= 0;
        }
        function rescan() {
            const all = entries();
            watched = watched.filter(w => w !== null && w !== undefined);
            for (const e of all) {
                if (watched.indexOf(e) < 0) {
                    watch(e);
                }
                if (control.compact !== e.compact) {
                    e.compact = control.compact;
                }
                const c = isGroup(e) ? e._header : e;
                if (c._sharedSelection === false) {
                    c._sharedSelection = true;
                }
            }
            applyFilter();
            updateTarget();
            const sel = selectedItem();
            if (sel) {
                reveal(sel);
            }
        }
        function watch(e: var) {
            watched.push(e);
            if (isGroup(e)) {
                e._entries.childrenChanged.connect(schedule);
                e._header.selectedChanged.connect(updateTarget);
                e.expandedChanged.connect(schedule);
                return;
            }
            e.selectedChanged.connect(() => {
                updateTarget();
                if (e.selected) {
                    reveal(e);
                }
            });
            e.visibleChanged.connect(updateTarget);
            e.activeFocusChanged.connect(() => {
                if (e.activeFocus) {
                    reveal(e);
                }
            });
        }
        function applyFilter() {
            const f = control.filterText.trim().toLowerCase();
            if (f.length === 0 && !filtered) {
                visibleCount = 1;
                return;
            }
            filtered = f.length > 0;
            let shown = 0;
            const top = column.children;
            for (let i = 0; i < top.length; ++i) {
                const c = top[i];
                if (isGroup(c)) {
                    const own = matches(c, f);
                    const subs = c._entries.children;
                    let any = false;
                    for (let j = 0; j < subs.length; ++j) {
                        if (isLeaf(subs[j])) {
                            const m = own || matches(subs[j], f);
                            subs[j].visible = m;
                            any = any || (m && f.length > 0 && matches(subs[j], f));
                        }
                    }
                    if (any && !own) {
                        c.expanded = true;
                    }
                    c.visible = own || any || f.length === 0;
                    shown += c.visible ? 1 : 0;
                } else if (isLeaf(c)) {
                    c.visible = matches(c, f);
                    shown += c.visible ? 1 : 0;
                }
            }
            visibleCount = shown;
        }
        function leaves(): var {
            return entries().filter(e => isLeaf(e));
        }
        function selectedItem(): var {
            const l = leaves();
            if (control.currentIndex >= 0 && control.currentIndex < l.length) {
                return l[control.currentIndex];
            }
            for (const e of l) {
                if (e.selected === true) {
                    return e;
                }
            }
            return null;
        }
        // Scrolls the entry into the viewport; a hidden one is left alone.
        function reveal(e: var) {
            if (!e || !e.visible || e.height <= 0) {
                return;
            }
            const y = e.mapToItem(column, 0, 0).y;
            const m = control.padding;
            const maxY = Math.max(0, flick.contentHeight - flick.height);
            let target = flick.contentY;
            if (y - m < target) {
                target = y - m;
            } else if (y + e.height + m > target + flick.height) {
                target = y + e.height + m - flick.height;
            }
            flick.contentY = Math.max(0, Math.min(maxY, target));
        }
        // The entry (or group, for its header) under a point in column coordinates.
        function entryAt(p: point): var {
            for (const e of entries()) {
                if (!e.visible) {
                    continue;
                }
                const target = isGroup(e) ? e._header : e;
                const r = target.mapToItem(column, 0, 0);
                if (p.x >= r.x && p.x < r.x + target.width && p.y >= r.y && p.y < r.y + target.height) {
                    return e;
                }
            }
            return null;
        }
        // The entry that holds the keyboard focus, or null.
        function focusedEntry(): var {
            let it = win ? win.activeFocusItem : null;
            while (it && it !== control) {
                if (isLeaf(it)) {
                    return it;
                }
                if (isGroup(it.parent) && it.parent._header === it) {
                    return it.parent;
                }
                it = it.parent;
            }
            return null;
        }
        onDropItemChanged: {
            if (!dropItem) {
                return;
            }
            const t = isGroup(dropItem) ? dropItem._header : dropItem;
            const r = t.mapToItem(flick.contentItem, 0, 0);
            dropHighlight.x = r.x;
            dropHighlight.y = r.y;
            dropHighlight.width = t.width;
            dropHighlight.height = t.height;
        }
        function schedule() {
            Qt.callLater(rescan);
        }
        function nextFocus(forward: bool) {
            const n = focusStop.nextItemInFocusChain(forward);
            if (n && n !== focusStop) {
                n.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
            }
        }
    }

    onFilterTextChanged: priv.schedule()
    onCurrentIndexChanged: Qt.callLater(() => priv.reveal(priv.selectedItem()))
    onCompactChanged: {
        for (const e of priv.entries()) {
            e.compact = control.compact;
        }
    }
    Component.onCompleted: {
        priv.rescan();
        Qt.callLater(() => priv.highlightReady = true);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            const e = priv.focusedEntry();
            if (e) {
                const t = priv.isGroup(e) ? e._header : e;
                control.contextMenuRequested(e, t.mapToItem(control, t.width / 2, t.height / 2));
                event.accepted = true;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: control.win && typeof control.win.sidebarColor === "function" ? control.win.sidebarColor(control.baseColor) : Qt.alpha(control.baseColor, Appearance.effective ? 0.94 : 1)
    }
    readonly property var win: priv.win

    // Tab lands here first, then moves on to the selected entry. Going back
    // (Shift+Tab) it just passes through.
    QQC2.Control {
        id: focusStop
        width: 0
        height: 0
        focusPolicy: Qt.TabFocus
        Accessible.role: Accessible.Grouping
        Accessible.name: qsTr("Sidebar entries")
        onActiveFocusChanged: {
            if (!activeFocus) {
                return;
            }
            if (focusReason === Qt.BacktabFocusReason) {
                priv.nextFocus(false);
                return;
            }
            const sel = priv.selectedItem();
            if (sel && sel.visible && sel.enabled && sel.activeFocusOnTab !== false) {
                sel.forceActiveFocus(Qt.TabFocusReason);
            } else {
                priv.nextFocus(true);
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SearchField {
            id: search
            Layout.fillWidth: true
            Layout.margins: control.padding
            visible: control.showFilter
            onQueryChanged: control.filterText = search.query
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: column.implicitHeight + control.padding * 2
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

            ColumnLayout {
                id: column
                x: control.padding
                y: control.padding
                width: flick.width - control.padding * 2
                spacing: control.spacing
                onChildrenChanged: priv.schedule()

                Repeater {
                    id: repeater
                }
            }

            // The selection highlight: one rectangle that slides to the selected
            // entry (a spring with a small overshoot), behind the entries.
            Rectangle {
                id: selectionHighlight
                z: -1
                visible: priv.hasTarget
                x: priv.targetRect.x + column.x
                y: priv.targetRect.y + column.y + priv.slideY
                width: priv.targetRect.width
                height: Math.max(0, priv.targetRect.height + priv.slideHeight)
                radius: AtlasStyle.radiusSmall
                color: AtlasStyle.selection
            }

            Rectangle {
                id: dropHighlight
                visible: control.dropEnabled && priv.dropItem !== null
                z: 2
                radius: AtlasStyle.radiusSmall
                color: AtlasStyle.selection
                border.width: 2
                border.color: AtlasStyle.accent
            }
        }
    }

    AtlasEmptyState {
        anchors.fill: parent
        anchors.topMargin: control.showFilter ? search.height + control.padding * 2 : 0
        visible: priv.visibleCount === 0 && (control.placeholderText.length > 0 || control.placeholderSymbol !== 0)
        symbol: control.placeholderSymbol
        title: control.compact ? "" : control.placeholderText
        Accessible.name: control.placeholderText
    }

    DropArea {
        anchors.fill: parent
        enabled: control.dropEnabled
        onEntered: drag => {
            priv.dropItem = priv.entryAt(control.mapToItem(column, drag.x, drag.y));
        }
        onPositionChanged: drag => {
            priv.dropItem = priv.entryAt(control.mapToItem(column, drag.x, drag.y));
        }
        onExited: priv.dropItem = null
        onDropped: drop => {
            const item = priv.entryAt(control.mapToItem(column, drop.x, drop.y));
            priv.dropItem = null;
            if (item) {
                control.dropped(item, drop);
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: (eventPoint, button) => {
            const e = priv.entryAt(control.mapToItem(column, eventPoint.position.x, eventPoint.position.y));
            if (e) {
                control.contextMenuRequested(e, eventPoint.position);
            }
        }
    }
}
