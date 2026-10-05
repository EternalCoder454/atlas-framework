import QtQuick
import QtQuick.Layouts
import QtTest
import Atlas.Ui

Item {
    id: root
    width: 640
    height: 400

    Component {
        id: carouselComp
        AtlasScreenshotCarousel {
            anchors.fill: parent
            expandable: true
            sources: ["file:///nonexistent/a.png", "file:///nonexistent/b.png", "file:///nonexistent/c.png"]
        }
    }
    Component {
        id: shelfComp
        AtlasShelf {
            width: root.width
            title: "Shelf"
            model: [
                { name: "One" }, { name: "Two" }, { name: "Three" }, { name: "Four" },
                { name: "Five" }, { name: "Six" }, { name: "Seven" }, { name: "Eight" }
            ]
        }
    }
    Component {
        id: rtlShelfComp
        AtlasShelf {
            width: root.width
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true
            model: 8
        }
    }
    Component {
        id: openAtCreationComp
        AtlasScreenshotCarousel {
            anchors.fill: parent
            expandable: true
            expanded: true
            sources: ["file:///nonexistent/a.png"]
            onOpened: index => root.openedAtCreation = index
        }
    }
    Component {
        id: noWindowComp
        AtlasScreenshotCarousel {
            expandable: true
            expanded: true
            sources: ["file:///nonexistent/a.png"]
        }
    }
    property int openedAtCreation: -1

    // The item with `objectName` somewhere under `item` (the viewer's popup
    // lives in the window's overlay, not under the carousel).
    function findItem(item, name) {
        if (item.objectName === name) {
            return item;
        }
        for (const c of item.children) {
            const f = findItem(c, name);
            if (f) {
                return f;
            }
        }
        return null;
    }

    Component {
        id: customShelfComp
        AtlasShelf {
            width: root.width
            model: 5
            delegate: Rectangle {
                required property int index
                width: 100
                height: 40 + index * 10
                color: "gray"
            }
        }
    }
    Component {
        id: installComp
        AtlasInstallButton {}
    }
    Component {
        id: cardComp
        AtlasAppCard {
            width: 400
            name: "Atlas Notepad"
            summary: "Plain text"
            sizeText: "12 MB"
        }
    }

    SignalSpy { id: openedSpy; signalName: "opened" }
    SignalSpy { id: expandedSpy; signalName: "expandedChanged" }
    SignalSpy { id: activatedSpy; signalName: "activated" }
    SignalSpy { id: cancelSpy; signalName: "cancelRequested" }

    TestCase {
        name: "ScreenshotViewer"
        when: windowShown

        function make(props) {
            const c = createTemporaryObject(carouselComp, root, props || {});
            verify(c !== null);
            c.forceActiveFocus();
            tryVerify(() => c.activeFocus);
            openedSpy.target = c;
            openedSpy.clear();
            expandedSpy.target = c;
            expandedSpy.clear();
            return c;
        }

        function test_enter_opens_and_escape_closes() {
            const c = make({ currentIndex: 1 });
            keyClick(Qt.Key_Return);
            compare(c.expanded, true);
            compare(openedSpy.count, 1);
            compare(openedSpy.signalArguments[0][0], 1);
            compare(expandedSpy.count, 1);
            keyClick(Qt.Key_Escape);
            tryCompare(c, "expanded", false);
            compare(expandedSpy.count, 2);
            tryVerify(() => c.activeFocus, 2000, "focus goes back to the carousel");
        }

        function test_not_expandable_stays_closed() {
            const c = make({ expandable: false });
            keyClick(Qt.Key_Return);
            compare(c.expanded, false);
            c.expanded = true;
            compare(c.expanded, false);
            compare(openedSpy.count, 0);
        }

        function test_arrows_move_in_viewer() {
            const c = make();
            c.expanded = true;
            compare(openedSpy.count, 1);
            const viewer = root.findItem(root.Window.window.contentItem, "viewer");
            verify(viewer !== null, "the viewer exists");
            tryVerify(() => viewer.activeFocus, 2000, "the viewer holds the focus");
            compare(viewer.Accessible.description, "1 of 3");
            keyClick(Qt.Key_Right);
            compare(c.currentIndex, 1);
            compare(viewer.Accessible.description, "2 of 3");
            keyClick(Qt.Key_End);
            compare(c.currentIndex, 2);
            keyClick(Qt.Key_Left);
            compare(c.currentIndex, 1);
            c.expanded = false;
        }

        function test_expanded_at_creation_opens() {
            root.openedAtCreation = -1;
            const c = createTemporaryObject(openAtCreationComp, root);
            verify(c !== null);
            tryCompare(root, "openedAtCreation", 0);
            compare(c.expanded, true);
            c.expanded = false;
        }

        function test_expanded_without_a_window_resets() {
            const c = noWindowComp.createObject(null);
            verify(c !== null);
            compare(c.expanded, false);
            c.destroy();
        }

        function test_click_opens() {
            const c = make();
            mouseClick(c, c.width / 2, c.height / 3);
            compare(c.expanded, true);
            c.expanded = false;
        }

        function test_no_sources_never_opens() {
            const c = make({ sources: [] });
            c.expanded = true;
            compare(c.expanded, false);
            compare(openedSpy.count, 0);
        }

        function viewerSource(c) {
            c.expanded = true;
            const top = root.Window.window.contentItem;
            tryVerify(() => { const v = root.findItem(top, "viewer"); return v !== null && v.visible; });
            const img = root.findItem(top, "viewerImage");
            verify(img !== null, "the viewer image exists");
            const url = img.source.toString();
            c.expanded = false;
            return url;
        }

        function test_remote_rule_is_shared() {
            // The viewer reads the carousel's vetted sources: http: never
            // loads, https: only with allowRemote.
            ignoreWarning(/refused screenshot/);
            compare(viewerSource(make({ sources: ["http://example.invalid/a.png"] })), "");
            ignoreWarning(/refused screenshot/);
            compare(viewerSource(make({ sources: ["https://example.invalid/a.png"] })), "");
            compare(viewerSource(make({ sources: ["https://example.invalid/a.png"], allowRemote: true })), "https://example.invalid/a.png");
        }
    }

    TestCase {
        name: "AtlasShelf"
        when: windowShown

        function make(comp, props) {
            const s = createTemporaryObject(comp || shelfComp, root, props || {});
            verify(s !== null);
            return s;
        }

        function test_count_and_title() {
            const s = make();
            compare(s.count, 8);
            compare(s.title, "Shelf");
            compare(s.Accessible.name, "Shelf");
        }

        // Waits until a button's scroll animation is over.
        function settle(list) {
            let last = NaN;
            tryVerify(() => {
                const now = list.contentX;
                const done = now === last;
                last = now;
                return done;
            }, 3000);
        }

        function test_buttons_hide_at_the_ends() {
            const s = make();
            const left = findChild(s, "scrollLeft");
            const right = findChild(s, "scrollRight");
            const list = findChild(s, "list");
            verify(left && right && list);
            tryVerify(() => list.contentWidth > list.width);
            verify(!left.available, "nothing before the first card");
            verify(right.available);
            mouseClick(right);
            tryVerify(() => left.available);
            settle(list);
            list.contentX = list.originX + list.contentWidth - list.width;
            tryVerify(() => !right.available);
        }

        function test_rtl_mirrors_the_buttons() {
            const s = make(rtlShelfComp);
            const left = findChild(s, "scrollLeft");
            const right = findChild(s, "scrollRight");
            const list = findChild(s, "list");
            tryVerify(() => list.contentWidth > list.width);
            verify(s.mirrored);
            // The row starts at the right edge, so the way on is to the left.
            verify(left.available);
            verify(!right.available);
        }

        function test_default_card_activates() {
            const s = make();
            activatedSpy.target = s;
            activatedSpy.clear();
            const list = findChild(s, "list");
            tryVerify(() => list.itemAtIndex(1) !== null);
            const card = list.itemAtIndex(1);
            mouseClick(card, card.width / 2, card.height / 2);
            compare(activatedSpy.count, 1);
            compare(activatedSpy.signalArguments[0][0], 1);
        }

        function test_arrows_move_between_cards() {
            const s = make();
            const list = findChild(s, "list");
            tryVerify(() => list.itemAtIndex(0) !== null);
            list.itemAtIndex(0).forceActiveFocus(Qt.TabFocusReason);
            verify(list.itemAtIndex(0).activeFocus);
            keyClick(Qt.Key_Right);
            tryVerify(() => list.itemAtIndex(1) && list.itemAtIndex(1).activeFocus);
            keyClick(Qt.Key_End);
            tryVerify(() => list.itemAtIndex(7) && list.itemAtIndex(7).activeFocus);
            compare(list.currentIndex, 7);
            verify(list.contentX > list.originX, "the last card was scrolled into view");
            keyClick(Qt.Key_Home);
            tryVerify(() => list.itemAtIndex(0) && list.itemAtIndex(0).activeFocus);
        }

        function test_lazy_cards() {
            const s = make(shelfComp, { model: 5000 });
            const list = findChild(s, "list");
            tryVerify(() => list.count === 5000);
            verify(list.itemAtIndex(4000) === null, "off-screen cards are not made");
        }

        function test_custom_delegate_takes_the_tallest_height() {
            const s = make(customShelfComp);
            const list = findChild(s, "list");
            tryVerify(() => list.height >= 40 + 3 * 10);
        }
    }

    TestCase {
        name: "InstallButtonStates"
        when: windowShown

        function make(state) {
            const b = createTemporaryObject(installComp, root, { installState: state });
            verify(b !== null);
            cancelSpy.target = b;
            cancelSpy.clear();
            return b;
        }

        function test_labels() {
            compare(make("remove").text, "Remove");
            compare(make("queued").text, "Queued");
            compare(make("removing").text, "Removing…");
            const p = make("removing");
            p.progress = 0.25;
            compare(p.text, "25%");
            const r = make("remove");
            r.removeText = "Uninstall";
            compare(r.text, "Uninstall");
            const q = make("queued");
            q.queuedText = "Waiting";
            compare(q.text, "Waiting");
        }

        function test_cancel_in_removing_and_queued_only() {
            for (const state of ["removing", "queued"]) {
                const b = make(state);
                b.clicked();
                compare(cancelSpy.count, 1, state);
            }
            const r = make("remove");
            r.clicked();
            compare(cancelSpy.count, 0, "Remove is a plain press");
        }
    }

    TestCase {
        name: "AppCardVerifiedCompact"
        when: windowShown

        function make(props) {
            const c = createTemporaryObject(cardComp, root, props || {});
            verify(c !== null);
            return c;
        }

        function test_verified_is_spoken() {
            const plain = make();
            verify(plain.Accessible.description.indexOf("Verified") < 0);
            const v = make({ verified: true });
            verify(v.Accessible.description.indexOf("Verified") >= 0);
        }

        function test_compact_is_a_shorter_row() {
            const full = make({ rating: 4.5 });
            const compact = make({ compact: true, rating: 4.5 });
            verify(compact.implicitHeight < full.implicitHeight);
        }
    }
}
