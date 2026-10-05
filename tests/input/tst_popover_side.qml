import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import Atlas.Ui

// AtlasPopover.side and placedSide: the chosen side, the flip when there is no
// room, and Auto keeping 1.4.0's behaviour.
Item {
    id: root
    width: 600
    height: 400

    Item {
        id: anchorItem
        width: 40
        height: 30
        x: 280
        y: 180
    }
    Component {
        id: popComp
        AtlasPopover {
            target: anchorItem
            QQC2.Label {
                text: "Hello there"
            }
        }
    }

    TestCase {
        name: "AtlasPopoverSide"
        when: windowShown

        function place(side, tx, ty, mirrored) {
            anchorItem.x = tx;
            anchorItem.y = ty;
            const p = createTemporaryObject(popComp, root, {
                side: side
            });
            p.open();
            tryVerify(() => p.visible);
            return p;
        }

        function test_auto_is_below() {
            const p = place(AtlasPopover.Auto, 280, 100);
            compare(p.placedSide, AtlasPopover.Below);
            verify(!p.above);
            verify(p.y >= 100 + 30);
        }

        function test_auto_flips_above_with_no_room() {
            const p = place(AtlasPopover.Auto, 280, 380);
            compare(p.placedSide, AtlasPopover.Above);
            verify(p.above);
        }

        function test_above() {
            const p = place(AtlasPopover.Above, 280, 200);
            compare(p.placedSide, AtlasPopover.Above);
            verify(p.y + p.height <= 200 + 1);
        }

        function test_above_flips_below_at_the_top() {
            const p = place(AtlasPopover.Above, 280, 4);
            compare(p.placedSide, AtlasPopover.Below);
        }

        function test_end_is_right_of_target_and_centred() {
            const p = place(AtlasPopover.End, 100, 180);
            compare(p.placedSide, AtlasPopover.End);
            verify(p.x >= 100 + 40);
            const centre = p.y + p.height / 2;
            verify(Math.abs(centre - (180 + 15)) <= 1);
        }

        function test_start_is_left_of_target() {
            const p = place(AtlasPopover.Start, 300, 180);
            compare(p.placedSide, AtlasPopover.Start);
            verify(p.x + p.width <= 300 + 1);
        }

        function test_end_flips_to_start_with_no_room() {
            const p = place(AtlasPopover.End, 570, 180);
            compare(p.placedSide, AtlasPopover.Start);
        }

        function test_clamped_into_the_window() {
            const p = place(AtlasPopover.End, 100, 2);
            verify(p.y >= 0);
            const q = place(AtlasPopover.End, 100, 395);
            verify(q.y + q.height <= root.height);
        }
    }
}
