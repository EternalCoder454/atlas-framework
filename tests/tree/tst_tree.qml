import QtQuick
import QtTest
import Atlas.Ui

Item {
    id: stage
    width: 400
    height: 400

    AtlasTreeModel {
        id: tree
        items: [
            { text: "Alpha", children: [{ text: "Apple" }, { text: "Avocado", children: [{ text: "Hass" }] }] },
            { text: "Beta" },
            { text: "Gamma", children: [{ text: "Grape" }] }
        ]
    }

    Component {
        id: viewC
        AtlasTreeView {
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
            view.selectionMode = AtlasTreeView.MultiSelection;
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
    }
}
