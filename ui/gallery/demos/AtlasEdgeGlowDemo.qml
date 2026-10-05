import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasEdgeGlow, active and inactive, each inside a window-like panel. Tests
// set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        font: Kirigami.Theme.smallFont
        color: AtlasStyle.textMuted
    }

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.gridUnit

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Caption { text: "Active" }
            Rectangle {
                implicitWidth: 240
                implicitHeight: 170
                color: AtlasStyle.base
                border.width: 1
                border.color: AtlasStyle.separator
                AtlasLabel { anchors.centerIn: parent; text: "Applying update"; textStyle: AtlasLabel.Heading }
                AtlasEdgeGlow { anchors.fill: parent; active: true; animated: root.animate }
            }
        }
        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Caption { text: "Inactive (draws nothing)" }
            Rectangle {
                implicitWidth: 240
                implicitHeight: 170
                color: AtlasStyle.base
                border.width: 1
                border.color: AtlasStyle.separator
                AtlasLabel { anchors.centerIn: parent; text: "Up to date"; textStyle: AtlasLabel.Heading }
                AtlasEdgeGlow { anchors.fill: parent; active: false; animated: root.animate }
            }
        }
    }
}
