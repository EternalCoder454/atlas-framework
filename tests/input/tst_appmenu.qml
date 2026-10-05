import QtQuick
import QtTest
import Atlas.Ui

// AtlasAppMenu: nested submenus, model-driven rows, exported shortcuts.
Item {
    id: root
    width: 400
    height: 300

    AtlasAction { id: openA; text: "Open" }
    AtlasAction { id: reopenA; text: "Reopen Closed Tab" }
    AtlasAction { id: clearA; text: "Clear List"; enabled: false }
    AtlasAction { id: saveA; text: "Save" }
    AtlasAction {
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
        AtlasAppMenu {
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
        name: "AtlasAppMenu"
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
            compare(m._nativeBar.menus[0].title, "Edit");
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
    }
}
