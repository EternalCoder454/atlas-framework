import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import Atlas.Ui

// AtlasSplitView.collapsible: one pane at a time below collapseWidth, with a
// Back row.
Item {
    id: root
    width: 700
    height: 400

    Component {
        id: svComp
        AtlasSplitView {
            id: sv
            height: 300
            width: 600
            collapsible: true
            collapseWidth: 400
            _pushDuration: 0
            property real p0Pref: 150
            property alias p0: pane0
            property alias p1: pane1
            property alias p2: pane2
            Rectangle {
                id: pane0
                QQC2.SplitView.preferredWidth: sv.p0Pref
                QQC2.SplitView.minimumWidth: 80
                color: "red"
            }
            Rectangle {
                id: pane1
                QQC2.SplitView.preferredWidth: 150
                QQC2.SplitView.minimumWidth: 80
                color: "green"
            }
            Rectangle {
                id: pane2
                QQC2.SplitView.fillWidth: true
                color: "blue"
            }
        }
    }
    Component {
        id: rtlComp
        Item {
            id: holder
            property alias sv: inner
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true
            width: 600
            height: 300
            AtlasSplitView {
                id: inner
                anchors.fill: parent
                collapsible: true
                collapseWidth: 400
                property alias p0: r0
                property alias p1: r1
                Rectangle { id: r0; QQC2.SplitView.preferredWidth: 150; color: "red" }
                Rectangle { id: r1; QQC2.SplitView.fillWidth: true; color: "green" }
            }
        }
    }
    SignalSpy {
        id: paneSpy
        signalName: "currentPaneChanged"
    }

    TestCase {
        name: "AtlasSplitViewCollapse"
        when: windowShown

        function make(props) {
            const sv = createTemporaryObject(svComp, root, props || {});
            verify(sv !== null);
            return sv;
        }
        function findBy(item, pred, depth) {
            if (depth === undefined) {
                depth = 0;
            }
            if (!item || depth > 12) {
                return null;
            }
            if (pred(item)) {
                return item;
            }
            const kids = item.children;
            for (let i = 0; i < kids.length; ++i) {
                const r = findBy(kids[i], pred, depth + 1);
                if (r) {
                    return r;
                }
            }
            return null;
        }
        function backButton(sv) {
            return findBy(sv, c => c.text === "Back" && typeof c.clicked === "function");
        }
        function shown(sv) {
            return [sv.p0.visible, sv.p1.visible, sv.p2.visible];
        }

        function test_not_collapsible_never_collapses() {
            const sv = make({ collapsible: false, width: 300 });
            compare(sv.collapsed, false);
            compare(shown(sv), [true, true, true]);
        }

        function test_collapse_and_expand_at_the_width() {
            const sv = make();
            compare(sv.collapsed, false, "600 >= 400");
            compare(shown(sv), [true, true, true]);
            sv.width = 399;
            compare(sv.collapsed, true);
            compare(shown(sv), [true, false, false], "the first pane only");
            sv.width = 400;
            compare(sv.collapsed, false, "the width itself expands");
            compare(shown(sv), [true, true, true]);
            sv.collapseWidth = 700;
            compare(sv.collapsed, true, "collapseWidth moves the limit");
        }

        function test_vertical_never_collapses() {
            const sv = make({ orientation: Qt.Vertical, width: 300 });
            compare(sv.collapsed, false);
        }

        function test_show_pane() {
            const sv = make({ width: 300 });
            compare(sv.currentPane, 0);
            sv.showPane(1);
            compare(sv.currentPane, 1);
            compare(shown(sv), [false, true, false]);
            sv.showPane(2);
            compare(shown(sv), [false, false, true]);
            sv.showPane(7);
            compare(sv.currentPane, 2, "out of range is ignored");
            sv.showPane(-1);
            compare(sv.currentPane, 2);
        }

        function test_back_row_only_after_the_first_pane() {
            const sv = make({ width: 300 });
            const back = backButton(sv);
            verify(back !== null, "a Back button exists");
            verify(!back.visible, "none on the first pane");
            sv.showPane(1);
            verify(back.visible, "Back on the second pane");
            // The pane starts below the row.
            const rowBottom = back.mapToItem(sv, 0, back.height).y;
            verify(sv.p1.mapToItem(sv, 0, 0).y >= rowBottom - 1, "pane below the Back row");
            sv.width = 600;
            verify(!back.visible, "none when expanded");
        }

        function test_back_button() {
            const sv = make({ width: 300 });
            sv.showPane(1);
            mouseClick(backButton(sv));
            compare(sv.currentPane, 0);
            compare(shown(sv), [true, false, false]);
        }

        function test_alt_left() {
            const sv = make({ width: 300 });
            sv.forceActiveFocus();
            sv.showPane(1);
            keyClick(Qt.Key_Left, Qt.AltModifier);
            compare(sv.currentPane, 0);
            // On the first pane it does nothing.
            keyClick(Qt.Key_Left, Qt.AltModifier);
            compare(sv.currentPane, 0);
        }

        function test_mouse_back_button() {
            const sv = make({ width: 300 });
            sv.showPane(1);
            mouseClick(sv, 150, 150, Qt.BackButton);
            compare(sv.currentPane, 0);
        }

        function test_back_follows_the_history() {
            const sv = make({ width: 300 });
            sv.showPane(2);
            sv.showPane(1);
            mouseClick(backButton(sv));
            compare(sv.currentPane, 2, "back to where it came from");
            mouseClick(backButton(sv));
            compare(sv.currentPane, 1, "then the pane before in order");
            mouseClick(backButton(sv));
            compare(sv.currentPane, 0);
        }

        function test_current_pane_kept_across_a_resize() {
            const sv = make({ width: 300 });
            sv.showPane(1);
            sv.width = 600;
            compare(sv.collapsed, false);
            compare(shown(sv), [true, true, true]);
            compare(sv.currentPane, 1);
            sv.width = 300;
            compare(sv.currentPane, 1);
            compare(shown(sv), [false, true, false]);
        }

        function test_sizes_kept_for_expanding() {
            const sv = make();
            sv.p0Pref = 210;
            tryCompare(sv.p0, "width", 210);
            const before = sv.saveSizes();
            verify(before.length > 0);
            sv.width = 300;
            sv.showPane(2);
            sv.width = 600;
            tryCompare(sv.p0, "width", 210);
            compare(sv.saveSizes(), before);
        }

        function test_push_is_not_animated_under_reduced_motion() {
            const sv = make({ width: 300, _pushDuration: 0 });
            sv.showPane(1);
            compare(sv._sliding, false);
            compare(sv.contentItem.transform[0].x, 0);
        }

        function test_push_slides_from_the_end() {
            const sv = make({ width: 300, _pushDuration: 600 });
            sv.showPane(1);
            tryVerify(() => sv._sliding);
            tryVerify(() => sv.contentItem.transform[0].x > 0, 500);
            tryCompare(sv, "_sliding", false, 2000);
            compare(sv.contentItem.transform[0].x, 0);
        }

        function test_rtl() {
            const holder = createTemporaryObject(rtlComp, root);
            verify(holder !== null);
            const sv = holder.sv;
            sv._pushDuration = 600;
            compare(sv.mirrored, true);
            compare(sv.collapsed, false);
            // Expanded and mirrored: the first pane is at the right.
            verify(sv.p0.mapToItem(sv, 0, 0).x > sv.p1.mapToItem(sv, 0, 0).x);
            sv.width = 300;
            compare(sv.collapsed, true);
            sv.showPane(1);
            const back = backButton(sv);
            verify(back.visible);
            // The Back button sits at the right (the start in RTL).
            verify(back.mapToItem(sv, 0, 0).x > sv.width / 2, "Back at the start edge");
            // The incoming pane slides in from the left.
            tryVerify(() => sv.contentItem.transform[0].x < 0, 500);
            tryCompare(sv, "_sliding", false, 2000);
            mouseClick(back);
            compare(sv.currentPane, 0);
        }

        function test_current_pane_signal() {
            const sv = make({ width: 300 });
            paneSpy.target = sv;
            paneSpy.clear();
            sv.showPane(1);
            compare(paneSpy.count, 1);
        }
    }
}
