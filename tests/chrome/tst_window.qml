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

        function test_mirrored_positions() {
            const h = createTemporaryObject(headerComp, root);
            let title = null;
            for (const c of h.children) {
                if (c.text === "Test") {
                    title = c;
                }
            }
            verify(title);
            const x = title.x;
            const w = title.width;
            h.LayoutMirroring.enabled = true;
            h.LayoutMirroring.childrenInherit = true;
            // Every position is the mirror image of the unmirrored one.
            fuzzyCompare(title.x + title.width, h.width - x, 1);
            compare(title.width, w);
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

        // The handles reach 6 px in; a corner runs 16 px along both edges (an
        // L, so the square inside it is the content's).
        function test_handles_are_easy_to_grab() {
            const w = createTemporaryObject(framelessComp, root);
            w.show();
            tryVerify(() => w.visible && w.visibility === Window.Windowed);
            const W = w.width;
            const H = w.height;
            compare(resizeAt(w, 5, H / 2), [Qt.LeftEdge]);
            compare(resizeAt(w, W - 6, H / 2), [Qt.RightEdge]);
            compare(resizeAt(w, W / 2, H - 6), [Qt.BottomEdge]);
            compare(resizeAt(w, 7, H / 2), []);
            compare(resizeAt(w, 14, H - 2), [Qt.BottomEdge | Qt.LeftEdge]);
            compare(resizeAt(w, 2, H - 14), [Qt.BottomEdge | Qt.LeftEdge]);
            compare(resizeAt(w, W - 14, H - 2), [Qt.BottomEdge | Qt.RightEdge]);
            compare(resizeAt(w, W - 2, H - 14), [Qt.BottomEdge | Qt.RightEdge]);
            compare(resizeAt(w, 2, 14), [Qt.TopEdge | Qt.LeftEdge]);
            compare(resizeAt(w, W - 2, 14), [Qt.TopEdge | Qt.RightEdge]);
            compare(resizeAt(w, W - 14, 2), [Qt.TopEdge | Qt.RightEdge]);
            compare(resizeAt(w, 10, H - 10), []);
            compare(resizeAt(w, W - 10, 10), []);
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
            compare(w._handles.length, 12);
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
            compare(AtlasWindowChrome._parseButtons("HIAX"), ["minimize", "maximize", "close"]);
            compare(AtlasWindowChrome._parseButtons("M"), ["menu"]);
            compare(AtlasWindowChrome._parseButtons("XAI"), ["close", "maximize", "minimize"]);
            compare(AtlasWindowChrome._parseButtons("IIX"), ["minimize", "close"]);
            compare(AtlasWindowChrome._parseButtons("SFB"), []);
            compare(AtlasWindowChrome._parseButtons(""), []);
        }

        function test_default_layout() {
            // The test environment has no kwinrc: AtlasOS's defaults.
            compare(AtlasWindowChrome.buttonsOnLeft, ["menu"]);
            compare(AtlasWindowChrome.buttonsOnRight, ["minimize", "maximize", "close"]);
        }
    }

    Component {
        id: navComp
        AtlasNavigationStack {
            width: 400
            height: 300
            initialItem: AtlasPage {
                title: "Home"
            }
        }
    }
    Component {
        id: navPageComp
        AtlasPage {
            title: "Details"
            headerTrailing: ToolbarButton {
                objectName: "pageAction"
                symbol: Symbols.Search
                text: "Search"
            }
        }
    }

    Component {
        id: plainPageComp
        Item {
            property string title
        }
    }

    TestCase {
        name: "AtlasNavigationStack"
        when: windowShown

        function findLabel(item, text) {
            if (!item) {
                return null;
            }
            if (item.text === text && item.font !== undefined && item.elide !== undefined) {
                return item;
            }
            for (let i = 0; i < item.children.length; ++i) {
                const found = findLabel(item.children[i], text);
                if (found) {
                    return found;
                }
            }
            return null;
        }
        function findNamed(item, name) {
            if (!item) {
                return null;
            }
            if (item.objectName === name) {
                return item;
            }
            for (let i = 0; i < item.children.length; ++i) {
                const found = findNamed(item.children[i], name);
                if (found) {
                    return found;
                }
            }
            return null;
        }

        // The header shows the page's title, so the page doesn't repeat it;
        // without the header the page shows its own again.
        function test_page_title_shown_once() {
            const nav = createTemporaryObject(navComp, root);
            verify(nav);
            const page = nav.push(navPageComp);
            verify(page);
            tryCompare(nav, "currentItem", page);
            const own = findLabel(page, "Details");
            verify(own, "the page's own title label");
            verify(!own.visible, "hidden under the stack's header");
            verify(findNamed(page, "pageAction").visible, "the page's header items stay");
            nav.showHeader = false;
            verify(own.visible, "shown when the stack has no header");
            nav.showHeader = true;
            nav.pop();
            tryCompare(nav, "depth", 1);
            verify(!findLabel(nav.currentItem, "Home").visible, "the first page too");
        }

        // A page that isn't an AtlasPage (no _titleInHeader) is left alone.
        function test_plain_item_page() {
            const nav = createTemporaryObject(navComp, root);
            const page = nav.push(plainPageComp, { title: "Plain" });
            verify(page);
            tryCompare(nav, "depth", 2);
            verify(!("_titleInHeader" in page), "a plain page gets no marker");
        }
    }
}
