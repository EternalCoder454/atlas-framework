import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A rounded progress bar in the accent colour. `value` runs from 0 to 1;
// `indeterminate` slides a short segment back and forth instead. `text` is a
// label shown beside the bar ("3 of 10", "42 %"), elided when short of room
// and placed on the trailing side. `status` is "normal", "paused" (muted fill,
// no motion) or "error" (error colour); a screen reader hears it too.
//
//   AtlasProgressBar { value: done / total; text: qsTr("%1 of %2").arg(done).arg(total) }
//   AtlasProgressBar { value: 0.4; status: "error"; text: qsTr("Failed") }
Item {
    id: root

    property real value: 0
    property bool indeterminate: false
    property string text
    // "normal" | "paused" | "error"
    property string status: "normal"

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

    RowLayout {
        anchors.fill: parent
        spacing: AtlasStyle.spacingLarge

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 4

            Rectangle {
                id: track
                width: parent.width
                height: Math.round(Kirigami.Units.gridUnit * 0.45)
                anchors.verticalCenter: parent.verticalCenter
                radius: AtlasStyle.radiusPill
                color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
                clip: true

                Rectangle {
                    visible: !root.indeterminate
                    height: parent.height
                    radius: AtlasStyle.radiusPill
                    x: Qt.locale().textDirection === Qt.RightToLeft ? parent.width - width : 0
                    width: root.indeterminate ? 0 : root.value > 0 ? Math.max(height, parent.width * Math.min(1, root.value)) : 0
                    color: root._fillColor
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
                    SequentialAnimation on x {
                        running: root.indeterminate && root.status !== "paused" && root.visible && AtlasStyle.duration > 0
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
