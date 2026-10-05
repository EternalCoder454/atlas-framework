import QtQuick
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
}
