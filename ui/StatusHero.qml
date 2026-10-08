import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Big centred status: a round icon badge (with a ring for busy/progress), a
// headline, a subtitle, and the action buttons you put inside.
ColumnLayout {
    id: root

    property string iconName
    property string headline
    property string subtitle
    // Spinning ring while true.
    property bool busy: false
    // 0..1 draws a progress ring; negative means none.
    property real progress: -1
    property color tint: TelamonStyle.accent
    // The badge's diameter in grid units, and its ring's stroke width.
    property real badgeUnits: 5
    property real ringWidth: 4
    // The icon is painted in `tint` (a one-colour symbol). False shows it in
    // its own colours, as a logo.
    property bool iconIsMask: true
    // The pale circle behind the icon. False lets the icon fill the badge.
    property bool showTintCircle: true
    // An icon in a small accent circle on the bottom right corner of the
    // icon (a check, say), ringed in the window colour. Empty: none.
    property string cornerBadgeIcon
    // A thin bar under the subtitle: filled to `progress` (0..1), or a
    // sliding segment while `progress` is negative.
    property bool showBar: false
    // A line under the bar ("120 MB of 300 MB").
    property string barText
    default property alias actions: actionRow.data

    Layout.fillWidth: true
    spacing: TelamonStyle.spacingLarge

    // The headline is the page's state. Say it when it changes, so a screen
    // reader hears the new state without a banner repeating it.
    onHeadlineChanged: {
        if (root.visible && root.headline.length > 0) {
            Accessible.announce(root.headline);
        }
    }

    Item {
        id: badge
        readonly property real size: Math.round(Kirigami.Units.gridUnit * root.badgeUnits)
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: size
        Layout.preferredHeight: size

        Rectangle {
            anchors.fill: parent
            visible: root.showTintCircle
            radius: width / 2
            color: TelamonStyle.alpha(root.tint, 0.14)
        }
        TelamonIcon {
            anchors.centerIn: parent
            width: Math.round(badge.size * (root.showTintCircle ? 0.5 : 0.9))
            height: width
            source: root.iconName
            isMask: root.iconIsMask
            color: root.tint
        }
        // The corner badge: accent circle, white check, and a ring in the
        // window colour that sets it apart from the icon.
        Rectangle {
            id: corner
            readonly property real ringWidth: Math.max(3, Math.round(badge.size * 0.04))
            visible: root.cornerBadgeIcon.length > 0
            width: Math.round(badge.size * 0.36)
            height: width
            radius: width / 2
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: Math.round(badge.size * 0.04)
            anchors.bottomMargin: Math.round(badge.size * 0.04)
            color: TelamonStyle.accent
            border.width: ringWidth
            border.color: Kirigami.Theme.backgroundColor
            TelamonIcon {
                anchors.centerIn: parent
                width: Math.round(corner.width * 0.6)
                height: width
                source: root.cornerBadgeIcon
                isMask: true
                color: "white"
            }
        }
        Shape {
            id: ring
            anchors.fill: parent
            visible: root.busy || root.progress >= 0
            preferredRendererType: Shape.CurveRenderer
            rotation: 0
            ShapePath {
                strokeColor: root.tint
                strokeWidth: root.ringWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: badge.size / 2
                    centerY: badge.size / 2
                    radiusX: badge.size / 2 - root.ringWidth / 2
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: root.progress >= 0 ? 360 * Math.max(0.02, root.progress) : 100
                }
            }
            RotationAnimator on rotation {
                running: root.visible && root.busy && root.progress < 0 && TelamonStyle.duration > 0 && !TelamonStyle.softwareRendering
                from: 0
                to: 360
                loops: Animation.Infinite
                duration: TelamonStyle.durationLong * 3
            }
            // Software rendering: 30 degree steps at about 12 frames a second.
            Timer {
                interval: 80
                repeat: true
                running: root.visible && root.busy && root.progress < 0 && TelamonStyle.duration > 0 && TelamonStyle.softwareRendering
                onTriggered: ring.rotation = (ring.rotation + 30) % 360
            }
        }
    }

    Kirigami.Heading {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        level: 1
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
        text: root.headline
        textFormat: Text.PlainText
    }
    QQC2.Label {
        Layout.fillWidth: true
        visible: root.subtitle.length > 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        opacity: 0.7
        text: root.subtitle
        textFormat: Text.PlainText
    }
    Item {
        id: bar
        visible: root.showBar
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: TelamonStyle.spacingSmall
        Layout.preferredWidth: Math.min(root.width, Kirigami.Units.gridUnit * 18)
        implicitHeight: 6
        clip: true

        Accessible.role: Accessible.ProgressBar
        Accessible.name: root.headline
        Accessible.description: root.barText

        Rectangle {
            anchors.fill: parent
            radius: TelamonStyle.radiusPill
            color: TelamonStyle.alpha(root.tint, 0.18)
        }
        Rectangle {
            id: fill
            readonly property bool known: root.progress >= 0
            property real slide: 0
            height: parent.height
            radius: TelamonStyle.radiusPill
            color: root.tint
            width: known ? Math.max(height, parent.width * Math.min(1, root.progress)) : parent.width * 0.3
            x: known ? 0 : slide
            Behavior on width {
                enabled: fill.known
                NumberAnimation {
                    duration: TelamonStyle.duration
                    easing.type: Easing.OutCubic
                }
            }
            NumberAnimation on slide {
                running: bar.visible && !fill.known && TelamonStyle.duration > 0 && !TelamonStyle.softwareRendering
                from: -bar.width * 0.3
                to: bar.width
                loops: Animation.Infinite
                duration: TelamonStyle.durationLong * 3
                easing.type: Easing.InOutQuad
            }
            // Software rendering: 20 frames a second at most, no easing.
            Timer {
                interval: 50
                repeat: true
                running: bar.visible && !fill.known && TelamonStyle.duration > 0 && TelamonStyle.softwareRendering
                onTriggered: {
                    const next = fill.slide + bar.width * 1.3 * interval / (TelamonStyle.durationLong * 3);
                    fill.slide = next > bar.width ? -bar.width * 0.3 : next;
                }
            }
        }
    }
    QQC2.Label {
        Layout.fillWidth: true
        visible: root.showBar && root.barText.length > 0
        horizontalAlignment: Text.AlignHCenter
        font.family: TelamonStyle.fontFamily
        font.pointSize: TelamonStyle.fontSizeCaption
        opacity: 0.7
        text: root.barText
        textFormat: Text.PlainText
    }
    // Actions sit side by side when they fit, and stack when they do not.
    GridLayout {
        id: actionRow
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: TelamonStyle.spacingSmall
        columnSpacing: TelamonStyle.spacingLarge
        rowSpacing: TelamonStyle.spacingSmall
        columns: root.sideBySide ? 100 : 1
    }
    readonly property real wideWidth: {
        var w = 0, n = 0;
        for (var i = 0; i < actionRow.children.length; ++i) {
            var c = actionRow.children[i];
            if (c.visible) {
                w += c.implicitWidth;
                n++;
            }
        }
        return w + Math.max(0, n - 1) * TelamonStyle.spacingLarge;
    }
    readonly property bool sideBySide: wideWidth <= root.width
}
