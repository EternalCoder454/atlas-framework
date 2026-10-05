import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import Atlas.Ui

// 1.5.0: AtlasPage.subtitle and busy, AtlasDialog.scrollToTop, the width
// breakpoints, AtlasWindow.toast() and confirm(), and the navigation stack.
Item {
    id: root
    width: 500
    height: 400

    Component {
        id: pageComp
        AtlasPage {
            anchors.fill: parent
            title: "T"
            Text { text: "content" }
        }
    }
    Component {
        id: dialogComp
        AtlasDialog {
            title: "Long"
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 3000; color: "gray" }
        }
    }
    Component {
        id: windowComp
        AtlasWindow {
            width: 400
            height: 300
            visible: true
        }
    }
    Component {
        id: vetoComp
        AtlasWindow {
            width: 400
            height: 300
            visible: true
            onClosing: close => { close.accepted = false; }
        }
    }
    Component {
        id: stackComp
        AtlasNavigationStack {
            anchors.fill: parent
            initialItem: Item { property string title: "First" }
        }
    }

    function find(item, pred) {
        if (pred(item)) {
            return item;
        }
        for (const c of item.children) {
            const f = find(c, pred);
            if (f) {
                return f;
            }
        }
        return null;
    }

    TestCase {
        name: "PageSubtitleBusy"
        when: windowShown

        function test_subtitle() {
            const p = createTemporaryObject(pageComp, root);
            const sub = () => find(p, i => i.maximumLineCount === 3 && i.text !== undefined);
            verify(sub());
            verify(!sub().visible, "hidden when empty");
            p.subtitle = "Two muted lines";
            verify(sub().visible);
            compare(sub().text, "Two muted lines");
            compare(p.Accessible.description, "Two muted lines");
        }

        function test_busy_row() {
            const p = createTemporaryObject(pageComp, root);
            const spinner = find(p, i => i.running !== undefined && i.animated !== undefined);
            verify(spinner);
            verify(!spinner.visible, "no room while idle");
            p.busyText = "Checking";
            p.busy = true;
            tryVerify(() => spinner.visible && spinner.height > 0);
            p.busy = false;
            tryVerify(() => !spinner.visible);
        }
    }

    TestCase {
        name: "DialogScrollToTop"
        when: windowShown

        function test_scrolls_to_top_on_open() {
            const d = createTemporaryObject(dialogComp, root);
            const fl = find(d.contentItem, i => i.contentY !== undefined && i.boundsBehavior !== undefined);
            verify(fl);
            d.open();
            tryVerify(() => d.opened);
            fl.contentY = 200;
            compare(fl.contentY, 200);
            d.close();
            tryVerify(() => !d.visible);
            d.open();
            tryVerify(() => d.opened);
            compare(fl.contentY, 0, "reopened at the top");
            fl.contentY = 150;
            d.scrollToTop();
            compare(fl.contentY, 0);
        }

        function test_an_open_dialog_is_not_scrolled_by_itself() {
            const d = createTemporaryObject(dialogComp, root);
            const fl = find(d.contentItem, i => i.contentY !== undefined && i.boundsBehavior !== undefined);
            d.open();
            tryVerify(() => d.opened);
            fl.contentY = 200;
            wait(150);
            compare(fl.contentY, 200);
        }
    }

    TestCase {
        name: "WindowBreakpoints"
        when: windowShown

        function test_defaults_and_tuning() {
            const gu = Kirigami.Units.gridUnit;
            const w = createTemporaryObject(windowComp, root);
            w.width = gu * 35;
            tryCompare(w, "width", gu * 35);
            tryCompare(w, "widthClass", AtlasWindow.WidthClass.Medium);
            w.compactBreakpoint = 38;
            tryCompare(w, "widthClass", AtlasWindow.WidthClass.Compact);
            verify(w.sidebarCollapsed);
            w.compactBreakpoint = 30;
            w.wideBreakpoint = 34;
            tryCompare(w, "widthClass", AtlasWindow.WidthClass.Wide);
        }

        function test_bad_values_use_the_defaults() {
            const gu = Kirigami.Units.gridUnit;
            const w = createTemporaryObject(windowComp, root);
            w.width = gu * 35;
            tryCompare(w, "width", gu * 35);
            w.compactBreakpoint = -5;
            tryCompare(w, "widthClass", AtlasWindow.WidthClass.Medium);
            w.compactBreakpoint = NaN;
            tryCompare(w, "widthClass", AtlasWindow.WidthClass.Medium);
            w.compactBreakpoint = Infinity;
            tryCompare(w, "widthClass", AtlasWindow.WidthClass.Medium);
        }

        function test_no_medium_when_compact_not_below_wide() {
            const gu = Kirigami.Units.gridUnit;
            const w = createTemporaryObject(windowComp, root);
            w.compactBreakpoint = 40;
            w.wideBreakpoint = 40;
            w.width = gu * 39;
            tryCompare(w, "width", gu * 39);
            tryCompare(w, "widthClass", AtlasWindow.WidthClass.Compact);
            w.width = gu * 41;
            tryCompare(w, "width", gu * 41);
            tryCompare(w, "widthClass", AtlasWindow.WidthClass.Wide);
        }
    }

    TestCase {
        name: "WindowToastConfirm"
        when: windowShown

        function test_toasts_queue_one_at_a_time() {
            const w = createTemporaryObject(windowComp, root);
            let acted = 0;
            w.toast("a");
            w.toast("a");
            compare(w._toastItem.text, "a");
            compare(w._toasts.length, 0, "the same text twice is shown once");
            tryVerify(() => w._toastItem.visible);
            const act = () => { acted++; };
            w.toast("b", { actionText: "Undo", onAction: act });
            w.toast("b", { actionText: "Undo", onAction: act });
            compare(w._toasts.length, 1, "queued behind the first");
            compare(w._toastItem.text, "a");
            w._toastItem.hide();
            tryCompare(w._toastItem, "text", "b", 3000);
            compare(w._toastItem.actionText, "Undo");
            w._toastItem.actionTriggered();
            compare(acted, 1);
            tryVerify(() => w._toastItem.visible);
            w.toast("c", { kind: "error" });
            w.toast(42);
            w._toastItem.hide();
            tryCompare(w._toastItem, "text", "c", 3000);
            compare(w._toastItem.interval, 5000);
        }

        function test_toast_ignores_bad_input() {
            const w = createTemporaryObject(windowComp, root);
            w.toast("");
            w.toast(null, 5);
            compare(w._toastItem, null, "nothing is made for nothing");
            w.toast("x", { timeout: -1, onAction: "no" });
            compare(w._toastItem.interval, 2500);
        }

        function test_confirm_accept_calls_done_once() {
            const w = createTemporaryObject(windowComp, root);
            const calls = [];
            const d = w.confirm({ title: "Sure?", text: "Really", acceptText: "Yes", destructive: true }, r => calls.push(r));
            verify(d);
            compare(d.title, "Sure?");
            compare(d.acceptText, "Yes");
            compare(d.destructive, true);
            tryVerify(() => d.opened);
            d.accepted();
            d.close();
            tryCompare(calls, "length", 1);
            wait(100);
            compare(calls.length, 1);
            compare(calls[0], true);
        }

        function test_confirm_cancel_and_window_close() {
            const w = createTemporaryObject(windowComp, root);
            const calls = [];
            const d = w.confirm({ title: "A" }, r => calls.push("a" + r));
            tryVerify(() => d.opened);
            d.close();
            tryCompare(calls, "length", 1);
            compare(calls[0], "afalse");
            w.confirm({ title: "B" }, r => calls.push("b" + r));
            w.confirm({ title: "C" });
            wait(50);
            w.visible = false;
            tryCompare(calls, "length", 2);
            wait(100);
            compare(calls.length, 2);
            compare(calls[1], "bfalse");
        }
    }

    TestCase {
        name: "WindowConfirmRobust"
        when: windowShown

        function test_hidden_window_answers_false_at_once() {
            const w = createTemporaryObject(windowComp, root);
            w.visible = false;
            const calls = [];
            const d = w.confirm({ title: "x" }, r => calls.push(r));
            compare(d, null);
            compare(calls.length, 1);
            compare(calls[0], false);
        }

        function test_two_open_confirms_each_answer_once() {
            const w = createTemporaryObject(windowComp, root);
            const calls = [];
            const a = w.confirm({ title: "A" }, r => calls.push("a" + r));
            const b = w.confirm({ title: "B" }, r => calls.push("b" + r));
            tryVerify(() => a.opened && b.opened);
            b.accepted();
            b.close();
            a.close();
            tryCompare(calls, "length", 2);
            wait(100);
            compare(calls.length, 2);
            verify(calls.indexOf("btrue") >= 0 && calls.indexOf("afalse") >= 0);
        }

        function test_caller_destroys_the_dialog() {
            const w = createTemporaryObject(windowComp, root);
            const calls = [];
            const d = w.confirm({ title: "A" }, r => calls.push(r));
            tryVerify(() => d.opened);
            d.destroy();
            tryCompare(calls, "length", 1);
            wait(100);
            compare(calls.length, 1);
            compare(calls[0], false);
        }

        function test_window_destroyed_while_open() {
            const w = windowComp.createObject(root);
            const calls = [];
            const d = w.confirm({ title: "A" }, r => calls.push(r));
            tryVerify(() => d.opened);
            w.destroy();
            tryCompare(calls, "length", 1);
            wait(100);
            compare(calls.length, 1);
            compare(calls[0], false);
        }

        function test_a_vetoed_close_keeps_the_confirmation() {
            const w = createTemporaryObject(vetoComp, root);
            const calls = [];
            const d = w.confirm({ title: "A" }, r => calls.push(r));
            tryVerify(() => d.opened);
            w.close();
            wait(150);
            compare(calls.length, 0);
            verify(w.visible);
            d.close();
            tryCompare(calls, "length", 1);
        }
    }

    TestCase {
        name: "WindowToastRobust"
        when: windowShown

        function test_queue_is_bounded() {
            const w = createTemporaryObject(windowComp, root);
            for (let i = 0; i < 40; ++i) {
                w.toast("t" + i);
            }
            compare(w._toasts.length, 20);
            compare(w._toasts[19].text, "t39");
        }

        function test_dedup_compares_the_action() {
            const w = createTemporaryObject(windowComp, root);
            const fn = () => {};
            w.toast("a");
            w.toast("a", { actionText: "Undo", onAction: fn });
            compare(w._toasts.length, 1);
            w.toast("a", { actionText: "Undo", onAction: fn });
            compare(w._toasts.length, 1, "same text and action");
            w.toast("a", { actionText: "Undo", onAction: () => {} });
            compare(w._toasts.length, 2, "another function is another action");
        }

        function test_timeout_is_clamped() {
            const w = createTemporaryObject(windowComp, root);
            w.toast("a", { timeout: 1e9 });
            compare(w._toastItem.interval, 60000);
            w.toast("b", { timeout: 0.4 });
            compare(w._toasts[0].timeout, 1);
            w.toast("c", { timeout: 1234.6 });
            compare(w._toasts[1].timeout, 1235);
        }

        function test_hidden_window_does_not_stall_the_queue() {
            const w = createTemporaryObject(windowComp, root);
            w.toast("a", { timeout: 100 });
            w.visible = false;
            wait(400);
            w.visible = true;
            w.toast("b");
            compare(w._toastCur.text, "b");
            compare(w._toastItem.text, "b");
        }

        function test_nothing_piles_up() {
            const w = createTemporaryObject(windowComp, root);
            w.toast("warm", { timeout: 1 });
            wait(100);
            const before = w.contentItem.data.length;
            for (let i = 0; i < 50; ++i) {
                const d = w.confirm({ title: "c" + i }, () => {});
                tryVerify(() => d.opened);
                d.close();
                w.toast("t" + i, { timeout: 1 });
            }
            wait(300);
            gc();
            wait(50);
            verify(w.contentItem.data.length <= before + 2, "objects were freed: " + w.contentItem.data.length + " vs " + before);
        }
    }

    TestCase {
        name: "NavigationStackAnnounce"
        when: windowShown

        function test_push_and_pop_still_work_with_titles() {
            const s = createTemporaryObject(stackComp, root);
            verify(s);
            compare(s.depth, 1);
            s.push(pageItem, { title: "Second" });
            tryCompare(s, "depth", 2);
            s.pop();
            tryCompare(s, "depth", 1);
        }
    }
    Component {
        id: pageItem
        Item { property string title }
    }
}
