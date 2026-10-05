import QtQuick
import QtTest
import Atlas.Ui

// AtlasActionCollection: lookup, user shortcuts (kept in AtlasSettings,
// validated), the command palette, the shortcuts dialog and the app menu
// reading it. Settings go to the private XDG_CONFIG_HOME of the test run.
Item {
    id: root
    width: 600
    height: 500

    Component {
        id: plainComp
        AtlasActionCollection {
            AtlasAction { objectName: "save"; text: "&Save"; shortcut: "Ctrl+S"; section: "File" }
            AtlasAction { objectName: "open"; text: "Open"; shortcut: "Ctrl+O"; section: "File"; category: "Documents" }
            AtlasAction { objectName: "copy"; text: "Copy"; shortcut: "Ctrl+C"; section: "Edit" }
        }
    }
    Component {
        id: storedComp
        AtlasActionCollection {
            property alias store: store
            settings: AtlasSettings {
                id: store
                group: "ActionsTest"
                fileName: "atlas-actions-testrc"
            }
            AtlasAction { objectName: "save"; text: "Save"; shortcut: "Ctrl+S" }
            AtlasAction { objectName: "open"; text: "Open"; shortcut: "Ctrl+O" }
            AtlasAction { text: "Nameless"; shortcut: "Ctrl+N" }
        }
    }
    Component {
        id: paletteComp
        AtlasCommandPalette {}
    }
    Component {
        id: dialogComp
        AtlasShortcutsDialog {}
    }
    Component {
        id: menuComp
        AtlasAppMenu {
            _forceButton: true
        }
    }

    TestCase {
        name: "AtlasActionCollection"
        when: windowShown

        function test_category_defaults_to_section() {
            const c = createTemporaryObject(plainComp, root);
            compare(c.action("save").category, "File");
            compare(c.action("open").category, "Documents");
        }

        function test_lookup() {
            const c = createTemporaryObject(plainComp, root);
            compare(c.action("copy").text, "Copy");
            compare(c.action("nothing"), null);
            compare(c.action(""), null);
        }

        function test_registered_once() {
            const before = AtlasShortcuts.actions.length;
            const c = createTemporaryObject(plainComp, root);
            compare(AtlasShortcuts.actions.length, before + 3);
            compare(AtlasShortcuts.actions.indexOf(c.action("save")) >= 0, true);
        }

        function test_set_shortcut_replaces_and_resets() {
            const c = createTemporaryObject(plainComp, root);
            const save = c.action("save");
            verify(c.setShortcut("save", "Ctrl+Shift+S"));
            compare(AtlasShortcuts.portable(save.shortcut), "Ctrl+Shift+S");
            compare(c.hasCustomShortcut("save"), true);
            c.resetShortcuts();
            compare(AtlasShortcuts.portable(save.shortcut), "Ctrl+S");
            compare(c.hasCustomShortcut("save"), false);
        }

        function test_set_shortcut_refuses_bad_input() {
            const c = createTemporaryObject(plainComp, root);
            compare(c.setShortcut("save", ""), false);
            compare(c.setShortcut("save", "x".repeat(500)), false);
            compare(c.setShortcut("save", "Ctrl+A, Ctrl+B, Ctrl+C, Ctrl+D, Ctrl+E"), false);
            compare(c.setShortcut("nothing", "Ctrl+Y"), false);
            compare(AtlasShortcuts.portable(c.action("save").shortcut), "Ctrl+S");
        }

        function test_keeps_and_reads_settings() {
            ignoreWarning(/has no objectName/);
            const c = createTemporaryObject(storedComp, root);
            verify(c.setShortcut("open", "Ctrl+Alt+O"));
            c.store.flush();
            compare(c.store.value("shortcuts/open", ""), "Ctrl+Alt+O");
            ignoreWarning(/has no objectName/);
            const again = createTemporaryObject(storedComp, root);
            compare(AtlasShortcuts.portable(again.action("open").shortcut), "Ctrl+Alt+O");
            again.resetShortcuts();
            compare(again.store.contains("shortcuts/open"), false);
            c.resetShortcuts();
        }

        function test_hostile_settings_values_are_ignored() {
            ignoreWarning(/has no objectName/);
            const c = createTemporaryObject(storedComp, root);
            c.store.setValue("shortcuts/save", "x".repeat(500));
            c.store.setValue("shortcuts/open", "not a key at all");
            c.store.flush();
            ignoreWarning(/has no objectName/);
            const again = createTemporaryObject(storedComp, root);
            compare(AtlasShortcuts.portable(again.action("save").shortcut), "Ctrl+S");
            compare(AtlasShortcuts.portable(again.action("open").shortcut), "Ctrl+O");
            compare(again.hasCustomShortcut("save"), false);
            compare(again.hasCustomShortcut("open"), false);
            c.store.remove("shortcuts/save");
            c.store.remove("shortcuts/open");
            c.store.flush();
        }

        function test_palette_reads_collection() {
            const c = createTemporaryObject(plainComp, root);
            const p = createTemporaryObject(paletteComp, root, { collection: c });
            compare(p._rows.length, 3);
            compare(p._rows[0].subtitle.length > 0, true);
            verify(c.setShortcut("copy", "Ctrl+Shift+C"));
            const copy = p._rows.filter(r => r.title === "Copy")[0];
            compare(copy.shortcut, AtlasShortcuts.readable("Ctrl+Shift+C"));
        }

        function test_palette_own_list_wins() {
            const c = createTemporaryObject(plainComp, root);
            const p = createTemporaryObject(paletteComp, root, { collection: c, actions: [c.action("save")] });
            compare(p._rows.length, 1);
        }

        function test_dialog_reads_collection() {
            const c = createTemporaryObject(plainComp, root);
            const d = createTemporaryObject(dialogComp, root, { collection: c, parent: root });
            d.open();
            tryCompare(d, "visible", true);
            compare(d._editable, false);
            compare(d.collection, c);
            d.close();
        }

        function test_dialog_editable_follows_collection() {
            const c = createTemporaryObject(plainComp, root);
            const d = createTemporaryObject(dialogComp, root, { collection: c, parent: root });
            compare(d._editable, false);
            c.shortcutsEditable = true;
            compare(d._editable, true);
        }

        function test_menu_from_collection_groups_by_category() {
            const c = createTemporaryObject(plainComp, root);
            const m = createTemporaryObject(menuComp, root, { collection: c });
            compare(m._menus.length, 3);
            compare(m._menus.map(g => g.title).join(","), "File,Documents,Edit");
            compare(m._menu.count, 3);
        }

        function test_menu_own_list_wins() {
            const c = createTemporaryObject(plainComp, root);
            const m = createTemporaryObject(menuComp, root, {
                collection: c,
                menus: [{ title: "Mine", actions: [c.action("save")] }]
            });
            compare(m._menus.length, 1);
            compare(m._menu.count, 1);
        }

        function test_menu_shows_user_shortcut() {
            const c = createTemporaryObject(plainComp, root);
            const m = createTemporaryObject(menuComp, root, { collection: c });
            verify(c.setShortcut("save", "Ctrl+Alt+S"));
            const save = c.action("save");
            compare(AtlasShortcuts.portable(save.shortcut), "Ctrl+Alt+S");
            verify(m._menus.length > 0);
        }
    }
}
