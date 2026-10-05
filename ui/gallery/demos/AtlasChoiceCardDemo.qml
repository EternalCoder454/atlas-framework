import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasChoiceCard: a group of three (the middle one
// chosen), a card with no picture and a disabled one. Fixed content; `animate`
// is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    QQC2.ButtonGroup {
        id: group
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.gridUnit

        RowLayout {
            spacing: Kirigami.Units.gridUnit
            AtlasChoiceCard {
                text: "Light"
                source: Qt.resolvedUrl("images/shot-blue.png")
                QQC2.ButtonGroup.group: group
            }
            AtlasChoiceCard {
                text: "Dark"
                source: Qt.resolvedUrl("images/shot-green.png")
                QQC2.ButtonGroup.group: group
                checked: true
            }
            AtlasChoiceCard {
                text: "Automatic"
                source: Qt.resolvedUrl("images/shot-orange.png")
                QQC2.ButtonGroup.group: group
            }
        }
        RowLayout {
            spacing: Kirigami.Units.gridUnit
            AtlasChoiceCard {
                text: "No picture"
            }
            AtlasChoiceCard {
                text: "Disabled"
                source: Qt.resolvedUrl("images/shot-blue.png")
                aspectRatio: 1
                checked: true
                enabled: false
            }
        }
    }
}
