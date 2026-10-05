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
            keyClick(Qt.Key_Return);
            compare(f.text, "Bern");
            compare(acceptedSpy.count, 1);
            compare(acceptedSpy.signalArguments[0][0], "Bern");
            verify(!f.popupOpen);
            verify(f._field.activeFocus, "the field keeps the focus");
        }

        function test_tab_takes_the_first_suggestion() {
            const f = make();
            keyClick("p");
            tryVerify(() => f.popupOpen);
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
            keyClick(Qt.Key_Return);
            compare(f.text, "Rome");
        }

        function test_html_is_escaped() {
            const f = make({ model: ["a<b>c", "a&b"] });
            keyClick("a");
            tryVerify(() => f.popupOpen);
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
    }
}
