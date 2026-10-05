import QtQuick
import QtTest
import Atlas.Ui

// A user edit must not end an app's binding on the property the user edits
// (docs/api-1.5.0.md, Part 1). Each control is made in the three app styles:
// bound and taking the edit, bound and refusing it, and a literal value.
// Edits are made with the mouse or the keyboard.
Item {
    id: root
    width: 500
    height: 400

    QtObject {
        id: app
        property real rating: 2
        property int index: 0
        property color color: "#112233"
        property string family: ""
        property real size: 11
    }

    Component {
        id: ratingAccept
        AtlasRating {
            readOnly: false
            value: app.rating
            onEdited: app.rating = value
        }
    }
    Component {
        id: ratingRefuse
        AtlasRating {
            readOnly: false
            value: app.rating
        }
    }
    Component {
        id: ratingLiteral
        AtlasRating {
            readOnly: false
            value: 2
        }
    }
    Component {
        id: segAccept
        AtlasSegmentedControl {
            model: ["A", "B", "C"]
            currentIndex: app.index
            onActivated: index => app.index = index
        }
    }
    Component {
        id: segRefuse
        AtlasSegmentedControl {
            model: ["A", "B", "C"]
            currentIndex: app.index
        }
    }
    Component {
        id: segLiteral
        AtlasSegmentedControl {
            model: ["A", "B", "C"]
            currentIndex: 0
        }
    }
    Component {
        id: colorAccept
        AtlasColorField {
            color: app.color
            onEdited: app.color = color
        }
    }
    Component {
        id: colorRefuse
        AtlasColorField {
            color: app.color
        }
    }
    Component {
        id: colorLiteral
        AtlasColorField {
            color: "#112233"
        }
    }
    Component {
        id: fontAccept
        AtlasFontPicker {
            font.family: app.family
            font.pointSize: app.size
            onEdited: {
                app.family = font.family;
                app.size = font.pointSize;
            }
        }
    }
    Component {
        id: fontRefuse
        AtlasFontPicker {
            font.family: app.family
            font.pointSize: app.size
        }
    }
    Component {
        id: fontLiteral
        AtlasFontPicker {
            font.family: "Sans Serif"
            font.pointSize: 11
        }
    }

    TestCase {
        name: "HoldRating"
        when: windowShown

        function init() {
            app.rating = 2;
        }
        function click4(r) {
            mouseClick(r, 3.5 * r.starSize, r.height / 2);
        }
        function test_accept() {
            const r = createTemporaryObject(ratingAccept, root);
            click4(r);
            compare(r.value, 4);
            compare(app.rating, 4);
            wait(50);
            compare(r.value, 4);
            app.rating = 1;
            compare(r.value, 1, "the binding follows the model");
        }
        function test_refuse() {
            const r = createTemporaryObject(ratingRefuse, root);
            let seen = -1;
            r.edited.connect(() => seen = r.value);
            click4(r);
            compare(seen, 4, "a handler reads the edit");
            compare(r.value, 4);
            tryCompare(r, "value", 2);
            app.rating = 5;
            compare(r.value, 5, "the binding follows the model");
        }
        function test_literal() {
            const r = createTemporaryObject(ratingLiteral, root);
            click4(r);
            compare(r.value, 4);
            wait(50);
            compare(r.value, 4);
            keyClick(Qt.Key_End);
            compare(r.value, 5);
        }
    }

    TestCase {
        name: "HoldSegmented"
        when: windowShown

        function init() {
            app.index = 0;
        }
        function test_accept() {
            const s = createTemporaryObject(segAccept, root);
            s.forceActiveFocus();
            keyClick(Qt.Key_Right);
            compare(s.currentIndex, 1);
            compare(app.index, 1);
            wait(50);
            compare(s.currentIndex, 1);
            app.index = 2;
            compare(s.currentIndex, 2, "the binding follows the model");
        }
        function test_refuse() {
            const s = createTemporaryObject(segRefuse, root);
            s.forceActiveFocus();
            let seen = -1;
            s.activated.connect(() => seen = s.currentIndex);
            keyClick(Qt.Key_End);
            compare(seen, 2, "a handler reads the edit");
            tryCompare(s, "currentIndex", 0);
            app.index = 1;
            compare(s.currentIndex, 1, "the binding follows the model");
        }
        function test_literal() {
            const s = createTemporaryObject(segLiteral, root);
            mouseClick(s, s.width * 5 / 6, s.height / 2);
            compare(s.currentIndex, 2);
            wait(50);
            compare(s.currentIndex, 2);
        }
    }

    TestCase {
        name: "HoldColorField"
        when: windowShown

        function init() {
            app.color = "#112233";
        }
        // Opens the card and types a colour into the hex field.
        function typeHex(f, hex) {
            f.forceActiveFocus();
            keyClick(Qt.Key_Space);
            mouseClick(f);
            tryVerify(() => Window.activeFocusItem && Window.activeFocusItem !== f);
            keyClick(Qt.Key_A, Qt.ControlModifier);
            for (const ch of hex)
                keyClick(ch);
        }
        function test_accept() {
            const f = createTemporaryObject(colorAccept, root);
            typeHex(f, "#ff0000");
            compare(String(f.color), "#ff0000");
            compare(String(app.color), "#ff0000");
            wait(50);
            compare(String(f.color), "#ff0000");
            app.color = "#00ff00";
            compare(String(f.color), "#00ff00", "the binding follows the model");
        }
        function test_refuse() {
            const f = createTemporaryObject(colorRefuse, root);
            let seen = "";
            f.edited.connect(() => seen = String(f.color));
            typeHex(f, "#ff0000");
            compare(seen, "#ff0000", "a handler reads the edit");
            tryCompare(f, "color", "#112233");
            app.color = "#00ff00";
            compare(String(f.color), "#00ff00", "the binding follows the model");
        }
        function test_literal() {
            const f = createTemporaryObject(colorLiteral, root);
            typeHex(f, "#ff0000");
            wait(50);
            compare(String(f.color), "#ff0000");
        }
    }

    TestCase {
        name: "HoldFontPicker"
        when: windowShown

        readonly property var families: Qt.fontFamilies()

        function init() {
            app.family = families[0];
            app.size = 11;
        }
        // Opens the list and takes the next family down.
        function pickNext(p) {
            p.forceActiveFocus();
            keyClick(Qt.Key_Return);
            tryVerify(() => Window.activeFocusItem && Window.activeFocusItem !== p);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
        }
        function test_accept() {
            if (families.length < 2)
                skip("needs two font families");
            const p = createTemporaryObject(fontAccept, root);
            compare(p.font.family, families[0]);
            pickNext(p);
            compare(p.font.family, families[1]);
            compare(app.family, families[1]);
            wait(50);
            compare(p.font.family, families[1]);
            compare(p.font.pointSize, 11, "the size binding is untouched");
            app.family = families[0];
            compare(p.font.family, families[0], "font.family still follows the model");
            app.size = 14;
            compare(p.font.pointSize, 14, "font.pointSize still follows the model");
        }
        function test_refuse() {
            if (families.length < 2)
                skip("needs two font families");
            const p = createTemporaryObject(fontRefuse, root);
            let seen = "";
            p.edited.connect(() => seen = p.font.family);
            pickNext(p);
            compare(seen, families[1], "a handler reads the edit");
            tryCompare(p.font, "family", families[0]);
            app.family = families[1];
            compare(p.font.family, families[1], "font.family still follows the model");
        }
        function test_literal() {
            if (families.length < 2)
                skip("needs two font families");
            const p = createTemporaryObject(fontLiteral, root);
            pickNext(p);
            const picked = p.font.family;
            verify(picked !== "Sans Serif");
            wait(50);
            compare(p.font.family, picked);
        }
    }

    TestCase {
        name: "HoldTogether"
        when: windowShown

        function init() {
            app.rating = 2;
            app.index = 0;
        }
        // Two instances edited in one turn, both refusing: each springs back.
        function test_two_ratings_and_two_segmented_controls() {
            const a = createTemporaryObject(ratingRefuse, root);
            const b = createTemporaryObject(ratingRefuse, root);
            const c = createTemporaryObject(segRefuse, root);
            const d = createTemporaryObject(segRefuse, root);
            (function () {
                a._set(4);
                b._set(5);
                c._choose(1);
                d._choose(2);
            })();
            compare(a.value, 4);
            compare(b.value, 5);
            compare(c.currentIndex, 1);
            compare(d.currentIndex, 2);
            wait(50);
            compare(a.value, 2);
            compare(b.value, 2);
            compare(c.currentIndex, 0);
            compare(d.currentIndex, 0);
            app.rating = 3;
            app.index = 1;
            compare(a.value, 3);
            compare(b.value, 3);
            compare(c.currentIndex, 1);
            compare(d.currentIndex, 1);
        }
        function test_rapid_edits_last_wins() {
            const r = createTemporaryObject(ratingAccept, root);
            r._set(3);
            r._set(5);
            compare(r.value, 5);
            wait(50);
            compare(r.value, 5);
            compare(app.rating, 5);
            const rr = createTemporaryObject(ratingRefuse, root);
            app.rating = 2;
            rr._set(3);
            rr._set(5);
            compare(rr.value, 5);
            tryCompare(rr, "value", 2);
            const s = createTemporaryObject(segAccept, root);
            s._choose(1);
            s._choose(2);
            compare(s.currentIndex, 2);
            wait(50);
            compare(s.currentIndex, 2);
            compare(app.index, 2);
            const sr = createTemporaryObject(segRefuse, root);
            app.index = 0;
            sr._choose(1);
            sr._choose(2);
            compare(sr.currentIndex, 2);
            tryCompare(sr, "currentIndex", 0);
            const sl = createTemporaryObject(segLiteral, root);
            sl._choose(1);
            sl._choose(2);
            wait(50);
            compare(sl.currentIndex, 2);
        }
        function test_rapid_keys() {
            const s = createTemporaryObject(segAccept, root);
            s.forceActiveFocus();
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Right);
            compare(s.currentIndex, 2);
            wait(50);
            compare(s.currentIndex, 2);
            compare(app.index, 2);
            const r = createTemporaryObject(ratingAccept, root);
            r.forceActiveFocus();
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Right);
            wait(50);
            compare(r.value, 5);
            compare(app.rating, 5);
        }
    }
}
