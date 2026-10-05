import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtTest
import Atlas.Ui

Item {
    id: root
    width: 400
    height: 200

    Component {
        id: actionComp
        QQC2.Action {
            property int count: 0
            checkable: true
            onTriggered: count++
        }
    }
    Component {
        id: buttonComp
        ToolbarButton {
            focusable: true
            symbol: Symbols.Add
        }
    }
    Component {
        id: barComp
        AtlasProgressBar {
            width: 200
        }
    }

    Component {
        id: dialogLabelsComp
        AtlasDialog {
            id: labelsDialog
            property int rejectedCount: 0
            title: "Info"
            onRejected: rejectedCount++
            footerContent: [
                SecondaryButton {
                    text: "Cancel"
                    onClicked: labelsDialog.reject()
                }
            ]
            AtlasLabel {
                text: "Nothing to edit here"
            }
        }
    }
    Component {
        id: dialogFieldComp
        AtlasDialog {
            property alias field: edit
            title: "Name"
            AtlasTextField {
                id: edit
                Layout.fillWidth: true
            }
        }
    }

    SignalSpy {
        id: spy
        signalName: "clicked"
    }

    TestCase {
        name: "ToolbarButton"
        when: windowShown

        function test_return_fires_bound_action() {
            const a = createTemporaryObject(actionComp, root);
            const b = createTemporaryObject(buttonComp, root, {
                "action": a
            });
            b.forceActiveFocus();
            verify(b.activeFocus);
            keyClick(Qt.Key_Return);
            compare(a.count, 1);
            compare(a.checked, true);
            compare(b.checked, true);
            keyClick(Qt.Key_Enter);
            compare(a.count, 2);
            compare(b.checked, false);
        }

        function test_return_without_action_clicks() {
            const b = createTemporaryObject(buttonComp, root, {
                "checkable": true
            });
            spy.target = b;
            b.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(spy.count, 1);
            compare(b.checked, true);
        }
    }

    TestCase {
        name: "ToolbarButtonTooltip"
        when: windowShown

        function test_tooltip_hides_while_pressed_and_after_use() {
            const b = createTemporaryObject(buttonComp, root, {
                "text": "More options"
            });
            mouseMove(b, b.width / 2, b.height / 2);
            tryVerify(() => b.hovered);
            verify(b._tipShown, "hovered: the tooltip shows");
            mousePress(b, b.width / 2, b.height / 2);
            verify(!b._tipShown, "pressed: hidden");
            mouseRelease(b, b.width / 2, b.height / 2);
            verify(!b._tipShown, "after the click (a menu may be open): hidden");
            mouseMove(root, root.width - 2, root.height - 2);
            tryVerify(() => !b.hovered);
            mouseMove(b, b.width / 2, b.height / 2);
            tryVerify(() => b._tipShown, 2000, "back after the pointer left and returned");
        }
    }

    TestCase {
        name: "AtlasDialogFocus"
        when: windowShown

        function test_labels_only_body_keeps_return_from_closing() {
            const d = createTemporaryObject(dialogLabelsComp, root);
            d.open();
            tryVerify(() => d.opened);
            verify(d.activeFocus || d.contentItem.activeFocus || d.visibleFocusItem === d, "the dialog holds the focus");
            const f = Window.window.activeFocusItem;
            verify(f, "something has focus");
            verify(!(f.text === "Back" || f.text === "Close" || f.text === "Cancel"), "not a header or footer button");
            keyClick(Qt.Key_Return);
            wait(50);
            verify(d.opened, "Return did not close the dialog");
            compare(d.rejectedCount, 0);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !d.opened, 2000, "Escape closes it");
        }

        function test_text_field_gets_the_focus() {
            const d = createTemporaryObject(dialogFieldComp, root);
            d.open();
            tryVerify(() => d.opened);
            tryVerify(() => d.field.activeFocus);
            d.close();
        }
    }

    TestCase {
        name: "AtlasProgressBar"
        when: windowShown

        function test_track_fills_height_without_text() {
            const p = createTemporaryObject(barComp, root, {
                "height": 20,
                "value": 0.5
            });
            compare(p.children.length > 0, true);
            // The track is the first Rectangle under the layout's Item.
            const track = p.children[0].children[0].children[0];
            compare(track.height, 20);
        }

        function test_narrow_bar_does_not_overflow() {
            const p = createTemporaryObject(barComp, root, {
                "width": 30,
                "text": "42 %"
            });
            const item = p.children[0].children[0];
            verify(item.x + item.width <= p.width + 0.5);
        }

        function test_unknown_status_warns_once() {
            ignoreWarning(/unknown status "weird"/);
            const p = createTemporaryObject(barComp, root, {
                "status": "weird"
            });
            p.status = "other";
            compare(p._warned, true);
        }
    }

    Component {
        id: atlasButtonComp
        AtlasButton {
            text: "Sync"
        }
    }

    TestCase {
        name: "AtlasButtonBusy"
        when: windowShown

        function test_accessible_press_is_ignored_while_busy() {
            const b = createTemporaryObject(atlasButtonComp, root);
            let n = 0;
            b.clicked.connect(() => n++);
            verify(a11y.press(b), "the button offers a press action");
            compare(n, 1, "an idle button clicks");
            b.busy = true;
            a11y.press(b);
            compare(n, 1, "a busy button ignores the press action");
            b.busy = false;
            b.enabled = false;
            a11y.press(b);
            compare(n, 1, "a disabled button ignores it too");
        }
    }

    TestCase {
        name: "ProgressShimmer"
        when: windowShown

        // The shimmer is a gradient band over a flat fill: it must show as
        // different pixels along the fill, also on the software renderer.
        function distinctAlongFill(item) {
            const img = grabImage(item);
            const y = Math.round(item.height / 2);
            const seen = {};
            let count = 0;
            for (let x = 4; x < Math.round(item.width * 0.7); x += 2) {
                const c = img.pixel(x, y).toString();
                if (!seen[c]) {
                    seen[c] = true;
                    count++;
                }
            }
            return count;
        }

        function test_progress_bar_shimmer_renders() {
            const p = createTemporaryObject(barComp, root, {
                "value": 0.8,
                "animated": true
            });
            verify(waitForRendering(p));
            tryVerify(() => distinctAlongFill(p) > 3, 3000, "the band shades the fill");
        }

        function test_progress_bar_without_shimmer_is_flat() {
            const p = createTemporaryObject(barComp, root, {
                "value": 0.8,
                "animated": true,
                "status": "paused"
            });
            verify(waitForRendering(p));
            compare(distinctAlongFill(p), 1);
        }
    }

    // 1.5.0 study B2: dialogs, popups, menus.
    Component {
        id: menuItemComp
        ContextMenuItem {}
    }
    Component {
        id: menuComp
        ContextMenu {}
    }
    Component {
        id: tipHostComp
        Item {
            width: 60
            height: 20
        }
    }
    Component {
        id: tipComp
        AtlasToolTip {}
    }
    Component {
        id: statusItemComp
        StatusBarItem {
            text: "Ln 1"
            property int count: 0
            onClicked: count++
        }
    }
    Component {
        id: sectionRowComp
        SectionRow {
            title: "Row"
            property int count: 0
            onClicked: count++
        }
    }
    Component {
        id: toolbarComp
        AtlasToolbar {
            width: 300
        }
    }
    Component {
        id: plainActionComp
        QQC2.Action {}
    }
    Component {
        id: tallDialogComp
        AtlasDialog {
            property alias last: lastField
            title: "Tall"
            AtlasTextField { Layout.fillWidth: true }
            Item { Layout.preferredHeight: 600 }
            AtlasTextField { id: lastField; Layout.fillWidth: true }
        }
    }
    Component {
        id: confirmComp
        ConfirmDialog {
            title: "T"
            text: "Delete the file?"
        }
    }
    Component {
        id: bannerComp
        InfoBanner {
            width: 300
            text: "Hi"
        }
    }
    Component {
        id: toastComp
        Toast {}
    }

    TestCase {
        name: "PopupsMenus"
        when: windowShown

        function test_context_menu_item_hides_the_mnemonic() {
            const i = createTemporaryObject(menuItemComp, root, {
                text: "&Save"
            });
            compare(i.Accessible.name, "Save");
            i.text = "Fish && &Chips";
            compare(i.Accessible.name, "Fish & Chips");
        }

        function test_context_menu_width_counts_rows_out_of_view() {
            const m = createTemporaryObject(menuComp, root);
            let last = null;
            for (let n = 0; n < 40; ++n) {
                last = createTemporaryObject(menuItemComp, root, {
                    text: n === 39 ? "x".repeat(300) : "Row " + n
                });
                m.addItem(last);
            }
            verify(last.implicitWidth > 400);
            tryVerify(() => m.implicitWidth >= last.implicitWidth, 1000, "the menu is as wide as its widest row");
        }

        // The width follows rows taken out. (The crash a width binding once
        // hit inside takeItem() shows only in the compiled module; the toolbar
        // tests here and the visual tests ran into it.)
        function test_context_menu_width_follows_taken_items() {
            const m = createTemporaryObject(menuComp, root);
            const wide = createTemporaryObject(menuItemComp, root, {
                text: "x".repeat(200)
            });
            m.addItem(wide);
            m.addItem(createTemporaryObject(menuItemComp, root, { text: "A" }));
            m.addItem(createTemporaryObject(menuItemComp, root, { text: "B" }));
            tryVerify(() => m.implicitWidth >= wide.implicitWidth, 1000);
            const taken = m.takeItem(0);
            compare(taken, wide);
            compare(m.count, 2);
            tryVerify(() => m.implicitWidth < wide.implicitWidth, 1000, "the width follows the rows left");
            while (m.count > 0)
                m.takeItem(0);
            tryCompare(m.contentItem, "implicitWidth", 0, 1000);
        }

        function test_context_menu_width_is_current_when_it_opens() {
            const m = createTemporaryObject(menuComp, root);
            const wide = createTemporaryObject(menuItemComp, root, {
                text: "x".repeat(120)
            });
            // Added and opened in one turn: no event loop in between.
            m.addItem(wide);
            m.popup(root, 0, 0);
            verify(m.contentItem.implicitWidth >= wide.implicitWidth, "measured before it is placed");
            m.close();
        }

        function test_tooltip_with_no_text_never_opens() {
            const host = createTemporaryObject(tipHostComp, root, {
                y: 100
            });
            const tip = createTemporaryObject(tipComp, host, {
                text: ""
            });
            tip.shown = true;
            wait(tip.delay + 200);
            verify(!tip.visible, "nothing to say, nothing shown");
            tip.text = "Hint";
            tip.shown = false;
            tip.shown = true;
            tryVerify(() => tip.visible, tip.delay + 2000);
        }

        function test_tooltip_goes_below_when_there_is_no_room_above() {
            const host = createTemporaryObject(tipHostComp, root, {
                y: 0
            });
            const tip = createTemporaryObject(tipComp, host, {
                text: "Hint"
            });
            tip.open();
            tryVerify(() => tip.visible);
            verify(tip.y >= host.height, "below the item: " + tip.y);
            tip.close();
            host.y = 150;
            tip.open();
            tryVerify(() => tip.visible);
            verify(tip.y < 0, "above the item when it fits: " + tip.y);
            tip.close();
        }

        function test_status_item_is_a_tab_stop_and_takes_return() {
            const c = createTemporaryObject(statusItemComp, root, {
                clickable: true
            });
            verify(c.focusPolicy & Qt.TabFocus, "a clickable cell is reached with Tab");
            verify(!(c.focusPolicy & Qt.ClickFocus), "a click does not take the editor's focus");
            c.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(c.count, 1);
            const t = createTemporaryObject(statusItemComp, root);
            compare(t.focusPolicy, Qt.NoFocus);
        }

        function test_disabled_row_ignores_the_accessible_press() {
            const r = createTemporaryObject(sectionRowComp, root, {
                clickable: true,
                enabled: false
            });
            a11y.press(r);
            compare(r.count, 0);
            r.enabled = true;
            a11y.press(r);
            compare(r.count, 1);
        }

        function test_toolbar_text_only_action_draws_its_first_letter() {
            const a = createTemporaryObject(plainActionComp, root, {
                text: "&Open"
            });
            const bar = createTemporaryObject(toolbarComp, root, {
                actions: [a]
            });
            verify(bar);
            wait(50);
            const found = [];
            const walk = item => {
                for (const c of item.children) {
                    if (c._letterFallback === true) {
                        found.push(c);
                    }
                    walk(c);
                }
            };
            walk(bar);
            verify(found.length > 0, "the action's button is made");
            compare(found[0]._label, "O");
            compare(found[0].Accessible.name, "Open", "the spoken name stays whole");
        }

        function test_dialog_scrolls_to_the_field_that_takes_the_focus() {
            const d = createTemporaryObject(tallDialogComp, root);
            d.open();
            tryVerify(() => d.opened);
            const scroller = d.contentItem.children[0];
            tryVerify(() => scroller.contentHeight > scroller.height, 2000, "the body is taller than the dialog");
            compare(scroller.contentY, 0);
            d.last.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => scroller.contentY > 0, 2000, "the last field is brought into view");
            d.close();
        }

        function test_dialogs_have_no_negative_width() {
            const holder = createTemporaryObject(tipHostComp, root, {
                width: 10,
                height: 10
            });
            const c = createTemporaryObject(confirmComp, root);
            c.parent = holder;
            verify(c.width >= 0, "ConfirmDialog width " + c.width);
            const d = createTemporaryObject(tallDialogComp, root);
            d.parent = holder;
            verify(d.width >= 0, "AtlasDialog width " + d.width);
            verify(d.height >= 0, "AtlasDialog height " + d.height);
        }

        function test_confirm_dialog_exposes_its_text() {
            const c = createTemporaryObject(confirmComp, root);
            compare(c.contentItem.Accessible.description, "Delete the file?");
        }

        function test_banner_action_without_an_icon_property() {
            const plain = createTemporaryObject(plainObjectComp, root);
            const b = createTemporaryObject(bannerComp, root, {
                actions: [plain]
            });
            verify(b, "a banner with an action that has no icon still loads");
            const button = findByName(b, "bannerAction");
            verify(button, "the action's button exists");
            compare(button.text, "Retry");
            compare(button.icon.name, "");
            failOnWarning(/TypeError/);
            // A second action, to build the other button kind too.
            b.actions = [plain, plain];
            wait(50);
        }

        function findByName(item, name) {
            if (item.objectName === name) {
                return item;
            }
            for (const c of item.children) {
                const r = findByName(c, name);
                if (r) {
                    return r;
                }
            }
            return null;
        }

        function test_toast_keeps_its_action_when_shown_nothing() {
            const t = createTemporaryObject(toastComp, root);
            t.showAction("Deleted", "Undo");
            compare(t.actionText, "Undo");
            t.show(undefined);
            compare(t.actionText, "Undo");
            t.showAction("", "Redo");
            compare(t.actionText, "Undo");
            t.show("Saved");
            compare(t.actionText, "");
        }

        function test_toast_show_with_nothing_shows_nothing() {
            const t = createTemporaryObject(toastComp, root);
            t.show(undefined);
            verify(!t._showing);
            t.show(null);
            verify(!t._showing);
            compare(t.text, "");
            t.show("Saved");
            verify(t._showing);
            compare(t.text, "Saved");
        }
    }
    Component {
        id: plainObjectComp
        QtObject {
            property string text: "Retry"
            property bool enabled: true
            function trigger() {}
        }
    }

    Component {
        id: rtlStackComp
        Item {
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true
            width: 400
            height: 200
            property alias stack: navStack
            AtlasNavigationStack {
                id: navStack
                anchors.fill: parent
                initialItem: Item {
                    property string title: "First"
                }
            }
        }
    }
    Component {
        id: rtlCrumbComp
        Item {
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true
            width: 500
            height: 40
            property alias crumb: bc
            AtlasBreadcrumb {
                id: bc
                width: 500
                segments: [{ title: "Home" }, { title: "Documents" }, { title: "Projects" }]
            }
        }
    }
    Component {
        id: findBarComp
        FindBar {
            width: 600
            opened: true
            replaceVisible: true
            property int replaced: 0
            onReplaceOne: replaced++
        }
    }

    function findAll(item, name, out) {
        for (const c of item.children) {
            if (c.objectName === name) {
                out.push(c);
            }
            findAll(c, name, out);
        }
        return out;
    }

    TestCase {
        name: "PopupsMenusRtl"
        when: windowShown

        function test_back_arrow_flips_around_the_button() {
            const w = createTemporaryObject(rtlStackComp, root);
            const btn = findAll(w, "backButton", [])[0];
            verify(btn);
            const left = btn.parent.mapToItem(w, btn.x, 0).x;
            const a = btn.mapToItem(w, 0, 0).x;
            const b = btn.mapToItem(w, btn.width, 0).x;
            verify(Math.min(a, b) >= left - 1 && Math.max(a, b) <= left + btn.width + 1, "the button stays where it is: " + a + ", " + b + " in " + left + ".." + (left + btn.width));
        }

        function test_breadcrumb_chevron_sits_beside_its_button_in_rtl() {
            const w = createTemporaryObject(rtlCrumbComp, root);
            const crumb = w.crumb;
            tryVerify(() => findAll(crumb, "segmentChevron", []).length > 0);
            const btn = findAll(crumb, "segmentButton", [])[0];
            const chev = findAll(crumb, "segmentChevron", [])[0];
            const bx = btn.mapToItem(crumb, 0, 0).x;
            const cx = chev.mapToItem(crumb, 0, 0).x;
            verify(cx + chev.width <= bx + 1 || cx >= bx + btn.width - 1, "the chevron does not sit on the button: button " + bx + "+" + btn.width + ", chevron " + cx);
            verify(cx + chev.width <= bx + 1, "in right-to-left it is on the left of the button");
        }

        function test_enter_in_the_replace_field_with_no_match_replaces_nothing() {
            const f = createTemporaryObject(findBarComp, root);
            tryCompare(f, "height", f.fullHeight);
            const field = findAll(f, "replaceField", [])[0];
            verify(field);
            field.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(f.replaced, 0, "no match: nothing to replace");
            f.matchCount = 2;
            keyClick(Qt.Key_Return);
            compare(f.replaced, 1);
        }
    }
}
