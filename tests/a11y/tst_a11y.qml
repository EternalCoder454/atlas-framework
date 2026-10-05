import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import Atlas.Ui

// One test row per ui/gallery/demos/*Demo.qml, found at run time. A new
// control with a demo needs no change here: it fails if something the
// keyboard can reach lacks an Accessible.role or Accessible.name, or if Tab
// does not walk the demo in reading order (see test_tab_order).
Rectangle {
    id: stage

    width: 900
    height: 700
    color: Kirigami.Theme.backgroundColor

    // Demos where Tab does not go in reading order (rows top to bottom, each
    // row left to right; right to left under RTL), or cannot be tried here,
    // with the reason. A listed demo still gets the focus-trap and
    // visible-and-sized checks, but not the order and Shift+Tab ones.
    readonly property var tabOrderExceptions: ({
            // The copy button sits in the corner over the code: the code is
            // read first, then the button.
            "AtlasCodeView": "copy button overlays the code",
            // The demo lays three zones out in two columns, top to bottom.
            "AtlasDropZone": "demo is in two columns",
            // The popup puts its children in the order body, header, footer
            // and Tab follows that order, so Back and Close come after the
            // fields. QML cannot reorder an item's children (there is no
            // stackBefore; re-parenting the body would break the popup's own
            // layout), so the order is left as Qt makes it.
            "AtlasDialog": "Qt's popup chain is body, header, footer",
            // An AtlasDialog (as above) with the page sidebar as a column:
            // Tab goes down the sidebar, then the search field and the page,
            // while rows across both columns would mix them.
            "AtlasPreferencesDialog": "dialog with a sidebar column"
        })

    // Demos the Tab walk cannot run on at all.
    readonly property var tabOrderSkipped: ({
            // A separate top-level window: the test's key events go to the
            // stage's window, not to it.
            "AtlasWindow": "separate window"
        })

    TestCase {
        name: "A11y"
        when: windowShown

        function describe(item) {
            const type = ("" + item).replace(/_QML.*$/, "").replace(/\(0x.*$/, "").replace(/^QQuick/, "");
            const name = item.Accessible.name;
            return type + (item.objectName ? "#" + item.objectName : "") + (name ? " \"" + name + "\"" : "");
        }

        // Presses `key` until the focus item is `stopAt` (or 200 presses).
        // Returns the focus items in the order reached, or null on a trap.
        function walk(win, key, stopAt, limit) {
            const seen = [];
            for (let i = 0; i < limit; ++i) {
                keyClick(key);
                const item = win.activeFocusItem;
                if (item === null || item === win.contentItem) {
                    // Focus left every item: the next press starts again.
                    if (seen.length > 0 && stopAt === null)
                        return seen;
                    continue;
                }
                if (stopAt !== null && item === stopAt)
                    return seen;
                if (stopAt === null && seen.length > 0 && item === seen[0])
                    return seen;
                seen.push(item);
            }
            return null;
        }

        // Reading order of `items` by their centres in the scene.
        function readingOrder(items, rtl) {
            const boxes = items.map(it => {
                const c = it.mapToItem(null, it.width / 2, it.height / 2);
                // The leading edge, so a control that holds another (a
                // password field and its eye button) comes before it.
                return {
                    item: it,
                    x: rtl ? c.x + it.width / 2 : c.x - it.width / 2,
                    y: c.y,
                    h: it.height
                };
            });
            boxes.sort((a, b) => a.y - b.y);
            const rows = [];
            for (const b of boxes) {
                const row = rows.length > 0 ? rows[rows.length - 1] : null;
                // The same row when the centres are within half a row
                // (the taller one's height: a field with an error line under it
                // has its centre lower than the eye button inside it).
                if (row && Math.abs(b.y - row[0].y) < Math.max(b.h, row[0].h) / 2)
                    row.push(b);
                else
                    rows.push([b]);
            }
            const ordered = [];
            for (const row of rows) {
                row.sort((a, b) => rtl ? b.x - a.x : a.x - b.x);
                for (const b of row)
                    ordered.push(b.item);
            }
            return ordered;
        }

        function test_tab_order_data() {
            return A11y.demos().filter(n => !(n in stage.tabOrderSkipped)).map(n => ({
                        tag: n
                    }));
        }

        function test_tab_order(data) {
            const comp = Qt.createComponent(A11y.demoUrl(data.tag));
            compare(comp.status, Component.Ready, comp.errorString());
            const obj = comp.createObject(stage);
            verify(obj !== null, "could not create " + data.tag + "Demo: " + comp.errorString());
            waitForRendering(stage);
            wait(300);
            const win = stage.Window.window;
            const problems = [];
            win.contentItem.forceActiveFocus();

            // Forward: Tab until the first item comes round again. The first
            // press only leaves "no focus item" (a SpinBox hands its focus on
            // to its text field after it), so the walk starts at the second.
            keyClick(Qt.Key_Tab);
            keyClick(Qt.Key_Tab);
            const first = win.activeFocusItem;
            let forward = [];
            if (first !== null && first !== win.contentItem) {
                const rest = walk(win, Qt.Key_Tab, first, 200);
                if (rest === null)
                    problems.push(data.tag + ": Tab does not come back to the first item in 200 presses (a focus trap)");
                else
                    forward = [first].concat(rest);
            }
            const rtl = stage.LayoutMirroring.enabled;
            for (const it of forward) {
                if (!it.visible || !(it.width > 0) || !(it.height > 0))
                    problems.push(data.tag + ": Tab reaches " + describe(it) + " but it is " + (it.visible ? "" : "not visible, ") + it.width + "x" + it.height);
            }
            const exempt = data.tag in stage.tabOrderExceptions;
            if (!exempt && forward.length > 1) {
                // The walk starts where the focus was (a dialog focuses its
                // first field), so compare as a ring: rotate to the start.
                let want = readingOrder(forward, rtl);
                const at = want.indexOf(forward[0]);
                want = want.slice(at).concat(want.slice(0, at));
                for (let i = 0; i < forward.length; ++i) {
                    if (forward[i] !== want[i]) {
                        problems.push(data.tag + ": Tab order is not reading order: press " + (i + 1) + " reaches " + describe(forward[i]) + ", reading order has " + describe(want[i]));
                        break;
                    }
                }
            }

            // Backward: from the first item, Shift+Tab must visit the same
            // items in the reverse order.
            if (!exempt && forward.length > 1 && win.activeFocusItem === forward[0]) {
                const back = [];
                for (let i = 0; i < forward.length - 1; ++i) {
                    keyClick(Qt.Key_Backtab);
                    back.push(win.activeFocusItem);
                }
                for (let i = 0; i < back.length; ++i) {
                    const want = forward[forward.length - 1 - i];
                    if (back[i] !== want) {
                        problems.push(data.tag + ": Shift+Tab press " + (i + 1) + " reaches " + describe(back[i]) + ", the reverse of Tab has " + describe(want));
                        break;
                    }
                }
            }
            obj.destroy();
            wait(50);
            if (problems.length > 0)
                fail(problems.join("\n"));
        }

        function test_demo_data() {
            return A11y.demos().map(n => ({
                        tag: n
                    }));
        }

        function test_demo(data) {
            const comp = Qt.createComponent(A11y.demoUrl(data.tag));
            compare(comp.status, Component.Ready, comp.errorString());
            const isWindow = A11y.rootIsWindow(data.tag);
            const obj = comp.createObject(isWindow ? null : stage);
            verify(obj !== null, "could not create " + data.tag + "Demo: " + comp.errorString());
            if (isWindow) {
                obj.visible = true;
                tryVerify(() => obj.visible, 5000);
            } else {
                waitForRendering(stage);
            }
            wait(300);
            const problems = A11y.audit(obj, data.tag);
            if (isWindow) {
                obj.close();
            }
            obj.destroy();
            wait(50);
            if (problems.length > 0) {
                fail(problems.join("\n"));
            }
        }
    }
}
