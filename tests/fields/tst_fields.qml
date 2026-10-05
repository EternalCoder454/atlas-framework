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
            AtlasChip { objectName: "chipA"; text: "A" }
            AtlasChip { objectName: "chipB"; text: "B" }
            AtlasChip { objectName: "chipC"; text: "C" }
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
    Component {
        id: spinComp
        AtlasSpinBox {
            from: 0
            to: 999
            editable: true
            prefix: "$ "
            suffix: " GB"
        }
    }
    Component {
        id: neverDialog
        Item {
            property url currentFile
            property url currentFolder
            visible: false
            function open() {
            }
        }
    }
    Component {
        id: briefDialog
        Item {
            property url currentFile
            property url currentFolder
            visible: false
            function open() {
                visible = true;
                Qt.callLater(() => visible = false);
            }
        }
    }
    Component {
        id: slowDialog
        Item {
            property url currentFile
            property url currentFolder
            visible: false
            // Shows after the field's open check has given up.
            Timer {
                id: late
                interval: 1500
                onTriggered: parent.visible = true
            }
            function open() {
                late.start();
            }
        }
    }
    Component {
        id: folderFieldComp
        AtlasFolderField {
            width: 300
        }
    }
    Component {
        id: fileFieldComp
        AtlasFileField {
            width: 300
        }
    }
    Component {
        id: pickerComp
        AtlasFontPicker {
            width: 300
        }
    }
    ListModel {
        id: bigModel
    }
    ListModel {
        id: segModel
        ListElement { text: "One" }
        ListElement { text: "Two" }
    }

    TestCase {
        name: "FieldsAndButtons"
        when: windowShown

        // Every item under `item`, itself first.
        function walk(item) {
            const out = [item];
            for (let i = 0; i < item.children.length; ++i) {
                out.push(...walk(item.children[i]));
            }
            return out;
        }

        // The first item inside `parent` with this objectName.
        function part(parent, name) {
            const item = findChild(parent, name);
            verify(item !== null, name + " exists");
            return item;
        }

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
            const main = part(b, "mainPart");
            main.forceActiveFocus();
            verify(main.activeFocus);
            keyClick(Qt.Key_Return);
            compare(spy.count, 1);
        }

        Component {
            id: signalSpyComp
            SignalSpy {}
        }

        function test_chip_group_tab_stop_moves_when_the_chip_hides() {
            const g = createTemporaryObject(chipGroupComp, root);
            const a = part(g, "chipA");
            const b = part(g, "chipB");
            const c = part(g, "chipC");
            tryCompare(a, "focusPolicy", Qt.StrongFocus);
            a.visible = false;
            tryCompare(b, "focusPolicy", Qt.StrongFocus);
            compare(a.focusPolicy, Qt.ClickFocus);
            b.enabled = false;
            tryCompare(c, "focusPolicy", Qt.StrongFocus);
        }

        function test_chip_moved_out_of_its_group_is_a_tab_stop_again() {
            const g = createTemporaryObject(chipGroupComp, root);
            const b = part(g, "chipB");
            tryCompare(b, "focusPolicy", Qt.ClickFocus);
            compare(b._tabOwner, g);
            b.parent = root;
            compare(b._tabOwner, null);
            compare(b.focusPolicy, Qt.StrongFocus);
            // The group no longer hears from it.
            failOnWarning(new RegExp(".*"));
            b.visible = false;
            b.destroy();
            wait(0);
        }

        function test_chip_group_destroyed_with_its_chips_warns_nothing() {
            failOnWarning(new RegExp(".*"));
            const g = chipGroupComp.createObject(root);
            tryCompare(part(g, "chipA"), "focusPolicy", Qt.StrongFocus);
            part(g, "chipB").visible = false;
            g.destroy();
            wait(50);
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
            const button = part(z, "browseButton");
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
            failOnWarning(new RegExp(".*"));
            c.popup.open();
            tryVerify(() => c.popup.visible);
            compare(c.count, 3);
            compare(c.textAt(0), "");
            const list = part(c.popup.contentItem, "choices");
            compare(list.count, 3, "no filter: every row, including the null ones, is listed");
            part(c.popup.contentItem, "filterField").text = "x";
            tryCompare(list, "count", 1);
            c.popup.close();
        }

        function test_combo_box_rows_survive_switching_filterable() {
            const c = createTemporaryObject(comboComp, root, {model: ["One", "Two", "Three"]});
            c.popup.open();
            tryVerify(() => c.popup.visible);
            tryCompare(part(c.popup.contentItem, "choices"), "count", 3);
            c.filterable = true;
            tryCompare(part(c.popup.contentItem, "choices"), "count", 3);
            c.filterable = false;
            tryCompare(part(c.popup.contentItem, "choices"), "count", 3);
            c.popup.close();
            // And opened again in each mode.
            c.popup.open();
            tryVerify(() => c.popup.visible);
            tryCompare(part(c.popup.contentItem, "choices"), "count", 3);
            c.popup.close();
        }

        function test_color_field_duplicate_swatch() {
            // A translucent colour that is in the palette adds no second swatch.
            const f = createTemporaryObject(colorField, root, {showAlpha: true, color: Qt.rgba(218 / 255, 68 / 255, 83 / 255, 0.5)});
            f.forceActiveFocus();
            mouseClick(f);
            const swatches = [];
            for (const w of walk(f.Window.window.contentItem)) {
                if (w.hasOwnProperty("modelData") && typeof w.modelData === "string" && w.modelData.charAt(0) === "#" && w.hasOwnProperty("current")) {
                    swatches.push(w.modelData);
                }
            }
            compare(swatches.filter(h => h === "#da4453").length, 1);
        }

        function test_popup_close_with_focus_moving_does_not_throw() {
            const f = createTemporaryObject(colorField, root, {x: 10, y: 10});
            const other = createTemporaryObject(emailField, root, {x: 10, y: 200});
            f.forceActiveFocus();
            failOnWarning(new RegExp(".*"));
            mouseClick(f);
            tryVerify(() => f.Window.window.activeFocusItem !== f, 2000);
            keyClick(Qt.Key_Escape);
            tryVerify(() => f.activeFocus, 2000, "focus comes back to the field when it was in the popup");
            // Open again and click elsewhere: focus stays where the user put it.
            mouseClick(f);
            tryVerify(() => f.Window.window.activeFocusItem !== f, 2000);
            mouseClick(other);
            tryVerify(() => other.activeFocus, 2000);
            verify(!f.activeFocus);
        }

        function _browseButton(f) {
            for (const w of walk(f)) {
                if (w.hasOwnProperty("symbol") && w.hasOwnProperty("clicked") && w.text === "Browse\u2026") {
                    return w;
                }
            }
            return null;
        }

        function _textField(f) {
            for (const w of walk(f)) {
                if (w.hasOwnProperty("invalidText") && w.hasOwnProperty("hasError")) {
                    return w;
                }
            }
            return null;
        }

        function test_file_field_symbols_and_validator() {
            verify(Symbols.FileOpen !== undefined && Symbols.Save !== undefined);
            const f = createTemporaryObject(fileFieldComp, root);
            const b = _browseButton(f);
            verify(b !== null, "the Browse button exists");
            compare(b.symbol, Symbols.FileOpen);
            f.saveMode = true;
            compare(b.symbol, Symbols.Save);
            f.validator = Qt.createQmlObject('import Atlas.Ui; AtlasUrlValidator {}', root);
            f.invalidText = "Not a path";
            compare(f.invalidText, "Not a path");
            const tf = _textField(f);
            verify(tf !== null);
            verify(!tf.hasError, "nothing shows before the user has typed");
            tf.forceActiveFocus();
            keyClick("x");
            keyClick(Qt.Key_Return);
            tryVerify(() => tf.hasError, 2000, "invalidText shows for an invalid path");
        }

        function test_file_and_folder_field_say_a_dialog_that_does_not_open() {
            for (const comp of [fileFieldComp, folderFieldComp]) {
                const f = createTemporaryObject(comp, root, {_dialogOverride: neverDialog});
                const tf = _textField(f);
                verify(tf !== null);
                verify(tf.errorText === "");
                _browseButton(f).clicked();
                tryVerify(() => tf.errorText === "The dialog could not be opened.", 3000);
                // A typed path clears it.
                tf.forceActiveFocus();
                keyClick("a");
                tryCompare(tf, "errorText", "");
            }
        }

        function test_file_and_folder_field_dialog_that_opens_and_closes_is_no_error() {
            for (const comp of [fileFieldComp, folderFieldComp]) {
                const f = createTemporaryObject(comp, root, {_dialogOverride: briefDialog});
                const tf = _textField(f);
                _browseButton(f).clicked();
                wait(1300);
                compare(tf.errorText, "", "a dialog that was shown and cancelled is not an error");
            }
        }

        function test_file_and_folder_field_dialog_that_opens_late_clears_the_error() {
            for (const comp of [fileFieldComp, folderFieldComp]) {
                const f = createTemporaryObject(comp, root, {_dialogOverride: slowDialog});
                const tf = _textField(f);
                _browseButton(f).clicked();
                tryVerify(() => tf.errorText === "The dialog could not be opened.", 3000);
                tryCompare(tf, "errorText", "", 3000, "the error goes once the dialog shows");
            }
        }

        function test_spin_box_validator_refuses_letters() {
            const s = createTemporaryObject(spinComp, root);
            s.contentItem.forceActiveFocus();
            s.contentItem.selectAll();
            keyClick("x");
            verify(s.contentItem.text.indexOf("x") < 0, "a letter is refused");
        }

        function test_spin_box_number_typed_over_a_selection_commits_with_a_prefix() {
            const s = createTemporaryObject(spinComp, root, {suffix: ""});
            s.contentItem.forceActiveFocus();
            s.contentItem.selectAll();
            keyClick("4");
            keyClick("2");
            compare(s.contentItem.text, "42", "digits typed over the selection are accepted without the prefix");
            keyClick(Qt.Key_Return);
            tryCompare(s, "value", 42);
        }

        function test_spin_box_number_typed_over_a_selection_commits_with_a_suffix() {
            const s = createTemporaryObject(spinComp, root, {prefix: ""});
            s.contentItem.forceActiveFocus();
            s.contentItem.selectAll();
            keyClick("7");
            keyClick(Qt.Key_Return);
            tryCompare(s, "value", 7);
        }

        function test_spin_box_pattern_takes_prefix_suffix_and_arabic_numbers() {
            const s = createTemporaryObject(spinComp, root);
            verify(s._pattern.test("$ 12 GB"), "prefix and suffix");
            verify(s._pattern.test("12"), "neither");
            verify(s._pattern.test("$ 12"), "prefix only");
            verify(s._pattern.test("12 GB"), "suffix only");
            verify(!s._pattern.test("1x2"), "a letter");
            // Arabic digits, decimal and group separators, and a direction mark
            // round the sign. (No ar_EG commit test: whether Number.fromLocaleString
            // reads these depends on the Qt build's locale data, so only the
            // pattern is checked here.)
            verify(s._pattern.test("\u200f-\u0661\u066c\u0662\u0663\u0664\u066b\u0665"));
        }

        function test_combo_box_filters_ten_thousand_rows() {
            const rows = [];
            for (let i = 0; i < 10000; ++i) {
                rows.push("Item " + i);
            }
            const c = createTemporaryObject(comboComp, root, {model: rows, filterable: true});
            c.popup.open();
            tryVerify(() => c.popup.visible);
            const list = part(c.popup.contentItem, "choices");
            compare(list.count, 10000);
            verify(list.contentItem.children.length < 200, "only the visible rows are built, not 10000");
            part(c.popup.contentItem, "filterField").text = "99";
            const expected = rows.filter(r => r.toLowerCase().indexOf("99") >= 0).length;
            tryCompare(list, "count", expected);
            verify(expected > 0 && expected < 10000);
            c.popup.close();
        }

        function test_font_picker_pixel_font_shows_no_minus_one_pt() {
            const f = createTemporaryObject(pickerComp, root);
            f.font.pixelSize = 14;
            compare(f.font.pointSize, -1);
            const texts = [];
            for (const t of walk(f)) {
                if (typeof t.text === "string") {
                    texts.push(t.text);
                }
            }
            verify(texts.every(t => t.indexOf("-1") < 0), "no -1 anywhere: " + texts.join("|"));
            verify(f.Accessible.description.indexOf("-1") < 0);
        }

        function test_font_picker_scan_is_shared() {
            const a = createTemporaryObject(pickerComp, root, {fixedOnly: true});
            tryVerify(() => a._scanned > 0, 5000);
            const b = createTemporaryObject(pickerComp, root, {fixedOnly: true});
            verify(b._scanned >= a._scanned, "a second picker starts where the first got to");
        }

        function test_color_field_label_for_alpha_999() {
            const f = createTemporaryObject(colorField, root, {showAlpha: true, color: Qt.rgba(1, 0, 0, 0.999)});
            compare(f._label, "#ff0000");
        }
    }
}
