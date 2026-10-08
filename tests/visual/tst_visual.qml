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

        // WCAG contrast of two opaque colours.
        function lum(c) {
            const lin = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
            return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
        }
        function ratio(a, b) {
            const x = lum(a);
            const y = lum(b);
            return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
        }
        // `fg` over the opaque `bg`.
        function over(fg, bg) {
            return Qt.rgba(fg.r * fg.a + bg.r * (1 - fg.a), fg.g * fg.a + bg.g * (1 - fg.a), fg.b * fg.a + bg.b * (1 - fg.a), 1);
        }

        // The error colour is text on every surface and on its own faint fill
        // (a destructive button, an invalid field): 4.5:1, in every variant.
        function test_error_is_readable_text() {
            const surfaces = {
                base: TelamonStyle.base,
                surface: TelamonStyle.surface,
                surfaceRaised: TelamonStyle.surfaceRaised,
                control: TelamonStyle.control,
                codeSurface: TelamonStyle.codeSurface
            };
            for (const name in surfaces) {
                const bg = surfaces[name];
                verify(ratio(TelamonStyle.error, bg) >= 4.5, "error on " + name + ": " + ratio(TelamonStyle.error, bg).toFixed(2));
                const filled = over(TelamonStyle.errorFill, bg);
                verify(ratio(TelamonStyle.error, filled) >= 4.5, "error on errorFill over " + name + ": " + ratio(TelamonStyle.error, filled).toFixed(2));
            }
        }

        // success and warning are text, icons and fills: 4.5:1 on every
        // surface and on their own faint fill (so 3:1 as an icon or a fill).
        function test_success_and_warning_are_readable() {
            const surfaces = [TelamonStyle.base, TelamonStyle.surface, TelamonStyle.surfaceRaised, TelamonStyle.control, TelamonStyle.codeSurface];
            for (const [name, c] of [["success", TelamonStyle.success], ["warning", TelamonStyle.warning]]) {
                for (const bg of surfaces) {
                    verify(ratio(c, bg) >= 4.5, name + " on " + bg + ": " + ratio(c, bg).toFixed(2));
                    const filled = over(Qt.rgba(c.r, c.g, c.b, 0.14), bg);
                    verify(ratio(c, filled) >= 4.5, name + " on its fill over " + bg + ": " + ratio(c, filled).toFixed(2));
                }
            }
        }

        // The focus ring is a UI component's edge (3:1) on the surfaces it is
        // drawn on, and the accent (or the accent nudged to reach 3:1).
        function test_focus_ring_has_contrast_and_follows_the_accent() {
            for (const bg of [TelamonStyle.base, TelamonStyle.surface, TelamonStyle.surfaceRaised, TelamonStyle.control]) {
                verify(ratio(TelamonStyle.focus, bg) >= 3, "focus on " + bg + ": " + ratio(TelamonStyle.focus, bg).toFixed(2));
            }
            if (Qt.colorEqual(TelamonStyle.focus, TelamonStyle.accent)) {
                return;
            }
            // Nudged: still the accent's hue family, not a second brand colour.
            const hueGap = Math.abs(TelamonStyle.focus.hsvHue - TelamonStyle.accent.hsvHue);
            verify(Math.min(hueGap, 1 - hueGap) < 0.1 || TelamonStyle.focus.hsvSaturation < 0.15, "focus " + TelamonStyle.focus + " is no tint of the accent " + TelamonStyle.accent);
        }

        function test_default_focus_is_the_accent() {
            const v = Goldens.variant();
            if (v === "light" || v === "dark" || v === "rtl" || v === "compact" || v === "text200" || v === "opaque") {
                verify(Qt.colorEqual(TelamonStyle.focus, TelamonStyle.accent), "focus " + TelamonStyle.focus + ", accent " + TelamonStyle.accent);
            }
        }

        // A menu parts from what is behind it: its outline is stronger than a hairline.
        function test_outline_is_stronger_than_the_separator() {
            verify(TelamonStyle.outline.a > TelamonStyle.separator.a, "outline " + TelamonStyle.outline.a + ", separator " + TelamonStyle.separator.a);
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
