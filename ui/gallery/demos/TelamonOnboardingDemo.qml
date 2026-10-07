import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonOnboarding with three pages, on the second: the step column, then the
// dots with custom labels and a busy Next. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: Kirigami.Units.gridUnit * 44
    // Two onboardings, about 280 px each: short enough for the 700 px test scene.
    implicitHeight: Kirigami.Units.gridUnit * 34
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.gridUnit

        TelamonOnboarding {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: 1

            Item {
                property string title: qsTr("Welcome")
                QQC2.Label { text: qsTr("Welcome to Telamon") }
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
                    TelamonTextField {
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

        TelamonOnboarding {
            Layout.fillWidth: true
            Layout.fillHeight: true
            stepStyle: TelamonOnboarding.Dots
            currentIndex: 1
            nextText: qsTr("Continue")
            backText: qsTr("Previous")
            busy: true
            autoAdvance: false
            _spinnerAnimated: root.animate

            Item {
                property string title: qsTr("Welcome")
                QQC2.Label { text: qsTr("Welcome to Telamon") }
            }
            Item {
                property string title: qsTr("Network")
                QQC2.Label { text: qsTr("Checking the connection") }
            }
            Item {
                property string title: qsTr("Done")
                QQC2.Label { text: qsTr("All set") }
            }
        }
    }
}
