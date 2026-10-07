import QtQuick
import QtTest
import Telamon.Ui

// TelamonAppMenu: nested submenus, model-driven rows, exported shortcuts.
Item {
    id: root
    width: 400
    height: 300

    TelamonAction { id: openA; text: "Open" }
    TelamonAction { id: reopenA; text: "Reopen Closed Tab" }
    TelamonAction { id: clearA; text: "Clear List"; enabled: false }
    TelamonAction { id: saveA; text: "Save" }
    TelamonAction {
        id: withMenu
        text: "&Tools"
        menu: ContextMenu {
            ContextMenuItem {
                text: "Inner"
                onTriggered: root.innerCount++
            }
            ContextMenuSeparator {}
            ContextMenuItem {
                action: openA
            }
        }
    }
    property int innerCount: 0
    ListModel {
        id: files
        ListElement { path: "/a/one.txt" }
        ListElement { path: "/a/two.txt" }
    }
    Component {
        id: menuComp
        TelamonAppMenu {
            _forceButton: true
        }
    }

    function texts(m) {
        const out = [];
        for (let i = 0; i < m.count; ++i) {
            const sub = m.menuAt(i);
            out.push(sub ? "> " + sub.title : (m.itemAt(i).text ?? "-"));
        }
        return out;
    }

    TestCase {
        name: "TelamonAppMenu"
        when: windowShown

        function test_plain_actions_and_separators() {
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [openA, null, saveA] }]
            });
            compare(m._menu.count, 1);
            const file = m._menu.menuAt(0);
            compare(file.title, "File");
            compare(file.count, 3);
            compare(file.itemAt(0).text, "Open");
        }

        function test_nested_submenu() {
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [{ title: "More", actions: [openA, { title: "Deeper", actions: [saveA] }] }] }]
            });
            const more = m._menu.menuAt(0).menuAt(0);
            compare(more.title, "More");
            compare(more.menuAt(1).title, "Deeper");
            compare(more.menuAt(1).itemAt(0).text, "Save");
        }

        function test_nesting_stops_at_eight_levels() {
            let entry = { title: "L9", actions: [openA] };
            for (let i = 8; i >= 1; --i) {
                entry = { title: "L" + i, actions: [entry] };
            }
            ignoreWarning(/submenus nest at most 8 levels/);
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "G", actions: [entry] }]
            });
            let sub = m._menu.menuAt(0);
            let depth = 0;
            while (sub && sub.count > 0 && sub.menuAt(0)) {
                sub = sub.menuAt(0);
                ++depth;
            }
            compare(depth, 8);
        }

        function test_model_rows_between_lead_and_trail() {
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [{ id: "recent", title: "Open Recent", model: files, textRole: "path", lead: [reopenA, null], trail: [null, clearA], emptyText: "No recent files" }] }]
            });
            const recent = m._menu.menuAt(0).menuAt(0);
            compare(recent.title, "Open Recent");
            // reopen, separator, two rows, separator, clear
            compare(recent.count, 6);
            compare(recent.itemAt(2).text, "/a/one.txt");
            compare(recent.itemAt(3).text, "/a/two.txt");
            let got = null;
            m.modelActivated.connect((id, data, index) => got = [id, data.path, index]);
            recent.itemAt(3).triggered();
            compare(got, ["recent", "/a/two.txt", 1]);
        }

        function test_string_model_and_empty_text() {
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [{ id: "r", title: "Recent", model: ["x.txt", "y.txt"], trail: [clearA] },
                        { id: "e", title: "Empty", model: [], emptyText: "Nothing here" }] }]
            });
            const r = m._menu.menuAt(0).menuAt(0);
            compare(r.itemAt(0).text, "x.txt");
            let got = null;
            m.modelActivated.connect((id, data, index) => got = [id, data, index]);
            r.itemAt(1).triggered();
            compare(got, ["r", "y.txt", 1]);
            const e = m._menu.menuAt(0).menuAt(1);
            compare(e.count, 1);
            compare(e.itemAt(0).text, "Nothing here");
            verify(!e.itemAt(0).enabled);
            // No rows and no enabled action: the entry is disabled.
            verify(!m._menu.menuAt(0).itemAt(1).enabled);
        }

        function test_model_changes_take_effect_when_the_menu_opens() {
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [{ id: "recent", title: "Recent", model: files, textRole: "path" }] }]
            });
            const before = m._menu.menuAt(0).menuAt(0).count;
            compare(before, 2);
            files.append({ path: "/a/three.txt" });
            compare(m._menu.menuAt(0).menuAt(0).count, 2);
            m.open();
            tryVerify(() => m._menu.visible);
            gc();
            compare(m._menu.menuAt(0).menuAt(0).count, 3);
            m._menu.close();
            files.remove(2);
        }

        function test_exported_shortcut_shows_in_the_rows() {
            const m = createTemporaryObject(menuComp, root, {
                exportShortcuts: true,
                menus: [{ title: "File", actions: [{ action: saveA, shortcut: "Ctrl+S" }, openA] }]
            });
            const file = m._menu.menuAt(0);
            compare(file.itemAt(0).shortcutText, "Ctrl+S");
            compare(file.itemAt(1).shortcutText, "");
            const n = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [{ action: saveA, shortcut: "Ctrl+S" }] }]
            });
            compare(n._menu.menuAt(0).itemAt(0).shortcutText, "");
        }

        function test_text_is_plain() {
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "<b>File</b>", actions: [{ id: "r", title: "<i>x</i>", model: ["<u>y</u>"] }] }]
            });
            compare(m._menu.menuAt(0).title, "<b>File</b>");
            compare(m._menu.menuAt(0).menuAt(0).itemAt(0).text, "<u>y</u>");
        }

        function test_native_export_has_the_same_structure() {
            const m = createTemporaryObject(menuComp, root, {
                _forceNative: true,
                exportShortcuts: true,
                menus: [{ title: "File", actions: [{ action: saveA, shortcut: "Ctrl+S" }, null,
                        { title: "More", actions: [openA] },
                        { id: "r", title: "Recent", model: ["x.txt"], trail: [clearA] }] }]
            });
            const bar = m._nativeBar;
            verify(bar);
            compare(bar.menus.length, 1);
            const file = bar.menus[0];
            compare(file.title, "File");
            compare(file.items.length, 4);
            compare(file.items[0].text, "Save");
            compare(file.items[1].separator, true);
            compare(file.items[2].subMenu.title, "More");
            compare(file.items[3].subMenu.items[0].text, "x.txt");
            let got = null;
            m.modelActivated.connect((id, data, index) => got = [id, data, index]);
            file.items[3].subMenu.items[0].triggered();
            compare(got, ["r", "x.txt", 0]);
        }

        function test_native_model_rows_refresh_when_a_group_shows() {
            const m = createTemporaryObject(menuComp, root, {
                _forceNative: true,
                menus: [{ title: "File", actions: [{ id: "recent", title: "Recent", model: files, textRole: "path" }] }]
            });
            const file = m._nativeBar.menus[0];
            compare(file.items[0].subMenu.items.length, 2);
            files.append({ path: "/a/three.txt" });
            compare(file.items[0].subMenu.items.length, 2);
            file.aboutToShow();
            compare(file.items[0].subMenu.items.length, 3);
            compare(file.items[0].subMenu.items[2].text, "/a/three.txt");
            files.remove(2);
            file.aboutToShow();
            compare(file.items[0].subMenu.items.length, 2);
            // A rebuild after refreshes is clean too.
            m.menus = [{ title: "Edit", actions: [openA] }];
            tryVerify(() => m._nativeBar.menus[0].title === "Edit");
        }

        function test_action_with_a_menu_is_a_submenu() {
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [withMenu] }]
            });
            const tools = m._menu.menuAt(0).menuAt(0);
            compare(tools.title, "Tools");
            compare(tools.count, 3);
            compare(tools.itemAt(0).text, "Inner");
            tools.itemAt(0).triggered();
            compare(root.innerCount, 1);
            compare(tools.itemAt(2).text, "Open");
            // The app's own menu is untouched.
            compare(withMenu.menu.count, 3);
        }

        function test_menus_changed_inside_a_native_row_is_safe() {
            const m = createTemporaryObject(menuComp, root, {
                _forceNative: true,
                menus: [{ title: "File", actions: [{ id: "r", title: "Recent", model: files, textRole: "path" }] }]
            });
            m.modelActivated.connect(() => {
                m.menus = [{ title: "Edit", actions: [openA] }];
                m.menus = [{ title: "View", actions: [saveA] }];
            });
            const bar = m._nativeBar;
            bar.menus[0].items[0].subMenu.items[0].triggered();
            tryVerify(() => bar.menus[0].title === "View");
            compare(bar.menus.length, 1);
        }

        function test_native_rebuilds_are_coalesced() {
            const m = createTemporaryObject(menuComp, root, {
                _forceNative: true,
                menus: [{ title: "File", actions: [openA] }]
            });
            m.menus = [{ title: "A", actions: [openA] }];
            m.menus = [{ title: "B", actions: [openA] }];
            tryVerify(() => m._nativeBar.menus[0].title === "B");
            compare(m._nativeBar.menus.length, 1);
        }

        function test_native_nested_model_refresh_has_no_stale_entries() {
            const inner = Qt.createQmlObject('import QtQuick; ListModel { ListElement { n: "i1" } }', root);
            const m = createTemporaryObject(menuComp, root, {
                _forceNative: true,
                menus: [{ title: "File", actions: [{ id: "o", title: "Outer", model: files, textRole: "path", lead: [{ id: "i", title: "Inner", model: inner, textRole: "n" }] }] }]
            });
            const file = m._nativeBar.menus[0];
            for (let k = 0; k < 5; ++k) {
                file.aboutToShow();
            }
            compare(m._nativeBar._watched.length, 1);
            compare(m._nativeBar._watched[0].kids.length, 1);
            compare(file.items[0].subMenu.items[0].subMenu.items.length, 1);
            compare(file.items[0].subMenu.items.length, 3);
        }

        function test_native_refresh_does_not_leak_objects() {
            const inner = Qt.createQmlObject('import QtQuick; ListModel { ListElement { n: "i1" } ListElement { n: "i2" } }', root);
            const spec = () => [{ title: "File", actions: [{ id: "o", title: "Outer", model: files, textRole: "path", lead: [{ id: "i", title: "Inner", model: inner, textRole: "n" }], trail: [{ title: "Trail", actions: [saveA] }] }] },
                { title: "Edit", actions: [{ id: "p", title: "Other", model: files, textRole: "path" }] }];
            const m = createTemporaryObject(menuComp, root, {
                _forceNative: true,
                menus: spec()
            });
            m._nativeBar.menus[0].aboutToShow();
            wait(20);
            const base = m._alive;
            verify(base > 0);
            for (let k = 0; k < 10; ++k) {
                m._nativeBar.menus[0].aboutToShow();
                m.menus = spec();
                wait(20);
                m._nativeBar.menus[0].aboutToShow();
            }
            wait(50);
            tryCompare(m, "_alive", base);
        }

        function test_model_not_loaded_yet_shows_disabled_with_empty_text() {
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [{ id: "r", title: "Recent", model: undefined, emptyText: "None" }] }]
            });
            const recent = m._menu.menuAt(0).menuAt(0);
            verify(recent);
            compare(recent.count, 1);
            compare(recent.itemAt(0).text, "None");
            verify(!recent.itemAt(0).enabled);
        }

        function test_native_rows_follow_model_changes() {
            const m = createTemporaryObject(menuComp, root, {
                _forceNative: true,
                menus: [{ title: "File", actions: [{ id: "recent", title: "Recent", model: files, textRole: "path" }] }]
            });
            const sub = m._nativeBar.menus[0].items[0].subMenu;
            const n = sub.items.length;
            files.append({ path: "/a/new.txt" });
            tryCompare(sub.items, "length", n + 1);
            files.remove(files.count - 1);
            tryCompare(sub.items, "length", n);
        }

        function test_native_row_data_is_a_copy() {
            const m = createTemporaryObject(menuComp, root, {
                _forceNative: true,
                menus: [{ title: "File", actions: [{ id: "r", title: "Recent", model: files, textRole: "path" }] }]
            });
            let got = null;
            m.modelActivated.connect((id, data) => got = data);
            m._nativeBar.menus[0].items[0].subMenu.items[0].triggered();
            const first = files.get(0);
            verify(got !== first);
            compare(got.path, "/a/one.txt");
        }

        function test_non_iterable_and_null_models_are_empty() {
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [
                    { id: "a", title: "Null", model: null, emptyText: "E" },
                    { id: "b", title: "Obj", model: { x: 1 }, emptyText: "E" }] }]
            });
            const file = m._menu.menuAt(0);
            compare(file.menuAt(0).count, 1);
            compare(file.menuAt(1).count, 1);
        }

        function test_null_and_undefined_entries_are_separators() {
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [openA, undefined, null, saveA] }, null, undefined]
            });
            compare(m._menu.count, 1);
            compare(m._menu.menuAt(0).count, 4);
        }

        function test_unknown_entry_warns_once() {
            ignoreWarning(/ignored/);
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [openA, "nonsense", 42, { foo: 1 }, saveA] }]
            });
            compare(m._menu.menuAt(0).count, 2);
        }

        function test_native_shortcut_with_export() {
            const m = createTemporaryObject(menuComp, root, {
                _forceNative: true,
                exportShortcuts: true,
                menus: [{ title: "File", actions: [{ action: openA, shortcut: "Ctrl+O" }] }]
            });
            const item = m._nativeBar.menus[0].items[0];
            verify(String(item.shortcut).length > 0);
            m.exportShortcuts = false;
            tryVerify(() => !m._nativeBar.menus[0].items[0].shortcut || String(m._nativeBar.menus[0].items[0].shortcut) === "");
        }

        function test_native_going_on_and_off() {
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [openA] }]
            });
            verify(!m._nativeBar);
            m._forceNative = true;
            tryVerify(() => m._nativeBar);
            m.menus = [{ title: "Edit", actions: [openA] }];
            m._forceNative = false;
            m._forceButton = true;
            wait(50);
            verify(!m._nativeBar);
            tryCompare(m._menu, "count", 1);
        }

        function test_action_menu_containing_itself_stops_at_the_depth_cap() {
            const loop = Qt.createQmlObject('import Telamon.Ui; TelamonAction { text: "Loop" }', root);
            const menu = Qt.createQmlObject('import Telamon.Ui; ContextMenu {}', root);
            menu.addAction(loop);
            loop.menu = menu;
            const m = createTemporaryObject(menuComp, root, {
                menus: [{ title: "File", actions: [loop] }]
            });
            verify(m._menu.count === 1);
        }

        function test_menus_changed_while_the_popup_is_open_apply_at_next_open() {
            const m = createTemporaryObject(menuComp, root, {
                width: 40,
                height: 30,
                menus: [{ title: "File", actions: [openA] }]
            });
            m.open();
            tryVerify(() => m._menu.visible);
            m.menus = [{ title: "Edit", actions: [openA] }];
            compare(m._menu.menuAt(0).title, "File");
            m._menu.close();
            tryVerify(() => !m._menu.visible);
            m.open();
            tryVerify(() => m._menu.visible);
            compare(m._menu.menuAt(0).title, "Edit");
            m._menu.close();
        }

        function test_action_rows_follow_the_action_and_other_objects_are_copied() {
            const act = Qt.createQmlObject('import Telamon.Ui; TelamonAction { text: "Live"; checkable: true }', root);
            const plainObj = Qt.createQmlObject('import QtQml; QtObject { property string name: "Plain" }', root);
            const m = createTemporaryObject(menuComp, root, {
                _forceNative: true,
                menus: [{ title: "File", actions: [
                    { id: "a", title: "A", model: [act], textRole: "text" },
                    { id: "b", title: "B", model: [plainObj], textRole: "name" }] }]
            });
            const file = m._nativeBar.menus[0];
            const live = file.items[0].subMenu.items[0];
            compare(live.text, "Live");
            act.text = "Renamed";
            compare(live.text, "Renamed");
            act.enabled = false;
            verify(!live.enabled);
            act.checked = true;
            verify(live.checked);
            // Choosing a checkable row toggles the item itself (as the menu
            // does), which must not leave it out of step with the Action.
            live.checked = false;
            live.triggered();
            verify(live.checked, "back in step with the Action");
            act.checked = false;
            verify(!live.checked);
            act.checked = true;
            verify(live.checked);
            const copy = file.items[1].subMenu.items[0];
            compare(copy.text, "Plain");
            let got = null;
            m.modelActivated.connect((id, data) => got = data);
            copy.triggered();
            compare(got.name, "Plain");
        }
    }
}
