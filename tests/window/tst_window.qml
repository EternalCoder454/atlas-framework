import QtQuick
import QtQuick.Window
import QtTest
import Telamon.Ui

TestCase {
    name: "WindowState"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: winComp
        TelamonWindow {
            visible: true
            width: 320
            height: 240
        }
    }
    // Reads the file the way an app would.
    Component {
        id: settingsComp
        TelamonSettings {}
    }

    function settingsFor(key) {
        return createTemporaryObject(settingsComp, this, {
            "group": "Window-" + key
        });
    }

    function shown(key, props) {
        const w = winComp.createObject(null, Object.assign({
            "stateKey": key
        }, props || {}));
        verify(w !== null);
        tryVerify(() => w.visible && w.width > 0);
        return w;
    }

    function test_save_and_restore() {
        const first = shown("t1");
        compare(first.width, 320, "no saved state: the window keeps its own size");
        first.width = 700;
        first.height = 500;
        wait(100);
        first.destroy();   // the settings flush when the window goes
        tryVerify(() => settingsFor("t1").value("Width", 0) === 700);
        const s = settingsFor("t1");
        compare(s.value("Height", 0), 500);
        compare(s.value("Maximized", true), false);

        const second = shown("t1");
        compare(second.width, 700);
        compare(second.height, 500);
        compare(second.visibility, Window.Windowed);
        second.destroy();
        // Another key is another window.
        const other = shown("t2");
        compare(other.width, 320);
        other.destroy();
    }

    function test_clamped_to_the_screen() {
        const s = settingsFor("big");
        s.setValue("Width", 99999);
        s.setValue("Height", 88888);
        verify(s.flush());
        const w = shown("big");
        const screen = w.screen;
        verify(screen.desktopAvailableWidth > 0);
        verify(w.width <= screen.desktopAvailableWidth, "width " + w.width + " on a screen " + screen.desktopAvailableWidth);
        verify(w.height <= screen.desktopAvailableHeight);
        verify(w.width > 320, "the saved size was used, clamped");
        w.destroy();
        // Nonsense is ignored: the window keeps its own size.
        const t = settingsFor("junk");
        t.setValue("Width", 3);
        t.setValue("Height", -5);
        verify(t.flush());
        const j = shown("junk");
        compare(j.width, 320);
        j.destroy();
    }

    function test_maximised() {
        const s = settingsFor("max");
        s.setValue("Maximized", true);
        s.setValue("Width", 640);
        s.setValue("Height", 480);
        verify(s.flush());
        const w = shown("max");
        tryCompare(w, "visibility", Window.Maximized);
        w.destroy();
        tryVerify(() => settingsFor("max").value("Maximized", false) === true);
        compare(settingsFor("max").value("Width", 0), 640, "the normal size is kept while maximised");
    }

    function test_off_by_default() {
        const w = winComp.createObject(null, {});
        tryVerify(() => w.visible);
        w.width = 777;
        wait(100);
        w.destroy();
        compare(settingsFor("").value("Width", 0), 0);
    }
}
