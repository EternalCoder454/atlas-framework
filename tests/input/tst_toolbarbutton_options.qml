import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import Atlas.Ui

// ToolbarButton: round, tipSide, toolTipText, focusOnClick, and actions that
// open a menu or a popover instead of triggering.
Item {
    id: root
    width: 400
    height: 200

    AtlasAction {
        id: plain
        text: "Bold"
        property int count: 0
        onTriggered: count++
    }
    AtlasAction {
        id: withMenu
        text: "More"
        property int count: 0
        onTriggered: count++
        menu: ContextMenu {
            ContextMenuItem {
                text: "One"
            }
        }
    }
    AtlasAction {
        id: withPopover
        text: "Info"
        property int count: 0
        onTriggered: count++
        popover: AtlasPopover {
            QQC2.Label {
                text: "Details"
            }
        }
    }
    Component {
        id: buttonComp
        ToolbarButton {
            x: 100
            y: 50
            symbol: Symbols.Add
        }
    }

    TestCase {
        name: "ToolbarButtonOptions"
        when: windowShown

        function test_round_is_a_circle() {
            const b = createTemporaryObject(buttonComp, root, {
                round: true
            });
            compare(b.width, b.height);
            compare(b.background.radius, b.height / 2);
            const r = createTemporaryObject(buttonComp, root);
            verify(r.background.radius < r.height / 2);
        }

        function test_tool_tip_text_does_not_change_the_spoken_name() {
            const b = createTemporaryObject(buttonComp, root, {
                text: "Bold",
                shortcutText: "Ctrl+B",
                toolTipText: "Make the text bold"
            });
            b._ensureTip();
            compare(b._tip.text, "Make the text bold (Ctrl+B)");
            compare(b.Accessible.name, "Bold");
        }

        function test_focus_on_click_false_is_a_tab_stop_only() {
            const b = createTemporaryObject(buttonComp, root, {
                focusable: true,
                focusOnClick: false
            });
            compare(b.focusPolicy, Qt.TabFocus);
            b.focusOnClick = true;
            compare(b.focusPolicy, Qt.StrongFocus);
            b.focusable = false;
            compare(b.focusPolicy, Qt.NoFocus);
        }

        function test_tip_beside_makes_a_tooltip() {
            const b = createTemporaryObject(buttonComp, root, {
                text: "Bold",
                tipSide: ToolbarButton.End
            });
            verify(b._tip !== null);
            const c = createTemporaryObject(buttonComp, root, {
                text: "Bold"
            });
            verify(c._tip === null, "a tip below is made when first wanted");
            mouseMove(c, c.width / 2, c.height / 2);
            tryVerify(() => c._tip !== null);
        }

        function test_plain_action_triggers() {
            const b = createTemporaryObject(buttonComp, root, {
                action: plain
            });
            mouseClick(b);
            compare(plain.count, 1);
            compare(b.Accessible.role, Accessible.Button);
        }

        function test_menu_action_opens_and_never_triggers() {
            const b = createTemporaryObject(buttonComp, root, {
                action: withMenu
            });
            compare(b.Accessible.role, Accessible.ButtonMenu);
            verify(b.action === withMenu);
            mouseClick(b);
            tryVerify(() => withMenu.menu.visible);
            verify(b.checked);
            compare(withMenu.count, 0);
            withMenu.menu.close();
            tryVerify(() => !b.checked);
        }

        function test_popover_action_opens_with_the_button_as_target() {
            const b = createTemporaryObject(buttonComp, root, {
                action: withPopover
            });
            verify(b.action === withPopover);
            mouseClick(b);
            tryVerify(() => withPopover.popover.visible);
            compare(withPopover.popover.target, b);
            compare(withPopover.count, 0);
            withPopover.popover.close();
        }

        function test_a_one_letter_glyphless_button_draws_its_letter() {
            const b = createTemporaryObject(buttonComp, root, {
                symbol: 0,
                text: "B",
                _letterFallback: true
            });
            let letter = null;
            const walk = item => {
                for (const c of item.children) {
                    if (c.text === "B" && c.textFormat === Text.PlainText) {
                        letter = c;
                    }
                    walk(c);
                }
            };
            walk(b.contentItem);
            verify(letter, "the label item is made");
            verify(letter.visible, "a one-letter text is drawn, not left blank");
            const plainIcon = createTemporaryObject(buttonComp, root, {
                text: "B"
            });
            letter = null;
            walk(plainIcon.contentItem);
            verify(letter === null || !letter.visible, "an icon-only button with a symbol stays icon-only");
        }

        function test_round_implicit_width_follows_implicit_height() {
            const b = createTemporaryObject(buttonComp, root, {
                round: true
            });
            compare(b.implicitWidth, b.implicitHeight);
        }

        function test_click_while_the_menu_is_open_closes_it_and_it_stays_closed() {
            const b = createTemporaryObject(buttonComp, root, {
                action: withMenu
            });
            mouseClick(b);
            tryVerify(() => withMenu.menu.visible);
            mouseClick(b);
            tryVerify(() => !withMenu.menu.visible);
            wait(300);
            verify(!withMenu.menu.visible);
            verify(!b._opened);
        }

        function test_click_focuses_an_opener() {
            const b = createTemporaryObject(buttonComp, root, {
                action: withMenu,
                focusable: true,
                focusOnClick: true
            });
            verify(!b.activeFocus);
            mouseClick(b);
            tryVerify(() => withMenu.menu.visible);
            verify(b._hadFocus);
            withMenu.menu.close();
            tryVerify(() => b.activeFocus);
        }

        function test_a_key_after_a_press_that_was_dragged_off_opens() {
            const b = createTemporaryObject(buttonComp, root, {
                action: withMenu,
                focusable: true
            });
            // A press that found it open, released elsewhere: no click.
            b._wasOpen = true;
            b.forceActiveFocus();
            keyClick(Qt.Key_Space);
            tryVerify(() => withMenu.menu.visible);
            withMenu.menu.close();
        }
    }
}
