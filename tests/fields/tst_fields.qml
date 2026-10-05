import QtQuick
import QtTest
import Atlas.Ui

Item {
    id: root
    width: 400
    height: 300

    property int escapes: 0
    Keys.onEscapePressed: root.escapes++

    Component {
        id: autocomplete
        AtlasAutocompleteField {
            x: 20
            y: 20
            width: 300
            model: ["Berlin", "Bern", "Bergen", "Paris", "Bremen"]
        }
    }
    Component {
        id: colorField
        AtlasColorField {}
    }

    Component {
        id: emailField
        AtlasTextField {
            width: 300
            validator: AtlasEmailValidator {}
            invalidText: "Enter an email address"
        }
    }

    ListModel {
        id: lm
        ListElement { name: "Oslo" }
        ListElement { name: "Rome" }
    }

    SignalSpy {
        id: acceptedSpy
        signalName: "accepted"
    }

    TestCase {
        name: "Autocomplete"
        when: windowShown

        function make(props) {
            const f = createTemporaryObject(autocomplete, root, props || {});
            verify(f !== null);
            f.forceActiveFocus();
            tryVerify(() => f._field.activeFocus);
            acceptedSpy.target = f;
            acceptedSpy.clear();
            root.escapes = 0;
            return f;
        }

        function test_down_and_return_take_the_second_suggestion() {
            const f = make();
            keyClick("B");
            keyClick("e");
            keyClick("r");
            tryVerify(() => f.popupOpen);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(f.text, "Bern");
            compare(acceptedSpy.count, 1);
            compare(acceptedSpy.signalArguments[0][0], "Bern");
            verify(!f.popupOpen);
            verify(f._field.activeFocus, "the field keeps the focus");
        }

        function test_return_without_moving_the_highlight_submits_the_typed_text() {
            const f = make();
            keyClick("B");
            keyClick("e");
            keyClick("r");
            tryVerify(() => f.popupOpen);
            keyClick(Qt.Key_Return);
            compare(f.text, "Ber");
            compare(acceptedSpy.count, 1);
            compare(acceptedSpy.signalArguments[0][0], "Ber");
        }

        function test_fast_return_acts_on_the_typed_text() {
            const f = make();
            keyClick("p");
            keyClick("a");
            keyClick(Qt.Key_Return); // inside the 60 ms debounce
            compare(acceptedSpy.signalArguments[0][0], "pa");
        }

        function test_tab_takes_the_first_suggestion() {
            const f = make();
            keyClick("p");
            tryVerify(() => f.popupOpen);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Tab);
            compare(f.text, "Paris");
            verify(f._field.activeFocus);
        }

        function test_escape_closes_then_passes_on() {
            const f = make();
            keyClick("b");
            tryVerify(() => f.popupOpen);
            keyClick(Qt.Key_Escape);
            verify(!f.popupOpen);
            compare(root.escapes, 0);
            keyClick(Qt.Key_Escape);
            compare(root.escapes, 1);
        }

        function test_contains_and_starts_with() {
            const f = make();
            keyClick("e");
            keyClick("m");
            tryVerify(() => f.popupOpen);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(f.text, "Bremen");
            f.text = "";
            f.filter = "startsWith";
            keyClick("e");
            keyClick("m");
            wait(200);
            verify(!f.popupOpen, "no string starts with 'em'");
        }

        function test_return_without_list_is_accepted() {
            const f = make();
            f.text = "Rome";
            keyClick(Qt.Key_Return);
            compare(acceptedSpy.count, 1);
            compare(acceptedSpy.signalArguments[0][0], "Rome");
        }

        function test_large_model_stays_quick() {
            const big = [];
            for (let i = 0; i < 10000; ++i) {
                big.push("item " + i);
            }
            const f = make({ model: big, maxSuggestions: 5 });
            const t0 = Date.now();
            keyClick("9");
            keyClick("9");
            tryVerify(() => f.popupOpen, 2000);
            verify(Date.now() - t0 < 1000, "took " + (Date.now() - t0) + " ms");
            keyClick(Qt.Key_Return);
            verify(f.text.indexOf("99") >= 0);
        }

        function test_model_with_text_role() {
            const f = make({ model: lm, textRole: "name" });
            keyClick("o");
            tryVerify(() => f.popupOpen);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(f.text, "Rome");
        }

        function test_html_is_escaped() {
            const f = make({ model: ["a<b>c", "a&b"] });
            keyClick("a");
            tryVerify(() => f.popupOpen);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(f.text, "a<b>c");
        }
    }

    TestCase {
        name: "ColorField"
        when: windowShown

        function test_hex_parsing() {
            const f = createTemporaryObject(colorField, root);
            compare(String(f._parseHex("#3daee9")), "#3daee9");
            compare(String(f._parseHex("3daee9")), "#3daee9");
            compare(String(f._parseHex("#f00")), "#ff0000");
            compare(f._parseHex("#12"), undefined);
            compare(f._parseHex("#12345"), undefined);
            compare(f._parseHex("#gg0000"), undefined);
            compare(f._parseHex(""), undefined);
            compare(f._parseHex("#80ff0000"), undefined, "alpha is off");
            f.showAlpha = true;
            compare(String(f._parseHex("#80ff0000")), "#80ff0000");
        }

        function test_hex_text() {
            const f = createTemporaryObject(colorField, root, { color: "#3daee9" });
            compare(f.hex, "#3daee9");
            f.showAlpha = true;
            f.color = "#803daee9";
            compare(f.hex, "#803daee9");
        }

        function test_rgba_text_and_input() {
            const f = createTemporaryObject(colorField, root, { color: "#3daee9" });
            compare(f._label, "#3daee9", "opaque shows hex");
            f.showAlpha = true;
            f.color = Qt.rgba(104 / 255, 88 / 255, 226 / 255, 0.5);
            compare(f._label, "rgba(104, 88, 226, 0.5)");
            const c = f._parseHex("rgba(104, 88, 226, 0.5)");
            verify(c !== undefined);
            compare(Math.round(c.r * 255), 104);
            compare(Math.round(c.a * 100), 50);
            compare(String(f._parseHex("rgb(255, 0, 0)")), "#ff0000");
            compare(f._parseHex("rgba(300, 0, 0, 1)"), undefined);
            compare(f._parseHex("rgba(1, 2, 3, 1.5)"), undefined);
            compare(f._parseHex("rgba(1, 2, 3"), undefined);
            f.showAlpha = false;
            compare(f._parseHex("rgba(1, 2, 3, 0.5)"), undefined, "alpha is off");
        }
    }

    TestCase {
        name: "ValidationTiming"
        when: windowShown

        function test_error_waits_for_leaving_then_follows_live() {
            const f = createTemporaryObject(emailField, root);
            f.forceActiveFocus();
            keyClick("a");
            keyClick("@");
            keyClick("b");
            verify(!f.acceptableInput);
            verify(!f.hasError, "no error while typing an unfinished address");
            // Leaving the field shows it.
            root.forceActiveFocus();
            tryVerify(() => f.hasError);
            // Back in the field the error updates live and clears when valid.
            f.forceActiveFocus();
            keyClick(".");
            keyClick("c");
            keyClick("o");
            verify(f.acceptableInput);
            verify(!f.hasError, "gone as soon as the text is valid");
            keyClick(Qt.Key_Backspace);
            keyClick(Qt.Key_Backspace);
            keyClick(Qt.Key_Backspace);
            verify(!f.hasError, "once acceptable the error waits for the next blur again");
            root.forceActiveFocus();
            tryVerify(() => f.hasError);
        }

        function test_blur_on_valid_then_partial_shows_no_error_until_blur() {
            const f = createTemporaryObject(emailField, root);
            f.forceActiveFocus();
            f.text = "a@b.co";
            verify(f.acceptableInput);
            root.forceActiveFocus();
            verify(!f.hasError);
            f.forceActiveFocus();
            f.text = "";
            keyClick("a");
            keyClick("@");
            verify(!f.acceptableInput);
            verify(!f.hasError, "no error while typing after a valid blur");
            root.forceActiveFocus();
            tryVerify(() => f.hasError);
        }

        function test_return_shows_the_error() {
            const f = createTemporaryObject(emailField, root);
            f.forceActiveFocus();
            keyClick("x");
            verify(!f.hasError);
            keyClick(Qt.Key_Return);
            verify(f.hasError);
        }

        function test_typing_mode_and_app_error_show_at_once() {
            const f = createTemporaryObject(emailField, root, { validateOn: "typing" });
            f.forceActiveFocus();
            keyClick("x");
            verify(f.hasError);
            const g = createTemporaryObject(emailField, root, { errorText: "Taken" });
            verify(g.hasError, "an app-set errorText shows at once");
        }
    }

    property int bound: 50
    Component {
        id: spin
        AtlasSpinBox {
            from: 0
            to: 100
            value: root.bound
            editable: true
        }
    }
    Component {
        id: dspin
        AtlasDoubleSpinBox {
            from: 0
            to: 5000
            value: 1234.5
            decimals: 2
            editable: true
        }
    }

    TestCase {
        name: "SpinBoxes"
        when: windowShown

        function test_page_keys_keep_the_binding() {
            const s = createTemporaryObject(spin, root);
            verify(s);
            s.forceActiveFocus();
            keyClick(Qt.Key_PageUp);
            compare(s.value, 60);
            keyClick(Qt.Key_PageDown);
            keyClick(Qt.Key_PageDown);
            compare(s.value, 40);
            // The binding survived: the app's property still drives the value.
            root.bound = 7;
            compare(s.value, 7);
            // The ends hold, also with wrap.
            s.wrap = true;
            keyClick(Qt.Key_PageDown);
            compare(s.value, 0);
            root.bound = 95;
            keyClick(Qt.Key_PageUp);
            compare(s.value, 100);
        }

        function test_double_text_and_bad_input() {
            const d = createTemporaryObject(dspin, root);
            verify(d);
            compare(d.textFromValue(1234.5, d.locale).indexOf(d.locale.groupSeparator), -1, "no group separator in the text");
            // Text that is not a number gives the old value back.
            compare(d.valueFromText("abc", d.locale), d.value);
            compare(d.valueFromText("", d.locale), d.value);
        }
    }

    // ROADMAP B2, Fields and buttons.
    Component {
        id: buttonWithAction
        AtlasButton {
            text: "Go"
            checkable: true
        }
    }
    Component {
        id: chipComp
        AtlasChip {
            text: "Tag"
            checkable: true
        }
    }
    Component {
        id: splitComp
        AtlasSplitButton {
            text: "Save"
            ContextMenuItem { text: "Save As" }
        }
    }
    Component {
        id: chipGroupComp
        AtlasChipGroup {
            width: 300
            AtlasChip { text: "A" }
            AtlasChip { text: "B" }
            AtlasChip { text: "C" }
        }
    }
    Component {
        id: dropComp
        AtlasDropZone {
            width: 300
            height: 150
            browseText: "Browse"
            nameFilters: ["*.png", "a?.txt"]
        }
    }
    Component {
        id: searchComp
        SearchField {
            width: 200
            delay: 5000
        }
    }
    Component {
        id: shortcutComp
        AtlasShortcutField {
            width: 200
        }
    }
    Component {
        id: segComp
        AtlasSegmentedControl {
            width: 240
        }
    }
    Component {
        id: comboComp
        AtlasComboBox {
            width: 200
        }
    }
    ListModel {
        id: segModel
        ListElement { text: "One" }
        ListElement { text: "Two" }
    }

    TestCase {
        name: "FieldsAndButtons"
        when: windowShown

        function test_return_clicks_through_click_not_clicked() {
            const b = createTemporaryObject(buttonWithAction, root);
            b.forceActiveFocus();
            verify(b.activeFocus);
            keyClick(Qt.Key_Return);
            verify(b.checked, "Return toggles a checkable button");
            const c = createTemporaryObject(chipComp, root);
            c.forceActiveFocus();
            keyClick(Qt.Key_Return);
            verify(c.checked, "Return toggles a checkable chip");
            keyClick(Qt.Key_Enter);
            verify(!c.checked);
        }

        function test_split_button_return_presses_the_focused_part() {
            const b = createTemporaryObject(splitComp, root);
            const spy = createTemporaryObject(signalSpyComp, root, {target: b, signalName: "clicked"});
            const part = b.children[0].children[0];
            part.forceActiveFocus();
            verify(part.activeFocus);
            keyClick(Qt.Key_Return);
            compare(spy.count, 1);
        }

        Component {
            id: signalSpyComp
            SignalSpy {}
        }

        function test_chip_group_tab_stop_moves_when_the_chip_hides() {
            const g = createTemporaryObject(chipGroupComp, root);
            tryCompare(g.children[0].children[0], "focusPolicy", Qt.StrongFocus);
            g.children[0].children[0].visible = false;
            tryCompare(g.children[0].children[1], "focusPolicy", Qt.StrongFocus);
            compare(g.children[0].children[0].focusPolicy, Qt.ClickFocus);
            g.children[0].children[1].enabled = false;
            tryCompare(g.children[0].children[2], "focusPolicy", Qt.StrongFocus);
        }

        function test_autocomplete_mark_survives_a_length_changing_lowercase() {
            const f = createTemporaryObject(autocomplete, root);
            f.text = "stan";
            compare(f._mark("\u0130stanbul"), "\u0130<b>stan</b>bul");
            compare(f._mark("Berlin & Bern"), "Berlin &amp; Bern");
        }

        function test_autocomplete_clear_closes_the_list() {
            const f = createTemporaryObject(autocomplete, root);
            f.forceActiveFocus();
            tryVerify(() => f._field.activeFocus);
            keyClick("b");
            tryVerify(() => f.popupOpen);
            f._field.clear();
            verify(!f.popupOpen, "clearing the text closes the list");
        }

        function test_drop_zone_glob_matches_a_newline_and_browse_emits_once() {
            const z = createTemporaryObject(dropComp, root);
            verify(z._accepts("file:///tmp/a%0Ab.png"), "* matches a newline");
            verify(z._accepts("file:///tmp/a%0A.txt"), "? matches a newline");
            verify(!z._accepts("file:///tmp/a.jpg"));
            const spy = createTemporaryObject(signalSpyComp, root, {target: z, signalName: "browseRequested"});
            const button = z.children[z.children.length - 1].children[3];
            mouseClick(button, button.width / 2, button.height / 2);
            compare(spy.count, 1, "one browseRequested per click");
        }

        function test_search_field_query_follows_return_and_clear_is_off_when_read_only() {
            const f = createTemporaryObject(searchComp, root);
            f.forceActiveFocus();
            keyClick("a");
            compare(f.query, "");
            keyClick(Qt.Key_Return);
            compare(f.query, "a");
            f.readOnly = true;
            keyClick(Qt.Key_Escape);
            compare(f.text, "a", "Escape does not clear a read-only field");
        }

        function test_shortcut_field_records_ctrl_delete_and_ctrl_escape() {
            const f = createTemporaryObject(shortcutComp, root);
            f.forceActiveFocus();
            f.startRecording();
            keyClick(Qt.Key_Delete, Qt.ControlModifier);
            compare(f.sequence, "Ctrl+Del");
            f.startRecording();
            keyClick(Qt.Key_Escape, Qt.ControlModifier);
            compare(f.sequence, "Ctrl+Esc");
            f.startRecording();
            keyClick(Qt.Key_Delete);
            compare(f.sequence, "", "a bare Delete still clears");
        }

        function test_segmented_control_takes_a_list_model_and_a_number() {
            const s = createTemporaryObject(segComp, root, {model: segModel});
            compare(s.count, 2);
            compare(s._text(1), "Two");
            s.model = 3;
            compare(s.count, 3);
            const t = createTemporaryObject(segComp, root, {model: ["A", "B"]});
            mouseClick(t, t.width * 0.75, t.height / 2);
            verify(t.activeFocus, "a click gives the control the focus");
        }

        function test_combo_box_null_entry_and_missing_role_do_not_throw() {
            const c = createTemporaryObject(comboComp, root, {model: [null, {name: "x"}, undefined], textRole: "name", filterable: true});
            c.popup.open();
            tryVerify(() => c.popup.visible);
            compare(c.count, 3);
            c.popup.close();
        }

        function test_color_field_label_for_alpha_999() {
            const f = createTemporaryObject(colorField, root, {showAlpha: true, color: Qt.rgba(1, 0, 0, 0.999)});
            compare(f._label, "#ff0000");
        }
    }
}
