import QtQuick
import QtTest
import Atlas.Ui

Item {
    id: root
    width: 700
    height: 100

    Component {
        id: headerComp
        AtlasHeaderBar {
            width: 700
            title: "Test"
        }
    }
    Component {
        id: framelessComp
        AtlasWindow {
            width: 400
            height: 300
            header: AtlasHeaderBar {
                title: "Frameless"
            }
        }
    }
    Component {
        id: plainComp
        AtlasWindow {
            width: 400
            height: 300
        }
    }

    TestCase {
        name: "AtlasHeaderBar"
        when: windowShown

        function test_drag_on_empty_bar_starts_system_move() {
            const h = createTemporaryObject(headerComp, root);
            let moves = 0;
            h._moveHook = () => ++moves;
            // Empty space, well right of the title and left of the buttons.
            mousePress(h, 400, 16);
            for (let i = 1; i <= 10; ++i) {
                mouseMove(h, 400 + i * 4, 16);
            }
            mouseRelease(h, 440, 16);
            compare(moves, 1);
        }

        function test_click_without_drag_does_not_move() {
            const h = createTemporaryObject(headerComp, root);
            let moves = 0;
            h._moveHook = () => ++moves;
            mouseClick(h, 400, 16);
            compare(moves, 0);
        }

        function test_double_click_toggles_maximize() {
            const h = createTemporaryObject(headerComp, root);
            let toggles = 0;
            h._toggleHook = () => ++toggles;
            mouseClick(h, 400, 16);
            mouseClick(h, 400, 16);
            compare(toggles, 1);
        }

        function test_window_buttons_keep_their_clicks() {
            const h = createTemporaryObject(headerComp, root);
            let toggles = 0;
            let moves = 0;
            h._toggleHook = () => ++toggles;
            h._moveHook = () => ++moves;
            // The buttons are on the right; a double click there is theirs.
            mouseClick(h, h.width - 9 - 16 - 36, 16);
            mouseClick(h, h.width - 9 - 16 - 36, 16);
            compare(toggles, 0);
            compare(moves, 0);
        }
    }

    TestCase {
        name: "AtlasWindow"
        when: windowShown

        function resizeAt(win, x, y) {
            const edges = [];
            win._resizeHook = e => edges.push(e);
            const scene = win.contentItem.parent.parent;
            wait(20);
            mousePress(scene, x, y);
            mouseRelease(scene, x, y);
            return edges;
        }

        function test_header_makes_window_frameless_and_plain_window_is_not() {
            const w = createTemporaryObject(framelessComp, root);
            verify(w.frameless);
            verify((w.flags & Qt.FramelessWindowHint) !== 0);
            const p = createTemporaryObject(plainComp, root);
            verify(!p.frameless);
            compare(p.flags & Qt.FramelessWindowHint, 0);
        }

        function test_edges_map_to_handles() {
            const w = createTemporaryObject(framelessComp, root);
            w.show();
            tryVerify(() => w.visible && w.visibility === Window.Windowed);
            const W = w.width;
            const H = w.height;
            compare(resizeAt(w, 2, 2), [Qt.TopEdge | Qt.LeftEdge]);
            compare(resizeAt(w, W / 2, 2), [Qt.TopEdge]);
            compare(resizeAt(w, W - 2, 2), [Qt.TopEdge | Qt.RightEdge]);
            compare(resizeAt(w, 2, H / 2), [Qt.LeftEdge]);
            compare(resizeAt(w, W - 2, H / 2), [Qt.RightEdge]);
            compare(resizeAt(w, 2, H - 2), [Qt.BottomEdge | Qt.LeftEdge]);
            compare(resizeAt(w, W / 2, H - 2), [Qt.BottomEdge]);
            compare(resizeAt(w, W - 2, H - 2), [Qt.BottomEdge | Qt.RightEdge]);
            // The middle of the window is not a handle.
            compare(resizeAt(w, W / 2, H / 2), []);
        }

        function test_handle_cursors() {
            const w = createTemporaryObject(framelessComp, root);
            const want = {};
            want[Qt.TopEdge | Qt.LeftEdge] = Qt.SizeFDiagCursor;
            want[Qt.TopEdge | Qt.RightEdge] = Qt.SizeBDiagCursor;
            want[Qt.BottomEdge | Qt.LeftEdge] = Qt.SizeBDiagCursor;
            want[Qt.BottomEdge | Qt.RightEdge] = Qt.SizeFDiagCursor;
            want[Qt.TopEdge] = Qt.SizeVerCursor;
            want[Qt.BottomEdge] = Qt.SizeVerCursor;
            want[Qt.LeftEdge] = Qt.SizeHorCursor;
            want[Qt.RightEdge] = Qt.SizeHorCursor;
            compare(w._handles.length, 8);
            for (const h of w._handles) {
                compare(h.cursor, want[h.edges]);
            }
        }

        function test_plain_window_has_no_handles() {
            const p = createTemporaryObject(plainComp, root);
            p.show();
            tryVerify(() => p.visible);
            compare(resizeAt(p, 2, 2), []);
        }
    }

    TestCase {
        name: "AtlasWindowChrome"

        function test_parse_buttons() {
            compare(AtlasWindowChrome.parseButtons("HIAX"), ["minimize", "maximize", "close"]);
            compare(AtlasWindowChrome.parseButtons("M"), ["menu"]);
            compare(AtlasWindowChrome.parseButtons("XAI"), ["close", "maximize", "minimize"]);
            compare(AtlasWindowChrome.parseButtons("IIX"), ["minimize", "close"]);
            compare(AtlasWindowChrome.parseButtons("SFB"), []);
            compare(AtlasWindowChrome.parseButtons(""), []);
        }

        function test_default_layout() {
            // The test environment has no kwinrc: AtlasOS's defaults.
            compare(AtlasWindowChrome.buttonsOnLeft, ["menu"]);
            compare(AtlasWindowChrome.buttonsOnRight, ["minimize", "maximize", "close"]);
        }
    }
}
