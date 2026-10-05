import QtQuick
import QtQuick.Layouts
import QtTest
import Atlas.Ui

// AtlasHeaderBar.stretch and showTitle.
Item {
    id: root
    width: 800
    height: 100

    AtlasAction {
        id: act
        text: "Save"
        symbol: Symbols.Save
    }
    Component {
        id: barComp
        AtlasHeaderBar {
            id: bar
            property alias filler: filler
            property alias tail: tail
            width: 700
            title: "Test"
            actions: [act]
            stretch: [
                Item {
                    id: filler
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                }
            ]
            trailing: [
                Item {
                    id: tail
                    width: 30
                    height: 20
                }
            ]
        }
    }

    TestCase {
        name: "AtlasHeaderBarStretch"
        when: windowShown

        function test_stretch_takes_the_free_width() {
            const h = createTemporaryObject(barComp, root);
            tryVerify(() => h.filler.width > 150, 2000, "width " + h.filler.width);
            const left = h.filler.mapToItem(h, 0, 0).x;
            const right = left + h.filler.width;
            // Between the tools and the trailing items: no overlap.
            verify(right <= h.tail.mapToItem(h, 0, 0).x);
            verify(left > 0);
        }

        function test_empty_stretch_still_drags() {
            const h = createTemporaryObject(barComp, root);
            let moves = 0;
            h._moveHook = () => ++moves;
            const p = h.filler.mapToItem(h, h.filler.width / 2, 10);
            mousePress(h, p.x, p.y);
            for (let i = 1; i <= 10; ++i) {
                mouseMove(h, p.x + i * 4, p.y);
            }
            mouseRelease(h, p.x + 40, p.y);
            compare(moves, 1);
        }

        function test_no_room_hides_the_row() {
            const h = createTemporaryObject(barComp, root);
            h.width = 150;
            tryVerify(() => !h.filler.visible);
        }

        function test_stretch_stops_centring_the_title() {
            const h = createTemporaryObject(barComp, root, {
                centerTitle: true,
                width: 800
            });
            verify(!h.titleCentered);
        }

        function test_show_title_false_leaves_the_title_out() {
            const h = createTemporaryObject(barComp, root);
            let title = null;
            for (const c of h.children) {
                if (c.text === "Test") {
                    title = c;
                }
            }
            verify(title);
            verify(title.visible);
            tryVerify(() => h.filler.width > 0);
            const before = h.filler.width;
            h.showTitle = false;
            verify(!title.visible);
            tryVerify(() => h.filler.width > before, 2000, "width " + h.filler.width + " before " + before);
        }
    }
}
