import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// The window of an Atlas app. With "Transparency effects" on (and the
// compositor blurring), the window background is the theme's background at
// `blurAlpha` over a blurred desktop, Mica style; otherwise it is the plain
// opaque background, exactly as before. Put `sidebarColor(base)` on a sidebar
// so it is a little more see-through; Section cards stay nearly opaque.
//
// `widthClass` says how roomy the window is (Compact, Medium or Wide), and
// `sidebarCollapsed` is true in Compact, so every app folds its sidebar to
// icons at the same width:
//
//   AtlasWindow {
//       AtlasSidebar {
//           compact: window.sidebarCollapsed
//           ...
//       }
//   }
//
// `stateKey` (empty: off) remembers the window: its width, height and whether
// it was maximised are saved under "Window-<stateKey>" in the app's settings
// file (AtlasSettings, a moment after a change) and restored when the window
// first shows, clamped to the screen. A sidebar's or split view's size is
// saved the same way by the app (see AtlasSettings).
//
// A second launch of an app started with atlas_app_run raises this window
// (with the launcher's activation token, so Wayland lets it come up) and
// exits; nothing is needed here.
QQC2.ApplicationWindow {
    id: root

    enum WidthClass {
        Compact,
        Medium,
        Wide
    }

    // Compact below 30 grid units wide, Wide from 60, Medium between.
    readonly property int widthClass: root.width < Kirigami.Units.gridUnit * 30 ? AtlasWindow.WidthClass.Compact : root.width >= Kirigami.Units.gridUnit * 60 ? AtlasWindow.WidthClass.Wide : AtlasWindow.WidthClass.Medium
    // True in Compact: show the sidebar as icons only (AtlasSidebar.compact).
    readonly property bool sidebarCollapsed: root.widthClass === AtlasWindow.WidthClass.Compact

    // Names the saved window state; empty keeps none.
    property string stateKey

    // True while the window is drawn over blur.
    readonly property bool blurred: Appearance.effective
    property real blurAlpha: 0.80
    // How much more see-through the sidebar is, as a factor on blurAlpha.
    property real sidebarFactor: 0.8

    // `base` with the window's alpha (times the sidebar's, for a sidebar), or
    // unchanged when there is no blur.
    function tinted(base: color, factor: real): color {
        return root.blurred ? Qt.alpha(base, root.blurAlpha * factor) : base;
    }
    function sidebarColor(base: color): color {
        return tinted(base, root.sidebarFactor);
    }

    // An alpha surface only while blurred: an opaque window otherwise, as before.
    color: root.blurred ? "transparent" : Kirigami.Theme.backgroundColor
    background: Rectangle {
        color: root.tinted(Kirigami.Theme.backgroundColor, 1)
    }

    function syncBlur() {
        Appearance.applyBlur(root);
    }
    onBlurredChanged: syncBlur()
    // Nothing tells us when KWin's blur effect is switched on or off:
    // check again when the window shows and when it gets focus.
    onVisibleChanged: if (visible) {
        Appearance.refresh();
        syncBlur();
        _firstShow();
    }
    onActiveChanged: if (active) {
        Appearance.refresh();
        syncBlur();
    }
    // The platform window (on Wayland, the surface) exists from here on.
    onSceneGraphInitialized: syncBlur()
    Component.onCompleted: {
        _restoreSize();
        if (visible) {
            syncBlur();
            _firstShow();
        }
    }

    // Window state (stateKey). Nothing is saved until the saved size has been
    // applied, so the defaults never overwrite it.
    property bool _stateReady: false
    property bool _shown: false
    readonly property AtlasSettings _state: AtlasSettings {
        group: root.stateKey.length > 0 ? "Window-" + root.stateKey : ""
    }
    function _restoreSize() {
        if (root.stateKey.length > 0) {
            const screen = root.screen;
            const maxW = screen ? screen.desktopAvailableWidth : 0;
            const maxH = screen ? screen.desktopAvailableHeight : 0;
            const w = root._state.value("Width", 0);
            const h = root._state.value("Height", 0);
            if (w >= 100 && h >= 100) {
                // Clamped: a screen smaller than last time must not hide the window.
                root.width = Math.max(root.minimumWidth, maxW > 0 ? Math.min(w, maxW) : w);
                root.height = Math.max(root.minimumHeight, maxH > 0 ? Math.min(h, maxH) : h);
            }
        }
        root._stateReady = true;
    }
    function _firstShow() {
        if (root._shown) {
            return;
        }
        root._shown = true;
        if (root.stateKey.length > 0 && root._state.value("Maximized", false)) {
            root.visibility = Window.Maximized;
        }
    }
    function _saveState() {
        if (!root._stateReady || root.stateKey.length === 0 || !root._shown) {
            return;
        }
        if (root.visibility === Window.Windowed) {
            root._state.setValue("Width", Math.round(root.width));
            root._state.setValue("Height", Math.round(root.height));
            root._state.setValue("Maximized", false);
        } else if (root.visibility === Window.Maximized) {
            // The size stays what it was before: that is where un-maximising goes.
            root._state.setValue("Maximized", true);
        }
    }
    onWidthChanged: _saveState()
    onHeightChanged: _saveState()
    onVisibilityChanged: _saveState()
}
