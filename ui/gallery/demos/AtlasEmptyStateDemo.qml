import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasEmptyState. Tests set `animate` to false.
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

        Caption { text: "Symbol, title, text, action" }
        AtlasEmptyState {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
            symbol: Symbols.FolderOpen
            title: qsTr("No files")
            text: qsTr("Files you download will show up here.")
            actionText: qsTr("Open Downloads")
        }
        Caption { text: "Without action" }
        AtlasEmptyState {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
            iconName: "edit-find"
            title: qsTr("No results")
            text: qsTr("Try a different search.")
        }
        Caption { text: "Title only" }
        AtlasEmptyState {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
            title: qsTr("Nothing here")
        }
        Caption { text: "Long text" }
        AtlasEmptyState {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
            symbol: Symbols.Error
            title: "A very long title that has to wrap onto a second line"
            text: "A long explanation that goes on for a while so that it wraps over several lines and shows how the block stays centred."
        }
    }
}
