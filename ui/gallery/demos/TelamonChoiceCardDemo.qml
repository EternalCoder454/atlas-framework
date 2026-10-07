import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonChoiceCard: a group of three (the middle one
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
            TelamonChoiceCard {
                text: "Light"
                source: Qt.resolvedUrl("images/shot-blue.png")
                QQC2.ButtonGroup.group: group
            }
            TelamonChoiceCard {
                text: "Dark"
                source: Qt.resolvedUrl("images/shot-green.png")
                QQC2.ButtonGroup.group: group
                checked: true
            }
            TelamonChoiceCard {
                text: "Automatic"
                source: Qt.resolvedUrl("images/shot-orange.png")
                QQC2.ButtonGroup.group: group
            }
        }
        RowLayout {
            spacing: Kirigami.Units.gridUnit
            TelamonChoiceCard {
                text: "No picture"
            }
            TelamonChoiceCard {
                text: "Disabled"
                source: Qt.resolvedUrl("images/shot-blue.png")
                aspectRatio: 1
                checked: true
                enabled: false
            }
        }
    }
}
