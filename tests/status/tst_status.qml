import QtQuick
import QtQuick.Layouts
import QtTest
import Telamon.Ui
import org.kde.kirigami as Kirigami

// TelamonStatus on TelamonListView, DataTable, TelamonTreeView and TelamonPage.
Item {
    id: root
    width: 480
    height: 360

    property bool keep: true
    ListModel {
        id: lm
        ListElement { name: "a"; cpu: 1 }
        ListElement { name: "b"; cpu: 2 }
        ListElement { name: "c"; cpu: 3 }
    }
    TelamonTreeModel {
        id: tm
        items: [{ text: "one", children: [{ text: "two" }] }, { text: "three" }]
    }
    TelamonAction {
        id: retry
        text: "Re&try"
        symbol: Symbols.Refresh
    }
    Component {
        id: spyComp
        SignalSpy {
            signalName: "activated"
        }
    }
    SignalSpy {
        id: retrySpy
        target: retry
        signalName: "triggered"
    }

    Component {
        id: listComp
        TelamonListView {
            anchors.fill: parent
            model: lm
            textRole: "name"
            header: Rectangle {
                objectName: "hdr"
                width: ListView.view.width
                height: 30
                color: "gray"
            }
            statusAction: retry
        }
    }
    Component {
        id: bindComp
        TelamonListView {
            anchors.fill: parent
            model: 3
            delegate: Rectangle {
                required property int index
                width: ListView.view.width
                height: 20
                color: "blue"
                visible: root.keep
            }
        }
    }
    Component {
        id: tableComp
        DataTable {
            anchors.fill: parent
            model: lm
            columns: [{ title: "Name", role: "name", fill: true }, { title: "CPU", role: "cpu", width: 5 }]
            statusAction: retry
        }
    }
    Component {
        id: treeComp
        TelamonTreeView {
            anchors.fill: parent
            model: tm
            statusAction: retry
        }
    }
    Component {
        id: pageComp
        TelamonPage {
            anchors.fill: parent
            title: "Pagetitle"
            statusAction: retry
            Rectangle {
                objectName: "content"
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                color: "red"
            }
        }
    }

    Component {
        id: emptyComp
        TelamonEmptyState {
            width: 300
            symbol: Symbols.Error
            title: "Something went wrong"
            text: "The folder could not be read."
            actionText: "Retry"
        }
    }

    TestCase {
        name: "TelamonEmptyStateFit"
        when: windowShown

        function parts(e) {
            const found = [];
            const walk = it => {
                for (let i = 0; i < it.children.length; ++i) {
                    found.push(it.children[i]);
                    walk(it.children[i]);
                }
            };
            walk(e);
            return found;
        }
        function button(e) {
            return parts(e).find(p => p.text === "Retry" && p.clicked !== undefined);
        }
        function symbolShown(e) {
            return parts(e).some(p => p.Layout && p.Layout.preferredHeight === Kirigami.Units.iconSizes.huge && p.visible);
        }

        function test_roomy_shows_everything_without_scrolling() {
            const e = createTemporaryObject(emptyComp, root, { height: 500 });
            waitForRendering(e);
            verify(symbolShown(e));
            const flick = parts(e).find(p => p.contentHeight !== undefined);
            verify(!flick.interactive);
        }

        function test_short_drops_the_symbol_and_stays_inside() {
            const e = createTemporaryObject(emptyComp, root, { height: 500 });
            waitForRendering(e);
            verify(symbolShown(e));
            // Room for the rest but not for the symbol, whatever the font metrics.
            const col = parts(e).find(p => p._bare !== undefined);
            e.height = Math.ceil(col._bare + Kirigami.Units.gridUnit * 2 + Kirigami.Units.iconSizes.huge / 2);
            waitForRendering(e);
            verify(!symbolShown(e), "the symbol goes first");
            const b = button(e);
            verify(b);
            const at = b.mapToItem(e, 0, 0);
            verify(at.y >= 0 && at.y + b.height <= e.height, "the button is inside: " + at.y + "+" + b.height);
        }

        // The implicit height always counts the symbol, so a short pass does
        // not drop it for good (the gallery's long-text cell lost it).
        function test_sized_to_its_implicit_height_after_a_short_pass_shows_the_symbol() {
            const e = createTemporaryObject(emptyComp, root, { height: 60 });
            waitForRendering(e);
            verify(!symbolShown(e));
            e.height = e.implicitHeight;
            waitForRendering(e);
            verify(symbolShown(e), "sized to its implicit height, the symbol shows");
        }

        function test_very_short_scrolls_inside_its_area() {
            const e = createTemporaryObject(emptyComp, root, { height: 60 });
            waitForRendering(e);
            const flick = parts(e).find(p => p.contentHeight !== undefined);
            verify(flick.interactive);
            verify(flick.clip, "nothing is drawn past the edges");
        }
    }

    TestCase {
        name: "TelamonStatus"
        when: windowShown

        function make(kind) {
            const comp = { "list": listComp, "table": tableComp, "tree": treeComp, "page": pageComp }[kind];
            const v = createTemporaryObject(comp, root);
            verify(v !== null);
            retrySpy.clear();
            return v;
        }
        // The status view inside a view: the one item with `spinnerShown`.
        function findBy(item, pred, depth) {
            if (depth === undefined) {
                depth = 0;
            }
            if (!item || depth > 14) {
                return null;
            }
            if (pred(item)) {
                return item;
            }
            const kids = item.children;
            for (let i = 0; i < kids.length; ++i) {
                const r = findBy(kids[i], pred, depth + 1);
                if (r) {
                    return r;
                }
            }
            return null;
        }
        function statusView(v) {
            const s = findBy(v, c => c.spinnerShown !== undefined);
            verify(s !== null, "the view has a status view");
            return s;
        }
        function emptyState(sv) {
            return findBy(sv, c => c.actionText !== undefined);
        }

        function test_enum_values() {
            compare(TelamonStatus.Ready, 0);
            compare(TelamonStatus.Loading, 1);
            compare(TelamonStatus.Empty, 2);
            compare(TelamonStatus.NoResults, 3);
            compare(TelamonStatus.Error, 4);
        }

        function test_each_status_on_each_view_data() {
            const out = [];
            for (const k of ["list", "table", "tree", "page"]) {
                for (const s of ["Empty", "NoResults", "Error"]) {
                    out.push({ tag: k + " " + s, kind: k, status: s });
                }
            }
            return out;
        }
        function test_each_status_on_each_view(data) {
            const v = make(data.kind);
            const sv = statusView(v);
            compare(v.status, TelamonStatus.Ready);
            verify(!sv.visible, "Ready shows no status");
            v.status = TelamonStatus[data.status];
            verify(sv.visible);
            const es = emptyState(sv);
            verify(es !== null && es.visible, "an empty state shows");
            const title = { "Empty": "Nothing here", "NoResults": "No results", "Error": "Something went wrong" }[data.status];
            const sym = { "Empty": Symbols.Inbox, "NoResults": Symbols.SearchOff, "Error": Symbols.Error }[data.status];
            compare(es.title, title);
            compare(es.symbol, sym);
            // The app's own text, symbol and title win.
            v.statusTitle = "Mine";
            v.statusText = "Because.";
            v.statusSymbol = Symbols.Folder;
            compare(es.title, "Mine");
            compare(es.text, "Because.");
            compare(es.symbol, Symbols.Folder);
            v.status = TelamonStatus.Ready;
            verify(!sv.visible, "back to Ready hides it");
        }

        function test_rows_replaced_data() {
            return [{ tag: "list" }, { tag: "table" }, { tag: "tree" }, { tag: "page" }];
        }
        function test_rows_replaced(data) {
            const v = make(data.tag);
            const rowItem = () => {
                if (data.tag === "list") {
                    return v.itemAtIndex(0);
                }
                if (data.tag === "page") {
                    return findBy(v, c => c.objectName === "content");
                }
                // The table's ListView and the tree's TreeView.
                return findBy(v, c => c.reuseItems !== undefined && c !== v);
            };
            tryVerify(() => rowItem() !== null && rowItem() !== undefined);
            verify(rowItem().visible, "rows show when Ready");
            v.status = TelamonStatus.Empty;
            verify(!rowItem().visible, "rows hidden under a status");
            v.status = TelamonStatus.Ready;
            verify(rowItem().visible, "rows are back");
        }

        function test_spinner_delay_is_300ms() {
            const v = make("list");
            compare(statusView(v)._delay, 300);
        }

        function test_loading_spinner_waits() {
            const v = make("list");
            const sv = statusView(v);
            sv._delay = 1200;
            v.status = TelamonStatus.Loading;
            verify(sv.visible);
            verify(!sv.spinnerShown);
            wait(100);
            verify(!sv.spinnerShown, "no spinner before the delay");
            tryVerify(() => sv.spinnerShown, 3000);
            compare(sv.effectiveTitle, "", "Loading has no heading");
            v.status = TelamonStatus.Ready;
            verify(!sv.spinnerShown);
            verify(!sv.visible);
        }

        function test_fast_load_never_shows_the_spinner() {
            const v = make("table");
            const sv = statusView(v);
            sv._delay = 800;
            v.status = TelamonStatus.Loading;
            wait(50);
            v.status = TelamonStatus.Ready;
            wait(1000);
            verify(!sv.spinnerShown, "a load that ended early left no spinner");
            verify(!sv.visible);
        }

        function test_loading_announces_nothing() {
            const v = make("list");
            const sv = statusView(v);
            const said = [];
            sv._announceHook = t => said.push(t);
            wait(50);
            v.status = TelamonStatus.Loading;
            wait(500);
            v.status = TelamonStatus.Ready;
            wait(50);
            compare(said.length, 0);
        }

        function test_error_is_announced_once() {
            const v = make("page");
            const sv = statusView(v);
            const said = [];
            sv._announceHook = t => said.push(t);
            wait(50);
            // The text comes a moment after the status: it is still spoken.
            v.status = TelamonStatus.Error;
            v.statusText = "No network.";
            tryCompare(said, "length", 1);
            compare(said[0], "Something went wrong. No network.");
            v.status = TelamonStatus.Empty;
            wait(50);
            compare(said.length, 1, "Empty is not announced");
        }

        function test_action_button_triggers() {
            const v = make("list");
            const sv = statusView(v);
            v.status = TelamonStatus.Error;
            const es = emptyState(sv);
            compare(es.actionText, "Retry", "the mnemonic marker is dropped");
            compare(es.actionSymbol, Symbols.Refresh);
            const btn = findBy(es, c => c.text === "Retry" && typeof c.clicked === "function");
            verify(btn !== null && btn.visible, "the button shows");
            // The layout settles on the next frame; a click before it misses.
            waitForRendering(v);
            mouseClick(btn);
            compare(retrySpy.count, 1);
            // No action, no button.
            v.statusAction = null;
            compare(es.actionText, "");
        }

        function test_disabled_action_has_no_button() {
            const v = make("list");
            const sv = statusView(v);
            v.status = TelamonStatus.Empty;
            const es = emptyState(sv);
            verify(findBy(es, c => c.text === "Retry" && typeof c.clicked === "function" && c.visible) !== null);
            retry.enabled = false;
            compare(es.actionText, "");
            verify(findBy(es, c => c.text === "Retry" && typeof c.clicked === "function" && c.visible) === null, "no dead button");
            es.triggered();
            compare(retrySpy.count, 0);
            retry.enabled = true;
            compare(es.actionText, "Retry");
            es.triggered();
            compare(retrySpy.count, 1);
        }

        function test_app_visible_binding_survives_a_status() {
            const l = createTemporaryObject(bindComp, root);
            verify(l !== null);
            tryVerify(() => l.itemAtIndex(0) !== null);
            const d = l.itemAtIndex(0);
            verify(d.visible);
            l.status = TelamonStatus.Empty;
            verify(!d.visible, "hidden under the status");
            l.status = TelamonStatus.Ready;
            verify(d.visible);
            root.keep = false;
            verify(!d.visible, "the app's binding still drives it");
            l.status = TelamonStatus.Loading;
            l.status = TelamonStatus.Ready;
            verify(!d.visible, "still hidden by the app");
            root.keep = true;
            verify(d.visible, "and shown again by the app");
            // Under a status the app's change waits for Ready.
            l.status = TelamonStatus.Error;
            root.keep = false;
            root.keep = true;
            verify(!d.visible);
            l.status = TelamonStatus.Ready;
            verify(d.visible);
        }

        function test_clicks_do_nothing_under_a_status() {
            const l = make("list");
            tryVerify(() => l.itemAtIndex(0) !== null);
            l.currentIndex = -1;
            const spy = createTemporaryObject(spyComp, root, { target: l });
            l.status = TelamonStatus.Empty;
            mouseClick(l, 20, 60);
            mouseDoubleClickSequence(l, 20, 60);
            mouseClick(l, 20, 60, Qt.RightButton);
            compare(l.currentIndex, -1);
            compare(l.selectedIndexes, []);
            compare(spy.count, 0);
        }

        function test_table_header_stays() {
            const t = make("table");
            const sv = statusView(t);
            t.status = TelamonStatus.NoResults;
            const head = findBy(t, c => c.Accessible.role === Accessible.ColumnHeader);
            verify(head !== null, "the table has a column header");
            verify(head.visible, "the header stays");
            const top = sv.mapToItem(t, 0, 0).y;
            const headBottom = head.mapToItem(t, 0, head.height).y;
            verify(top >= headBottom - 1, "the status sits under the header: " + top + " vs " + headBottom);
        }

        function test_list_header_stays() {
            const l = make("list");
            const sv = statusView(l);
            l.status = TelamonStatus.Empty;
            tryVerify(() => l.headerItem !== null);
            verify(l.headerItem.visible, "the list's header stays");
            verify(sv.y >= l.headerItem.height - 1, "the status sits under the header: " + sv.y);
            verify(!l.itemAtIndex(0).visible);
        }

        function test_page_title_stays() {
            const p = make("page");
            p.status = TelamonStatus.Error;
            const title = findBy(p, c => c.text === "Pagetitle");
            verify(title !== null && title.visible, "the title stays");
            const content = findBy(p, c => c.objectName === "content");
            verify(!content.visible, "the content is hidden");
            const sv = statusView(p);
            verify(sv.visible);
            // The layout settles on the next frame.
            tryVerify(() => sv.mapToItem(p, 0, 0).y >= title.mapToItem(p, 0, title.height).y - 1);
        }

        function test_tree_keys_do_nothing_under_a_status() {
            const t = make("tree");
            t.forceActiveFocus();
            t.status = TelamonStatus.Empty;
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            compare(t.selectionModel.hasSelection, false);
        }

        function test_reused_rows_stay_hidden() {
            const l = createTemporaryObject(bindComp, root);
            verify(l !== null);
            l.model = 300;
            tryVerify(() => l.itemAtIndex(0) !== null);
            const rows = () => l.contentItem.children.filter(c => c.ListView.view === l);
            l.status = TelamonStatus.Empty;
            verify(rows().every(r => !r.visible), "rows hidden");
            // Scrolling reuses the delegates: they stay hidden, with new rows too.
            l.contentY = 1500;
            wait(100);
            l.contentY = 3000;
            wait(100);
            verify(rows().length > 0);
            verify(rows().every(r => !r.visible), "reused rows hidden");
            l.status = TelamonStatus.Ready;
            verify(rows().every(r => r.visible), "rows back");
        }
    }
}
