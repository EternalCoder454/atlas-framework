import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonCopyButton beside the text it copies, with a label (text mode), and disabled. Tests set
// `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 420
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                Layout.fillWidth: true
                text: "flatpak install flathub org.example.App"
                font: Kirigami.Theme.fixedWidthFont
                elide: Text.ElideRight
            }
            TelamonCopyButton {
                text: "flatpak install flathub org.example.App"
            }
        }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                Layout.fillWidth: true
                text: "Details with a label"
                elide: Text.ElideRight
            }
            TelamonCopyButton {
                text: "version 1.5.0, build 42"
                label: qsTr("Copy Details")
            }
        }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label {
                Layout.fillWidth: true
                text: "Disabled"
            }
            TelamonCopyButton {
                text: "never copied"
                enabled: false
            }
        }
    }
}
