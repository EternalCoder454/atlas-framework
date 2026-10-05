import QtQuick
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
}
