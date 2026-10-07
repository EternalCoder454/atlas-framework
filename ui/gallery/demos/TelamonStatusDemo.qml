import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonStatus: each view with a status in place of its
// rows. The Loading list shows its spinner only after 300 ms, so tests (which
// set `animate` to false before the picture) see it as Ready and empty.
Item {
    id: root

    property bool animate: true

    implicitWidth: 840
    implicitHeight: 690
    width: implicitWidth
    height: implicitHeight

    TelamonAction {
        id: retry
        text: "Retry"
        symbol: Symbols.Refresh
    }
    TelamonAction {
        id: clearSearch
        text: "Clear search"
    }
    ListModel {
        id: rows
        ListElement { name: "firefox"; cpu: 12.5 }
        ListElement { name: "systemd"; cpu: 0.1 }
    }
    TelamonTreeModel {
        id: noFiles
        items: []
    }

    component Caption: QQC2.Label {
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        columns: 2
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.gridUnit

        Caption { text: "AtlasListView: Empty, with an action" }
        Caption { text: "DataTable: NoResults, header kept" }
        TelamonListView {
            Layout.fillWidth: true
            Layout.preferredHeight: 250
            model: []
            status: TelamonStatus.Empty
            statusTitle: "No files"
            statusText: "Files you download will show up here."
            statusAction: clearSearch
            Accessible.name: "Files"
        }
        DataTable {
            Layout.fillWidth: true
            Layout.preferredHeight: 250
            model: rows
            status: TelamonStatus.NoResults
            statusText: "Nothing matches \"fox\"."
            statusAction: clearSearch
            columns: [
                { title: "Name", role: "name", fill: true },
                { title: "CPU", role: "cpu", width: 5, align: Qt.AlignRight }
            ]
            Accessible.name: "Processes"
        }

        Caption { text: "AtlasTreeView: Error" }
        Caption { text: "AtlasPage: Error, title kept" }
        TelamonTreeView {
            Layout.fillWidth: true
            Layout.preferredHeight: 250
            model: noFiles
            status: TelamonStatus.Error
            statusText: "The folder could not be read."
            statusAction: retry
            Accessible.name: "Folders"
        }
        TelamonPage {
            Layout.fillWidth: true
            Layout.preferredHeight: 250
            title: "Updates"
            status: TelamonStatus.Error
            statusText: "Checking for updates failed."
            statusAction: retry
        }

        Caption { text: "AtlasListView: Loading (spinner after 300 ms)" }
        Caption { text: "" }
        TelamonListView {
            Layout.fillWidth: true
            // Only a spinner: the scene stays inside the 700 px test stage.
            Layout.preferredHeight: 80
            model: []
            status: root.animate ? TelamonStatus.Loading : TelamonStatus.Ready
            statusText: "Reading the folder"
            Accessible.name: "Loading files"
        }
        Item {
            Layout.fillWidth: true
        }
    }
}
