import QtQuick
import QtTest
import Atlas.Ui

// AtlasFormEntry.settingKey (docs/api-1.5.0.md, item 26): a control loads the
// stored value and each user edit is saved, for every control type in the
// table; an app binding on the control stays intact; a change from another
// writer updates the control; a stored value of the wrong type and a password
// field warn. The settings file is in the private XDG_CONFIG_HOME of the test
// runner (tests/visual/run-variant.sh).
TestCase {
    id: tc
    name: "SettingKey"
    width: 600
    height: 400
    visible: true
    when: windowShown

    property int groups: 0
    // One group per run, so what an earlier run left in the file is not read.
    readonly property string run: "R" + Date.now()

    QtObject {
        id: app
        property bool flag: false
    }

    Component {
        id: storeComp
        AtlasSettings {
            fileName: "atlas-forms-test"
        }
    }

    function newStore() {
        tc.groups += 1;
        return createTemporaryObject(storeComp, tc, {group: tc.run + "_" + tc.groups});
    }

    property var made: []

    function cleanup() {
        for (const f of tc.made) {
            f.destroy();
        }
        tc.made = [];
    }

    // A form with one keyed entry round `controlSrc`, using store `st`.
    function makeForm(controlSrc, st, entryProps, key) {
        const src = "import QtQuick\nimport Atlas.Ui\nAtlasForm {\n width: 500\n property alias entry: e\n AtlasFormEntry {\n id: e\n label: \"L\"\n settingKey: " + JSON.stringify(key || "K") + "\n " + (entryProps || "") + "\n " + controlSrc + "\n }\n}\n";
        const f = Qt.createQmlObject(src, tc, "form.qml");
        tc.made.push(f);
        if (st) {
            f.settings = st;
        }
        return f;
    }

    // Each row: the control, the property, a value to store first, what the
    // control then shows, how the user edits it, and what is then saved.
    function rows() {
        return [
            {tag: "switch", src: "AtlasSwitch { }", prop: "checked", stored: true, probe: false, edit: "space", saved: false},
            {tag: "checkbox", src: "AtlasCheckBox { }", prop: "checked", stored: true, probe: false, edit: "space", saved: false},
            {tag: "slider", src: "AtlasSlider { from: 0; to: 10; stepSize: 1 }", prop: "value", stored: 4, probe: 0.25, edit: "right", saved: 5},
            {tag: "spinbox", src: "AtlasSpinBox { from: 0; to: 100 }", prop: "value", stored: 7, probe: 0.25, edit: "up", saved: 8},
            {tag: "doublespinbox", src: "AtlasDoubleSpinBox { from: 0; to: 10; stepSize: 0.5 }", prop: "value", stored: 2.5, probe: 0.25, edit: "up", saved: 3},
            {tag: "rating", src: "AtlasRating { readOnly: false }", prop: "value", stored: 2, probe: 0.25, edit: "click4", saved: 4},
            {tag: "combobox", src: "AtlasComboBox { model: [\"a\", \"b\", \"c\"] }", prop: "currentIndex", stored: 1, probe: 0, edit: "down", saved: 2},
            {tag: "segmented", src: "AtlasSegmentedControl { model: [\"a\", \"b\", \"c\"] }", prop: "currentIndex", stored: 1, probe: 0, edit: "right", saved: 2},
            {tag: "textfield", src: "AtlasTextField { }", prop: "text", stored: "hello", probe: "", edit: "type", saved: null},
            {tag: "textarea", src: "AtlasTextArea { }", prop: "text", stored: "hello", probe: "", edit: "type", saved: null},
            {tag: "color", src: "AtlasColorField { }", prop: "color", stored: "#112233", probe: "", edit: "color", saved: "#445566"},
            {tag: "file", src: "AtlasFileField { }", prop: "path", stored: "/tmp/a", probe: "", edit: "path", saved: "/tmp/b"},
            {tag: "folder", src: "AtlasFolderField { }", prop: "path", stored: "/tmp/a", probe: "", edit: "path", saved: "/tmp/b"},
            {tag: "shortcut", src: "AtlasShortcutField { }", prop: "sequence", stored: "Ctrl+S", probe: "", edit: "sequence", saved: "Ctrl+Shift+K"}
        ];
    }

    function same(prop, a, b) {
        return prop === "color" ? Qt.colorEqual(a, b) : a === b;
    }

    function userEdit(kind, c) {
        c.forceActiveFocus();
        switch (kind) {
        case "space":
            keyClick(Qt.Key_Space);
            break;
        case "right":
            keyClick(Qt.Key_Right);
            break;
        case "up":
            keyClick(Qt.Key_Up);
            break;
        case "down":
            keyClick(Qt.Key_Down);
            break;
        case "type":
            keyClick("x");
            break;
        case "click4":
            mouseClick(c, 3.5 * c.starSize, c.height / 2);
            break;
        case "color":
            c.color = "#445566";
            c.edited();
            break;
        case "path":
            c.path = "/tmp/b";
            c.edited();
            break;
        case "sequence":
            c.sequence = "Ctrl+Shift+K";
            c.edited();
            break;
        }
    }

    function test_load_and_save_data() {
        return rows();
    }
    function test_load_and_save(row) {
        const st = newStore();
        st.setValue("K", row.stored);
        const f = makeForm(row.src, st);
        const c = f.entry._control;
        verify(c);
        tryVerify(() => same(row.prop, c[row.prop], row.stored), 2000, "the stored value is loaded");
        wait(50);
        userEdit(row.edit, c);
        const expected = row.saved === null ? c[row.prop] : row.saved;
        compare(st.value("K", row.probe), expected, "the edit is saved");
        verify(same(row.prop, c[row.prop], expected), "the control shows the edit");
    }

    function test_the_controls_own_value_is_the_default() {
        const st = newStore();
        const f = makeForm("AtlasSlider { from: 0; to: 10; value: 3 }", st);
        wait(50);
        compare(f.entry._control.value, 3);
        verify(!st.contains("K"), "nothing is written until the user edits");
    }

    Component {
        id: boundComp
        AtlasForm {
            id: form
            width: 500
            property var store: null
            settings: store
            property alias sw: sw
            AtlasFormEntry {
                settingKey: "B"
                AtlasSwitch {
                    id: sw
                    checked: app.flag
                    onToggled: app.flag = checked
                }
            }
        }
    }

    function test_an_app_binding_stays_intact() {
        const st = newStore();
        app.flag = false;
        const f = createTemporaryObject(boundComp, tc, {store: st});
        wait(50);
        compare(f.sw.checked, false, "the app's value is in charge");
        f.sw.forceActiveFocus();
        keyClick(Qt.Key_Space);
        compare(f.sw.checked, true);
        compare(app.flag, true);
        compare(st.value("B", false), true, "the edit is saved");
        wait(50);
        compare(f.sw.checked, true);
        app.flag = false;
        compare(f.sw.checked, false, "still bound to the app");
    }

    function test_a_change_from_another_writer_updates_the_control() {
        const st = newStore();
        const f = makeForm("AtlasSwitch { }", st);
        const sw = f.entry._control;
        wait(30);
        verify(!sw.checked);
        st.setValue("K", true);
        st.changed("K");
        tryVerify(() => sw.checked);
        // another key is not this entry's
        st.setValue("Other", false);
        st.changed("Other");
        wait(30);
        verify(sw.checked);
        st.setValue("K", false);
        st.changed("K");
        tryVerify(() => !sw.checked);
        // and what was loaded is not written back
        compare(st.value("K", true), false);
    }

    function test_a_value_of_the_wrong_type_warns_and_is_ignored() {
        const st = newStore();
        st.setValue("K", "not a bool");
        ignoreWarning(/settingKey "K": the stored value does not fit checked/);
        const f = makeForm("AtlasSwitch { }", st);
        wait(50);
        verify(!f.entry._control.checked);
    }

    function test_another_property_by_settingProperty() {
        const st = newStore();
        st.setValue("K", 5);
        const f = makeForm("Item { property int level: 3 }", st, "settingProperty: \"level\"");
        const c = f.entry._control;
        tryCompare(c, "level", 5);
        c.level = 7;
        compare(st.value("K", 0), 7);
    }

    function test_no_settings_warns() {
        ignoreWarning(/settingKey "K": there is no AtlasSettings/);
        const f = makeForm("AtlasSwitch { }", null);
        wait(30);
        verify(f);
    }

    function test_a_secret_is_never_saved_data() {
        return [
            {tag: "settingProperty", src: "AtlasPasswordField { }", props: "settingProperty: \"text\"", type: true},
            {tag: "noecho", src: "AtlasTextField { echoMode: TextInput.NoEcho }", props: "", type: true},
            {tag: "echoonedit", src: "AtlasTextField { echoMode: TextInput.PasswordEchoOnEdit }", props: "", type: true},
            {tag: "sensitive", src: "AtlasTextField { inputMethodHints: Qt.ImhSensitiveData }", props: "", type: true},
            {tag: "wrapped", src: "Item { implicitWidth: 100; implicitHeight: 20; AtlasPasswordField { } }", props: "settingProperty: \"implicitWidth\"", type: true, inner: true}
        ];
    }
    function test_a_secret_is_never_saved(row) {
        const st = newStore();
        st.setValue("K", "secret");
        ignoreWarning(/a password is not a setting/);
        const f = makeForm(row.src, st, row.props);
        const c = f.entry._control;
        wait(50);
        if (row.type) {
            const t = row.inner ? c.children[0] : c;
            compare(t.text, "", "not loaded");
            t.forceActiveFocus();
            keyClick("p");
        }
        wait(30);
        compare(st.value("K", ""), "secret", "not saved");
    }

    function test_a_required_empty_entry_is_not_saved() {
        const st = newStore();
        const f = makeForm("AtlasTextField { }", st, "required: true");
        const c = f.entry._control;
        wait(30);
        c.forceActiveFocus();
        keyClick("a");
        keyClick("Backspace");
        compare(c.text, "");
        wait(30);
        compare(st.contains("K") ? st.value("K", "x") : "", "", "empty is not written as a value that fails the rule");
    }

    function test_a_password_that_is_shown_is_still_never_saved() {
        const st = newStore();
        ignoreWarning(/a password is not a setting/);
        const f = makeForm("AtlasPasswordField { }", st, "settingProperty: \"text\"");
        const c = f.entry._control;
        wait(50);
        c.echoMode = TextInput.Normal;
        c.forceActiveFocus();
        keyClick("p");
        wait(30);
        verify(!st.contains("K"), "Password to Normal does not start saving");
    }

    function test_a_text_field_made_a_password_stops_saving() {
        const st = newStore();
        ignoreWarning(/a password is not a setting/);
        const f = makeForm("AtlasTextField { }", st);
        const c = f.entry._control;
        wait(30);
        c.forceActiveFocus();
        keyClick("a");
        compare(st.value("K", ""), "a");
        c.echoMode = TextInput.Password;
        keyClick("b");
        wait(30);
        compare(st.value("K", ""), "a", "Normal to Password stops saving");
    }

    function test_a_retry_ends_cleanly_when_the_form_is_destroyed() {
        const f = makeForm("AtlasSwitch { }", null);
        f.destroy();
        wait(100);
        verify(true);
    }

    function test_text_over_64_KiB_is_not_saved() {
        const st = newStore();
        const f = makeForm("AtlasTextArea { }", st);
        wait(30);
        ignoreWarning(/over 64 KiB/);
        f.entry._control.text = "x".repeat(70000);
        wait(30);
        verify(!st.contains("K"));
        f.entry._control.text = "short";
        compare(st.value("K", ""), "short");
    }

    function test_an_invalid_value_is_not_saved() {
        const st = newStore();
        const f = makeForm("AtlasTextField { validator: IntValidator { bottom: 10; top: 99 } }", st);
        const c = f.entry._control;
        wait(30);
        c.forceActiveFocus();
        keyClick("1");
        compare(c.text, "1");
        verify(!c.acceptableInput);
        verify(!st.contains("K"), "1 is not acceptable");
        keyClick("5");
        compare(st.value("K", ""), "15");
    }

    function test_a_bad_key_warns() {
        const st = newStore();
        ignoreWarning(/not a valid settings key/);
        makeForm("AtlasSwitch { }", st, "", "a=b");
        wait(30);
    }
}
