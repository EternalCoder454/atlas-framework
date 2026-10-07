import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonFileField and TelamonFolderField. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.largeSpacing

        Caption { text: "File" }
        TelamonFileField { path: "/home/user/Documents/report.pdf" }
        Caption { text: "File, empty (placeholder)" }
        TelamonFileField { placeholderText: qsTr("Choose a file") }
        Caption { text: "File, not editable" }
        TelamonFileField { path: "/home/user/Documents/report.pdf"; editable: false }
        Caption { text: "Folder" }
        TelamonFolderField { path: "/home/user/Documents" }
        Caption { text: "Folder, empty (placeholder)" }
        TelamonFolderField { placeholderText: qsTr("Choose a folder") }
        Caption { text: "Disabled" }
        TelamonFolderField { path: "/home/user/Documents"; enabled: false }
    }
}
