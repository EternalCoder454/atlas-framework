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
// The native export is made only when a global menu is there, so a desktop
// without one never creates a menu bar of its own. Detection is an
// asynchronous D-Bus check with a timeout: until it answers, the button shows.
Item {
    id: root

    // [{title: string, actions: [Action | null | {action, shortcut} | {title, actions} | {id, title, model, ...}]}]
    property var menus: []
    // The name of the menu button for screen readers and its tooltip.
    property string accessibleName: qsTr("Main menu")
    // Shows each `{action, shortcut}` entry's shortcut in the global menu (and
    // in the button's rows). The action must then leave its own `shortcut`
    // empty, or the key has two owners and neither fires.
    property bool exportShortcuts: false

    // A row of a model-driven submenu was chosen.
    signal modelActivated(string id, var modelData, int index)

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

    visible: _showButton && menus.length > 0
    implicitWidth: visible ? button.implicitWidth : 0
    implicitHeight: visible ? button.implicitHeight : 0

    // ---- Shared by the button's menus and the native export -------------

    property bool _warned: false
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
    function _rowsOf(model): var {
        const rows = [];
        if (model === null || model === undefined) {
            return rows;
        }
        // A ListModel gives plain objects with every role.
        if (typeof model.get === "function" && typeof model.count === "number") {
            for (let i = 0; i < model.count; ++i) {
                rows.push(model.get(i));
            }
            return rows;
        }
        const reader = readerComponent.createObject(null, {
            model: model
        });
        for (let i = 0; i < reader.count; ++i) {
            const md = reader.objectAt(i).modelData;
            // What the model hands out dies with the reader: keep a plain copy.
            if (md !== null && typeof md === "object" && !Array.isArray(md)) {
                const copy = {};
                for (const k in md) {
                    copy[k] = md[k];
                }
                rows.push(copy);
            } else {
                rows.push(md);
            }
        }
        reader.destroy();
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
            } else if (e.model !== undefined || e.lead !== undefined || e.trail !== undefined) {
                if (depth + 1 > root._maxDepth) {
                    _tooDeep();
                    continue;
                }
                const sub = kit.sub(String(e.title ?? ""));
                const rows = _fillModel(kit, sub, e, depth + 1);
                kit.addSub(menu, sub, rows > 0 || _anyEnabled(e.lead) || _anyEnabled(e.trail));
                if (kit.watch) {
                    kit.watch(sub, e, depth + 1);
                }
            } else if (e.actions !== undefined) {
                if (depth + 1 > root._maxDepth) {
                    _tooDeep();
                    continue;
                }
                const sub = kit.sub(String(e.title ?? ""));
                _fill(kit, sub, e.actions, depth + 1);
                kit.addSub(menu, sub, true);
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
            kit.add(sub, kit.row(String(e.id ?? ""), _rowText(rows[i], e.textRole), rows[i], i, true));
        }
        _fill(kit, sub, e.trail, depth);
        return rows.length;
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
            onTriggered: root.modelActivated(row.rowId, row.rowData, row.rowIndex)
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
        _clearMenu(popup);
        if (!_showButton) {
            return;
        }
        for (const g of menus ?? []) {
            if (!g || g.actions === undefined) {
                continue;
            }
            const sub = _ctxKit.sub(String(g.title ?? ""));
            _fill(_ctxKit, sub, g.actions, 0);
            popup.addMenu(sub);
        }
    }
    onMenusChanged: if (!popup.visible) _rebuildButton()
    on_ShowButtonChanged: if (!popup.visible) _rebuildButton()
    onExportShortcutsChanged: if (!popup.visible) _rebuildButton()
    Component.onCompleted: _rebuildButton()

    // ---- The native export, only when the desktop has a global menu -------

    Loader {
        id: nativeLoader
        active: root._native && root.menus.length > 0
        sourceComponent: Platform.MenuBar {
            id: menuBar
            window: root.Window.window
            property var _objs: []
            // The model-driven submenus, whose rows are read again when a group shows.
            property var _watched: []

            Component {
                id: nItem
                Platform.MenuItem {
                    id: it
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
                    property string rowId
                    property var rowData
                    property int rowIndex: -1
                    onTriggered: root.modelActivated(nr.rowId, nr.rowData, nr.rowIndex)
                }
            }
            Component {
                id: nCall
                Platform.MenuItem {
                    id: nc
                    property var fn
                    onTriggered: nc.fn()
                }
            }
            Component {
                id: nSep
                Platform.MenuSeparator {}
            }
            Component {
                id: nMenu
                Platform.Menu {}
            }
            function _track(o) {
                _objs.push(o);
                return o;
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
                    watch: (sub, e, depth) => menuBar._watched.push({
                            sub: sub,
                            e: e,
                            depth: depth
                        })
                })
            // A model's rows as they are now, when a group is about to show.
            function refreshModels(): void {
                _objs = _objs.filter(o => o);
                for (const w of _watched) {
                    // clear() takes the old rows out and deletes them.
                    w.sub.clear();
                    const rows = root._fillModel(_kit, w.sub, w.e, w.depth);
                    w.sub.enabled = rows > 0 || root._anyEnabled(w.e.lead) || root._anyEnabled(w.e.trail);
                }
            }
            // The groups: rebuilt when the list changes, and a group's model
            // rows again each time it is about to show.
            function rebuild(): void {
                root._warned = false;
                menuBar.clear();
                for (const o of _objs) {
                    // clear() may have deleted it already.
                    try {
                        o.destroy();
                    } catch (e) {
                        // gone
                    }
                }
                _objs = [];
                _watched = [];
                for (const g of root.menus ?? []) {
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
            Connections {
                target: root
                function onMenusChanged() {
                    menuBar.rebuild();
                }
                function onExportShortcutsChanged() {
                    menuBar.rebuild();
                }
            }
        }
    }
}
