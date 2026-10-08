import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtTest
import Telamon.Ui

// TelamonIcon behind a dialog, with the software renderer. Kirigami.Icon draws
// as a render node there, and a repaint that touches part of an icon (a text
// cursor, typing) could paint the whole icon again over the dialog in front of
// it; TelamonIcon is a layer on that renderer so it stays in place. The picture
// is the window as the screen holds it, after the partial repaints. The
// dialog's empty body is in front of a grid of folder icons and must stay
// grey while a field above it is typed in.
Item {
    id: root
    width: 700
    height: 500

    GridView {
        id: grid
        anchors.fill: parent
        cellWidth: 36
        cellHeight: 36
        clip: true
        model: 18 * 14
        delegate: Item {
            width: 36
            height: 36
            TelamonIcon {
                id: icon
                objectName: "icon" + index
                width: 32
                height: 32
                source: "folder"
            }
        }
    }

    TelamonDialog {
        id: dialog
        title: "Find"
        preferredWidth: 400
        TelamonTextField {
            id: field
            Layout.fillWidth: true
        }
        Item {
            id: body
            Layout.fillWidth: true
            Layout.preferredHeight: 160
        }
    }

    TestCase {
        name: "TelamonIconOverPopup"
        when: windowShown

        function icon() {
            waitForRendering(root);
            const item = grid.itemAtIndex(0);
            verify(item);
            return item.children[0];
        }

        // A layer exactly when Quick draws in software, plain otherwise.
        function test_layer_follows_the_backend() {
            const i = icon();
            compare(i.layer.enabled, root.GraphicsInfo.api === GraphicsInfo.Software);
        }

        // The layer is drawn again when the icon changes (it is not live).
        function test_layer_follows_the_icon() {
            if (root.GraphicsInfo.api !== GraphicsInfo.Software) {
                skip("the software renderer only");
            }
            const i = icon();
            // Not live at rest.
            tryCompare(i.layer, "live", false);
            const p = i.mapToItem(null, 0, 0);
            const r = Qt.rect(p.x, p.y, i.width, i.height);
            tryVerify(() => pixels.colorIn(Window.window, r) > 100);
            i.source = "";
            wait(300);
            compare(pixels.colorIn(Window.window, r), 0);
            i.source = "folder";
            tryVerify(() => pixels.colorIn(Window.window, r) > 100);
        }

        function test_icons_stay_under_a_dialog() {
            if (root.GraphicsInfo.api !== GraphicsInfo.Software) {
                skip("the software renderer only");
            }
            icon();
            const all = Qt.rect(0, 0, root.width, root.height);
            // The icons are drawn at all (else the test proves nothing).
            verify(pixels.colorIn(Window.window, all) > 10000);
            dialog.open();
            tryCompare(dialog, "opened", true);
            wait(400);
            field.forceActiveFocus();
            for (let i = 0; i < 6; ++i) {
                keyClick("a");
                wait(150);
            }
            const p = body.mapToItem(null, 0, 0);
            compare(pixels.colorIn(Window.window, Qt.rect(p.x, p.y, body.width, body.height)), 0);
            dialog.close();
        }
    }
}
