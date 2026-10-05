import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasDropZone. Tests set `animate` to false.
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

        Caption { text: "Idle, with Browse" }
        AtlasDropZone {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            subtitle: qsTr("PNG or JPEG images")
            browseText: qsTr("Browse…")
            nameFilters: ["*.png", "*.jpg"]
        }
        Caption { text: "A drag over it" }
        AtlasDropZone {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            subtitle: qsTr("PNG or JPEG images")
            _forceHover: true
        }
        Caption { text: "A drag it can't accept" }
        AtlasDropZone {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            subtitle: qsTr("PNG or JPEG images")
            _forceReject: true
        }
        Caption { text: "Disabled" }
        AtlasDropZone {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            enabled: false
            symbol: Symbols.FolderOpen
            text: qsTr("Drop a folder here")
        }
    }
}
