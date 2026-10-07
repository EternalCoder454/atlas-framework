import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import Telamon.Ui

// MenuButton: a second click on the button closes the menu it opened, and
// Escape and a press elsewhere still close it. The menu's state is read from
// the button's accessible description, which is what a screen reader hears.
Item {
    id: root
    width: 600
    height: 400

    Component {
        id: buttonComp
        MenuButton {
            x: 40
            y: 40
            text: "View"
            QQC2.MenuItem {
                text: "One"
            }
            QQC2.MenuItem {
                text: "Two"
            }
        }
    }

    TestCase {
        name: "MenuButton"
        when: windowShown

        function expanded(b) {
            return b.Accessible.description === qsTr("Expanded");
        }
        function make() {
            const b = createTemporaryObject(buttonComp, root);
            verify(b);
            waitForRendering(b);
            return b;
        }

        function test_click_opens() {
            const b = make();
            verify(!expanded(b));
            mouseClick(b);
            tryVerify(() => expanded(b));
        }

        function test_second_click_closes() {
            const b = make();
            mouseClick(b);
            tryVerify(() => expanded(b));
            mouseClick(b);
            tryVerify(() => !expanded(b));
            // and it stays closed: the click did not open it again
            wait(200);
            verify(!expanded(b));
        }

        function test_third_click_opens_again() {
            const b = make();
            mouseClick(b);
            tryVerify(() => expanded(b));
            mouseClick(b);
            tryVerify(() => !expanded(b));
            wait(200);
            mouseClick(b);
            tryVerify(() => expanded(b));
        }

        function test_escape_closes() {
            const b = make();
            mouseClick(b);
            tryVerify(() => expanded(b));
            keyClick(Qt.Key_Escape);
            tryVerify(() => !expanded(b));
        }

        function test_press_elsewhere_closes() {
            const b = make();
            mouseClick(b);
            tryVerify(() => expanded(b));
            mouseClick(root, 560, 360);
            tryVerify(() => !expanded(b));
        }
    }
}
