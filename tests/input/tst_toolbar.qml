import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import Atlas.Ui

// AtlasToolbar: orientation, Scroll overflow, focusOnClick, and actions that
// hold a menu or a popover in the overflow menu.
Item {
    id: root
    width: 500
    height: 500

    AtlasAction { id: a1; text: "One"; symbol: Symbols.Add }
    AtlasAction { id: a2; text: "Two"; symbol: Symbols.Add }
    AtlasAction { id: a3; text: "Three"; symbol: Symbols.Add }
    AtlasAction { id: a4; text: "Four"; symbol: Symbols.Add }
    AtlasAction { id: a5; text: "Five"; symbol: Symbols.Add }
    AtlasAction { id: a6; text: "Six"; symbol: Symbols.Add }
    AtlasAction {
        id: withMenu
        text: "Sub"
        symbol: Symbols.Add
        menu: ContextMenu {
            ContextMenuItem {
                text: "Inner"
            }
        }
    }
    AtlasAction {
        id: withPopover
        text: "Pop"
        symbol: Symbols.Add
        popover: AtlasPopover {
            QQC2.Label {
                text: "Details"
            }
        }
    }
    Component {
        id: barComp
        AtlasToolbar {
            x: 10
            y: 10
            actions: [a1, a2, a3, a4, a5, a6]
        }
    }

    TestCase {
        name: "AtlasToolbar"
        when: windowShown

        function buttons(item, out) {
            for (const c of item.children) {
                if (c instanceof ToolbarButton) {
                    out.push(c);
                }
                buttons(c, out);
            }
            return out;
        }
        function shown(bar) {
            return buttons(bar, []).filter(b => b.visible && b.action);
        }

        function test_vertical_stacks_top_to_bottom() {
            const bar = createTemporaryObject(barComp, root, {
                orientation: Qt.Vertical,
                width: 40,
                height: 400
            });
            const b = shown(bar);
            compare(b.length, 6);
            const p0 = b[0].mapToItem(bar, 0, 0);
            const p1 = b[1].mapToItem(bar, 0, 0);
            compare(p0.x, p1.x);
            verify(p1.y > p0.y);
        }

        function test_vertical_fits_by_height() {
            const bar = createTemporaryObject(barComp, root, {
                orientation: Qt.Vertical,
                width: 40,
                height: 120
            });
            verify(bar.overflowCount > 0);
            verify(bar.visibleCount < 6);
            bar.height = 400;
            compare(bar.overflowCount, 0);
        }

        function test_scroll_steps_one_button() {
            const bar = createTemporaryObject(barComp, root, {
                overflow: AtlasToolbar.Scroll,
                width: 160
            });
            verify(bar.scrolls);
            compare(bar.moreMenu.count, 0);
            verify(bar.overflowCount > 0);
            compare(bar._index, 0);
            mouseWheel(bar, 80, 16, 0, -120);
            compare(bar._index, 1);
            // A partial turn adds up with the next.
            mouseWheel(bar, 80, 16, 0, 60);
            compare(bar._index, 1);
            mouseWheel(bar, 80, 16, 0, 60);
            compare(bar._index, 0);
        }

        function test_scroll_follows_focus() {
            const bar = createTemporaryObject(barComp, root, {
                overflow: AtlasToolbar.Scroll,
                width: 160
            });
            const b = shown(bar);
            b[5].forceActiveFocus(Qt.TabFocusReason);
            compare(bar._index, bar._maxIndex);
            b[0].forceActiveFocus(Qt.TabFocusReason);
            compare(bar._index, 0);
        }

        function test_scroll_that_fits_does_not_scroll() {
            const bar = createTemporaryObject(barComp, root, {
                overflow: AtlasToolbar.Scroll,
                width: 400
            });
            verify(!bar.scrolls);
            compare(bar.overflowCount, 0);
        }

        function test_focus_on_click_passes_to_buttons() {
            const bar = createTemporaryObject(barComp, root, {
                focusOnClick: false
            });
            for (const b of shown(bar)) {
                compare(b.focusPolicy, Qt.TabFocus);
            }
        }

        function test_overflow_shows_a_menu_as_a_submenu_and_keeps_it() {
            const bar = createTemporaryObject(barComp, root, {
                actions: [a1, a2, withMenu, withPopover],
                width: 70
            });
            verify(bar.overflowCount >= 2);
            bar.moreMenu.popup(bar, 0, 30);
            tryVerify(() => bar.moreMenu.visible);
            let subs = 0;
            for (let i = 0; i < bar.moreMenu.count; ++i) {
                if (bar.moreMenu.itemAt(i).subMenu) {
                    ++subs;
                }
            }
            compare(subs, 1);
            bar.moreMenu.close();
            tryVerify(() => !bar.moreMenu.visible);
            // A rebuild never destroys the app's own menu.
            bar.width = 400;
            bar.width = 70;
            verify(withMenu.menu !== null);
            compare(withMenu.menu.title, "Sub");
        }

        function test_overflow_popover_opens_from_more() {
            const bar = createTemporaryObject(barComp, root, {
                actions: [a1, a2, withPopover],
                width: 70
            });
            let row = null;
            bar.moreMenu.popup(bar, 0, 30);
            tryVerify(() => bar.moreMenu.visible);
            for (let i = 0; i < bar.moreMenu.count; ++i) {
                if (bar.moreMenu.itemAt(i).text === "Pop") {
                    row = bar.moreMenu.itemAt(i);
                }
            }
            verify(row);
            row.triggered();
            tryVerify(() => withPopover.popover.visible);
            verify(bar._menuOpen);
            withPopover.popover.close();
        }

        function test_menu_button_open_marks_bar_active() {
            const bar = createTemporaryObject(barComp, root, {
                actions: [a1, withMenu],
                width: 300
            });
            verify(!bar._menuOpen);
            const b = shown(bar)[1];
            mouseClick(b);
            tryVerify(() => withMenu.menu.visible);
            verify(bar._menuOpen);
            withMenu.menu.close();
            tryVerify(() => !bar._menuOpen);
        }
    }
}
