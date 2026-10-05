import QtQuick
import QtQuick.Layouts
import QtTest
import Atlas.Ui

Item {
    id: root
    width: 400
    height: 300

    Component {
        id: listComp
        AtlasListView {
            anchors.fill: parent
            selectionMode: AtlasListView.MultiSelection
            model: ["Apple", "Banana", "Berry", "Cherry", "Date", "Elder", "Fig"]
        }
    }
    Component {
        id: bigComp
        AtlasListView {
            anchors.fill: parent
            model: 10000
        }
    }

    SignalSpy { id: activatedSpy; signalName: "activated" }
    SignalSpy { id: menuSpy; signalName: "contextMenuRequested" }
    SignalSpy { id: moveSpy; signalName: "moveRequested" }

    TestCase {
        name: "AtlasListView"
        when: windowShown

        function make(props) {
            const l = createTemporaryObject(listComp, root, props || {});
            verify(l !== null);
            l.forceActiveFocus();
            tryVerify(() => l.activeFocus);
            for (const s of [activatedSpy, menuSpy, moveSpy]) {
                s.target = l;
                s.clear();
            }
            return l;
        }
        function rowY(l, i) {
            return (i + 0.5) * l._rowH;
        }

        function test_arrows_select_and_shift_extends() {
            const l = make();
            keyClick(Qt.Key_Down);
            compare(l.currentIndex, 1);
            compare(l.selectedIndexes, [1]);
            keyClick(Qt.Key_Down, Qt.ShiftModifier);
            keyClick(Qt.Key_Down, Qt.ShiftModifier);
            compare(l.selectedIndexes, [1, 2, 3]);
            keyClick(Qt.Key_Up, Qt.ShiftModifier);
            compare(l.selectedIndexes, [1, 2]);
        }
        function test_ctrl_a_and_clear() {
            const l = make();
            keyClick(Qt.Key_A, Qt.ControlModifier);
            compare(l.selectedIndexes.length, 7);
            l.clearSelection();
            compare(l.selectedIndexes.length, 0);
            verify(!l.isSelected(0));
        }
        function test_ctrl_a_single_selects_nothing_more() {
            const l = make({selectionMode: AtlasListView.SingleSelection});
            keyClick(Qt.Key_A, Qt.ControlModifier);
            compare(l.selectedIndexes.length, 0);
        }
        function test_no_selection() {
            const l = make({selectionMode: AtlasListView.NoSelection});
            keyClick(Qt.Key_Down);
            compare(l.currentIndex, 1);
            compare(l.selectedIndexes.length, 0);
            l.select(2);
            compare(l.selectedIndexes.length, 0);
        }
        function test_clicks() {
            const l = make();
            mouseClick(l, 50, rowY(l, 1));
            compare(l.selectedIndexes, [1]);
            mouseClick(l, 50, rowY(l, 3), Qt.LeftButton, Qt.ControlModifier);
            compare(l.selectedIndexes, [1, 3]);
            mouseClick(l, 50, rowY(l, 3), Qt.LeftButton, Qt.ControlModifier);
            compare(l.selectedIndexes, [1]);
            mouseClick(l, 50, rowY(l, 1));
            mouseClick(l, 50, rowY(l, 4), Qt.LeftButton, Qt.ShiftModifier);
            compare(l.selectedIndexes, [1, 2, 3, 4]);
        }
        function test_activate() {
            const l = make();
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(activatedSpy.count, 1);
            compare(activatedSpy.signalArguments[0][0], 1);
        }
        function test_context_menu() {
            const l = make();
            mouseClick(l, 50, rowY(l, 1));
            mouseClick(l, 50, rowY(l, 5), Qt.RightButton);
            compare(menuSpy.count, 1);
            compare(menuSpy.signalArguments[0][0], 5);
            compare(l.selectedIndexes, [5]); // an unselected row is selected first
            keyClick(Qt.Key_Menu);
            compare(menuSpy.count, 2);
            keyClick(Qt.Key_F10, Qt.ShiftModifier);
            compare(menuSpy.count, 3);
            compare(menuSpy.signalArguments[2][0], 5);
        }
        function test_reorder_keys() {
            const l = make({reorderable: true});
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down, Qt.AltModifier);
            compare(moveSpy.count, 1);
            compare(moveSpy.signalArguments[0][0], 1);
            compare(moveSpy.signalArguments[0][1], 2);
            keyClick(Qt.Key_Home);
            keyClick(Qt.Key_Up, Qt.AltModifier);
            compare(moveSpy.count, 1); // already first
        }
        function test_no_reorder_unless_asked() {
            const l = make();
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down, Qt.AltModifier);
            compare(moveSpy.count, 0);
        }
        function test_type_ahead() {
            const l = make();
            keyClick("c");
            compare(l.currentIndex, 3);
            wait(600);
            keyClick("d");
            compare(l.currentIndex, 4);
            wait(600);
            keyClick("b");
            keyClick("e");
            keyClick("r");
            compare(l.currentIndex, 2);
        }
        function test_count_shrink_drops_selection() {
            const l = make({model: ["a", "b", "c", "d"]});
            keyClick(Qt.Key_A, Qt.ControlModifier);
            compare(l.selectedIndexes.length, 4);
            // A new model starts with nothing selected.
            l.model = ["a", "b"];
            compare(l.selectedIndexes, []);
        }
        function test_big_list_select_all() {
            const l = createTemporaryObject(bigComp, root, {selectionMode: AtlasListView.MultiSelection});
            l.forceActiveFocus();
            const t0 = Date.now();
            keyClick(Qt.Key_A, Qt.ControlModifier);
            compare(l.selectedIndexes.length, 10000);
            keyClick(Qt.Key_End);
            compare(l.currentIndex, 9999);
            verify(Date.now() - t0 < 3000);
        }

        function test_enum_values() {
            compare(AtlasListView.SingleSelection, 0);
            compare(AtlasListView.MultiSelection, 1);
            compare(AtlasListView.NoSelection, 2);
        }
        function test_select_api() {
            const l = make();
            l.selectRows([1, 3, 99, -2]);
            compare(l.selectedRows, [1, 3]);
            compare(l.selectedIndexes, [1, 3]);
            l.selectAll();
            compare(l.selectedRows.length, 7);
            l.clearSelection();
            compare(l.selectedRows, []);
            const s = make({selectionMode: AtlasListView.SingleSelection});
            s.selectRows([99, 4, 2]);
            compare(s.selectedRows, [4]);
            s.selectAll();
            compare(s.selectedRows, [4]);
            const n = make({selectionMode: AtlasListView.NoSelection});
            n.selectRows([1]);
            compare(n.selectedRows, []);
        }
        function test_model_change_clears_selection() {
            const l = make();
            l.selectRows([1, 2]);
            l.model = ["x", "y", "z"];
            compare(l.selectedRows, []);
        }
        function test_selection_follows_list_model() {
            const l = make({model: lm});
            lm.clear();
            for (const t of ["a", "b", "c", "d", "e"]) {
                lm.append({text: t});
            }
            l.selectRows([1, 3]);
            lm.insert(0, {text: "new"});
            compare(l.selectedRows, [2, 4]);
            lm.remove(2, 1);
            compare(l.selectedRows, [3]);
            lm.remove(0, 1);
            compare(l.selectedRows, [2]);
            lm.clear();
            compare(l.selectedRows, []);
        }
        function test_ctrl_shift_click_adds_range() {
            const l = make();
            mouseClick(l, 50, rowY(l, 1));
            mouseClick(l, 50, rowY(l, 5), Qt.LeftButton, Qt.ControlModifier);
            compare(l.selectedRows, [1, 5]);
            // Anchor is row 5 now: Ctrl+Shift to row 3 keeps 1 and adds 3..5.
            mouseClick(l, 50, rowY(l, 3), Qt.LeftButton, Qt.ControlModifier | Qt.ShiftModifier);
            compare(l.selectedRows, [1, 3, 4, 5]);
        }
        function test_menu_key_uses_row_item() {
            const l = make();
            keyClick(Qt.Key_Menu);
            compare(menuSpy.count, 1);
            const p = menuSpy.signalArguments[0][1];
            verify(Math.abs(p.y - rowY(l, 0)) < 2);
        }
    }
    ListModel { id: lm }

    Component {
        id: sidebarComp
        AtlasSidebar {
            width: 240
            height: 300
            SidebarItem { Layout.fillWidth: true; text: "One"; selected: true }
            SidebarItem { Layout.fillWidth: true; text: "Two" }
            SidebarItem { Layout.fillWidth: true; text: "Three" }
        }
    }
    Component {
        id: groupSidebarComp
        AtlasSidebar {
            width: 240
            height: 300
            property alias one: itemOne
            property alias group: grp
            property alias inGroup: itemIn
            SidebarItem { id: itemOne; Layout.fillWidth: true; text: "One"; badge: "3"; badgeText: "3 unread" }
            SidebarGroup {
                id: grp
                Layout.fillWidth: true
                text: "Group"
                SidebarItem { id: itemIn; Layout.fillWidth: true; text: "Inner" }
            }
        }
    }
    Component {
        id: tallSidebarComp
        AtlasSidebar {
            width: 240
            height: 120
            property bool rtl: false
            LayoutMirroring.enabled: rtl
            LayoutMirroring.childrenInherit: true
            Repeater {
                model: 12
                SidebarItem { Layout.fillWidth: true; text: "Entry " + index }
            }
        }
    }
    Component {
        id: ringComp
        Rectangle {
            width: 100
            height: 40
            property alias ring: focusRing
            AtlasFocusRing { id: focusRing }
        }
    }

    TestCase {
        name: "MotionHighlight"
        when: windowShown

        function findHighlight(item) {
            for (const c of item.children) {
                if (c instanceof Rectangle && c.z === -1 && Qt.colorEqual(c.color, AtlasStyle.selection)) {
                    return c;
                }
                const f = findHighlight(c);
                if (f) {
                    return f;
                }
            }
            return null;
        }
        function test_sidebar_selection_slides() {
            if (AtlasStyle.reducedMotion) {
                skip("reduced motion");
            }
            const sb = createTemporaryObject(sidebarComp, root);
            verify(sb !== null);
            const hl = findHighlight(sb);
            verify(hl !== null);
            tryVerify(() => hl.visible && hl.height > 0);
            wait(100);
            const y0 = hl.y;
            // Moving the selection deselects the old entry first: the highlight
            // must stay placed and slide, not jump.
            let leaves = [];
            const find = it => { for (const c of it.children) { if (c._sharedSelection !== undefined && c._entries === undefined && c.selected !== undefined) leaves.push(c); else find(c); } };
            find(sb);
            compare(leaves.length, 3);
            leaves[0].selected = false;
            leaves[2].selected = true;
            wait(30);
            verify(hl.visible);
            verify(hl.y > y0 && hl.y < leaves[2].mapToItem(hl.parent, 0, 0).y - 1, "highlight is mid-flight, y=" + hl.y);
            tryVerify(() => Math.abs(hl.y - leaves[2].mapToItem(hl.parent, 0, 0).y) < 1, 3000);
        }
        function test_focus_ring_scale_animates() {
            if (AtlasStyle.reducedMotion) {
                skip("reduced motion");
            }
            const r = createTemporaryObject(ringComp, root);
            verify(r !== null);
            compare(r.ring.scale, 0.96);
            r.ring.shown = true;
            wait(40);
            verify(r.ring.scale > 0.96 && r.ring.scale < 1, "scale mid-flight: " + r.ring.scale);
            tryVerify(() => Math.abs(r.ring.scale - 1) < 0.002, 2000);
        }
    }

    TestCase {
        name: "SidebarWatch"
        when: windowShown

        function findHighlight(item) {
            for (const c of item.children) {
                if (c instanceof Rectangle && c.z === -1 && Qt.colorEqual(c.color, AtlasStyle.selection)) {
                    return c;
                }
                const f = findHighlight(c);
                if (f) {
                    return f;
                }
            }
            return null;
        }
        // A handler that ran without its scope logs a TypeError; any warning fails.
        function test_hiding_and_group_header_follow_without_warnings() {
            failOnWarning();
            const sb = createTemporaryObject(groupSidebarComp, root);
            verify(sb !== null);
            const hl = findHighlight(sb);
            verify(hl !== null);
            sb.one.selected = true;
            tryVerify(() => hl.visible && hl.height > 0);
            // Hiding the selected entry takes the highlight away.
            sb.one.visible = false;
            tryVerify(() => !hl.visible);
            sb.one.visible = true;
            tryVerify(() => hl.visible);
            // A group header selection moves it; so does hiding the group.
            sb.group._header.selected = true;
            sb.one.selected = false;
            tryVerify(() => hl.visible && Math.abs(hl.y - sb.group._header.mapToItem(hl.parent, 0, 0).y) < 1, 3000);
            sb.group.visible = false;
            tryVerify(() => !hl.visible);
            sb.group.visible = true;
            sb.group._header.selected = false;
            tryVerify(() => !hl.visible);
        }
        function test_compact_tooltip_has_badge_text() {
            const sb = createTemporaryObject(groupSidebarComp, root);
            verify(sb !== null);
            sb.compact = true;
            let tip = null;
            const find = it => { for (const c of (it.data || [])) { if (c && c.shown !== undefined && typeof c.text === "string" && c.text.indexOf("One") === 0) tip = c; find(c); } };
            find(sb.one);
            verify(tip !== null, "tooltip found");
            verify(tip.text.indexOf("3 unread") >= 0, tip.text);
        }
    }

    TestCase {
        name: "SidebarScrollBar"
        when: windowShown

        function column(sb) {
            let col = null;
            const find = it => { for (const c of it.children) { if (c instanceof ColumnLayout && c.barSpace !== undefined) col = c; else find(c); } };
            find(sb);
            return col;
        }
        function test_bar_space_follows_direction_and_compact() {
            failOnWarning();
            const sb = createTemporaryObject(tallSidebarComp, root);
            verify(sb !== null);
            const col = column(sb);
            verify(col !== null);
            tryVerify(() => col.barSpace > 0);
            // LTR: the bar is on the right, the column stays at the padding.
            compare(col.x, sb.padding);
            verify(col.x + col.width <= sb.width - col.barSpace);
            sb.rtl = true;
            tryVerify(() => Math.abs(col.x - (sb.padding + col.barSpace)) < 0.5, 2000, "x=" + col.x + "" + " bar=" + col.barSpace);
            sb.compact = true;
            tryVerify(() => col.barSpace === 0);
            compare(col.x, sb.padding);
        }
    }
}
