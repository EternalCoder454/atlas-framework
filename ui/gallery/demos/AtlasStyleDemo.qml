import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import Atlas.Ui

// Visual-test scene for AtlasStyle: the colours, the radii and the four font
// sizes. Fixed content, no timers or randomness. `animate` is switched off by
// tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 460
    implicitHeight: 330
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: AtlasStyle.spacingLarge
        spacing: AtlasStyle.spacingLarge

        Flow {
            Layout.fillWidth: true
            spacing: AtlasStyle.spacingSmall
            Repeater {
                model: [
                    { name: "accent", color: AtlasStyle.accent },
                    { name: "accentText", color: AtlasStyle.accentText },
                    { name: "surface", color: AtlasStyle.surface },
                    { name: "surfaceAlt", color: AtlasStyle.surfaceAlt },
                    { name: "text", color: AtlasStyle.text },
                    { name: "textMuted", color: AtlasStyle.textMuted },
                    { name: "separator", color: AtlasStyle.separator },
                    { name: "success", color: AtlasStyle.success },
                    { name: "warning", color: AtlasStyle.warning },
                    { name: "error", color: AtlasStyle.error }
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    spacing: 2
                    Rectangle {
                        implicitWidth: 78
                        implicitHeight: 32
                        radius: AtlasStyle.radiusSmall
                        color: parent.modelData.color
                        border.width: 1
                        border.color: AtlasStyle.separator
                    }
                    QQC2.Label {
                        text: parent.modelData.name
                        font.pointSize: AtlasStyle.fontSizeCaption
                        color: AtlasStyle.textMuted
                    }
                }
            }
        }

        RowLayout {
            spacing: AtlasStyle.spacingLarge
            Repeater {
                model: [
                    { name: "small", r: AtlasStyle.radiusSmall },
                    { name: "radius", r: AtlasStyle.radius },
                    { name: "large", r: AtlasStyle.radiusLarge },
                    { name: "pill", r: AtlasStyle.radiusPill }
                ]
                delegate: Rectangle {
                    id: box
                    required property var modelData
                    implicitWidth: 80
                    implicitHeight: 40
                    radius: Math.min(modelData.r, height / 2)
                    color: AtlasStyle.surface
                    border.width: 1
                    border.color: AtlasStyle.separator
                    QQC2.Label {
                        anchors.centerIn: parent
                        text: box.modelData.name
                        font.pointSize: AtlasStyle.fontSizeCaption
                    }
                }
            }
        }

        ColumnLayout {
            spacing: AtlasStyle.spacingSmall
            QQC2.Label { text: "Title"; font.pointSize: AtlasStyle.fontSizeTitle; font.bold: true }
            QQC2.Label { text: "Heading"; font.pointSize: AtlasStyle.fontSizeHeading; font.bold: true }
            QQC2.Label { text: "Body text"; font.pointSize: AtlasStyle.fontSizeBody }
            QQC2.Label { text: "Caption"; font.pointSize: AtlasStyle.fontSizeCaption; color: AtlasStyle.textMuted }
        }
        Item { Layout.fillHeight: true }
    }
}
