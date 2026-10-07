import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import Telamon.Ui

// Item 42, the Telamon OS Wizard's controls. Each control is driven the way the
// Wizard drives it; user edits are made with the mouse or the keyboard.
Item {
    id: root
    width: 700
    height: 500

    // The first descendant for which `match(item)` is true, or null.
    function find(item, match) {
        for (const c of item.children) {
            if (match(c)) {
                return c;
            }
            const r = find(c, match);
            if (r) {
                return r;
            }
        }
        return null;
    }
    // A button with this text (a Text or Label has no `clicked`).
    function button(item, text) {
        return find(item, c => c.clicked !== undefined && c.text === text);
    }
    function shownText(item, text) {
        const t = find(item, c => c.text === text && c.clicked === undefined && c.visible);
        return t !== null;
    }

    QtObject {
        id: app
        property bool dark: false
        property int accent: 0
    }

    Component {
        id: onboardingComp
        TelamonOnboarding {
            id: ob
            width: 640
            height: 400
            currentIndex: 1
            Item {
                property string title: "One"
            }
            Item {
                property string title: "Two"
                property bool skippable: true
            }
            Item {
                property string title: "Three"
            }
        }
    }

    TestCase {
        name: "TelamonOnboarding42"
        when: windowShown

        function make(props) {
            const o = createTemporaryObject(onboardingComp, root, props || {});
            verify(o !== null);
            return o;
        }

        // Shortcuts work in the active window only; activate the test's.
        function activate() {
            const w = root.Window.window;
            w.requestActivate();
            tryVerify(() => w.active, 2000);
            if (!w.active) {
                skip("no active window on this platform");
            }
        }

        function test_labels() {
            const o = make();
            verify(button(o, "Back") !== null);
            verify(button(o, "Next") !== null);
            o.nextText = "Continue";
            o.backText = "Previous";
            verify(button(o, "Continue") !== null);
            verify(button(o, "Previous") !== null);
            verify(button(o, "Next") === null);
            o.currentIndex = 2;
            verify(button(o, "Finish") !== null);
            o.finishText = "Start";
            verify(button(o, "Start") !== null);
            o.nextText = "";
            o.backText = "";
            o.finishText = "";
            verify(button(o, "Finish") !== null);
            verify(button(o, "Back") !== null);
        }

        function test_advance_requested_then_moves() {
            const o = make();
            const spy = createTemporaryObject(spyComp, root, {
                target: o,
                signalName: "advanceRequested"
            });
            mouseClick(button(o, "Next"));
            compare(spy.count, 1);
            compare(spy.signalArguments[0][0], 1);
            compare(o.currentIndex, 2);
            // On the last page it still asks, then finishes.
            const done = createTemporaryObject(spyComp, root, {
                target: o,
                signalName: "finished"
            });
            mouseClick(button(o, "Finish"));
            compare(spy.count, 2);
            compare(spy.signalArguments[1][0], 2);
            compare(done.count, 1);
        }

        function test_manual_advance() {
            const o = make({
                autoAdvance: false
            });
            const spy = createTemporaryObject(spyComp, root, {
                target: o,
                signalName: "advanceRequested"
            });
            mouseClick(button(o, "Next"));
            compare(spy.count, 1);
            compare(o.currentIndex, 1, "the control stays until the app calls next()");
            o.next();
            compare(o.currentIndex, 2);
            compare(spy.count, 1, "next() itself does not ask again");
        }

        function test_busy() {
            const o = make({
                busy: true
            });
            const next = button(o, "Next");
            const spy = createTemporaryObject(spyComp, root, {
                target: o,
                signalName: "advanceRequested"
            });
            compare(next.Accessible.description, "Busy");
            mouseClick(next);
            next.forceActiveFocus();
            keyClick(Qt.Key_Space);
            keyClick(Qt.Key_Return);
            compare(spy.count, 0);
            compare(o.currentIndex, 1);
            verify(!button(o, "Back").enabled);
            verify(!button(o, "Skip").enabled);
            o.busy = false;
            compare(next.Accessible.description, "");
            verify(button(o, "Back").enabled);
            mouseClick(next);
            compare(spy.count, 1);
            compare(o.currentIndex, 2);
        }

        function test_alt_left_not_while_busy() {
            const o = make();
            activate();
            o.forceActiveFocus();
            keyClick(Qt.Key_Left, Qt.AltModifier);
            compare(o.currentIndex, 0, "the shortcut works in this fixture");
            o.currentIndex = 1;
            o.busy = true;
            keyClick(Qt.Key_Left, Qt.AltModifier);
            compare(o.currentIndex, 1, "Alt+Left does nothing while busy");
            o.busy = false;
            keyClick(Qt.Key_Left, Qt.AltModifier);
            compare(o.currentIndex, 0);
        }

        function test_second_next_waits_for_busy() {
            const o = make({
                autoAdvance: false
            });
            const spy = createTemporaryObject(spyComp, root, {
                target: o,
                signalName: "advanceRequested"
            });
            const next = button(o, "Next");
            // An app that refuses (a check failed) leaves Next free.
            mouseClick(next);
            mouseClick(next);
            compare(spy.count, 2, "a refused Next can be pressed again");
            compare(o.currentIndex, 1, "the app did not move on");
            // An app that answers later sets busy in its handler.
            const answer = () => {
                o.busy = true;
            };
            o.advanceRequested.connect(answer);
            mouseClick(next);
            mouseClick(next);
            compare(spy.count, 3, "the second press waits while busy");
            o.advanceRequested.disconnect(answer);
            o.busy = false;
            o.next();
            compare(o.currentIndex, 2);
            mouseClick(button(o, "Finish"));
            compare(spy.count, 4, "asks again once busy has fallen");
        }

        function test_can_go_back() {
            const o = make();
            activate();
            o.forceActiveFocus();
            keyClick(Qt.Key_Left, Qt.AltModifier);
            compare(o.currentIndex, 0, "Alt+Left goes back");
            o.currentIndex = 1;
            o.canGoBack = false;
            verify(!button(o, "Back").visible);
            keyClick(Qt.Key_Left, Qt.AltModifier);
            compare(o.currentIndex, 1, "Alt+Left does nothing without canGoBack");
            o.canGoBack = true;
            verify(button(o, "Back").visible);
        }

        function dotsOf(o) {
            const row = find(o, c => c.Accessible.name.indexOf("Step ") === 0 && c.spacing !== undefined);
            return row;
        }

        function test_dots() {
            const o = make({
                stepStyle: TelamonOnboarding.Dots
            });
            const row = dotsOf(o);
            verify(row !== null && row.visible);
            const dots = row.children.filter(c => c.isCurrent !== undefined);
            compare(dots.length, 3);
            verify(dots[1].isCurrent);
            verify(dots[1].width > dots[0].width);
            compare(dots[0].width, dots[2].width);
            compare(row.Accessible.name, "Step 2 of 3");
            // The step column is not shown with the dots.
            const step = find(o, c => c.number !== undefined && c.done !== undefined);
            verify(step === null || !step.visible);
            if (!TelamonStyle.highContrast) {
                fuzzyCompare(dots[0].color.a, 0.45, 0.02);
                fuzzyCompare(dots[2].color.a, 0.2, 0.02);
                compare(dots[1].color, TelamonStyle.accent);
            }
            o.showSteps = false;
            verify(!row.visible);
            o.showSteps = true;
            o.stepStyle = TelamonOnboarding.Column;
            verify(!row.visible);
        }

        function test_dots_move_with_page() {
            const o = make({
                stepStyle: TelamonOnboarding.Dots
            });
            const row = dotsOf(o);
            const dots = row.children.filter(c => c.isCurrent !== undefined);
            o.currentIndex = 2;
            verify(dots[2].isCurrent);
            tryVerify(() => dots[2].width > dots[1].width);
            tryCompare(dots[1], "width", dots[0].width);
        }

        function test_column_is_the_default() {
            const o = make();
            compare(o.stepStyle, TelamonOnboarding.Column);
            verify(dotsOf(o) === null || !dotsOf(o).visible);
        }
    }

    Component {
        id: spyComp
        SignalSpy {}
    }

    // ---- TelamonPasswordStrength ----

    Component {
        id: strengthComp
        TelamonPasswordStrength {
            width: 240
        }
    }

    TestCase {
        name: "TelamonPasswordStrength"
        when: windowShown

        function test_scores() {
            const s = createTemporaryObject(strengthComp, root);
            const names = ["Very weak", "Weak", "Fair", "Good", "Strong"];
            for (let i = 0; i < 5; ++i) {
                s.score = i;
                verify(shownText(s, names[i]), names[i]);
                compare(s.Accessible.name, names[i] + ", " + i + " of 4");
            }
        }

        function test_nothing_typed() {
            const s = createTemporaryObject(strengthComp, root);
            compare(s.score, -1);
            const labels = ["Very weak", "Weak", "Fair", "Good", "Strong"];
            for (const l of labels) {
                verify(!shownText(s, l));
            }
            compare(s.Accessible.name, "Password strength");
        }

        function test_custom_text_and_clamp() {
            const s = createTemporaryObject(strengthComp, root, {
                score: 2,
                text: "Needs a number"
            });
            verify(shownText(s, "Needs a number"));
            verify(!shownText(s, "Fair"));
            compare(s.Accessible.name, "Needs a number, 2 of 4");
            s.score = 9;
            compare(s.Accessible.name, "Needs a number, 4 of 4");
            s.score = -5;
            compare(s.Accessible.name, "Password strength");
            s.score = 3;
            s.text = "";
            verify(shownText(s, "Good"));
        }
    }

    // ---- TelamonChoiceCard ----

    Component {
        id: cardsComp
        Row {
            property alias a: ca
            property alias b: cb
            property alias c: cc
            spacing: 20
            TelamonChoiceCard {
                id: ca
                text: "Light"
                autoExclusive: true
            }
            TelamonChoiceCard {
                id: cb
                text: "Dark"
                autoExclusive: true
            }
            TelamonChoiceCard {
                id: cc
                text: "Auto"
                autoExclusive: true
            }
        }
    }
    Component {
        id: cardAccept
        TelamonChoiceCard {
            text: "Dark"
            checked: app.dark
            onToggled: app.dark = checked
        }
    }
    Component {
        id: cardRefuse
        TelamonChoiceCard {
            text: "Dark"
            checked: app.dark
        }
    }
    Component {
        id: cardLiteral
        TelamonChoiceCard {
            text: "Dark"
        }
    }
    Component {
        id: groupedComp
        Row {
            property alias group: g
            QQC2.ButtonGroup {
                id: g
            }
            TelamonChoiceCard {
                text: "One"
                QQC2.ButtonGroup.group: g
            }
            TelamonChoiceCard {
                text: "Two"
                QQC2.ButtonGroup.group: g
                checked: true
            }
        }
    }

    TestCase {
        name: "TelamonChoiceCard"
        when: windowShown

        function test_exclusive_with_autoexclusive() {
            const r = createTemporaryObject(cardsComp, root);
            mouseClick(r.a);
            verify(r.a.checked);
            mouseClick(r.b);
            verify(r.b.checked);
            verify(!r.a.checked);
            mouseClick(r.b);
            verify(r.b.checked, "an exclusive card stays chosen when clicked again");
        }

        function test_exclusive_with_button_group() {
            const r = createTemporaryObject(groupedComp, root);
            const one = r.children.filter(c => c.text === "One")[0];
            const two = r.children.filter(c => c.text === "Two")[0];
            verify(two.checked);
            mouseClick(one);
            verify(one.checked);
            verify(!two.checked);
            compare(r.group.checkedButton, one);
        }

        function test_keyboard() {
            const r = createTemporaryObject(cardsComp, root);
            // visualFocus is only for focus that came by keyboard.
            r.a.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            verify(r.a.checked);
            verify(r.a.visualFocus);
        }

        function test_accessible() {
            const c = createTemporaryObject(cardLiteral, root);
            compare(c.Accessible.role, Accessible.RadioButton);
            compare(c.Accessible.name, "Dark");
            verify(c.Accessible.checkable);
            c.checked = true;
            verify(c.Accessible.checked);
        }

        function test_aspect_ratio() {
            const c = createTemporaryObject(cardLiteral, root, {
                width: 200
            });
            compare(c.aspectRatio, 1.6);
            // The layout inside sizes the card one turn after a change.
            tryVerify(() => c.implicitHeight > 0);
            const wide = c.implicitHeight;
            c.aspectRatio = 1;
            tryVerify(() => c.implicitHeight > wide, 5000, "a squarer picture is taller");
            c.aspectRatio = 0;
            tryCompare(c, "implicitHeight", wide, 5000, "a ratio of 0 uses the default");
            c.aspectRatio = NaN;
            tryCompare(c, "implicitHeight", wide);
        }

        function test_bad_source_is_quiet() {
            const c = createTemporaryObject(cardLiteral, root, {
                source: "file:///does/not/exist.png"
            });
            verify(c !== null);
            wait(50);
            verify(c.width > 0);
        }

        // The edit rule: a user's choice keeps an app's binding.
        function test_edit_taken() {
            app.dark = false;
            const c = createTemporaryObject(cardAccept, root);
            mouseClick(c);
            verify(app.dark);
            tryVerify(() => c.checked);
            app.dark = false;
            tryVerify(() => !c.checked, 1000, "still bound: follows the app");
        }

        function test_edit_refused() {
            app.dark = false;
            const c = createTemporaryObject(cardRefuse, root);
            mouseClick(c);
            tryVerify(() => !c.checked, 1000, "springs back");
            app.dark = true;
            tryVerify(() => c.checked, 1000, "and stays bound");
            app.dark = false;
        }

        function test_edit_literal() {
            const c = createTemporaryObject(cardLiteral, root);
            mouseClick(c);
            verify(c.checked);
            wait(50);
            verify(c.checked, "no binding: the choice stays");
        }
    }

    // ---- TelamonAccentPicker ----

    Component {
        id: pickerComp
        TelamonAccentPicker {
            model: [{
                    "color": "#3584e4",
                    "name": "Blue"
                }, {
                    "color": "#26a269",
                    "name": "Green"
                }, "#e5487a", {
                    "color": "#9141ac"
                }]
        }
    }
    Component {
        id: pickerAccept
        TelamonAccentPicker {
            model: ["#111111", "#222222", "#333333"]
            currentIndex: app.accent
            onActivated: index => app.accent = index
        }
    }
    Component {
        id: pickerRefuse
        TelamonAccentPicker {
            model: ["#111111", "#222222", "#333333"]
            currentIndex: app.accent
        }
    }
    Component {
        id: pickerLiteral
        TelamonAccentPicker {
            model: ["#111111", "#222222", "#333333"]
        }
    }
    Component {
        id: rtlComp
        Item {
            property alias picker: p
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true
            TelamonAccentPicker {
                id: p
                model: ["#111111", "#222222", "#333333"]
            }
        }
    }

    TestCase {
        name: "TelamonAccentPicker"
        when: windowShown

        function swatches(p) {
            return p.contentItem.children.filter(c => c.swatchColor !== undefined);
        }

        function test_model_and_color() {
            const p = createTemporaryObject(pickerComp, root);
            compare(p.count, 4);
            compare(p.currentIndex, 0);
            compare(p.currentColor, Qt.color("#3584e4"));
            p.currentIndex = 2;
            compare(p.currentColor, Qt.color("#e5487a"));
            p.currentIndex = 3;
            compare(p.currentColor, Qt.color("#9141ac"));
            p.currentIndex = 9;
            compare(p.currentColor.a, 0, "out of range is nothing");
            compare(swatches(p).length, 4);
        }

        function test_accessible_names() {
            const p = createTemporaryObject(pickerComp, root);
            const s = swatches(p);
            compare(s[0].Accessible.name, "Blue");
            compare(s[1].Accessible.name, "Green");
            compare(s[2].Accessible.name, "Accent color 3");
            compare(s[3].Accessible.name, "Accent color 4");
            compare(s[0].Accessible.role, Accessible.RadioButton);
            verify(s[0].Accessible.checked);
            verify(!s[1].Accessible.checked);
        }

        function test_click_activates() {
            const p = createTemporaryObject(pickerComp, root);
            const spy = createTemporaryObject(spyComp, root, {
                target: p,
                signalName: "activated"
            });
            mouseClick(swatches(p)[1]);
            compare(p.currentIndex, 1);
            compare(spy.count, 1);
            compare(spy.signalArguments[0][0], 1);
            mouseClick(swatches(p)[1]);
            compare(spy.count, 1, "the same swatch is no new choice");
            p.currentIndex = 3;
            compare(spy.count, 1, "a change from code is not an activation");
        }

        function test_keys() {
            const p = createTemporaryObject(pickerComp, root);
            p.forceActiveFocus();
            keyClick(Qt.Key_Right);
            compare(p.currentIndex, 1);
            keyClick(Qt.Key_End);
            compare(p.currentIndex, 3);
            keyClick(Qt.Key_Right);
            compare(p.currentIndex, 3, "stops at the end");
            keyClick(Qt.Key_Left);
            compare(p.currentIndex, 2);
            keyClick(Qt.Key_Home);
            compare(p.currentIndex, 0);
            keyClick(Qt.Key_Left);
            compare(p.currentIndex, 0);
        }

        function test_keys_mirrored() {
            const r = createTemporaryObject(rtlComp, root);
            const p = r.picker;
            verify(p.mirrored);
            p.forceActiveFocus();
            keyClick(Qt.Key_Left);
            compare(p.currentIndex, 1, "Left moves forward in right-to-left");
            keyClick(Qt.Key_Right);
            compare(p.currentIndex, 0);
            const s = swatches(p);
            verify(s[0].mapToItem(p, 0, 0).x > s[2].mapToItem(p, 0, 0).x, "the first swatch is on the right");
        }

        function test_bad_model() {
            const p = createTemporaryObject(pickerComp, root, {
                model: ["not a colour", null, 7, {}]
            });
            compare(p.count, 4);
            p.currentIndex = 1;
            compare(p.currentColor.a, 0);
            p.model = undefined;
            compare(p.count, 0);
            p.model = [];
            compare(p.currentColor.a, 0);
            p.forceActiveFocus();
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_End);
        }

        function test_edit_taken() {
            app.accent = 0;
            const p = createTemporaryObject(pickerAccept, root);
            mouseClick(swatches(p)[2]);
            compare(app.accent, 2);
            tryCompare(p, "currentIndex", 2);
            app.accent = 1;
            tryCompare(p, "currentIndex", 1, 1000, "still bound");
            app.accent = 0;
        }

        function test_edit_refused() {
            app.accent = 0;
            const p = createTemporaryObject(pickerRefuse, root);
            mouseClick(swatches(p)[2]);
            tryCompare(p, "currentIndex", 0, 1000, "springs back");
            app.accent = 1;
            tryCompare(p, "currentIndex", 1, 1000, "and stays bound");
            app.accent = 0;
        }

        function test_edit_literal() {
            const p = createTemporaryObject(pickerLiteral, root);
            mouseClick(swatches(p)[2]);
            compare(p.currentIndex, 2);
            wait(50);
            compare(p.currentIndex, 2);
        }

        function test_disabled_takes_no_clicks() {
            const p = createTemporaryObject(pickerLiteral, root, {
                enabled: false
            });
            mouseClick(swatches(p)[2]);
            compare(p.currentIndex, 0);
        }
    }

    // ---- TelamonWindow.kiosk ----

    Component {
        id: winComp
        TelamonWindow {
            width: 320
            height: 240
        }
    }
    Component {
        id: buttonsWinComp
        TelamonWindow {
            width: 320
            height: 240
            TelamonWindowButtons {
                buttons: ["minimize", "maximize", "close"]
            }
        }
    }

    TestCase {
        name: "TelamonWindowKiosk"
        when: windowShown

        function shown(comp, props) {
            const w = comp.createObject(null, props);
            verify(w !== null);
            w.visible = true;
            tryVerify(() => w.visible && w.width > 0);
            return w;
        }

        function test_default_closes() {
            const w = shown(winComp, {});
            compare(w.kiosk, false);
            w.close();
            tryVerify(() => !w.visible);
            w.destroy();
        }

        function test_kiosk_is_full_screen_and_refuses_close() {
            const w = shown(winComp, {
                kiosk: true
            });
            tryCompare(w, "visibility", Window.FullScreen);
            verify((w.flags & Qt.WindowCloseButtonHint) === 0);
            w.close();
            wait(100);
            verify(w.visible, "a close request is refused");
            compare(w.visibility, Window.FullScreen);
            w.kiosk = false;
            tryVerify(() => w.visibility !== Window.FullScreen);
            w.close();
            tryVerify(() => !w.visible);
            w.destroy();
        }

        function test_kiosk_set_later() {
            const w = shown(winComp, {});
            w.kiosk = true;
            tryCompare(w, "visibility", Window.FullScreen);
            w.close();
            wait(100);
            verify(w.visible);
            w.destroy();
        }

        function test_leaving_kiosk_and_showing_again() {
            const w = shown(winComp, {
                kiosk: true
            });
            tryCompare(w, "visibility", Window.FullScreen);
            w.kiosk = false;
            tryVerify(() => w.visibility === Window.Windowed);
            w.kiosk = true;
            tryCompare(w, "visibility", Window.FullScreen);
            // Hide, leave kiosk while hidden, show: not full screen.
            w.visible = false;
            w.kiosk = false;
            w.visible = true;
            tryVerify(() => w.visible && w.visibility === Window.Windowed);
            // The reverse: hide, enter kiosk, show: full screen.
            w.visible = false;
            w.kiosk = true;
            w.visible = true;
            tryCompare(w, "visibility", Window.FullScreen);
            w.destroy();
        }

        function test_kiosk_goes_back_to_full_screen() {
            const w = shown(winComp, {
                kiosk: true
            });
            tryCompare(w, "visibility", Window.FullScreen);
            w.showNormal();
            tryCompare(w, "visibility", Window.FullScreen);
            w.showMaximized();
            tryCompare(w, "visibility", Window.FullScreen);
            w.destroy();
        }

        function test_hidden_kiosk_stays_hidden() {
            const w = winComp.createObject(null, {
                kiosk: true
            });
            wait(100);
            verify(!w.visible, "kiosk does not show a window nobody showed");
            w.destroy();
        }

        function test_no_close_button() {
            const w = shown(buttonsWinComp, {});
            const named = n => root.find(w.contentItem, c => c.Accessible.name === n && c.visible);
            verify(named("Close") !== null, "a normal window has the close button");
            w.kiosk = true;
            tryVerify(() => named("Close") === null);
            verify(named("Minimize") !== null, "the other window buttons stay");
            verify(named("Maximize") === null, "no Maximize in a kiosk window");
            w.kiosk = false;
            tryVerify(() => named("Maximize") !== null);
            w.destroy();
        }
    }
}
