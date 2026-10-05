import QtQuick
import QtTest
import Atlas.Ui

// Regression tests for names that qmllint showed as unqualified or missing and
// that did not resolve at run time: an object nested in another (a Behavior, a
// Connections, a Scale, a handler) looks names up on the file's root object,
// not on the object that declares them.
Item {
    id: root
    width: 600
    height: 400

    Component {
        id: switcherComp
        AtlasViewSwitcher {
            model: [{ text: "One" }, { text: "Two" }, { text: "Three" }]
            currentIndex: 0
        }
    }
    Component {
        id: flowComp
        AtlasFlowLayout {
            width: 200
        }
    }
    Component {
        id: boxComp
        Rectangle {
            implicitWidth: 80
            implicitHeight: 30
        }
    }
    Component {
        id: pageComp
        Item {
            property string title: "Page"
        }
    }
    Component {
        id: navComp
        AtlasNavigationStack {
            width: 400
            height: 300
            initialItem: pageComp
        }
    }
    Component {
        id: searchComp
        SearchField {
            width: 120
            placeholderText: "A placeholder far longer than the field is wide"
        }
    }
    Component {
        id: findComp
        FindBar {
            width: 400
        }
    }

    // The first item under `item` (itself included) for which `match` is true.
    function find(item, match) {
        if (match(item)) {
            return item;
        }
        for (const child of item.children) {
            const hit = find(child, match);
            if (hit) {
                return hit;
            }
        }
        return null;
    }
    // Every item under `item` (itself included) for which `match` is true.
    function findAll(item, match, into) {
        if (match(item)) {
            into.push(item);
        }
        for (const child of item.children) {
            findAll(child, match, into);
        }
        return into;
    }

    TestCase {
        name: "LintViewSwitcher"
        when: windowShown

        function tintOf(sw) {
            return root.find(sw, it => it !== sw && it._springing !== undefined && it._sync !== undefined);
        }
        function test_tint_follows_item() {
            const sw = createTemporaryObject(switcherComp, root);
            verify(sw);
            sw.currentIndex = 1;
            const tint = tintOf(sw);
            verify(tint);
            const cur = sw._cur;
            verify(cur);
            const where = () => cur.mapToItem(sw, 0, 0).x;
            tryVerify(() => Math.abs(tint.x - where()) < 0.5 && Math.abs(tint.width - cur.width) < 0.5);
            // The current button resized: the tint's width follows.
            cur.implicitWidth = cur.implicitWidth + 40;
            tryVerify(() => Math.abs(tint.width - cur.width) < 0.5 && cur.width > 0);
            // A button before it resized moves the current one: the tint's x follows.
            const first = cur.parent.children.find(c => c.label === "One");
            verify(first);
            const before = where();
            first.implicitWidth = first.implicitWidth + 30;
            tryVerify(() => where() > before + 20);
            tryVerify(() => Math.abs(tint.x - where()) < 0.5);
        }
        function test_change_springs() {
            const sw = createTemporaryObject(switcherComp, root);
            verify(sw);
            const tint = tintOf(sw);
            verify(tint);
            tryVerify(() => tint.visible && tint._shown !== null);
            sw.currentIndex = 2;
            compare(tint._springing, true);
            if (!AtlasStyle.reducedMotion) {
                // The Behavior is on: the lag starts away from 0 and settles to it.
                verify(Math.abs(tint._slideX) > 0);
            }
            tryVerify(() => Math.abs(tint._slideX) < 0.5 && Math.abs(tint._slideW) < 0.5);
            tryVerify(() => Math.abs(tint.x - sw._cur.mapToItem(sw, 0, 0).x) < 0.5);
        }
    }

    TestCase {
        name: "LintFlowLayout"
        when: windowShown

        function test_child_reparented_out_is_forgotten() {
            failOnWarning(/.*/);
            const flow = createTemporaryObject(flowComp, root);
            const a = createTemporaryObject(boxComp, flow);
            const b = createTemporaryObject(boxComp, flow);
            verify(flow && a && b);
            wait(50);
            b.parent = root;
            wait(50);
            const h = flow.implicitHeight;
            b.implicitHeight = 500;
            b.implicitWidth = 300;
            b.visible = false;
            wait(50);
            compare(flow.implicitHeight, h);
        }
        function test_destroyed_layout_leaves_children_alone() {
            failOnWarning(/.*/);
            const outside = createTemporaryObject(boxComp, root);
            const flow = flowComp.createObject(root);
            verify(outside && flow);
            outside.parent = flow;
            wait(50);
            flow.destroy();
            wait(50);
            outside.implicitWidth = 123;
            outside.implicitHeight = 77;
            outside.visible = false;
            wait(50);
            compare(outside.implicitWidth, 123);
        }
    }

    TestCase {
        name: "LintNavigationStack"
        when: windowShown

        // The Back arrow turns about the button's centre, not the stack's.
        function test_back_arrow_origin() {
            const nav = createTemporaryObject(navComp, root);
            verify(nav);
            const back = root.find(nav, it => it.text === "Back" && it.transform !== undefined && it.transform.length > 0);
            verify(back);
            tryVerify(() => back.width > 0);
            compare(back.transform[0].origin.x, back.width / 2);
            verify(back.width < nav.width / 2);
        }
    }

    TestCase {
        name: "LintPlaceholderWidth"
        when: windowShown

        // Checks the placeholder of every text field under `item`: as wide as
        // the room between the paddings, so a long one elides.
        function checkPlaceholders(item) {
            const fields = root.findAll(item, it => it.placeholderText !== undefined && it.placeholderText.length > 0 && it.leftPadding !== undefined, []);
            verify(fields.length > 0);
            for (const f of fields) {
                const t = root.find(f, it => it !== f && it.text === f.placeholderText && it.elide !== undefined);
                verify(t);
                fuzzyCompare(t.width, f.width - f.leftPadding - f.rightPadding, 0.5);
            }
        }
        function test_search_field() {
            const sf = createTemporaryObject(searchComp, root);
            verify(sf);
            checkPlaceholders(sf);
            verify(sf.width > 0);
        }
        function test_find_bar() {
            const bar = createTemporaryObject(findComp, root);
            verify(bar);
            bar.open(true);
            wait(50);
            checkPlaceholders(bar);
        }
    }
}
