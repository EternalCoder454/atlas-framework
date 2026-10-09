import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonHeaderBar: wide with a title, tools and the window buttons; centred
// title; narrow, with tools behind the "more" button; inactive window;
// without window buttons; and a stretch row that fills the bar. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 840
    implicitHeight: col.implicitHeight + Kirigami.Units.gridUnit * 2

    TelamonAction { id: save; text: "Save"; symbol: Symbols.Save; section: "File" }
    TelamonAction { id: open; text: "Open"; symbol: Symbols.FolderOpen; section: "File" }
    TelamonAction { id: undo; text: "Undo"; symbol: Symbols.Undo; section: "Edit" }
    TelamonAction { id: redo; text: "Redo"; symbol: Symbols.Redo; section: "Edit" }
    TelamonAction { id: link; text: "Link"; symbol: Symbols.Link; section: "Insert" }

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        spacing: Kirigami.Units.gridUnit

        TelamonHeaderBar {
            Layout.preferredWidth: 600
            title: "Notes"
            active: true
            actions: [save, open, undo, redo, link]
            leading: TelamonAppMenu {
                _forceButton: true
                menus: [{ title: "File", actions: [save, null, open] }]
            }
        }
        TelamonHeaderBar {
            Layout.preferredWidth: 800
            title: "Centred title"
            centerTitle: true
            active: true
            actions: [save, open]
        }
        TelamonHeaderBar {
            Layout.preferredWidth: 300
            title: "Narrow, tools overflow"
            active: true
            actions: [save, open, undo, redo, link]
        }
        TelamonHeaderBar {
            Layout.preferredWidth: 600
            title: "Inactive window"
            active: false
            actions: [save, open]
        }
        TelamonHeaderBar {
            Layout.preferredWidth: 600
            title: "No window buttons"
            active: true
            windowButtons: false
            actions: [undo, redo]
        }
        TelamonHeaderBar {
            Layout.preferredWidth: 600
            showTitle: false
            active: true
            actions: [undo, redo]
            stretch: [
                QQC2.Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: "A stretch row takes the rest of the bar"
                    elide: Text.ElideRight
                }
            ]
        }
    }
}
