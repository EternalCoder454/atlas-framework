import QtQuick
import QtQuick.Controls
import QtTest
import org.kde.kirigami as Kirigami
import Telamon.Ui

// One test row per ui/gallery/demos/*Demo.qml, found at run time. A new
// control with a demo needs no change here, only a golden (see tests/README.md).
Rectangle {
    id: stage

    width: 900
    height: 700
    color: Kirigami.Theme.backgroundColor

    // rtl: what an app does for an Arabic or Hebrew user (main.cpp also sets
    // the application's layout direction, which popups and windows follow).
    LayoutMirroring.enabled: Goldens.variant() === "rtl"
    LayoutMirroring.childrenInherit: true

    TestCase {
        name: "Visual"
        when: windowShown

        // compact: the density an app sets on the style (TelamonStyle.density).
        // Popups and dialogs live in the window's overlay, which is not a child
        // of the app's root: an RTL app mirrors it too (Qt does not do it).
        function mirrorOverlay() {
            if (Goldens.variant() === "rtl" && Overlay.overlay) {
                Overlay.overlay.LayoutMirroring.enabled = true;
                Overlay.overlay.LayoutMirroring.childrenInherit = true;
            }
        }

        function init() {
            TelamonStyle.density = Goldens.variant() === "compact" ? TelamonStyle.Compact : TelamonStyle.Normal;
            mirrorOverlay();
        }

        function cleanup() {
            TelamonStyle.density = TelamonStyle.Normal;
        }

        // The variant really is on: a picture of the wrong state would be
        // accepted as a golden without anyone noticing.
        function test_variant_is_on() {
            const v = Goldens.variant();
            compare(TelamonStyle.highContrast, v === "contrast", "TelamonStyle.highContrast");
            compare(Qt.application.layoutDirection === Qt.RightToLeft, v === "rtl", "layout direction");
            compare(TelamonStyle.compact, v === "compact", "TelamonStyle.compact");
            fuzzyCompare(TelamonStyle.textScale, v === "text200" ? 2.0 : 1.0, 0.01, "TelamonStyle.textScale");
            compare(stage.LayoutMirroring.enabled, v === "rtl", "the stage is mirrored");
        }

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
                if (Goldens.variant() === "rtl") {
                    obj.contentItem.LayoutMirroring.enabled = true;
                    obj.contentItem.LayoutMirroring.childrenInherit = true;
                    obj.Overlay.overlay.LayoutMirroring.enabled = true;
                    obj.Overlay.overlay.LayoutMirroring.childrenInherit = true;
                }
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
