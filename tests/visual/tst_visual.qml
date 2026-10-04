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
            // Popups open and transitions end. A new golden waits for them;
            // a comparison looks early and again every 200 ms until the
            // picture matches or 3 s have gone, so a busy machine (tests
            // run in parallel) only takes longer, and a pass takes a frame.
            let message;
            if (Goldens.updating()) {
                wait(600);
                message = Goldens.check(obj, data.tag);
            } else {
                wait(50);
                message = Goldens.check(obj, data.tag);
                for (let tries = 0; message !== "" && tries < 15; ++tries) {
                    wait(200);
                    message = Goldens.check(obj, data.tag);
                }
            }
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
