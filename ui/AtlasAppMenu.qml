pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Qt.labs.platform as Platform

// The app's menus, for the header (put it in AtlasHeaderBar.leading). With a
// global menu on the desktop (Plasma's app menu widget; see
// AtlasWindowChrome.globalMenu) the menus are exported through DBusMenu and
// this item shows nothing. Without one, it is a menu button in the header
// that opens the same menus as submenus.
//
// `menus` is a list of groups, each `{title, actions}`. An entry of `actions`
// is an AtlasAction or Qt Action, `null` for a separator, `{action, shortcut}`
// for an action with the key sequence to export, `{title, actions}` for a
// nested submenu (up to eight levels), or `{id, title, model, textRole, lead,
// trail, emptyText}` for a submenu whose rows come from a model, between the
// `lead` and `trail` lists. Choosing such a row emits modelActivated():
//
//   AtlasHeaderBar {
//       leading: AtlasAppMenu {
//           menus: [
//               { title: qsTr("File"), actions: [openAction, null, quitAction] },
//               { title: qsTr("Edit"), actions: [undoAction, redoAction] }
//           ]
//       }
//   }
//
// With a `collection` (AtlasActionCollection) and no `menus`, the menus are
// the collection's actions grouped by `category`, in the order each category
// first appears; `menus`, when it is not empty, wins.
//
// The native export is made only when a global menu is there, so a desktop
// without one never creates a menu bar of its own. Detection is an
// asynchronous D-Bus check with a timeout: until it answers, the button shows.
Item {
    id: root

    // [{title: string, actions: [Action | null | {action, shortcut} | {title, actions} | {id, title, model, ...}]}]
    property var menus: []
    // The app's AtlasActionCollection: its actions make the menus when `menus`
    // is empty.
    property AtlasActionCollection collection: null
    // The name of the menu button for screen readers and its tooltip.
    property string accessibleName: qsTr("Main menu")
    // Shows each `{action, shortcut}` entry's shortcut in the global menu (and
    // in the button's rows). The action must then leave its own `shortcut`
    // empty, or the key has two owners and neither fires.
    property bool exportShortcuts: false

    // A row of a model-driven submenu was chosen.
    signal modelActivated(string id, var modelData, int index)

    // What the menus are made of: `menus`, else the collection's actions by category.
    readonly property var _menus: root.menus.length > 0 || !root.collection ? root.menus : root._fromCollection(root.collection)
    function _fromCollection(c): var {
        const general = qsTr("General");
        const groups = [];
        const index = {};
        const all = c._all ?? [];
        for (let i = 0; i < all.length; ++i) {
            const a = all[i];
            if (!a) {
                continue;
            }
            const title = a.category && a.category.length > 0 ? a.category : general;
            if (!Object.prototype.hasOwnProperty.call(index, title)) {
                index[title] = groups.length;
                groups.push({
                    "title": title,
                    "actions": []
                });
            }
            groups[index[title]].actions.push(a);
        }
        return groups;
    }

    // Tests: true builds the native export whatever the desktop has.
    property bool _forceNative: false
    readonly property bool _native: _forceNative || AtlasWindowChrome.globalMenu
    readonly property var _nativeBar: nativeLoader.item
    // Tests: true shows the button whatever the desktop has.
    property bool _forceButton: false
    readonly property bool _showButton: _forceButton || !_native
    // Tests: the button's root menu.
    readonly property ContextMenu _menu: popup
    readonly property int _maxDepth: 8

    // Opens the button's menu (no effect with a global menu).
    function open() {
        if (root._showButton) {
            button.clicked();
        }
    }

    visible: _showButton && _menus.length > 0
    implicitWidth: visible ? button.implicitWidth : 0
    implicitHeight: visible ? button.implicitHeight : 0

    // ---- Shared by the button's menus and the native export -------------

    property bool _warned: false
    property bool _warnedShape: false
    // Tests: how many native menu objects exist.
    property int _alive: 0
    function _isAction(e): bool {
        return e !== null && e !== undefined && typeof e.trigger === "function";
    }
    function _actionEnabled(e): bool {
        const a = _isAction(e) ? e : (e && _isAction(e.action) ? e.action : null);
        return a !== null && a.enabled !== false;
    }
    function _anyEnabled(list): bool {
        for (const e of list ?? []) {
            if (_actionEnabled(e)) {
                return true;
            }
        }
        return false;
    }
    // The rows of a model, read once: a throwaway Instantiator gives modelData
    // for any kind of model (a list of strings, a ListModel, a C++ model).
    function _plain(md, always): var {
        // An Action row outlives the reader and stays live. Any other QObject
        // may be owned by the reader's delegate, and a ListModel row is a view
        // of the model: those are copied.
        if (always !== true && md !== null && typeof md === "object" && typeof md.trigger === "function") {
            return md;
        }
        // What the model hands out is live or dies with the reader: keep a plain copy.
        if (md !== null && typeof md === "object" && !Array.isArray(md)) {
            const copy = {};
            for (const k in md) {
                copy[k] = md[k];
            }
            return copy;
        }
        return md;
    }
    function _rowsOf(model): var {
        const rows = [];
        if (model === null || model === undefined) {
            return rows;
        }
        // A ListModel gives objects with every role.
        if (typeof model.get === "function" && typeof model.count === "number") {
            for (let i = 0; i < model.count; ++i) {
                rows.push(_plain(model.get(i), true));
            }
            return rows;
        }
        const reader = readerComponent.createObject(null, {
            model: model
        });
        if (!reader) {
            return rows;
        }
        try {
            // A model that is not iterable has no rows.
            const n = typeof reader.count === "number" ? reader.count : 0;
            for (let i = 0; i < n; ++i) {
                const d = reader.objectAt(i);
                rows.push(d ? _plain(d.modelData) : undefined);
            }
        } finally {
            reader.destroy();
        }
        return rows;
    }
    function _rowText(md, textRole): string {
        if (typeof md === "string") {
            return md;
        }
        if (md !== null && md !== undefined && typeof md === "object" && textRole && md[textRole] !== undefined) {
            return String(md[textRole]);
        }
        return md === null || md === undefined ? "" : String(md);
    }
    function _shortcutOf(e): var {
        return root.exportShortcuts && e.shortcut !== undefined && e.shortcut !== null ? e.shortcut : undefined;
    }
    // Fills `menu` (at nesting level `depth`) from `entries` through `kit`:
    // kit.sep(), kit.action(action, shortcut), kit.row(id, text, data, index,
    // enabled), kit.sub(title), kit.add(menu, item), kit.addSub(menu, sub, enabled).
    function _fill(kit, menu, entries, depth): void {
        for (const e of entries ?? []) {
            if (e === null || e === undefined) {
                kit.add(menu, kit.sep());
            } else if (_isAction(e) && e.menu) {
                // An action with a menu is a submenu, with the same rows.
                if (depth + 1 > root._maxDepth) {
                    _tooDeep();
                    continue;
                }
                const sub = kit.sub(String(e.text ?? "").replace(/&(.)/g, "$1"));
                _mirror(kit, sub, e.menu, depth + 1);
                kit.addSub(menu, sub, e.enabled !== false);
            } else if (_isAction(e)) {
                kit.add(menu, kit.action(e, undefined));
            } else if (_isAction(e.action)) {
                kit.add(menu, kit.action(e.action, _shortcutOf(e)));
            } else if (typeof e === "object" && ("model" in e || "lead" in e || "trail" in e)) {
                if (depth + 1 > root._maxDepth) {
                    _tooDeep();
                    continue;
                }
                const sub = kit.sub(String(e.title ?? ""));
                const rec = kit.begin ? kit.begin(sub, e, depth + 1) : null;
                let rows = 0;
                try {
                    rows = _fillModel(kit, sub, e, depth + 1);
                } finally {
                    if (kit.end) {
                        kit.end(rec);
                    }
                }
                kit.addSub(menu, sub, rows > 0 || _anyEnabled(e.lead) || _anyEnabled(e.trail));
            } else if (e.actions !== undefined) {
                if (depth + 1 > root._maxDepth) {
                    _tooDeep();
                    continue;
                }
                const sub = kit.sub(String(e.title ?? ""));
                _fill(kit, sub, e.actions, depth + 1);
                kit.addSub(menu, sub, true);
            } else if (!_warnedShape) {
                _warnedShape = true;
                console.warn("AtlasAppMenu: an entry that is not an action, null, {action}, {title, actions} or {title, model} is ignored");
            }
        }
    }
    // Copies the rows of an app's own menu (an AtlasAction.menu): its actions,
    // separators, plain items and submenus.
    function _mirror(kit, sub, m, depth): void {
        for (let i = 0; i < m.count; ++i) {
            const inner = m.menuAt(i);
            if (inner) {
                if (depth + 1 > root._maxDepth) {
                    _tooDeep();
                    continue;
                }
                const copy = kit.sub(String(inner.title ?? ""));
                _mirror(kit, copy, inner, depth + 1);
                kit.addSub(sub, copy, true);
                continue;
            }
            const it = m.itemAt(i);
            if (!it || it.text === undefined) {
                kit.add(sub, kit.sep());
            } else if (it.action) {
                kit.add(sub, kit.action(it.action, undefined));
            } else {
                kit.add(sub, kit.call(String(it.text), it.enabled, () => it.triggered()));
            }
        }
    }
    // The lead actions, the rows and the trail actions; returns the row count.
    function _fillModel(kit, sub, e, depth): int {
        _fill(kit, sub, e.lead, depth);
        const rows = _rowsOf(e.model);
        if (rows.length === 0 && e.emptyText !== undefined && String(e.emptyText).length > 0) {
            kit.add(sub, kit.row("", String(e.emptyText), undefined, -1, false));
        }
        for (let i = 0; i < rows.length; ++i) {
            const item = kit.row(String(e.id ?? ""), _rowText(rows[i], e.textRole), rows[i], i, true);
            _follow(item, rows[i], e.textRole);
            kit.add(sub, item);
        }
        _fill(kit, sub, e.trail, depth);
        return rows.length;
    }
    // A row that is an Action follows it: text, enabled and checked.
    function _follow(item, md, textRole): void {
        if (!item || md === null || md === undefined || typeof md !== "object" || typeof md.trigger !== "function") {
            return;
        }
        item.text = Qt.binding(() => root._rowText(md, textRole));
        item.enabled = Qt.binding(() => md.enabled !== false);
        if (md.checkable !== undefined) {
            item.checkable = Qt.binding(() => md.checkable === true);
            item.checked = Qt.binding(() => md.checked === true);
        }
    }
    // A checkable row toggles itself when chosen, which breaks the binding;
    // choosing only emits modelActivated, so the Action decides.
    function _refollow(item): void {
        const md = item.rowData;
        if (md !== null && typeof md === "object" && typeof md.trigger === "function" && md.checkable !== undefined) {
            item.checked = Qt.binding(() => md.checked === true);
        }
    }
    function _tooDeep(): void {
        if (!_warned) {
            _warned = true;
            console.warn("AtlasAppMenu: submenus nest at most " + _maxDepth + " levels; deeper ones are ignored");
        }
    }

    Component {
        id: readerComponent
        Instantiator {
            delegate: QtObject {
                required property var modelData
            }
        }
    }

    // ---- The button and its menus ----------------------------------------

    ToolbarButton {
        id: button
        anchors.fill: parent
        visible: root.visible
        focusable: true
        symbol: Symbols.Menu
        text: root.accessibleName
        Accessible.role: Accessible.ButtonMenu
        Accessible.name: root.accessibleName
        onClicked: popup.popup(button, 0, button.height)
    }

    ContextMenu {
        id: popup
        // The rows of a model come from the model as it is when the menu opens;
        // a change while it is open takes effect when it closes.
        onAboutToShow: root._rebuildButton()
    }
    Component {
        id: itemComponent
        ContextMenuItem {}
    }
    Component {
        id: separatorComponent
        ContextMenuSeparator {}
    }
    Component {
        id: rowComponent
        ContextMenuItem {
            id: row
            property string rowId
            property var rowData
            property int rowIndex: -1
            onTriggered: {
                root._refollow(row);
                root.modelActivated(row.rowId, row.rowData, row.rowIndex);
            }
        }
    }
    Component {
        id: callComponent
        ContextMenuItem {
            id: call
            property var fn
            onTriggered: call.fn()
        }
    }
    Component {
        id: subComponent
        ContextMenu {}
    }

    readonly property var _ctxKit: ({
            sep: () => separatorComponent.createObject(root),
            action: (act, sc) => itemComponent.createObject(root, sc !== undefined ? {
                action: act,
                shortcutText: AtlasShortcuts.readable(sc)
            } : {
                action: act
            }),
            row: (id, text, data, index, enabled) => rowComponent.createObject(root, {
                text: text,
                enabled: enabled,
                rowId: id,
                rowData: data,
                rowIndex: index
            }),
            call: (text, enabled, fn) => callComponent.createObject(root, {
                text: text,
                enabled: enabled,
                fn: fn
            }),
            sub: title => subComponent.createObject(root, {
                title: title
            }),
            add: (m, item) => m.addItem(item),
            addSub: (m, sub, enabled) => {
                m.addMenu(sub);
                const entry = m.itemAt(m.count - 1);
                if (entry) {
                    entry.enabled = enabled;
                }
            }
        })

    // Empties a menu and destroys what this item made in it. (They are made
    // with `root` as their parent: with none, the garbage collector would take
    // a menu that only the menu above it points to.)
    function _clearMenu(m): void {
        while (m.count > 0) {
            const sub = m.menuAt(0);
            if (sub) {
                _clearMenu(sub);
                m.takeMenu(0);
                sub.destroy();
                continue;
            }
            const item = m.takeItem(0);
            if (item) {
                item.destroy();
            }
        }
    }
    function _rebuildButton(): void {
        _warned = false;
        _warnedShape = false;
        _clearMenu(popup);
        if (!_showButton) {
            return;
        }
        for (const g of root._menus ?? []) {
            if (!g || g.actions === undefined) {
                continue;
            }
            const sub = _ctxKit.sub(String(g.title ?? ""));
            _fill(_ctxKit, sub, g.actions, 0);
            popup.addMenu(sub);
        }
    }
    on_MenusChanged: if (!popup.visible) _rebuildButton()
    on_ShowButtonChanged: if (!popup.visible) _rebuildButton()
    onExportShortcutsChanged: if (!popup.visible) _rebuildButton()
    Component.onCompleted: _rebuildButton()

    // ---- The native export, only when the desktop has a global menu -------

    // Run through Qt.callLater, so several changes make one rebuild; the bar
    // may be gone by then.
    function _rebuildNative(): void {
        const bar = root._nativeBar;
        if (bar) {
            bar.rebuild();
        }
    }
    // A model changed: its rows are read again once the changes have stopped.
    function _scheduleNative(): void {
        modelTimer.restart();
    }
    Timer {
        id: modelTimer
        interval: 50
        onTriggered: {
            const bar = root._nativeBar;
            if (bar) {
                bar.refreshModels();
            }
        }
    }

    Loader {
        id: nativeLoader
        active: root._native && root._menus.length > 0
        sourceComponent: Platform.MenuBar {
            id: menuBar
            window: root.Window.window
            property var _objs: []
            // The model-driven submenus, whose rows are read again when a group
            // shows or their model changes. Each record owns what its last fill
            // made (`objs`), the records inside it (`kids`) and its signal links.
            property var _watched: []
            property var _curRec: null

            Component {
                id: nItem
                Platform.MenuItem {
                    id: it
                    Component.onCompleted: root._alive++
                    Component.onDestruction: if (root) root._alive--
                    property var act
                    property var sc
                    text: act ? act.text : ""
                    enabled: act ? act.enabled : true
                    checkable: act ? act.checkable === true : false
                    checked: act ? act.checked === true : false
                    shortcut: sc
                    onTriggered: if (act) {
                        act.trigger()
                    }
                }
            }
            Component {
                id: nRow
                Platform.MenuItem {
                    id: nr
                    Component.onCompleted: root._alive++
                    Component.onDestruction: if (root) root._alive--
                    property string rowId
                    property var rowData
                    property int rowIndex: -1
                    onTriggered: {
                        root._refollow(nr);
                        root.modelActivated(nr.rowId, nr.rowData, nr.rowIndex);
                    }
                }
            }
            Component {
                id: nCall
                Platform.MenuItem {
                    id: nc
                    Component.onCompleted: root._alive++
                    Component.onDestruction: if (root) root._alive--
                    property var fn
                    onTriggered: nc.fn()
                }
            }
            Component {
                id: nSep
                Platform.MenuSeparator {
                    Component.onCompleted: root._alive++
                    Component.onDestruction: if (root) root._alive--
                }
            }
            Component {
                id: nMenu
                Platform.Menu {
                    Component.onCompleted: root._alive++
                    Component.onDestruction: if (root) root._alive--
                }
            }
            function _track(o) {
                if (menuBar._curRec) {
                    menuBar._curRec.objs.push(o);
                } else {
                    _objs.push(o);
                }
                return o;
            }
            function _kill(o): void {
                // clear() may have deleted it already.
                try {
                    if (o) {
                        o.destroy();
                    }
                } catch (e) {
                    // gone
                }
            }
            // Lets go of a record: its signal links, the records inside it and
            // the objects its rows made, which are parented to the bar and would pile up.
            function _release(rec): void {
                _disconnect(rec);
                for (const k of rec.kids) {
                    _release(k);
                }
                rec.kids = [];
                for (const o of rec.objs) {
                    _kill(o);
                }
                rec.objs = [];
            }
            function _disconnect(rec): void {
                for (const c of rec.conns) {
                    try {
                        c.model[c.sig].disconnect(root._scheduleNative);
                    } catch (e) {
                        // gone
                    }
                }
                rec.conns = [];
            }
            function _watchModel(rec): void {
                const m = rec.e.model;
                if (m === null || m === undefined || typeof m !== "object") {
                    return;
                }
                for (const sig of ["modelReset", "rowsInserted", "rowsRemoved", "dataChanged", "layoutChanged", "countChanged"]) {
                    if (m[sig] && typeof m[sig].connect === "function") {
                        m[sig].connect(root._scheduleNative);
                        rec.conns.push({
                            model: m,
                            sig: sig
                        });
                    }
                }
            }
            readonly property var _kit: ({
                    sep: () => menuBar._track(nSep.createObject(menuBar)),
                    action: (act, sc) => menuBar._track(nItem.createObject(menuBar, {
                            act: act,
                            sc: sc
                        })),
                    row: (id, text, data, index, enabled) => menuBar._track(nRow.createObject(menuBar, {
                            text: text,
                            enabled: enabled,
                            rowId: id,
                            rowData: data,
                            rowIndex: index
                        })),
                    call: (text, enabled, fn) => menuBar._track(nCall.createObject(menuBar, {
                            text: text,
                            enabled: enabled,
                            fn: fn
                        })),
                    sub: title => menuBar._track(nMenu.createObject(menuBar, {
                            title: title
                        })),
                    add: (m, item) => m.addItem(item),
                    addSub: (m, sub, enabled) => {
                        sub.enabled = enabled;
                        m.addMenu(sub);
                    },
                    // A model-driven submenu starts a record that owns what its
                    // rows make; end() puts the outer record back.
                    begin: (sub, e, depth) => {
                        const rec = {
                            sub: sub,
                            e: e,
                            depth: depth,
                            objs: [],
                            kids: [],
                            conns: [],
                            prev: menuBar._curRec
                        };
                        (rec.prev ? rec.prev.kids : menuBar._watched).push(rec);
                        menuBar._curRec = rec;
                        return rec;
                    },
                    end: rec => {
                        menuBar._curRec = rec.prev;
                        menuBar._watchModel(rec);
                    }
                })
            // A model's rows as they are now. Walks a copy of the list: filling
            // a record adds records inside it, which this pass must not visit.
            function refreshModels(): void {
                _objs = _objs.filter(o => o);
                for (const w of _watched.slice()) {
                    const prev = menuBar._curRec;
                    // What the last fill made, and the records inside it, go first.
                    _release(w);
                    // clear() takes the old rows out and deletes them.
                    w.sub.clear();
                    menuBar._curRec = w;
                    let rows = 0;
                    try {
                        rows = root._fillModel(_kit, w.sub, w.e, w.depth);
                    } finally {
                        menuBar._curRec = prev;
                    }
                    w.sub.enabled = rows > 0 || root._anyEnabled(w.e.lead) || root._anyEnabled(w.e.trail);
                    _watchModel(w);
                }
            }
            // The groups: rebuilt when the list changes, and a group's model
            // rows again each time it is about to show.
            function rebuild(): void {
                root._warned = false;
                root._warnedShape = false;
                menuBar._curRec = null;
                menuBar.clear();
                for (const w of _watched) {
                    _release(w);
                }
                for (const o of _objs) {
                    _kill(o);
                }
                _objs = [];
                _watched = [];
                for (const g of root._menus ?? []) {
                    if (!g || g.actions === undefined) {
                        continue;
                    }
                    const m = _kit.sub(String(g.title ?? ""));
                    root._fill(_kit, m, g.actions, 0);
                    menuBar.addMenu(m);
                    m.aboutToShow.connect(() => menuBar.refreshModels());
                }
            }
            Component.onCompleted: menuBar.rebuild()
            Component.onDestruction: {
                for (const w of _watched) {
                    _release(w);
                }
            }
            Connections {
                target: root
                // Later, never inside the handler that changed them: that could
                // be a row's onTriggered, and clear() deletes the row.
                function on_MenusChanged() {
                    Qt.callLater(root._rebuildNative);
                }
                function onExportShortcutsChanged() {
                    Qt.callLater(root._rebuildNative);
                }
            }
        }
    }
}
