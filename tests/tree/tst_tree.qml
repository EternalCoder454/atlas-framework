import QtQuick
import QtTest
import Telamon.Ui

Item {
    id: stage
    width: 400
    height: 400

    TelamonTreeModel {
        id: tree
        items: [
            { text: "Alpha", children: [{ text: "Apple" }, { text: "Avocado", children: [{ text: "Hass" }] }] },
            { text: "Beta" },
            { text: "Gamma", children: [{ text: "Grape" }] }
        ]
    }

    Component {
        id: viewC
        TelamonTreeView {
            anchors.fill: parent
            model: tree
        }
    }

    Component {
        id: spyC
        SignalSpy {}
    }

    TestCase {
        name: "Tree"
        when: windowShown

        property var view

        function init() {
            view = createTemporaryObject(viewC, stage);
            verify(view);
            waitForRendering(view);
            view.forceActiveFocus();
        }

        function row() {
            return view.selectionModel.currentIndex.row;
        }
        function name() {
            return tree.data(view.currentIndex, Qt.DisplayRole);
        }

        function test_model() {
            compare(tree.rowCount(), 3);
            compare(tree.rowCount(tree.index(0, 0)), 2);
            compare(tree.data(tree.index(0, 0, tree.index(0, 0)), Qt.DisplayRole), "Apple");
            verify(!tree.parent(tree.index(1, 0)).valid);
            compare(tree.parent(tree.index(0, 0, tree.index(0, 0))).row, 0);
            // Not objects, and a bad index, make no rows or crashes.
            tree.items = [1, "x", { text: "ok" }];
            compare(tree.rowCount(), 1);
            verify(!tree.index(5, 0).valid);
            compare(tree.data(tree.index(9, 0), Qt.DisplayRole), undefined);
            tree.items = [{ text: "Alpha", children: [{ text: "Apple" }, { text: "Avocado", children: [{ text: "Hass" }] }] }, { text: "Beta" }, { text: "Gamma", children: [{ text: "Grape" }] }];
        }

        function test_expand_collapse_keys() {
            compare(view.count, 3);
            // Focus made the first row current.
            compare(name(), "Alpha");
            keyClick(Qt.Key_Right);
            tryCompare(view, "count", 5);
            compare(name(), "Alpha");
            keyClick(Qt.Key_Right); // enters the first child
            compare(name(), "Apple");
            keyClick(Qt.Key_Left); // back to the parent
            compare(name(), "Alpha");
            keyClick(Qt.Key_Left); // collapses
            tryCompare(view, "count", 3);
        }

        function test_home_end_typeahead() {
            keyClick(Qt.Key_End);
            compare(name(), "Gamma");
            keyClick(Qt.Key_Home);
            compare(name(), "Alpha");
            keyClick(Qt.Key_G);
            compare(name(), "Gamma");
            wait(600);
            keyClick(Qt.Key_B);
            compare(name(), "Beta");
        }

        function test_signals() {
            const act = createTemporaryObject(spyC, stage, { target: view, signalName: "activated" });
            const ctx = createTemporaryObject(spyC, stage, { target: view, signalName: "contextMenuRequested" });
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(act.count, 1);
            keyClick(Qt.Key_Menu);
            compare(ctx.count, 1);
            keyClick(Qt.Key_F10, Qt.ShiftModifier);
            compare(ctx.count, 2);
        }

        function test_multi() {
            view.selectionMode = TelamonTreeView.MultiSelection;
            keyClick(Qt.Key_Down, Qt.ShiftModifier);
            keyClick(Qt.Key_Down, Qt.ShiftModifier);
            verify(view.selectionModel.isSelected(tree.index(0, 0)));
            verify(view.selectionModel.isSelected(tree.index(1, 0)));
            verify(view.selectionModel.isSelected(tree.index(2, 0)));
            keyClick(Qt.Key_Up);
            verify(!view.selectionModel.isSelected(tree.index(2, 0)));
        }

        function test_single() {
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            verify(view.selectionModel.isSelected(tree.index(2, 0)));
            verify(!view.selectionModel.isSelected(tree.index(1, 0)));
            keyClick(Qt.Key_Up);
            verify(view.selectionModel.isSelected(tree.index(1, 0)));
            verify(!view.selectionModel.isSelected(tree.index(0, 0)));
        }

        function test_enum_values() {
            compare(TelamonTreeView.SingleSelection, 0);
            compare(TelamonTreeView.MultiSelection, 1);
            compare(TelamonTreeView.NoSelection, 2);
        }

        function test_no_selection() {
            view.selectionMode = TelamonTreeView.NoSelection;
            keyClick(Qt.Key_Down);
            compare(name(), "Beta");
            keyClick(Qt.Key_Space);
            keyClick(Qt.Key_Down);
            compare(name(), "Gamma");
            verify(!view.selectionModel.hasSelection);
            view.selectAll();
            verify(!view.selectionModel.hasSelection);
        }

        function test_select_all_and_clear() {
            view.selectionMode = TelamonTreeView.MultiSelection;
            view.selectAll();
            compare(view.selectionModel.selectedIndexes.length, 3);
            view.clearSelection();
            verify(!view.selectionModel.hasSelection);
            keyClick(Qt.Key_A, Qt.ControlModifier);
            compare(view.selectionModel.selectedIndexes.length, 3);
            view.clearSelection();
            // In single mode selectAll does nothing.
            view.selectionMode = TelamonTreeView.SingleSelection;
            view.selectAll();
            verify(!view.selectionModel.hasSelection);
        }

        function test_range_across_levels_in_one_selection() {
            view.selectionMode = TelamonTreeView.MultiSelection;
            view.expandAll();
            tryCompare(view, "count", 7);
            keyClick(Qt.Key_End);
            keyClick(Qt.Key_Home, Qt.ShiftModifier);
            compare(view.selectionModel.selectedIndexes.length, 7);
            keyClick(Qt.Key_Down, Qt.ControlModifier);
        }

        function test_collapse_moves_hidden_current_to_ancestor() {
            view.expandAll();
            tryCompare(view, "count", 7);
            keyClick(Qt.Key_Down); // Apple
            keyClick(Qt.Key_Down); // Avocado
            keyClick(Qt.Key_Down); // Hass
            compare(name(), "Hass");
            view.collapse(tree.index(0, 0));
            tryCompare(view, "count", 4);
            compare(name(), "Alpha");
            verify(view.selectionModel.isSelected(tree.index(0, 0)));
            // collapseAll from a nested row.
            view.expandAll();
            tryCompare(view, "count", 7);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            view.collapseAll();
            tryCompare(view, "count", 3);
            compare(name(), "Alpha");
        }

        function test_anchor_resets_on_items_change() {
            view.selectionMode = TelamonTreeView.MultiSelection;
            keyClick(Qt.Key_End);
            keyClick(Qt.Key_Up, Qt.ShiftModifier);
            tree.items = [{ text: "One" }, { text: "Two" }, { text: "Three" }];
            wait(50);
            view.forceActiveFocus();
            keyClick(Qt.Key_Home);
            keyClick(Qt.Key_Down, Qt.ShiftModifier);
            compare(view.selectionModel.selectedIndexes.length, 2);
            tree.items = [{ text: "Alpha", children: [{ text: "Apple" }, { text: "Avocado", children: [{ text: "Hass" }] }] }, { text: "Beta" }, { text: "Gamma", children: [{ text: "Grape" }] }];
        }

        function test_rtl_chevron_on_the_right() {
            const rtl = createTemporaryObject(viewC, stage, { "LayoutMirroring.enabled": true });
            verify(rtl);
            waitForRendering(rtl);
            rtl.forceActiveFocus();
            rtl.expandAll();
            tryCompare(rtl, "count", 7);
            const table = rtl.contentItem;
            const top = table.itemAtCell(Qt.point(0, 0));
            const child = table.itemAtCell(Qt.point(0, 1));
            verify(top && child);
            const c0 = findChild(top, "chevron");
            const c1 = findChild(child, "chevron");
            verify(c0 && c1);
            // On the right of the row, and the child indented further left.
            verify(c0.x + c0.width > top.width / 2);
            verify(c1.x + c1.width < c0.x + c0.width);
            // The LTR view has them on the left, the child further right.
            const ltr = view.contentItem.itemAtCell(Qt.point(0, 0));
            verify(findChild(ltr, "chevron").x < ltr.width / 2);
        }
    }
}
