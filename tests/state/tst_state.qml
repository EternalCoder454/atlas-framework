import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import Atlas.Ui

// The state contract (docs/DESIGN.md, "States"), checked on every
// ui/gallery/demos/*Demo.qml found at run time. Per demo:
//   a) with the root `enabled: false`, Tab reaches no item of the demo;
//   b) the picture of the disabled demo differs from the enabled one;
//   c) every item Tab reaches shows a visible change when it has keyboard
//      focus (its picture, with 12 px around it, against the same area
//      without focus).
// A control that breaks a rule is listed below with the reason, so the test
// stays green while the control is fixed. An entry whose check now passes
// fails the test: delete the entry.
Rectangle {
    id: stage

    width: 900
    height: 700
    color: Kirigami.Theme.backgroundColor
    focus: true

    // Demos where a check cannot apply, or a control that breaks it today.
    // check: "a" Tab reaches an item while disabled, "b" no picture change
    // when disabled, "c" no visible change on keyboard focus, "all" skip.
    readonly property var allowed: ({
            // The root is a window: Tab and `enabled` do not reach through it.
            "AtlasWindow": {
                all: "window root"
            },
            // Its empty-model instance takes Tab focus but has no row to
            // draw the ring on ("No Results" looks the same either way).
            "AtlasSearchResults": {
                c: "an empty list shows no focus"
            }
        })

    function allow(demo, check) {
        const e = stage.allowed[demo];
        return e !== undefined && (e.all !== undefined || e[check] !== undefined);
    }

    TestCase {
        name: "State"
        when: windowShown

        // The focused item, or null.
        function focused() {
            return stage.Window.window ? stage.Window.window.activeFocusItem : null;
        }

        // Grab again until the picture holds still (animations end), at most 8 times.
        function settle(item) {
            let prev = States.grab(item, 12);
            for (let i = 0; i < 8; ++i) {
                wait(30);
                const now = States.grab(item, 12);
                if (!States.differs(prev, now))
                    return now;
                prev = now;
            }
            return prev;
        }

        function test_demo_data() {
            return States.shardDemos().map(n => ({
                        tag: n
                    }));
        }

        // Presses Tab up to `max` times and returns the items it reached, in
        // order, until the focus comes back to the first one.
        function tabStops(max) {
            const stops = [];
            for (let i = 0; i < max; ++i) {
                keyClick(Qt.Key_Tab);
                const f = focused();
                if (!f || f === stage)
                    break;
                if (stops.indexOf(f) >= 0)
                    break;
                stops.push(f);
            }
            return stops;
        }

        function test_demo(data) {
            const demo = data.tag;
            if (stage.allow(demo, "all") && stage.allowed[demo].all !== undefined)
                skip(stage.allowed[demo].all);
            const comp = Qt.createComponent(States.demoUrl(demo));
            compare(comp.status, Component.Ready, comp.errorString());
            const obj = comp.createObject(stage);
            verify(obj !== null, "could not create " + demo + "Demo: " + comp.errorString());
            if (obj.animate !== undefined)
                obj.animate = false;
            waitForRendering(stage);
            wait(100);
            const problems = [];
            const known = [];
            const report = (check, text) => (stage.allow(demo, check) ? known : problems).push(demo + ": " + text);
            const reportPass = check => {
                if (stage.allow(demo, check) && stage.allowed[demo][check] !== undefined)
                    problems.push(demo + ": check " + check + " passes now, remove it from the allow-list");
            };

            // b) disabled differs from enabled
            const enabledPicture = States.grab(obj, 0);
            obj.enabled = false;
            wait(60);
            const disabledPicture = settle(obj);
            if (States.isNull(enabledPicture))
                report("b", "the demo is not on screen, cannot compare");
            else if (!States.differs(enabledPicture, disabledPicture))
                report("b", "looks the same with enabled: false");
            else
                reportPass("b");

            // a) disabled: Tab reaches nothing of the demo
            stage.forceActiveFocus();
            const reached = tabStops(6);
            const inside = reached.filter(i => States.isInside(i, obj));
            if (inside.length > 0)
                report("a", "Tab reaches " + inside.map(i => States.describe(i)).join(", ") + " with enabled: false");
            else
                reportPass("a");
            obj.enabled = true;
            stage.forceActiveFocus();
            wait(60);

            // c) enabled: every Tab stop shows keyboard focus
            const stops = tabStops(80);
            States.log("state " + demo + ": " + stops.length + " Tab stops, " + reached.length + " reached while disabled");
            let bad = [];
            for (const item of stops) {
                if (!States.isInside(item, obj))
                    continue;
                // Focus it by keyboard (the Tab above did), grab, drop focus, grab.
                item.forceActiveFocus(Qt.TabFocusReason);
                const withFocus = settle(item);
                stage.forceActiveFocus();
                const without = settle(item);
                if (States.isNull(withFocus) || States.isNull(without))
                    bad.push(States.describe(item) + " (not on screen)");
                else if (!States.differs(withFocus, without)) {
                    const where = States.save(withFocus, demo + "-" + bad.length + "-focused");
                    States.save(without, demo + "-" + bad.length + "-unfocused");
                    bad.push(States.describe(item) + (where !== "" ? " (pictures: " + where + ")" : ""));
                }
            }
            if (bad.length > 0)
                report("c", "no visible change on keyboard focus: " + bad.join("; "));
            else
                reportPass("c");

            obj.destroy();
            wait(50);
            for (const k of known)
                States.log("known failure: " + k);
            if (problems.length > 0)
                fail(problems.join("\n"));
        }
    }
}
