import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import Telamon.Ui

Item {
    id: root
    width: 600
    height: 400

    ListModel {
        id: lm
        ListElement { name: "a"; cpu: 1 }
        ListElement { name: "b"; cpu: 2 }
        ListElement { name: "c"; cpu: 3 }
        ListElement { name: "d"; cpu: 4 }
        ListElement { name: "e"; cpu: 5 }
    }
    Component {
        id: table
        DataTable {
            anchors.fill: parent
            model: lm
            columns: [
                { title: "Name", role: "name", fill: true },
                { title: "CPU", role: "cpu", width: 5, align: Qt.AlignRight },
                { title: "Other", role: "cpu", width: 5, align: Qt.AlignRight }
            ]
        }
    }
    SignalSpy { id: menuSpy; signalName: "rowContextMenuRequested" }
    SignalSpy { id: resizeSpy; signalName: "columnResized" }

    TestCase {
        name: "DataTable"
        when: windowShown

        function make(props) {
            const t = createTemporaryObject(table, root, props || {});
            verify(t !== null);
            t.forceActiveFocus();
            tryVerify(() => t.count === 5);
            waitForRendering(t);
            return t;
        }
        // The middle of row i, in the table's coordinates.
        function rowY(t, i) {
            const top = t.padding + Math.round(Kirigami.Units.gridUnit * 1.8) + 1 + t.padding / 2;
            return top + (i + 0.5) * t.rowHeight;
        }

        function test_single_selection_follows_current() {
            const t = make();
            compare(t.selectedRows, []);
            keyClick(Qt.Key_Down);
            compare(t.selectedRows, [0]);
            keyClick(Qt.Key_Down);
            compare(t.selectedRows, [1]);
        }

        function test_no_selection_selects_nothing() {
            const t = make({ selectionMode: DataTable.NoSelection });
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            compare(t.selectedRows, []);
        }

        function test_multi_keyboard() {
            const t = make({ selectionMode: DataTable.MultiSelection });
            keyClick(Qt.Key_Down);
            compare(t.selectedRows, [0]);
            keyClick(Qt.Key_Down, Qt.ShiftModifier);
            keyClick(Qt.Key_Down, Qt.ShiftModifier);
            compare(t.selectedRows, [0, 1, 2]);
            keyClick(Qt.Key_Up, Qt.ShiftModifier);
            compare(t.selectedRows, [0, 1]);
            keyClick(Qt.Key_Down);
            compare(t.selectedRows, [2]);
            keyClick(Qt.Key_A, Qt.ControlModifier);
            compare(t.selectedRows, [0, 1, 2, 3, 4]);
            keyClick(Qt.Key_Space, Qt.ControlModifier);
            compare(t.selectedRows, [0, 1, 3, 4]);
        }

        function test_multi_mouse() {
            const t = make({ selectionMode: DataTable.MultiSelection });
            mouseClick(t, 100, rowY(t, 0));
            compare(t.selectedRows, [0]);
            mouseClick(t, 100, rowY(t, 2), Qt.LeftButton, Qt.ControlModifier);
            compare(t.selectedRows, [0, 2]);
            mouseClick(t, 100, rowY(t, 4), Qt.LeftButton, Qt.ShiftModifier);
            compare(t.selectedRows, [2, 3, 4]);
        }

        function test_right_click_selects_and_signals() {
            const t = make({ selectionMode: DataTable.MultiSelection });
            menuSpy.target = t;
            menuSpy.clear();
            mouseClick(t, 100, rowY(t, 1), Qt.RightButton);
            compare(t.selectedRows, [1]);
            compare(menuSpy.count, 1);
            compare(menuSpy.signalArguments[0][0], 1);
            keyClick(Qt.Key_Menu);
            compare(menuSpy.count, 2);
        }

        function test_select_rows_and_prune() {
            const t = make({ selectionMode: DataTable.MultiSelection });
            t.selectRows([1, 4, 9]);
            compare(t.selectedRows, [1, 4]);
            lm.remove(4);
            tryCompare(t, "selectedRows", [1]);
            lm.append({ name: "e", cpu: 5 });
        }

        function test_hidden_columns_keep_one() {
            const t = make({ hiddenColumns: [0, 1, 2] });
            compare(t.widths[0] > 0, true);
            compare(t.widths[1], 0);
            const u = make({ hiddenColumns: [1] });
            compare(u.widths[1], 0);
            verify(u.widths[2] > 0);
        }

        function test_column_widths_and_resize() {
            const t = make({ resizableColumns: true });
            resizeSpy.target = t;
            resizeSpy.clear();
            const before = t.widths[1];
            // The boundary after the fill column moves the next column.
            const x = t.width - t.padding - t.widths[1] - t.widths[2] - 4;
            mousePress(t, x, 14);
            mouseMove(t, x - 40, 14, 0, Qt.LeftButton);
            mouseRelease(t, x - 40, 14);
            verify(resizeSpy.count > 0);
            compare(t.widths[1], before + 40);
            compare(t.columnWidths.length, 3);
            t.columnWidths = [0, 100, 100];
            compare(t.widths[1], 100);
        }

        function test_columns_menu_hides_and_keeps_one() {
            const t = make({ columnsMenu: true });
            mouseClick(t, 100, 14, Qt.RightButton);
            tryVerify(() => t._columnsMenu && t._columnsMenu.opened);
            compare(t._columnsMenu.count, 3);
            t._columnsMenu.itemAt(1).triggered();
            compare(t.hiddenColumns, [1]);
            t._columnsMenu.itemAt(2).triggered();
            compare(t.hiddenColumns, [1, 2]);
            // The last visible column stays.
            t._toggleColumn(0);
            compare(t.hiddenColumns, [1, 2]);
            t._columnsMenu.close();
        }

        function test_double_click_fits_column() {
            const t = make({ resizableColumns: true });
            const before = t.widths[1];
            const x = t.width - t.padding - t.widths[1] - t.widths[2] - 4;
            mouseDoubleClickSequence(t, x, 14);
            verify(t.widths[1] < before);
            verify(t.widths[1] >= t._minColumnWidth);
        }

        function test_compact_density_shrinks_rows() {
            const t = make();
            const normal = t.rowHeight;
            t.density = TelamonStyle.Compact;
            verify(t.rowHeight < normal);
        }
    }
}
