import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A rounded progress bar in the accent colour. `value` runs from 0 to 1;
// `indeterminate` slides a short segment back and forth instead. `text` is a
// label shown beside the bar ("3 of 10", "42 %"), elided when short of room
// and placed on the trailing side. `status` is "normal", "paused" (muted fill,
// no motion) or "error" (error colour); a screen reader hears it too. Any
// other value is treated as "normal" (and warned about once). Without `text`
// the track fills the item's height; with it the track is a thin bar centred
// beside the label. The fill starts on the right in right-to-left layouts.
// While it is working ("normal", more than 0 and less than 1 or indeterminate)
// a soft violet-to-sakura shimmer travels along the fill; it stops when the
// bar is idle, paused, in error or complete, and under reduced motion (a flat
// accent fill). `animated: false` freezes the shimmer in place.
//
//   AtlasProgressBar { value: done / total; text: qsTr("%1 of %2").arg(done).arg(total) }
//   AtlasProgressBar { value: 0.4; status: "error"; text: qsTr("Failed") }
Item {
    id: root

    property real value: 0
    property bool indeterminate: false
    property string text
    // "normal" | "paused" | "error"; anything else counts as "normal"
    property string status: "normal"
    // Whether the shimmer travels. False holds it still (a screenshot).
    property bool animated: true
    property bool _warned: false
    onStatusChanged: _checkStatus()
    Component.onCompleted: _checkStatus()
    function _checkStatus() {
        if (!_warned && status !== "normal" && status !== "paused" && status !== "error") {
            _warned = true;
            console.warn("AtlasProgressBar: unknown status \"" + status + "\"; use \"normal\", \"paused\" or \"error\"");
        }
    }

    // The shimmer shows while the bar is working, and not under reduced motion.
    readonly property bool _working: status !== "paused" && status !== "error" && (indeterminate || (value > 0 && value < 1))
    readonly property bool _shimmer: _working && !AtlasStyle.reducedMotion
    readonly property color _fillColor: status === "error" ? AtlasStyle.error : status === "paused" ? Qt.alpha(Kirigami.Theme.textColor, 0.4) : AtlasStyle.accent

    implicitWidth: Kirigami.Units.gridUnit * 16
    implicitHeight: Math.max(Math.round(Kirigami.Units.gridUnit * 0.45), label.visible ? label.implicitHeight : 0)

    Accessible.role: Accessible.ProgressBar
    //: Spoken name of a progress bar: %1 is the percent done; "Working" when the time left is unknown
    Accessible.name: root.indeterminate ? qsTr("Working") : qsTr("%1%").arg(Math.round(root.value * 100))
    Accessible.description: {
        const st = root.status === "error" ? qsTr("Error") : root.status === "paused" ? qsTr("Paused") : "";
        return root.text.length > 0 && st.length > 0 ? root.text + ", " + st : root.text.length > 0 ? root.text : st;
    }

    // A bright band, violet to sakura, that crosses its parent (the fill).
    component Shimmer: Rectangle {
        id: band
        // 0 to 1 crosses the fill once.
        property real phase: 0.5
        visible: root._shimmer && !AtlasStyle.softwareRendering
        width: Math.max(parent.width * 0.6, Kirigami.Units.gridUnit * 3)
        height: parent.height
        x: -width + (parent.width + width) * phase
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(AtlasStyle.sakura, 0) }
            GradientStop { position: 0.5; color: Qt.alpha(AtlasStyle.sakura, 0.5) }
            GradientStop { position: 1; color: Qt.alpha(AtlasStyle.accent, 0) }
        }
        NumberAnimation on phase {
            running: root._shimmer && root.animated && root.visible && !AtlasStyle.softwareRendering
            from: 0
            to: 1
            duration: AtlasStyle.durationLong * 7
            loops: Animation.Infinite
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: AtlasStyle.spacingLarge

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: label.visible ? Math.min(Kirigami.Units.gridUnit * 4, root.width * 0.5) : 0

            Rectangle {
                id: track
                width: parent.width
                height: label.visible ? Math.round(Kirigami.Units.gridUnit * 0.45) : parent.height
                anchors.verticalCenter: parent.verticalCenter
                radius: AtlasStyle.radiusPill
                color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
                clip: true

                Rectangle {
                    visible: !root.indeterminate
                    height: parent.height
                    radius: AtlasStyle.radiusPill
                    x: root.LayoutMirroring.enabled ? parent.width - width : 0
                    width: root.indeterminate ? 0 : root.value > 0 ? Math.max(height, parent.width * Math.min(1, root.value)) : 0
                    color: root._fillColor
                    clip: true
                    Shimmer {}
                    Behavior on width {
                        NumberAnimation {
                            duration: AtlasStyle.duration
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Rectangle {
                    id: slider
                    visible: root.indeterminate
                    height: parent.height
                    radius: AtlasStyle.radiusPill
                    width: parent.width * 0.3
                    color: root._fillColor
                    clip: true
                    Shimmer {}
                    // Software rendering: 20 frames a second at most, no easing.
                    Timer {
                        property real cycle: 0
                        interval: 50
                        repeat: true
                        running: root.indeterminate && root.status !== "paused" && root.visible && root.animated && AtlasStyle.duration > 0 && AtlasStyle.softwareRendering
                        // Start where the slider is, not at the left edge.
                        onRunningChanged: if (running) {
                            cycle = Math.min(1, Math.max(0, slider.x / Math.max(1, track.width - slider.width))) / 2;
                        }
                        onTriggered: {
                            cycle = (cycle + interval / (AtlasStyle.durationLong * 4)) % 1;
                            slider.x = Math.max(0, track.width - slider.width) * (cycle < 0.5 ? cycle * 2 : (1 - cycle) * 2);
                        }
                    }
                    SequentialAnimation on x {
                        running: root.indeterminate && root.status !== "paused" && root.visible && root.animated && AtlasStyle.duration > 0 && !AtlasStyle.softwareRendering
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0
                            to: track.width - slider.width
                            duration: AtlasStyle.durationLong * 2
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            from: track.width - slider.width
                            to: 0
                            duration: AtlasStyle.durationLong * 2
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }
        }

        AtlasLabel {
            id: label
            visible: root.text.length > 0
            Layout.maximumWidth: root.width * 0.5
            text: root.text
            textStyle: AtlasLabel.Caption
            elide: Text.ElideRight
            Accessible.ignored: true
        }
    }
}
