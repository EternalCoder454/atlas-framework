import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Templates as T
import QtTest
import org.kde.kirigami as Kirigami
import Telamon.Ui

// ContextMenu's keyboard: Up and Down skip separators, disabled and hidden
// rows and wrap at the ends, Home and End jump, Enter and Space activate, Escape
// closes, Right opens a submenu and Left closes it (mirrored in a right-to-left
// layout), and a row that holds the keyboard (an icon row, a custom delegate)
// never keeps the arrow keys from the menu.
Item {
    id: root
    width: 600
    height: 400

    property var fired: []

    // A row of icon buttons like Telamon Files' IconRowItem: one row of the
    // menu that takes Left, Right, Enter and Space itself and lets the rest go.
    Component {
        id: iconRowComp
        T.MenuItem {
            id: row
            property int current: -1
            property var presses: []
            implicitWidth: 160
            implicitHeight: 40
            padding: 0
            onHighlightedChanged: current = highlighted ? 0 : -1
            Keys.onPressed: event => {
                event.accepted = false;
                if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                    row.current = Math.max(0, Math.min(2, row.current + (event.key === Qt.Key_Right ? 1 : -1)));
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
                    row.presses.push(row.current);
                    event.accepted = true;
                }
            }
            background: Item {}
            contentItem: Item {}
        }
    }

    Component {
        id: menuComp
        ContextMenu {
            id: menu
            // 0
            ContextMenuItem {
                text: "Open"
                onTriggered: root.fired.push("Open")
            }
            // 1
            ContextMenuItem {
                text: "Off"
                enabled: false
                onTriggered: root.fired.push("Off")
            }
            // 2
            ContextMenuSeparator {}
            // 3
            ContextMenuItem {
                text: "Copy"
                onTriggered: root.fired.push("Copy")
            }
            // 4
            ContextMenuItem {
                text: "Gone"
                visible: false
                onTriggered: root.fired.push("Gone")
            }
            // 5
            ContextMenuSeparator {}
            // 6
            ContextMenuItem {
                text: "Delete"
                onTriggered: root.fired.push("Delete")
            }
        }
    }

    Component {
        id: subMenuComp
        ContextMenu {
            id: menu
            ContextMenuItem {
                text: "First"
                onTriggered: root.fired.push("First")
            }
            ContextMenu {
                id: sub
                title: "More"
                ContextMenuItem {
                    text: "Inner"
                    onTriggered: root.fired.push("Inner")
                }
                ContextMenuItem {
                    text: "Inner two"
                }
            }
            ContextMenuItem {
                text: "Last"
                onTriggered: root.fired.push("Last")
            }
        }
    }

    Component {
        id: longMenuComp
        ContextMenu {
            Repeater {
                model: 40
                delegate: ContextMenuItem {
                    required property int index
                    text: "Row " + index
                }
            }
        }
    }

    // The same, shown in a right-to-left layout (see mirrorOverlay).
    Component {
        id: mirroredComp
        ContextMenu {
            ContextMenuItem {
                text: "First"
            }
            ContextMenu {
                title: "More"
                ContextMenuItem {
                    text: "Inner"
                }
                ContextMenuItem {
                    text: "Inner two"
                }
            }
        }
    }

    // Two plain rows; the test puts the icon row between them.
    Component {
        id: withRowComp
        ContextMenu {
            ContextMenuItem {
                text: "Before"
            }
            ContextMenuItem {
                text: "After"
            }
        }
    }

    TestCase {
        name: "ContextMenuKeys"
        when: windowShown

        function openMenu(comp, props) {
            root.fired = [];
            // The pointer far from the menu: a row it hovers would be the current one.
            mouseMove(root, 590, 390);
            const m = createTemporaryObject(comp ?? menuComp, root, props ?? {});
            verify(m);
            m.popup(root, 20, 20);
            tryVerify(() => m.opened);
            return m;
        }
        // An RTL app mirrors the window's overlay, where popups live (Qt does not).
        function mirrorOverlay(on) {
            QQC2.Overlay.overlay.LayoutMirroring.enabled = on;
            QQC2.Overlay.overlay.LayoutMirroring.childrenInherit = on;
        }
        function cleanup() {
            mirrorOverlay(false);
        }
        function idx(m) {
            return m.currentIndex;
        }

        function test_down_skips_separators_disabled_and_hidden_and_wraps() {
            const m = openMenu();
            keyClick(Qt.Key_Down);
            compare(idx(m), 0);
            keyClick(Qt.Key_Down);
            compare(idx(m), 3, "Off (disabled) and the separator are passed");
            keyClick(Qt.Key_Down);
            compare(idx(m), 6, "Gone (hidden) and the separator are passed");
            keyClick(Qt.Key_Down);
            compare(idx(m), 0, "wraps to the first");
            verify(m.itemAt(0).highlighted);
            verify(!m.itemAt(6).highlighted);
            m.close();
        }

        function test_up_skips_and_wraps() {
            const m = openMenu();
            keyClick(Qt.Key_Up);
            compare(idx(m), 6, "Up from nothing: the last usable row");
            keyClick(Qt.Key_Up);
            compare(idx(m), 3);
            keyClick(Qt.Key_Up);
            compare(idx(m), 0);
            keyClick(Qt.Key_Up);
            compare(idx(m), 6, "wraps to the last");
            m.close();
        }

        function test_one_key_moves_the_menu_and_its_list_by_one_row() {
            const m = openMenu();
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            compare(idx(m), 3);
            compare(m.contentItem.currentIndex, 3, "the list follows the menu");
            m.close();
        }

        function test_home_and_end() {
            const m = openMenu();
            keyClick(Qt.Key_End);
            compare(idx(m), 6);
            keyClick(Qt.Key_Home);
            compare(idx(m), 0);
            keyClick(Qt.Key_Down);
            compare(idx(m), 3);
            keyClick(Qt.Key_End);
            compare(idx(m), 6);
            m.close();
        }

        function test_home_and_end_pass_over_unusable_rows() {
            const m = openMenu();
            m.itemAt(0).enabled = false;
            m.itemAt(6).enabled = false;
            keyClick(Qt.Key_Home);
            compare(idx(m), 3, "the first usable row");
            keyClick(Qt.Key_End);
            compare(idx(m), 3, "the last usable row");
            m.close();
        }

        function test_enter_activates_and_closes() {
            const m = openMenu();
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(root.fired, ["Copy"]);
            tryVerify(() => !m.visible);
        }

        function test_numpad_enter_activates() {
            const m = openMenu();
            keyClick(Qt.Key_End);
            keyClick(Qt.Key_Enter);
            compare(root.fired, ["Delete"]);
            tryVerify(() => !m.visible);
        }

        function test_space_activates_and_closes() {
            const m = openMenu();
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Space);
            compare(root.fired, ["Open"]);
            tryVerify(() => !m.visible);
        }

        function test_enter_with_no_row_chosen_does_nothing() {
            const m = openMenu();
            keyClick(Qt.Key_Return);
            compare(root.fired, []);
            verify(m.visible);
            m.close();
        }

        function test_a_disabled_row_is_never_activated() {
            const m = openMenu();
            m.itemAt(1).forceActiveFocus();
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(root.fired, []);
            m.close();
        }

        function test_escape_closes() {
            const m = openMenu();
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !m.visible);
            compare(root.fired, []);
        }

        function test_highlight_follows_the_keyboard_and_the_row_has_the_focus() {
            const m = openMenu();
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            verify(m.itemAt(3).highlighted);
            verify(!m.itemAt(0).highlighted);
            m.close();
        }

        function test_every_key_still_works_after_the_pointer_moved_the_row() {
            const m = openMenu();
            const r = m.itemAt(3);
            mouseMove(r, r.width / 2, r.height / 2);
            tryCompare(r, "hovered", true);
            keyClick(Qt.Key_Down);
            compare(idx(m), 6, "the key continues from the hovered row");
            keyClick(Qt.Key_Up);
            compare(idx(m), 3);
            m.close();
        }

        function test_enter_and_space_choose_the_row_the_pointer_is_on() {
            const m = openMenu();
            const r = m.itemAt(3);
            mouseMove(r, r.width / 2, r.height / 2);
            tryCompare(r, "hovered", true);
            keyClick(Qt.Key_Return);
            compare(root.fired, ["Copy"]);
            tryVerify(() => !m.visible);
            const m2 = openMenu();
            const r2 = m2.itemAt(6);
            mouseMove(r2, r2.width / 2, r2.height / 2);
            tryCompare(r2, "hovered", true);
            keyClick(Qt.Key_Space);
            compare(root.fired, ["Delete"]);
            tryVerify(() => !m2.visible);
        }

        function test_a_long_menu_keeps_the_current_row_in_view() {
            const m = openMenu(longMenuComp);
            const list = m.contentItem;
            verify(list.contentHeight > list.height, "the menu scrolls");
            keyClick(Qt.Key_End);
            compare(idx(m), 39);
            const last = m.itemAt(39);
            verify(last.y + last.height <= list.contentY + list.height + 1, "the last row is in view");
            keyClick(Qt.Key_Down);
            compare(idx(m), 0, "wraps");
            tryCompare(list, "contentY", 0);
            keyClick(Qt.Key_Up);
            compare(idx(m), 39);
            verify(last.y + last.height <= list.contentY + list.height + 1);
            m.close();
        }

        function test_all_rows_unusable_keys_do_nothing_and_do_not_loop() {
            const m = openMenu();
            for (const i of [0, 3, 6]) {
                m.itemAt(i).enabled = false;
            }
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Home);
            keyClick(Qt.Key_End);
            compare(idx(m), -1);
            verify(m.visible);
            m.close();
        }

        function test_right_opens_the_submenu_and_left_closes_it() {
            const m = openMenu(subMenuComp);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            compare(idx(m), 1);
            const sub = m.menuAt(1);
            verify(sub);
            verify(!sub.visible);
            keyClick(Qt.Key_Right);
            tryVerify(() => sub.visible);
            compare(sub.currentIndex, 0, "the first row of the submenu is current");
            keyClick(Qt.Key_Down);
            compare(sub.currentIndex, 1);
            keyClick(Qt.Key_Down);
            compare(sub.currentIndex, 0, "the submenu wraps by itself");
            keyClick(Qt.Key_Left);
            tryVerify(() => !sub.visible);
            verify(m.visible, "Left closes the submenu, not the menu");
            compare(idx(m), 1);
            keyClick(Qt.Key_Down);
            compare(idx(m), 2, "the menu goes on");
            m.close();
        }

        function test_enter_on_a_submenu_row_opens_it() {
            const m = openMenu(subMenuComp);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            const sub = m.menuAt(1);
            keyClick(Qt.Key_Return);
            tryVerify(() => sub.visible);
            keyClick(Qt.Key_Return);
            compare(root.fired, ["Inner"]);
            tryVerify(() => !m.visible && !sub.visible);
        }

        function test_left_in_the_top_menu_leaves_it_open() {
            const m = openMenu(subMenuComp);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Left);
            verify(m.visible);
            compare(idx(m), 0);
            m.close();
        }

        function test_escape_in_a_submenu_closes_it_and_a_second_one_the_menu() {
            const m = openMenu(subMenuComp);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            const sub = m.menuAt(1);
            keyClick(Qt.Key_Right);
            tryVerify(() => sub.visible);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !sub.visible);
            verify(m.visible, "the first Escape closes the submenu only");
            keyClick(Qt.Key_Escape);
            tryVerify(() => !m.visible);
        }

        function test_mirrored_left_opens_the_submenu_and_right_closes_it() {
            mirrorOverlay(true);
            const m = openMenu(mirroredComp);
            verify(m.mirrored);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            const sub = m.menuAt(1);
            keyClick(Qt.Key_Right);
            wait(100);
            verify(!sub.visible, "Right does not open it in a right-to-left layout");
            keyClick(Qt.Key_Left);
            tryVerify(() => sub.visible);
            keyClick(Qt.Key_Left);
            wait(100);
            verify(sub.visible, "Left does not close it either");
            keyClick(Qt.Key_Right);
            tryVerify(() => !sub.visible);
            verify(m.visible);
            m.close();
        }

        // The rows that hold the keyboard.
        function makeWithRow() {
            const m = createTemporaryObject(withRowComp, root);
            const row = iconRowComp.createObject(m.contentItem);
            m.insertItem(1, row);
            m.popup(root, 20, 20);
            tryVerify(() => m.opened);
            return {
                menu: m,
                row: row
            };
        }

        function test_an_icon_row_takes_its_own_keys_and_gives_up_the_arrows() {
            const r = makeWithRow();
            const m = r.menu;
            const row = r.row;
            root.fired = [];
            keyClick(Qt.Key_Down);
            compare(idx(m), 0);
            keyClick(Qt.Key_Down);
            compare(idx(m), 1, "the icon row is a row of the menu");
            verify(row.activeFocus, "it holds the keyboard");
            keyClick(Qt.Key_Right);
            compare(row.current, 1, "Right is the row's");
            keyClick(Qt.Key_Right);
            compare(row.current, 2);
            keyClick(Qt.Key_Left);
            compare(row.current, 1);
            keyClick(Qt.Key_Space);
            compare(row.presses, [1], "so are Enter and Space");
            compare(idx(m), 1);
            keyClick(Qt.Key_Down);
            compare(idx(m), 2, "Down leaves the row");
            verify(!row.highlighted);
            keyClick(Qt.Key_Up);
            compare(idx(m), 1, "Up comes back");
            keyClick(Qt.Key_Up);
            compare(idx(m), 0, "and goes on");
            keyClick(Qt.Key_Up);
            compare(idx(m), 2, "and wraps");
            keyClick(Qt.Key_Home);
            compare(idx(m), 0);
            keyClick(Qt.Key_End);
            compare(idx(m), 2);
            m.close();
        }

        function test_escape_closes_from_the_icon_row() {
            const r = makeWithRow();
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            verify(r.row.activeFocus);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !r.menu.visible);
        }

        function test_an_app_that_turned_the_lists_navigation_off_still_works() {
            // Telamon Files did, before the menu got it right
            // (`contentItem.keyNavigationEnabled = false`).
            const m = openMenu();
            m.contentItem.keyNavigationEnabled = false;
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            compare(idx(m), 3);
            keyClick(Qt.Key_End);
            compare(idx(m), 6);
            keyClick(Qt.Key_Return);
            compare(root.fired, ["Delete"]);
            tryVerify(() => !m.visible);
        }

        function test_a_menu_of_a_model_driven_delegate() {
            // Rows made from `delegate` (a Menu fed by a model) are rows too.
            const m = createTemporaryObject(modelMenuComp, root);
            m.popup(root, 20, 20);
            tryVerify(() => m.opened);
            keyClick(Qt.Key_Down);
            compare(idx(m), 0);
            keyClick(Qt.Key_Up);
            compare(idx(m), 2);
            keyClick(Qt.Key_Return);
            compare(root.fired, ["c"]);
        }
    }

    Component {
        id: modelMenuComp
        ContextMenu {
            Instantiator {
                model: ["a", "b", "c"]
                delegate: ContextMenuItem {
                    required property string modelData
                    text: modelData
                    onTriggered: root.fired.push(modelData)
                }
                onObjectAdded: (i, o) => insertItem(i, o)
                onObjectRemoved: (i, o) => removeItem(o)
            }
        }
    }
}
