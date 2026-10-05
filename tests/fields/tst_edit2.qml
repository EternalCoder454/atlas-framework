import QtQuick
import QtTest
import Atlas.Ui

// More user-edit cases (see tst_edit.qml): FindBar keystrokes, cursor and
// undo, an app that normalises the text; AtlasComboBox with instance-level
// handlers, the filter, and a model reset during the held turn.
TestCase {
    id: tc
    name: "UserEdits2"
    width: 700
    height: 400
    visible: true
    when: windowShown

    function findItem(item, test) {
        for (const c of item.children) {
            if (test(c)) {
                return c;
            }
            const r = findItem(c, test);
            if (r) {
                return r;
            }
        }
        return null;
    }
    function turn() {
        wait(30);
    }

    Component {
        id: modelComp
        QtObject {
            property string find: ""
            property int index: 0
        }
    }

    // FindBar ------------------------------------------------------------

    Component {
        id: acceptingBar
        FindBar {
            id: bar
            width: 680
            opened: true
            property var m
            property int changes: 0
            findText: m.find
            onFindTextChanged: {
                ++changes;
                m.find = findText;
            }
        }
    }
    Component {
        id: trimmingBar
        FindBar {
            id: bar
            width: 680
            opened: true
            property var m
            findText: m.find
            onFindTextChanged: m.find = findText.trim()
        }
    }

    function findField(bar) {
        const f = findItem(bar, c => c.hasOwnProperty("placeholderText") && c.placeholderText === "Find");
        verify(f);
        return f;
    }

    function test_find_text_changes_once_per_keystroke() {
        const m = createTemporaryObject(modelComp, tc);
        const b = createTemporaryObject(acceptingBar, tc, {
            m: m
        });
        tryCompare(b, "height", b.fullHeight);
        const f = findField(b);
        f.forceActiveFocus();
        b.changes = 0;
        for (const ch of "abc") {
            keyClick(ch);
            turn();
        }
        compare(f.text, "abc");
        compare(b.findText, "abc");
        compare(m.find, "abc");
        compare(b.changes, 3);
    }

    function test_cursor_and_undo_survive() {
        const m = createTemporaryObject(modelComp, tc);
        const b = createTemporaryObject(acceptingBar, tc, {
            m: m
        });
        tryCompare(b, "height", b.fullHeight);
        const f = findField(b);
        f.forceActiveFocus();
        keyClick("a");
        turn();
        keyClick("b");
        turn();
        keyClick(Qt.Key_Left);
        keyClick("c");
        turn();
        compare(f.text, "acb");
        compare(f.cursorPosition, 2);
        verify(f.canUndo);
        f.undo();
        turn();
        compare(f.text, "ab");
        compare(b.findText, "ab");
    }

    function test_app_that_trims() {
        const m = createTemporaryObject(modelComp, tc);
        const b = createTemporaryObject(trimmingBar, tc, {
            m: m
        });
        tryCompare(b, "height", b.fullHeight);
        const f = findField(b);
        f.forceActiveFocus();
        keyClick("a");
        turn();
        keyClick(" ");
        turn();
        compare(m.find, "a");
        compare(b.findText, "a", "the bar follows what the app stored");
        compare(f.text, "a", "and so does the field");
        keyClick("b");
        turn();
        compare(b.findText, "ab");
        compare(f.text, "ab");
    }

    // AtlasComboBox ------------------------------------------------------

    Component {
        id: handlerCombo
        AtlasComboBox {
            id: cb
            property var m
            width: 200
            model: ["A", "B", "C"]
            currentIndex: m.index
            onActivated: index => m.index = index
        }
    }
    Component {
        id: refusingCombo
        AtlasComboBox {
            property var m
            width: 200
            model: ["A", "B", "C"]
            currentIndex: m.index
        }
    }
    Component {
        id: filterCombo
        AtlasComboBox {
            property var m
            width: 200
            filterable: true
            model: ["Apple", "Banana", "Cherry"]
            currentIndex: m.index
            onActivated: index => m.index = index
        }
    }
    Component {
        id: refusingFilterCombo
        AtlasComboBox {
            property var m
            width: 200
            filterable: true
            model: ["Apple", "Banana", "Cherry"]
            currentIndex: m.index
        }
    }

    function test_instance_handler_stores_the_edit() {
        const m = createTemporaryObject(modelComp, tc);
        const c = createTemporaryObject(handlerCombo, tc, {
            m: m
        });
        c.forceActiveFocus();
        keyClick(Qt.Key_Down);
        turn();
        compare(m.index, 1);
        compare(c.currentIndex, 1);
        m.index = 2;
        compare(c.currentIndex, 2, "still bound");
    }

    function test_filterable_choice_with_bound_index() {
        const m = createTemporaryObject(modelComp, tc);
        const c = createTemporaryObject(filterCombo, tc, {
            m: m
        });
        c.popup.open();
        tryVerify(() => c.popup.opened);
        const f = findItem(c.popup.contentItem, x => x.hasOwnProperty("placeholderText") && x.placeholderText === "Filter");
        verify(f);
        f.forceActiveFocus();
        keyClick("c");
        keyClick("h");
        keyClick(Qt.Key_Return);
        turn();
        compare(m.index, 2);
        compare(c.currentIndex, 2);
        m.index = 0;
        compare(c.currentIndex, 0, "still bound");
    }

    function test_filterable_choice_refused_springs_back() {
        const m = createTemporaryObject(modelComp, tc);
        const c = createTemporaryObject(refusingFilterCombo, tc, {
            m: m
        });
        c.popup.open();
        tryVerify(() => c.popup.opened);
        const f = findItem(c.popup.contentItem, x => x.hasOwnProperty("placeholderText") && x.placeholderText === "Filter");
        verify(f);
        f.forceActiveFocus();
        keyClick("c");
        keyClick("h");
        keyClick(Qt.Key_Return);
        turn();
        compare(c.currentIndex, 0, "no handler took it: springs back");
        m.index = 1;
        compare(c.currentIndex, 1, "still bound");
    }

    function test_model_reset_during_the_held_turn() {
        const m = createTemporaryObject(modelComp, tc);
        const c = createTemporaryObject(refusingCombo, tc, {
            m: m
        });
        c.forceActiveFocus();
        keyClick(Qt.Key_Down);
        c.model = ["X", "Y"];
        turn();
        compare(c.currentIndex, 0, "the binding is back");
        m.index = 1;
        compare(c.currentIndex, 1, "and still bound");
    }
}
