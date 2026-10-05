import QtQuick
import QtTest
import Atlas.Ui

// A user edit and an app binding (docs/api-1.5.0.md, Part 1): a bound value
// that takes the edit stays bound, one that refuses springs back and stays
// bound, a literal or unbound value keeps the edit, and onXChanged fires.
TestCase {
    id: tc
    name: "UserEdits"
    width: 700
    height: 300
    visible: true
    when: windowShown

    QtObject {
        id: model
        property int index: 0
        property string path: "/a"
        property string find: "a"
        property string find2: "a"
        property bool flag: false
    }

    // The first descendant for which `test` is true.
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

    // AtlasComboBox.currentIndex ---------------------------------------

    Component {
        id: comboComp
        AtlasComboBox {
            width: 200
            model: ["A", "B", "C"]
        }
    }

    function combo(props) {
        const c = createTemporaryObject(comboComp, tc, props);
        verify(c);
        c.forceActiveFocus();
        return c;
    }

    function test_combo_bound_and_accepting() {
        model.index = 0;
        const c = combo({});
        c.currentIndex = Qt.binding(() => model.index);
        c.activated.connect(i => model.index = i);
        keyClick(Qt.Key_Down);
        compare(c.currentIndex, 1);
        turn();
        compare(c.currentIndex, 1);
        model.index = 2;
        compare(c.currentIndex, 2, "still bound");
    }

    function test_combo_bound_and_refusing() {
        model.index = 0;
        const c = combo({});
        c.currentIndex = Qt.binding(() => model.index);
        let seen = -1;
        c.currentIndexChanged.connect(() => {
            if (c.currentIndex === 1) {
                seen = 1;
            }
        });
        keyClick(Qt.Key_Down);
        compare(seen, 1, "the edit shows, so onCurrentIndexChanged fires");
        turn();
        compare(c.currentIndex, 0, "springs back");
        model.index = 2;
        compare(c.currentIndex, 2, "still bound");
    }

    function test_combo_unbound_keeps_the_edit() {
        const c = combo({
            currentIndex: 0
        });
        keyClick(Qt.Key_Down);
        turn();
        compare(c.currentIndex, 1);
        const u = combo({});
        keyClick(Qt.Key_Down);
        turn();
        compare(u.currentIndex, 1);
    }

    // AtlasFileField and AtlasFolderField.path -----------------------------

    Component {
        id: fileComp
        AtlasFileField {
            width: 400
        }
    }
    Component {
        id: folderComp
        AtlasFolderField {
            width: 400
        }
    }

    function typeInto(control, text) {
        const f = findItem(control, c => c.hasOwnProperty("textEdited") && c.hasOwnProperty("placeholderText"));
        verify(f);
        f.forceActiveFocus();
        f.selectAll();
        keyClick(text); // one key replaces the selection: one edit
        return f;
    }

    function pathStyles(comp) {
        // bound and accepting
        model.path = "/a";
        let c = createTemporaryObject(comp, tc, {});
        c.path = Qt.binding(() => model.path);
        c.edited.connect(() => model.path = c.path);
        let f = typeInto(c, "x");
        turn();
        compare(c.path, "x");
        compare(f.text, "x");
        model.path = "/z";
        compare(c.path, "/z", "still bound");
        compare(f.text, "/z", "the field follows");

        // bound and refusing
        model.path = "/a";
        c = createTemporaryObject(comp, tc, {});
        c.path = Qt.binding(() => model.path);
        let handled = "";
        c.edited.connect(() => handled = c.path);
        f = typeInto(c, "x");
        compare(handled, "x", "the handler sees the edit");
        turn();
        compare(c.path, "/a", "springs back");
        compare(f.text, "/a", "the field springs back");
        model.path = "/y";
        compare(c.path, "/y", "still bound");

        // unbound
        c = createTemporaryObject(comp, tc, {});
        f = typeInto(c, "x");
        turn();
        compare(c.path, "x");
        c = createTemporaryObject(comp, tc, {
            path: "/lit"
        });
        typeInto(c, "x");
        turn();
        compare(c.path, "x");
    }

    function test_file_field_path() {
        pathStyles(fileComp);
    }
    function test_folder_field_path() {
        pathStyles(folderComp);
    }

    // FindBar -------------------------------------------------------------

    Component {
        id: findComp
        FindBar {
            width: 680
            opened: true
        }
    }

    function findBar(props) {
        const b = createTemporaryObject(findComp, tc, props);
        verify(b);
        tryCompare(b, "height", b.fullHeight);
        return b;
    }
    function toggle(bar, name) {
        const t = findItem(bar, c => c.hasOwnProperty("checkable") && c.text === name);
        verify(t);
        mouseClick(t);
    }

    function test_find_toggles_bound_and_accepting() {
        model.flag = false;
        const b = findBar({});
        b.matchCase = Qt.binding(() => model.flag);
        b.onMatchCaseChanged.connect(() => model.flag = b.matchCase);
        toggle(b, "Match Case");
        turn();
        compare(b.matchCase, true);
        model.flag = false;
        compare(b.matchCase, false, "still bound");
    }

    function test_find_toggles_bound_and_refusing() {
        model.flag = false;
        const b = findBar({});
        b.wholeWords = Qt.binding(() => model.flag);
        let seen = false;
        b.wholeWordsChanged.connect(() => {
            if (b.wholeWords) {
                seen = true;
            }
        });
        toggle(b, "Whole Word");
        compare(seen, true, "onWholeWordsChanged fires");
        turn();
        compare(b.wholeWords, false, "springs back");
        model.flag = true;
        compare(b.wholeWords, true, "still bound");
    }

    function test_find_toggles_unbound() {
        const b = findBar({
            regularExpression: false
        });
        toggle(b, "Regular Expression");
        turn();
        compare(b.regularExpression, true);
        toggle(b, "Regular Expression");
        turn();
        compare(b.regularExpression, false);
    }

    function test_find_text_styles() {
        model.find = "a";
        let b = findBar({});
        b.findText = Qt.binding(() => model.find);
        b.onFindTextChanged.connect(() => model.find = b.findText);
        let f = findItem(b, c => c.hasOwnProperty("placeholderText") && c.placeholderText === "Find");
        verify(f);
        compare(f.text, "a");
        f.forceActiveFocus();
        keyClick("b");
        turn();
        compare(b.findText, "ab");
        model.find = "q";
        compare(b.findText, "q", "still bound");
        compare(f.text, "q");

        // refusing
        model.find2 = "a";
        b = findBar({});
        b.findText = Qt.binding(() => model.find2);
        f = findItem(b, c => c.hasOwnProperty("placeholderText") && c.placeholderText === "Find");
        f.forceActiveFocus();
        let changes = 0;
        let seenText = "";
        b.findTextChanged.connect(() => {
            ++changes;
            if (b.findText !== "a") {
                seenText = b.findText;
            }
        });
        keyClick("b");
        compare(changes >= 1, true, "the change handler fires on the edit");
        compare(seenText, "ab");
        turn();
        compare(b.findText, "a", "springs back");
        compare(f.text, "a");
        model.find2 = "n";
        compare(b.findText, "n", "still bound");

        // unbound, and replaceText
        b = findBar({
            replaceVisible: true
        });
        const r = findItem(b, c => c.hasOwnProperty("placeholderText") && c.placeholderText === "Replace" && c.hasOwnProperty("textEdited"));
        verify(r);
        r.forceActiveFocus();
        keyClick("x");
        turn();
        compare(b.replaceText, "x");
        b.replaceText = "y";
        compare(r.text, "y", "an app write reaches the field");
    }

    // InfoBanner ----------------------------------------------------------

    Component {
        id: bannerComp
        InfoBanner {
            width: 400
            closable: true
            text: "One"
        }
    }

    function dismiss(b) {
        tryVerify(() => b.visible);
        wait(50);
        const x = findItem(b, c => c.hasOwnProperty("visualFocus") && c.hasOwnProperty("pressed") && c.visible && c.Accessible.name === b.closeName);
        verify(x);
        x.clicked();
    }

    function test_banner_dismiss_keeps_shown_bound() {
        model.flag = true;
        const b = createTemporaryObject(bannerComp, tc, {});
        b.shown = Qt.binding(() => model.flag);
        compare(b.shown, true);
        let closed = 0;
        b.closed.connect(() => ++closed);
        dismiss(b);
        compare(closed, 1);
        compare(b.dismissed, true);
        compare(b.shown, false);
        // A new text shows it again.
        b.text = "Two";
        compare(b.dismissed, false);
        compare(b.shown, true);
        // Still bound: it follows the app.
        model.flag = false;
        compare(b.shown, false);
        model.flag = true;
        compare(b.shown, true);
    }

    function test_banner_imperative_show_after_dismiss() {
        const b = createTemporaryObject(bannerComp, tc, {
            shown: false
        });
        b.shown = true;
        dismiss(b);
        compare(b.shown, false);
        compare(b.dismissed, true);
        b.shown = true; // Monitor does this when something reports
        compare(b.shown, true);
        compare(b.dismissed, false);
        b.shown = false;
        compare(b.shown, false);
    }

    function test_banner_new_type_shows_again() {
        const b = createTemporaryObject(bannerComp, tc, {});
        dismiss(b);
        compare(b.shown, false);
        b.type = "error";
        compare(b.dismissed, false);
        compare(b.shown, true);
    }

    // AtlasCopyButton -------------------------------------------------------

    Component {
        id: copyComp
        AtlasCopyButton {
            text: "secret"
        }
    }

    function test_copy_button_text_mode() {
        const icon = createTemporaryObject(copyComp, tc, {});
        compare(icon.Accessible.name, "Copy");
        const b = createTemporaryObject(copyComp, tc, {
            label: "Copy Details"
        });
        compare(b.Accessible.name, "Copy Details");
        compare(b.copiedLabel, "Copied");
        verify(b.implicitWidth > icon.implicitWidth);
        const w = b.implicitWidth;
        b.copiedLabel = "Done, thanks";
        const wide = b.implicitWidth;
        mouseClick(b);
        compare(b._done, true);
        compare(b.Accessible.description, "Done, thanks");
        compare(b.text, "secret", "text is still what is copied");
        compare(b.implicitWidth, wide, "the width does not jump");
        verify(wide >= w);
        tryCompare(b, "_done", false, 3000);
        compare(b.Accessible.name, "Copy Details");
    }
}
