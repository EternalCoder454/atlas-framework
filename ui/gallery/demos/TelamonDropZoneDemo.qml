import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonDropZone. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    // Two columns: four zones stacked are taller than the test window.
    GridLayout {
        id: layout
        anchors.centerIn: parent
        columns: 2
        flow: GridLayout.TopToBottom
        rows: 4
        rowSpacing: Kirigami.Units.largeSpacing
        columnSpacing: Kirigami.Units.gridUnit

        Caption { text: "Idle, with Browse" }
        TelamonDropZone {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            subtitle: qsTr("PNG or JPEG images")
            browseText: qsTr("Browse…")
            nameFilters: ["*.png", "*.jpg"]
        }
        Caption { text: "A drag over it" }
        TelamonDropZone {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            subtitle: qsTr("PNG or JPEG images")
            _forceHover: true
        }
        Caption { text: "A drag it can't accept" }
        TelamonDropZone {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            subtitle: qsTr("PNG or JPEG images")
            _forceReject: true
        }
        Caption { text: "Disabled" }
        TelamonDropZone {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            enabled: false
            symbol: Symbols.FolderOpen
            text: qsTr("Drop a folder here")
        }
    }
}
