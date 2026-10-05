import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtTest
import Atlas.Ui

Item {
    id: root
    width: 400
    height: 200

    Component {
        id: actionComp
        QQC2.Action {
            property int count: 0
            checkable: true
            onTriggered: count++
        }
    }
    Component {
        id: buttonComp
        ToolbarButton {
            focusable: true
            symbol: Symbols.Add
        }
    }
    Component {
        id: barComp
        AtlasProgressBar {
            width: 200
        }
    }

    Component {
        id: dialogLabelsComp
        AtlasDialog {
            id: labelsDialog
            property int rejectedCount: 0
            title: "Info"
            onRejected: rejectedCount++
            footerContent: [
                SecondaryButton {
                    text: "Cancel"
                    onClicked: labelsDialog.reject()
                }
            ]
            AtlasLabel {
                text: "Nothing to edit here"
            }
        }
    }
    Component {
        id: dialogFieldComp
        AtlasDialog {
            property alias field: edit
            title: "Name"
            AtlasTextField {
                id: edit
                Layout.fillWidth: true
            }
        }
    }

    SignalSpy {
        id: spy
        signalName: "clicked"
    }

    TestCase {
        name: "ToolbarButton"
        when: windowShown

        function test_return_fires_bound_action() {
            const a = createTemporaryObject(actionComp, root);
            const b = createTemporaryObject(buttonComp, root, {
                "action": a
            });
            b.forceActiveFocus();
            verify(b.activeFocus);
            keyClick(Qt.Key_Return);
            compare(a.count, 1);
            compare(a.checked, true);
            compare(b.checked, true);
            keyClick(Qt.Key_Enter);
            compare(a.count, 2);
            compare(b.checked, false);
        }

        function test_return_without_action_clicks() {
            const b = createTemporaryObject(buttonComp, root, {
                "checkable": true
            });
            spy.target = b;
            b.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(spy.count, 1);
            compare(b.checked, true);
        }
    }

    TestCase {
        name: "ToolbarButtonTooltip"
        when: windowShown

        function test_tooltip_hides_while_pressed_and_after_use() {
            const b = createTemporaryObject(buttonComp, root, {
                "text": "More options"
            });
            mouseMove(b, b.width / 2, b.height / 2);
            tryVerify(() => b.hovered);
            verify(b._tipShown, "hovered: the tooltip shows");
            mousePress(b, b.width / 2, b.height / 2);
            verify(!b._tipShown, "pressed: hidden");
            mouseRelease(b, b.width / 2, b.height / 2);
            verify(!b._tipShown, "after the click (a menu may be open): hidden");
            mouseMove(root, root.width - 2, root.height - 2);
            tryVerify(() => !b.hovered);
            mouseMove(b, b.width / 2, b.height / 2);
            tryVerify(() => b._tipShown, 2000, "back after the pointer left and returned");
        }
    }

    TestCase {
        name: "AtlasDialogFocus"
        when: windowShown

        function test_labels_only_body_keeps_return_from_closing() {
            const d = createTemporaryObject(dialogLabelsComp, root);
            d.open();
            tryVerify(() => d.opened);
            verify(d.activeFocus || d.contentItem.activeFocus || d.visibleFocusItem === d, "the dialog holds the focus");
            const f = Window.window.activeFocusItem;
            verify(f, "something has focus");
            verify(!(f.text === "Back" || f.text === "Close" || f.text === "Cancel"), "not a header or footer button");
            keyClick(Qt.Key_Return);
            wait(50);
            verify(d.opened, "Return did not close the dialog");
            compare(d.rejectedCount, 0);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !d.opened, 2000, "Escape closes it");
        }

        function test_text_field_gets_the_focus() {
            const d = createTemporaryObject(dialogFieldComp, root);
            d.open();
            tryVerify(() => d.opened);
            tryVerify(() => d.field.activeFocus);
            d.close();
        }
    }

    TestCase {
        name: "AtlasProgressBar"
        when: windowShown

        function test_track_fills_height_without_text() {
            const p = createTemporaryObject(barComp, root, {
                "height": 20,
                "value": 0.5
            });
            compare(p.children.length > 0, true);
            // The track is the first Rectangle under the layout's Item.
            const track = p.children[0].children[0].children[0];
            compare(track.height, 20);
        }

        function test_narrow_bar_does_not_overflow() {
            const p = createTemporaryObject(barComp, root, {
                "width": 30,
                "text": "42 %"
            });
            const item = p.children[0].children[0];
            verify(item.x + item.width <= p.width + 0.5);
        }

        function test_unknown_status_warns_once() {
            ignoreWarning(/unknown status "weird"/);
            const p = createTemporaryObject(barComp, root, {
                "status": "weird"
            });
            p.status = "other";
            compare(p._warned, true);
        }
    }

    Component {
        id: atlasButtonComp
        AtlasButton {
            text: "Sync"
        }
    }

    TestCase {
        name: "AtlasButtonBusy"
        when: windowShown

        function test_accessible_press_is_ignored_while_busy() {
            const b = createTemporaryObject(atlasButtonComp, root);
            let n = 0;
            b.clicked.connect(() => n++);
            verify(a11y.press(b), "the button offers a press action");
            compare(n, 1, "an idle button clicks");
            b.busy = true;
            a11y.press(b);
            compare(n, 1, "a busy button ignores the press action");
            b.busy = false;
            b.enabled = false;
            a11y.press(b);
            compare(n, 1, "a disabled button ignores it too");
        }
    }

    TestCase {
        name: "ProgressShimmer"
        when: windowShown

        // The shimmer is a gradient band over a flat fill: it must show as
        // different pixels along the fill, also on the software renderer.
        function distinctAlongFill(item) {
            const img = grabImage(item);
            const y = Math.round(item.height / 2);
            const seen = {};
            let count = 0;
            for (let x = 4; x < Math.round(item.width * 0.7); x += 2) {
                const c = img.pixel(x, y).toString();
                if (!seen[c]) {
                    seen[c] = true;
                    count++;
                }
            }
            return count;
        }

        function test_progress_bar_shimmer_renders() {
            const p = createTemporaryObject(barComp, root, {
                "value": 0.8,
                "animated": true
            });
            verify(waitForRendering(p));
            tryVerify(() => distinctAlongFill(p) > 3, 3000, "the band shades the fill");
        }

        function test_progress_bar_without_shimmer_is_flat() {
            const p = createTemporaryObject(barComp, root, {
                "value": 0.8,
                "animated": true,
                "status": "paused"
            });
            verify(waitForRendering(p));
            compare(distinctAlongFill(p), 1);
        }
    }
}
