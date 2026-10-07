import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import Telamon.Ui

// Visual-test scene for TelamonStyle: the colours, the radii and the four font
// sizes. Fixed content, no timers or randomness. `animate` is switched off by
// tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 460
    implicitHeight: 560
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: TelamonStyle.spacingLarge
        spacing: TelamonStyle.spacingLarge

        Flow {
            Layout.fillWidth: true
            spacing: TelamonStyle.spacingSmall
            Repeater {
                model: [
                    { name: "accent", color: TelamonStyle.accent },
                    { name: "accentText", color: TelamonStyle.accentText },
                    { name: "surface", color: TelamonStyle.surface },
                    { name: "surfaceAlt", color: TelamonStyle.surfaceAlt },
                    { name: "text", color: TelamonStyle.text },
                    { name: "textMuted", color: TelamonStyle.textMuted },
                    { name: "separator", color: TelamonStyle.separator },
                    { name: "success", color: TelamonStyle.success },
                    { name: "warning", color: TelamonStyle.warning },
                    { name: "error", color: TelamonStyle.error }
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    spacing: 2
                    Rectangle {
                        implicitWidth: 78
                        implicitHeight: 32
                        radius: TelamonStyle.radiusSmall
                        color: parent.modelData.color
                        border.width: 1
                        border.color: TelamonStyle.separator
                    }
                    QQC2.Label {
                        text: parent.modelData.name
                        font.pointSize: TelamonStyle.fontSizeCaption
                        color: TelamonStyle.textMuted
                    }
                }
            }
        }

        RowLayout {
            spacing: TelamonStyle.spacingLarge
            Repeater {
                model: [
                    { name: "small", r: TelamonStyle.radiusSmall },
                    { name: "radius", r: TelamonStyle.radius },
                    { name: "large", r: TelamonStyle.radiusLarge },
                    { name: "pill", r: TelamonStyle.radiusPill }
                ]
                delegate: Rectangle {
                    id: box
                    required property var modelData
                    implicitWidth: 80
                    implicitHeight: 40
                    radius: Math.min(modelData.r, height / 2)
                    color: TelamonStyle.surface
                    border.width: 1
                    border.color: TelamonStyle.separator
                    QQC2.Label {
                        anchors.centerIn: parent
                        text: box.modelData.name
                        font.pointSize: TelamonStyle.fontSizeCaption
                    }
                }
            }
        }

        ColumnLayout {
            spacing: TelamonStyle.spacingSmall
            QQC2.Label { text: "Title"; font.pointSize: TelamonStyle.fontSizeTitle; font.bold: true }
            QQC2.Label { text: "Heading"; font.pointSize: TelamonStyle.fontSizeHeading; font.bold: true }
            QQC2.Label { text: "Body text"; font.pointSize: TelamonStyle.fontSizeBody }
            QQC2.Label { text: "Caption"; font.pointSize: TelamonStyle.fontSizeCaption; color: TelamonStyle.textMuted }
        }

        // Density: the same controls forced to Compact (about 75% of the height).
        QQC2.Label { text: "Density: Compact"; font.pointSize: TelamonStyle.fontSizeCaption; color: TelamonStyle.textMuted }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: TelamonStyle.spacingSmall
            SectionRow { Layout.fillWidth: true; density: TelamonStyle.Compact; title: "Compact row"; value: "42" }
            TabBar {
                Layout.fillWidth: true
                density: TelamonStyle.Compact
                model: ListModel {
                    ListElement { title: "One"; modified: false; toolTip: "" }
                    ListElement { title: "Two"; modified: false; toolTip: "" }
                }
                currentIndex: 0
            }
            StatusBar {
                Layout.fillWidth: true
                density: TelamonStyle.Compact
                StatusBarItem { text: "Ln 3, Col 14" }
                Item { Layout.fillWidth: true }
                StatusBarItem { text: "100%" }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
