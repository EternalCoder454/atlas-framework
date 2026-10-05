pragma ComponentBehavior: Bound

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
// Frameless mode is opt-in: give the window an AtlasHeaderBar as its `header`
// and the window draws its own title row (title, main tools and the window
// buttons, in one) instead of KWin's title bar:
//
//   AtlasWindow {
//       header: AtlasHeaderBar { actions: [saveAction, openAction] }
//   }
//
// Then the window has the Qt.FramelessWindowHint, a hairline border (none when
// maximised or full screen), and 6 px invisible handles around it that resize
// it through the compositor (startSystemResize), with the right cursors. The
// header moves the window and maximises it on a double click. The header sits
// above the content, as with any ApplicationWindow `header`, so it composes
// with Kirigami page stacks inside (their global toolbars are separate).
// Without an AtlasHeaderBar nothing changes: KWin decorates the window.
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

    // The header, when it is an AtlasHeaderBar: the window is then frameless.
    readonly property AtlasHeaderBar _atlasHeader: root.header as AtlasHeaderBar
    readonly property bool frameless: root._atlasHeader !== null
    // The window can be resized by the handles: frameless and in a normal state.
    readonly property bool _resizable: root.frameless && root.visibility !== Window.Maximized && root.visibility !== Window.FullScreen
    flags: root.frameless ? Qt.Window | Qt.FramelessWindowHint : Qt.Window

    // Test hook: replaces startSystemResize(edges).
    property var _resizeHook: null
    function _startResize(edges: int) {
        if (_resizeHook) {
            _resizeHook(edges);
        } else {
            root.startSystemResize(edges);
        }
    }
    // The handles: the edges each one resizes and its cursor.
    readonly property var _handles: [
        {
            edges: Qt.TopEdge | Qt.LeftEdge,
            cursor: Qt.SizeFDiagCursor
        },
        {
            edges: Qt.TopEdge,
            cursor: Qt.SizeVerCursor
        },
        {
            edges: Qt.TopEdge | Qt.RightEdge,
            cursor: Qt.SizeBDiagCursor
        },
        {
            edges: Qt.LeftEdge,
            cursor: Qt.SizeHorCursor
        },
        {
            edges: Qt.RightEdge,
            cursor: Qt.SizeHorCursor
        },
        {
            edges: Qt.BottomEdge | Qt.LeftEdge,
            cursor: Qt.SizeBDiagCursor
        },
        {
            edges: Qt.BottomEdge,
            cursor: Qt.SizeVerCursor
        },
        {
            edges: Qt.BottomEdge | Qt.RightEdge,
            cursor: Qt.SizeFDiagCursor
        }
    ]
    readonly property real _grip: 6

    // An alpha surface only while blurred: an opaque window otherwise, as before.
    color: root.blurred ? "transparent" : Kirigami.Theme.backgroundColor
    background: Rectangle {
        color: root.tinted(Kirigami.Theme.backgroundColor, 1)
        border.width: root._resizable ? 1 : 0
        border.color: AtlasStyle.separator
    }

    Repeater {
        // The window's own root item, above the header (the content control
        // the header sits beside would put the handles below it).
        parent: Window.contentItem
        model: root._resizable ? root._handles : []

        MouseArea {
            id: handle

            required property var modelData
            readonly property int _edges: modelData.edges
            readonly property bool _left: (_edges & Qt.LeftEdge) !== 0
            readonly property bool _right: (_edges & Qt.RightEdge) !== 0
            readonly property bool _top: (_edges & Qt.TopEdge) !== 0
            readonly property bool _bottom: (_edges & Qt.BottomEdge) !== 0
            readonly property bool _corner: (_left || _right) && (_top || _bottom)

            // Corners are grip x grip squares; sides run between them.
            x: handle._left ? 0 : handle._right ? root.width - root._grip : root._grip
            y: handle._top ? 0 : handle._bottom ? root.height - root._grip : root._grip
            width: handle._left || handle._right ? root._grip : root.width - 2 * root._grip
            height: handle._top || handle._bottom ? root._grip : root.height - 2 * root._grip
            z: 1000
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: modelData.cursor
            onPressed: root._startResize(handle._edges)
        }
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
    }
    onActiveChanged: if (active) {
        Appearance.refresh();
        syncBlur();
    }
    // The platform window (on Wayland, the surface) exists from here on.
    onSceneGraphInitialized: syncBlur()
    Component.onCompleted: if (visible) {
        syncBlur()
    }
}
