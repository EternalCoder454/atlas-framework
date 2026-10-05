pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// The minimise, maximise/restore and close buttons of a frameless window,
// drawn like the AtlasOS KWin (Aurorae) decoration: 32x32 cells with a 26 px
// rounded square (7 px corners) in the glyph colour at 7%, 1.6 px round-cap
// glyphs, 4 px between cells. Hover tints the square with the accent (28%),
// a press 45%; close turns red (#C42B1C, pressed #A52416) with a white glyph.
// An inactive window and a disabled button are fainter, as in the decoration.
// The colours come from the Header colour set, so a scheme other than
// AtlasOS's still works.
//
// AtlasHeaderBar places two of these (KWin's left and right button layout);
// use one on its own to build a custom title bar:
//
//   AtlasWindowButtons { buttons: ["minimize", "maximize", "close"] }
//
// A click minimises, maximises or restores, or closes the window the item is
// in. The buttons never take keyboard focus (the header's window menu is the
// keyboard way), and carry Accessible names.
Row {
    id: root

    // Which buttons, left to right: "minimize", "maximize", "close".
    property var buttons: ["minimize", "maximize", "close"]
    // Whether the window is active; inactive windows draw fainter buttons.
    property bool active: Window.active
    // True while the window is maximised (the maximise button shows "restore").
    readonly property bool maximized: _forceMaximized >= 0 ? _forceMaximized === 1 : (Window.window ? Window.window.visibility === Window.Maximized : false)

    // Pictures and tests: 1 or 0 override `maximized`, a button name forces
    // hover or pressed on it.
    property int _forceMaximized: -1
    property string _forceHover
    property string _forcePressed
    // Tests switch the 120 ms colour fade off.
    property bool _animate: true

    spacing: AtlasStyle.spacingSmall
    Kirigami.Theme.colorSet: Kirigami.Theme.Header
    Kirigami.Theme.inherit: false

    function _minimize() {
        if (Window.window) {
            Window.window.showMinimized();
        }
    }
    function _toggleMaximize() {
        const w = Window.window;
        if (w) {
            if (w.visibility === Window.Maximized) {
                w.showNormal();
            } else {
                w.showMaximized();
            }
        }
    }
    function _close() {
        if (Window.window) {
            Window.window.close();
        }
    }

    Repeater {
        model: root.buttons

        T.AbstractButton {
            id: btn

            required property string modelData
            readonly property bool _isClose: modelData === "close"
            readonly property bool _hover: root._forceHover === modelData || hovered
            readonly property bool _down: root._forcePressed === modelData || down
            readonly property bool _restore: modelData === "maximize" && root.maximized
            readonly property color _glyph: _isClose && (_hover || _down) ? "#FFFFFF" : Kirigami.Theme.textColor
            readonly property color _fill: {
                if (_isClose && _down) {
                    return "#A52416";
                }
                if (_isClose && _hover) {
                    return "#C42B1C";
                }
                if (_down) {
                    return Qt.alpha(Kirigami.Theme.highlightColor, 0.45);
                }
                if (_hover) {
                    return Qt.alpha(Kirigami.Theme.highlightColor, 0.28);
                }
                const a = !enabled ? (root.active ? 0.04 : 0.03) : root.active ? 0.07 : 0.05;
                return Qt.alpha(Kirigami.Theme.textColor, a);
            }
            readonly property real _glyphOpacity: _hover || _down ? 1 : !enabled ? (root.active ? 0.4 : 0.35) : root.active ? 1 : 0.7
            readonly property string _glyphPath: {
                switch (modelData) {
                case "minimize":
                    return "M11.5 16 H20.5";
                case "close":
                    return "M11.5 11.5 L20.5 20.5 M20.5 11.5 L11.5 20.5";
                default:
                    return _restore ? "M12.9 14 H16.1 A1.4 1.4 0 0 1 17.5 15.4 V19.1 A1.4 1.4 0 0 1 16.1 20.5 H12.9 A1.4 1.4 0 0 1 11.5 19.1 V15.4 A1.4 1.4 0 0 1 12.9 14 Z M14 14 V12.9 A1.4 1.4 0 0 1 15.4 11.5 H19.1 A1.4 1.4 0 0 1 20.5 12.9 V16.6 A1.4 1.4 0 0 1 19.1 18 H18" : "M13.3 11.5 H18.7 A1.8 1.8 0 0 1 20.5 13.3 V18.7 A1.8 1.8 0 0 1 18.7 20.5 H13.3 A1.8 1.8 0 0 1 11.5 18.7 V13.3 A1.8 1.8 0 0 1 13.3 11.5 Z";
                }
            }

            // No close button in a kiosk window (AtlasWindow.kiosk).
            // Nor Maximize or Restore: a kiosk window stays full screen.
            visible: !((_isClose || modelData === "maximize") && Window.window && Window.window["kiosk"] === true)
            implicitWidth: 32
            implicitHeight: 32
            focusPolicy: Qt.NoFocus
            hoverEnabled: true

            Accessible.role: Accessible.Button
            Accessible.name: modelData === "minimize" ? qsTr("Minimize") : modelData === "close" ? qsTr("Close") : _restore ? qsTr("Restore") : qsTr("Maximize")
            Accessible.onPressAction: clicked()

            onClicked: {
                if (modelData === "minimize") {
                    root._minimize();
                } else if (modelData === "close") {
                    root._close();
                } else {
                    root._toggleMaximize();
                }
            }

            background: Rectangle {
                x: 3
                y: 3
                width: 26
                height: 26
                radius: 7 // KWin button geometry, kept as the spec
                color: btn._fill
                Behavior on color {
                    enabled: root._animate
                    ColorAnimation {
                        duration: Appearance.reducedMotion ? 0 : 120
                    }
                }
            }
            contentItem: Shape {
                opacity: btn._glyphOpacity
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: btn._glyph
                    strokeWidth: 1.6
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg {
                        path: btn._glyphPath
                    }
                }
            }
        }
    }
}
