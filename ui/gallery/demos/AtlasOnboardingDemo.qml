import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasOnboarding with three pages, on the second. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: Kirigami.Units.gridUnit * 44
    implicitHeight: Kirigami.Units.gridUnit * 28

    AtlasOnboarding {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        currentIndex: 1

        Item {
            property string title: qsTr("Welcome")
            QQC2.Label { text: qsTr("Welcome to Atlas") }
        }
        Item {
            property string title: qsTr("Account")
            property bool skippable: true
            ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Kirigami.Units.largeSpacing
                QQC2.Label {
                    text: qsTr("Choose a name")
                    font.bold: true
                }
                AtlasTextField {
                    Layout.fillWidth: true
                    placeholderText: qsTr("Your name")
                }
            }
        }
        Item {
            property string title: qsTr("Done")
            QQC2.Label { text: qsTr("All set") }
        }
    }
}
