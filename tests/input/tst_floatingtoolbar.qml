import QtQuick
import QtTest
import Atlas.Ui

// AtlasFloatingToolbar: shape, dimming, Escape and the focus.
Item {
    id: root
    width: 600
    height: 400
    property int appEscapes: 0
    Keys.onEscapePressed: appEscapes++

    AtlasAction { id: a1; text: "One"; symbol: Symbols.Add }
    AtlasAction { id: a2; text: "Two"; symbol: Symbols.Add }
    AtlasAction { id: a3; text: "Three"; symbol: Symbols.Add }
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
    Item {
        id: editor
        focus: true
        activeFocusOnTab: true
        width: 10
        height: 10
    }
    Item {
        id: elsewhere
        activeFocusOnTab: true
        width: 10
        height: 10
    }
    Component {
        id: barComp
        AtlasFloatingToolbar {
            x: 250
            y: 150
            actions: [a1, a2, a3]
        }
    }

    TestCase {
        name: "AtlasFloatingToolbar"
        when: windowShown

        function find(item, action) {
            for (const c of item.children) {
                if (c instanceof ToolbarButton && c.action === action) {
                    return c;
                }
                const r = find(c, action);
                if (r) {
                    return r;
                }
            }
            return null;
        }

        function test_defaults_are_notepads() {
            const b = createTemporaryObject(barComp, root);
            compare(b.dimOpacity, 0.35);
            compare(b.nearDistance, 80);
            verify(!b.autoDim);
            compare(b.opacity, 1);
        }

        function test_vertical_is_a_tall_capsule() {
            const b = createTemporaryObject(barComp, root, {
                orientation: Qt.Vertical
            });
            verify(b.height > b.width);
            const h = createTemporaryObject(barComp, root);
            verify(h.width > h.height);
        }

        function test_auto_dim_follows_the_pointer() {
            const b = createTemporaryObject(barComp, root, {
                autoDim: true
            });
            mouseMove(root, 5, 5);
            tryCompare(b, "opacity", 0.35);
            verify(!b.near);
            mouseMove(root, b.x + b.width / 2, b.y + b.height + 40);
            tryCompare(b, "opacity", 1);
            verify(b.near);
            mouseMove(root, 5, 395);
            tryCompare(b, "opacity", 0.35);
        }

        function test_keep_active_holds_full_strength() {
            const b = createTemporaryObject(barComp, root, {
                autoDim: true,
                keepActive: true
            });
            mouseMove(root, 5, 5);
            wait(50);
            compare(b.opacity, 1);
            b.keepActive = false;
            tryCompare(b, "opacity", 0.35);
        }

        function test_an_open_menu_holds_full_strength() {
            const b = createTemporaryObject(barComp, root, {
                autoDim: true,
                actions: [a1, withMenu]
            });
            mouseMove(root, 5, 5);
            tryCompare(b, "opacity", 0.35);
            const btn = find(b, withMenu);
            verify(btn);
            mouseClick(btn);
            tryVerify(() => withMenu.menu.visible);
            // The pointer is far away, yet the capsule stays at full strength.
            mouseMove(root, 5, 5);
            tryCompare(b, "opacity", 1);
            withMenu.menu.close();
            tryCompare(b, "opacity", 0.35);
        }

        function test_escape_returns_the_focus() {
            const b = createTemporaryObject(barComp, root, {
                focusable: true
            });
            let escaped = 0;
            b.escaped.connect(() => ++escaped);
            editor.forceActiveFocus();
            compare(editor.activeFocus, true);
            // Into the strip, then Escape.
            const first = find(b, a1);
            first.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => first.activeFocus);
            keyClick(Qt.Key_Escape);
            compare(escaped, 1);
            tryVerify(() => editor.activeFocus);
        }

        function test_escape_goes_to_return_focus() {
            const b = createTemporaryObject(barComp, root, {
                focusable: true,
                returnFocus: elsewhere
            });
            editor.forceActiveFocus();
            const first = find(b, a1);
            first.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => first.activeFocus);
            keyClick(Qt.Key_Escape);
            tryVerify(() => elsewhere.activeFocus);
        }

        function test_escape_reaches_the_app_when_there_is_nowhere_to_go() {
            const b = createTemporaryObject(barComp, root, {
                focusable: true
            });
            const first = find(b, a1);
            first.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => first.activeFocus);
            let escaped = 0;
            b.escaped.connect(() => ++escaped);
            // No last item and no returnFocus: Escape goes on up to the app.
            b._last = null;
            root.appEscapes = 0;
            keyClick(Qt.Key_Escape);
            compare(escaped, 1);
            compare(root.appEscapes, 1);
        }

        function test_escape_passes_on_when_the_target_already_has_the_focus() {
            const b = createTemporaryObject(barComp, root, {
                focusable: true
            });
            const btn = find(b, a1);
            b.returnFocus = btn;
            btn.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => btn.activeFocus);
            let escaped = 0;
            b.escaped.connect(() => ++escaped);
            root.appEscapes = 0;
            keyClick(Qt.Key_Escape);
            compare(escaped, 1);
            compare(root.appEscapes, 1);
        }
    }
}
