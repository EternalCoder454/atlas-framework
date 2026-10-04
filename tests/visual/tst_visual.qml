import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import Atlas.Ui

// One test row per ui/gallery/demos/*Demo.qml, found at run time. A new
// control with a demo needs no change here, only a golden (see tests/README.md).
Rectangle {
    id: stage

    width: 900
    height: 700
    color: Kirigami.Theme.backgroundColor

    TestCase {
        name: "Visual"
        when: windowShown

        function test_demo_data() {
            return Goldens.demos().map(n => ({
                        tag: n
                    }));
        }

        function test_demo(data) {
            const comp = Qt.createComponent(Goldens.demoUrl(data.tag));
            compare(comp.status, Component.Ready, comp.errorString());
            const isWindow = Goldens.rootIsWindow(data.tag);
            const obj = comp.createObject(isWindow ? null : stage);
            verify(obj !== null, "could not create " + data.tag + "Demo: " + comp.errorString());
            if (obj.animate !== undefined) {
                obj.animate = false;
            }
            if (isWindow) {
                obj.visible = true;
                tryVerify(() => obj.visible, 5000);
            } else {
                waitForRendering(stage);
            }
            // Popups open and transitions end.
            wait(600);
            const message = Goldens.check(obj, data.tag);
            if (isWindow) {
                obj.close();
            }
            obj.destroy();
            wait(50);
            if (message !== "") {
                fail(message);
            }
        }
    }
}
