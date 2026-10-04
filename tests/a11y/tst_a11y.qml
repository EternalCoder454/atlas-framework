import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import Atlas.Ui

// One test row per ui/gallery/demos/*Demo.qml, found at run time. A new
// control with a demo needs no change here: it fails if something the
// keyboard can reach lacks an Accessible.role or Accessible.name.
Rectangle {
    id: stage

    width: 900
    height: 700
    color: Kirigami.Theme.backgroundColor

    TestCase {
        name: "A11y"
        when: windowShown

        function test_demo_data() {
            return A11y.demos().map(n => ({
                        tag: n
                    }));
        }

        function test_demo(data) {
            const comp = Qt.createComponent(A11y.demoUrl(data.tag));
            compare(comp.status, Component.Ready, comp.errorString());
            const isWindow = A11y.rootIsWindow(data.tag);
            const obj = comp.createObject(isWindow ? null : stage);
            verify(obj !== null, "could not create " + data.tag + "Demo: " + comp.errorString());
            if (isWindow) {
                obj.visible = true;
                tryVerify(() => obj.visible, 5000);
            } else {
                waitForRendering(stage);
            }
            wait(300);
            const problems = A11y.audit(obj, data.tag);
            if (isWindow) {
                obj.close();
            }
            obj.destroy();
            wait(50);
            if (problems.length > 0) {
                fail(problems.join("\n"));
            }
        }
    }
}
