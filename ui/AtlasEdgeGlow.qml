import QtQuick
import org.kde.kirigami as Kirigami

// A soft violet-to-sakura glow along the inside edges of its parent: the
// window-edge glow. It has ONE meaning only: "the system or the app is doing
// something for you right now", such as an update being applied or an update
// that is ready. Never use it for decoration, hover, focus, selection or an
// error. Anything else that wants attention has its own control.
//
// Set `active` while that something is going on. The glow fades in, breathes
// slowly while it is active, and fades out; while inactive nothing is drawn
// and no timer or animation runs. Under reduced motion the glow is static (it
// still shows and hides, without the fade). `animated: false` holds the
// breathing still. In software rendering (AtlasStyle.softwareRendering) it is
// static as well: no fade, no breathing, no running animation. It takes no
// input and is hidden from screen readers: say what is happening in text as
// well (a label, an AtlasStatusHero).
//
// Size it to the parent, and put it last in the window's content so that it
// draws above the rest:
//
//   AtlasEdgeGlow { anchors.fill: parent; active: updater.applying }
//
// It is drawn with stacked gradient rectangles (no shader), so it also works
// with the software renderer.
Item {
    id: root

    // True while the system or the app is working for the user.
    property bool active: false
    // False holds the breathing still (a screenshot); the glow stays visible.
    property bool animated: true
    // How far the glow reaches in from each edge, in pixels. The four edges
    // overlap in the corners by design, so a corner is a little brighter.
    property real reach: AtlasStyle.spacingXXLarge * 1.5

    // 0 to 1: how far the glow has faded in.
    property real _shown: root.active ? 1 : 0
    // 0 to 1: the breathing (1 is the brightest).
    property real _breath: 1
    readonly property bool _breathing: root.active && root.animated && !AtlasStyle.reducedMotion && !AtlasStyle.softwareRendering && root.visible

    visible: _shown > 0
    opacity: _shown * (0.6 + 0.4 * _breath)
    Accessible.ignored: true

    Behavior on _shown {
        enabled: !AtlasStyle.softwareRendering
        NumberAnimation {
            duration: AtlasStyle.durationLong
        }
    }

    SequentialAnimation on _breath {
        running: root._breathing
        loops: Animation.Infinite
        NumberAnimation {
            to: 0
            duration: AtlasStyle.durationLong * 10
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 1
            duration: AtlasStyle.durationLong * 10
            easing.type: Easing.InOutSine
        }
        onRunningChanged: if (!running) root._breath = 1
    }

    // One edge: strongest at the window's edge, gone by `reach`. `reversed` is
    // for the bottom and trailing edges, whose window edge is at position 1.
    component Edge: Rectangle {
        required property color tone
        required property bool reversed
        // True for the top and bottom edges (the gradient runs down the strip),
        // false for the left and right ones.
        required property bool vertical
        readonly property real _a: AtlasStyle.highContrast ? 0.8 : 0.5
        gradient: Gradient {
            orientation: vertical ? Gradient.Vertical : Gradient.Horizontal
            GradientStop {
                position: 0
                color: Qt.alpha(tone, reversed ? 0 : _a)
            }
            GradientStop {
                position: 0.35
                color: Qt.alpha(tone, reversed ? 0.04 : _a * 0.3)
            }
            GradientStop {
                position: 0.65
                color: Qt.alpha(tone, reversed ? _a * 0.3 : 0.04)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(tone, reversed ? _a : 0)
            }
        }
    }

    // Violet on the top and leading edges, sakura on the bottom and trailing
    // ones: the colour runs across the window corner to corner.
    Edge {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.reach
        tone: AtlasStyle.accent
        reversed: false
        vertical: true
    }
    Edge {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.reach
        tone: AtlasStyle.sakura
        reversed: true
        vertical: true
    }
    Edge {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.reach
        tone: AtlasStyle.accent
        reversed: false
        vertical: false
    }
    Edge {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.reach
        tone: AtlasStyle.sakura
        reversed: true
        vertical: false
    }
}
