import QtQuick
import QtQuick.Layouts
import QtTest
import Telamon.Ui

Item {
    id: root
    width: 640
    height: 400

    Component {
        id: carouselComp
        TelamonScreenshotCarousel {
            anchors.fill: parent
            expandable: true
            sources: ["file:///nonexistent/a.png", "file:///nonexistent/b.png", "file:///nonexistent/c.png"]
        }
    }
    Component {
        id: shelfComp
        TelamonShelf {
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
        TelamonShelf {
            width: root.width
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true
            model: 8
        }
    }
    Component {
        id: openAtCreationComp
        TelamonScreenshotCarousel {
            anchors.fill: parent
            expandable: true
            expanded: true
            sources: ["file:///nonexistent/a.png"]
            onOpened: index => root.openedAtCreation = index
        }
    }
    Component {
        id: noWindowComp
        TelamonScreenshotCarousel {
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

    // The first visible item with `objectName` under `item`.
    function findVisible(item, name) {
        if (item.objectName === name && item.visible) {
            return item;
        }
        for (const c of item.children) {
            const f = findVisible(c, name);
            if (f) {
                return f;
            }
        }
        return null;
    }

    Component {
        id: customShelfComp
        TelamonShelf {
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
        TelamonInstallButton {}
    }
    Component {
        id: cardComp
        TelamonAppCard {
            width: 400
            name: "Telamon Notepad"
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
            const top = root.Window.window.contentItem;
            // A viewer still closing from the last carousel must be gone.
            tryVerify(() => root.findVisible(top, "viewer") === null, 3000);
            c.expanded = true;
            tryVerify(() => root.findVisible(top, "viewer") !== null);
            const img = root.findItem(root.findVisible(top, "viewer"), "viewerImage");
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
        name: "TelamonShelf"
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
            // The ring shows: nothing refocuses the card with no reason.
            verify(list.itemAtIndex(7).visualFocus, "card 7 shows keyboard focus");
            list.itemAtIndex(6).forceActiveFocus(Qt.TabFocusReason);
            verify(list.itemAtIndex(6).visualFocus, "a card focused from outside shows keyboard focus");
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

        // The index of the card that holds the focus, or -1.
        function focusedIndex(list) {
            let it = list.Window.activeFocusItem;
            while (it && it.parent !== list.contentItem)
                it = it.parent;
            if (!it)
                return -1;
            const p = it.mapToItem(list.contentItem, 1, 1);
            return list.indexAt(p.x, p.y);
        }

        // Scrolling far away and back makes the first cards again, after the
        // others among the list's children (the order Qt's focus chain
        // follows); Tab and Shift+Tab still go card by card in index order.
        function test_tab_goes_by_index_after_scrolling() {
            // More cards than the shelf keeps alive (24), so card 0 is released.
            const s = make(null, { model: 40 });
            const list = findChild(s, "list");
            tryVerify(() => list.contentWidth > list.width);
            list.contentX = list.originX + list.contentWidth - list.width;
            tryVerify(() => list.itemAtIndex(0) === null, 3000, "card 0 is released once scrolled far away");
            list.contentX = list.originX;
            tryVerify(() => list.itemAtIndex(0) !== null);
            list.itemAtIndex(0).forceActiveFocus(Qt.TabFocusReason);
            // Each card is two stops: the card, then its install button.
            const seen = [focusedIndex(list)];
            for (let i = 0; i < 15; ++i) {
                keyClick(Qt.Key_Tab);
                seen.push(focusedIndex(list));
            }
            compare(seen.join(","), "0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7");
            verify(list.Window.activeFocusItem !== list.itemAtIndex(7), "Tab reached the last card's button");
            const back = [];
            for (let i = 0; i < 15; ++i) {
                keyClick(Qt.Key_Backtab);
                back.push(focusedIndex(list));
            }
            compare(back.join(","), "7,6,6,5,5,4,4,3,3,2,2,1,1,0,0");
            compare(list.Window.activeFocusItem, list.itemAtIndex(0));
        }

        // Focus that comes from outside the row (a click elsewhere, then a
        // card focused) still scrolls the card fully into view.
        function test_focus_from_outside_scrolls_the_card_into_view() {
            const s = make();
            const list = findChild(s, "list");
            tryVerify(() => list.contentWidth > list.width);
            let card = null;
            for (let i = 0; i < list.count && !card; ++i) {
                const c = list.itemAtIndex(i);
                if (c && c.x + c.width > list.contentX + list.width + 1)
                    card = c;
            }
            verify(card !== null, "a card that is partly hidden");
            root.forceActiveFocus();
            verify(!list.activeFocus);
            card.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => card.x + card.width <= list.contentX + list.width + 0.5, 3000, "the card is scrolled fully into view");
        }

        // The default cards take the row's height, and the row still
        // shrinks when a new model holds only shorter cards.
        function test_default_cards_share_the_row_height() {
            const s = make(shelfComp, {
                model: [{ name: "Short" }, { name: "Tall", summary: "A summary long enough to wrap onto a second line of the card", rating: 4.5, sizeText: "3 MB" }]
            });
            const list = findChild(s, "list");
            tryVerify(() => list.itemAtIndex(0) !== null && list.itemAtIndex(1) !== null);
            const a = list.itemAtIndex(0);
            const b = list.itemAtIndex(1);
            const tall = b.implicitHeight;
            verify(tall > a.implicitHeight, "the second card is taller");
            tryCompare(a, "height", b.height);
            compare(list.height, tall);
            s.model = [{ name: "Short" }, { name: "Also short" }];
            tryVerify(() => list.height < tall, 3000, "the row shrinks for shorter cards");
            tryVerify(() => list.itemAtIndex(0) !== null);
            compare(list.itemAtIndex(0).height, list.height);
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
