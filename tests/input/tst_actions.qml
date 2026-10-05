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
        id: delComp
        AtlasActionCollection {
            AtlasAction { objectName: "del"; text: "Delete"; shortcut: "Delete" }
        }
    }
    Component {
        id: sharedComp
        AtlasActionCollection {
            AtlasAction { objectName: "one"; text: "One"; shortcut: "Ctrl+Alt+K" }
            AtlasAction { objectName: "two"; text: "Two"; shortcut: "Ctrl+Alt+K" }
        }
    }
    property string declaredKey: "Ctrl+Alt+Y"
    Component {
        id: boundComp
        AtlasActionCollection {
            AtlasAction { objectName: "bound"; text: "Bound"; shortcut: root.declaredKey }
            AtlasAction { objectName: "std"; text: "Standard"; shortcut: StandardKey.Save }
        }
    }
    Component {
        id: editComp
        AtlasActionCollection {
            shortcutsEditable: true
            AtlasAction { objectName: "save"; text: "Save"; shortcut: "Ctrl+S"; section: "File" }
            AtlasAction { objectName: "open"; text: "Open"; shortcut: "Ctrl+O"; section: "File" }
            AtlasAction { objectName: "copy"; text: "Copy"; shortcut: "Ctrl+C"; section: "Edit" }
        }
    }
    Component {
        id: spyComp
        SignalSpy {
            signalName: "changed"
        }
    }
    Component {
        id: otherComp
        AtlasSettings {
            group: "ActionsTest"
            fileName: "atlas-actions-testrc"
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
            // The menu item runs the same action, so it reads the new shortcut.
            const file = m._menu.menuAt(0);
            compare(file.title, "File");
            compare(AtlasShortcuts.portable(file.itemAt(0).action.shortcut), "Ctrl+Alt+S");
        }

        function test_reset_restores_declared_binding() {
            const c = createTemporaryObject(boundComp, root);
            const bound = c.action("bound");
            verify(c.setShortcut("bound", "Ctrl+Alt+B"));
            compare(AtlasShortcuts.portable(bound.shortcut), "Ctrl+Alt+B");
            verify(c.resetShortcut("bound"));
            root.declaredKey = "Ctrl+Alt+Z";
            compare(AtlasShortcuts.portable(bound.shortcut), "Ctrl+Alt+Z");
            root.declaredKey = "Ctrl+Alt+Y";
            const std = c.action("std");
            verify(c.setShortcut("std", "Ctrl+Alt+W"));
            verify(c.resetShortcuts());
            compare(AtlasShortcuts.portable(std.shortcut), AtlasShortcuts.portable(StandardKey.Save));
        }

        function test_set_shortcut_to_declared_removes_override() {
            const c = createTemporaryObject(plainComp, root);
            verify(c.setShortcut("save", "Ctrl+Alt+S"));
            verify(c.setShortcut("save", "Ctrl+S"));
            compare(c.hasCustomShortcut("save"), false);
        }

        function test_unsafe_shortcuts_are_refused() {
            const c = createTemporaryObject(plainComp, root);
            for (const bad of ["Shift+A", "A", "Ctrl+Shift", "Shift", "Ctrl+A, Ctrl+B", "Ctrl+A\u0000", "\u202eCtrl+A", "Ctrl+\u200bA"]) {
                compare(c.setShortcut("save", bad), false, JSON.stringify(bad));
            }
            verify(c.setShortcut("save", "F5"));
            verify(c.setShortcut("save", "Shift+F6"));
            verify(c.setShortcut("save", "Alt+X"));
        }

        function test_hostile_stored_chords_are_ignored() {
            ignoreWarning(/has no objectName/);
            const c = createTemporaryObject(storedComp, root);
            c.store.setValue("shortcuts/save", "Shift+A");
            c.store.setValue("shortcuts/open", "Ctrl+A, Ctrl+B");
            c.store.flush();
            ignoreWarning(/has no objectName/);
            const again = createTemporaryObject(storedComp, root);
            compare(again.hasCustomShortcut("save"), false);
            compare(again.hasCustomShortcut("open"), false);
            c.store.remove("shortcuts/save");
            c.store.remove("shortcuts/open");
            c.store.flush();
        }

        function test_stored_shortcut_that_conflicts_is_ignored() {
            ignoreWarning(/has no objectName/);
            const c = createTemporaryObject(storedComp, root);
            // "open" declares Ctrl+O; a file giving it to "save" must not win.
            c.store.setValue("shortcuts/save", "Ctrl+O");
            c.store.flush();
            ignoreWarning(/has no objectName/);
            ignoreWarning(/is used by/);
            const again = createTemporaryObject(storedComp, root);
            compare(again.hasCustomShortcut("save"), false);
            compare(AtlasShortcuts.portable(again.action("save").shortcut), "Ctrl+S");
            c.store.remove("shortcuts/save");
            c.store.flush();
        }

        function test_reset_refused_when_declared_shortcut_is_taken() {
            const c = createTemporaryObject(editComp, root);
            verify(c.setShortcut("save", "Ctrl+Alt+S"));
            verify(c.setShortcut("copy", "Ctrl+S"));
            compare(c.declaredConflict("save"), "Copy");
            compare(c.resetShortcut("save"), false);
            compare(c.hasCustomShortcut("save"), true);
        }

        function test_external_settings_change_is_picked_up() {
            ignoreWarning(/has no objectName/);
            const c = createTemporaryObject(storedComp, root);
            const spy = createTemporaryObject(spyComp, root, { target: c.store });
            const other = createTemporaryObject(otherComp, root);
            other.setValue("shortcuts/open", "Ctrl+Alt+P");
            other.flush();
            tryVerify(() => spy.count > 0);
            tryVerify(() => c.hasCustomShortcut("open"));
            compare(AtlasShortcuts.portable(c.action("open").shortcut), "Ctrl+Alt+P");
            other.remove("shortcuts/open");
            other.flush();
        }

        function walk(item, pred, out) {
            if (!item) {
                return out;
            }
            if (pred(item)) {
                out.push(item);
            }
            for (const ch of item.children) {
                walk(ch, pred, out);
            }
            if (item.contentItem && item.contentItem !== item) {
                walk(item.contentItem, pred, out);
            }
            return out;
        }
        function rowFor(d, text) {
            const rows = walk(d.contentItem, it => it.modelData !== undefined && it.modelData !== null && it.modelData.text === text && it.isEditing !== undefined, []);
            return rows.length > 0 ? rows[0] : null;
        }
        function inRow(row, pred) {
            const f = walk(row, pred, []);
            return f.length > 0 ? f[0] : null;
        }
        function button(row, label) {
            return inRow(row, it => it.text === label && it.clicked !== undefined && it.visible);
        }
        function shown(d, prefix) {
            return walk(d.contentItem, it => typeof it.text === "string" && it.text.startsWith(prefix) && it.visible, []).length > 0;
        }
        function openEditable() {
            const c = createTemporaryObject(editComp, root);
            const d = createTemporaryObject(dialogComp, root, { collection: c, parent: root });
            d.open();
            tryCompare(d, "visible", true);
            tryVerify(() => rowFor(d, "Save") !== null);
            return { c: c, d: d };
        }
        function record(d, text, key, mods) {
            const row = rowFor(d, text);
            mouseClick(button(row, "Change"));
            const field = inRow(row, it => it.recording !== undefined && it.conflictText !== undefined);
            tryCompare(field, "recording", true);
            keyClick(key, mods);
        }

        function test_dialog_edit_flow() {
            const x = openEditable();
            const c = x.c, d = x.d;
            // Accept a new shortcut.
            record(d, "Save", Qt.Key_P, Qt.ControlModifier | Qt.AltModifier);
            tryCompare(c, "_overrides", { "save": "Ctrl+Alt+P" });
            compare(AtlasShortcuts.portable(c.action("save").shortcut), "Ctrl+Alt+P");
            // Refuse one another action has, in words.
            record(d, "Copy", Qt.Key_O, Qt.ControlModifier);
            tryVerify(() => shown(d, "Already used by"));
            compare(c.hasCustomShortcut("copy"), false);
            compare(AtlasShortcuts.portable(c.action("copy").shortcut), "Ctrl+C");
            const copyField = inRow(rowFor(d, "Copy"), it => it.recording !== undefined && it.conflictText !== undefined);
            tryCompare(copyField, "recording", true);
            keyClick(Qt.Key_Q, Qt.ControlModifier | Qt.AltModifier);
            tryCompare(c, "_overrides", { "save": "Ctrl+Alt+P", "copy": "Ctrl+Alt+Q" });
            // Reset one.
            mouseClick(button(rowFor(d, "Save"), "Reset"));
            tryCompare(c, "_overrides", { "copy": "Ctrl+Alt+Q" });
            // Reset all.
            mouseClick(inRow(d.contentItem, it => it.text === "Reset all" && it.clicked !== undefined));
            tryCompare(c, "_overrides", {});
            compare(AtlasShortcuts.portable(c.action("copy").shortcut), "Ctrl+C");
        }

        function test_dialog_held_escape_does_not_close() {
            const x = openEditable();
            const d = x.d;
            const row = rowFor(d, "Open");
            mouseClick(button(row, "Change"));
            const field = inRow(row, it => it.recording !== undefined && it.conflictText !== undefined);
            tryCompare(field, "recording", true);
            keyPress(Qt.Key_Escape);
            tryCompare(field, "recording", false);
            wait(400);
            keyRelease(Qt.Key_Escape);
            tryVerify(() => button(rowFor(d, "Open"), "Change") !== null);
            compare(d.visible, true);
        }

        function test_dialog_focus_loss_ends_edit_mode() {
            const x = openEditable();
            const d = x.d;
            const row = rowFor(d, "Open");
            mouseClick(button(row, "Change"));
            const field = inRow(row, it => it.recording !== undefined && it.conflictText !== undefined);
            tryCompare(field, "recording", true);
            keyClick(Qt.Key_Tab);
            tryVerify(() => button(rowFor(d, "Open"), "Change") !== null);
            compare(d.visible, true);
        }

        function test_dialog_refuse_then_record_again() {
            const x = openEditable();
            const c = x.c, d = x.d;
            record(d, "Copy", Qt.Key_O, Qt.ControlModifier);
            tryVerify(() => shown(d, "Already used by"));
            const field = inRow(rowFor(d, "Copy"), it => it.recording !== undefined && it.conflictText !== undefined);
            tryCompare(field, "recording", true);
            keyClick(Qt.Key_R, Qt.ControlModifier | Qt.AltModifier);
            tryCompare(c, "_overrides", { "copy": "Ctrl+Alt+R" });
        }

        function test_dialog_list_keeps_scroll_position() {
            let src = "import QtQuick\nimport Atlas.Ui\nAtlasActionCollection {\n shortcutsEditable: true\n";
            const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
            for (let i = 0; i < 26; ++i) {
                src += ` AtlasAction { objectName: "a${i}"; text: "Act ${letters[i]}"; shortcut: "Ctrl+Alt+${letters[i]}" }\n`;
            }
            src += "}";
            const c = Qt.createQmlObject(src, root);
            const d = createTemporaryObject(dialogComp, root, { collection: c, parent: root });
            d.open();
            tryCompare(d, "visible", true);
            const lists = walk(d.contentItem, it => it.contentY !== undefined && it.model !== undefined && it.section !== undefined, []);
            verify(lists.length > 0);
            const list = lists[0];
            tryVerify(() => list.contentHeight > list.height);
            mouseWheel(list, list.width / 2, list.height / 2, 0, -240);
            tryVerify(() => list.contentY > 0);
            tryVerify(() => !list.moving);
            const before = list.contentY;
            verify(c.setShortcut("a0", "Ctrl+Alt+Home"));
            wait(100);
            tryVerify(() => Math.abs(list.contentY - before) < 1);
            d.close();
            c.destroy();
        }

        function test_media_key_is_refused_unless_declared() {
            const c = createTemporaryObject(plainComp, root);
            compare(c.setShortcut("save", "Media Play"), false);
            compare(c.setShortcut("save", "Delete"), false);
        }

        function test_declared_lone_key_can_be_recorded_back() {
            const c = createTemporaryObject(delComp, root);
            verify(c.setShortcut("del", "Ctrl+Alt+D"));
            verify(c.setShortcut("del", "Delete"));
            compare(c.hasCustomShortcut("del"), false);
            compare(AtlasShortcuts.portable(c.action("del").shortcut), AtlasShortcuts.portable("Delete"));
        }

        function test_swapped_stored_shortcuts_both_load() {
            ignoreWarning(/has no objectName/);
            const c = createTemporaryObject(storedComp, root);
            // save declares Ctrl+S and open Ctrl+O: swap them in the file.
            c.store.setValue("shortcuts/save", "Ctrl+O");
            c.store.setValue("shortcuts/open", "Ctrl+S");
            c.store.flush();
            ignoreWarning(/has no objectName/);
            const again = createTemporaryObject(storedComp, root);
            compare(AtlasShortcuts.portable(again.action("save").shortcut), "Ctrl+O");
            compare(AtlasShortcuts.portable(again.action("open").shortcut), "Ctrl+S");
            c.store.remove("shortcuts/save");
            c.store.remove("shortcuts/open");
            c.store.flush();
        }

        function test_reset_all_skips_a_taken_shortcut() {
            const c = createTemporaryObject(editComp, root);
            verify(c.setShortcut("save", "Ctrl+Alt+S"));
            verify(c.setShortcut("open", "Ctrl+Alt+O"));
            verify(c.setShortcut("copy", "Ctrl+S"));
            compare(c.resetShortcuts(), false);
            compare(c.hasCustomShortcut("save"), true);
            compare(c.hasCustomShortcut("open"), false);
        }

        function test_shared_declared_shortcut_does_not_block_reset() {
            const c = createTemporaryObject(sharedComp, root);
            verify(c.setShortcut("one", "Ctrl+Alt+1"));
            compare(c.declaredConflict("one"), "");
            verify(c.resetShortcut("one"));
            compare(c.hasCustomShortcut("one"), false);
        }

        function test_dialog_escape_cancels_capture_only() {
            const x = openEditable();
            const c = x.c, d = x.d;
            const row = rowFor(d, "Open");
            mouseClick(button(row, "Change"));
            const field = inRow(row, it => it.recording !== undefined && it.conflictText !== undefined);
            tryCompare(field, "recording", true);
            keyClick(Qt.Key_Escape);
            // Edit mode ended: the Change button is back.
            tryVerify(() => button(rowFor(d, "Open"), "Change") !== null);
            compare(d.visible, true);
            compare(c.hasCustomShortcut("open"), false);
            // With nothing being recorded, Escape closes the dialog as before.
            keyClick(Qt.Key_Escape);
            tryCompare(d, "visible", false);
        }
    }
}
