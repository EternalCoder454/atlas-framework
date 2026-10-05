import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasFileField and AtlasFolderField. Tests set `animate` to false.
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
        AtlasFileField { path: "/home/user/Documents/report.pdf" }
        Caption { text: "File, empty (placeholder)" }
        AtlasFileField { placeholderText: qsTr("Choose a file") }
        Caption { text: "File, not editable" }
        AtlasFileField { path: "/home/user/Documents/report.pdf"; editable: false }
        Caption { text: "Folder" }
        AtlasFolderField { path: "/home/user/Documents" }
        Caption { text: "Folder, empty (placeholder)" }
        AtlasFolderField { placeholderText: qsTr("Choose a folder") }
        Caption { text: "Disabled" }
        AtlasFolderField { path: "/home/user/Documents"; enabled: false }
    }
}
