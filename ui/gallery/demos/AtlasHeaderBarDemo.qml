import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasHeaderBar: wide with a title, tools and the window buttons; centred
// title; narrow, with tools behind the "more" button; inactive window; and
// without window buttons. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 840
    implicitHeight: col.implicitHeight + Kirigami.Units.gridUnit * 2

    AtlasAction { id: save; text: "Save"; symbol: Symbols.Save; section: "File" }
    AtlasAction { id: open; text: "Open"; symbol: Symbols.FolderOpen; section: "File" }
    AtlasAction { id: undo; text: "Undo"; symbol: Symbols.Undo; section: "Edit" }
    AtlasAction { id: redo; text: "Redo"; symbol: Symbols.Redo; section: "Edit" }
    AtlasAction { id: link; text: "Link"; symbol: Symbols.Link; section: "Insert" }

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        spacing: Kirigami.Units.gridUnit

        AtlasHeaderBar {
            Layout.preferredWidth: 600
            title: "Notes"
            active: true
            actions: [save, open, undo, redo, link]
            leading: AtlasAppMenu {
                _forceButton: true
                menus: [{ title: "File", actions: [save, null, open] }]
            }
        }
        AtlasHeaderBar {
            Layout.preferredWidth: 800
            title: "Centred title"
            centerTitle: true
            active: true
            actions: [save, open]
        }
        AtlasHeaderBar {
            Layout.preferredWidth: 300
            title: "Narrow, tools overflow"
            active: true
            actions: [save, open, undo, redo, link]
        }
        AtlasHeaderBar {
            Layout.preferredWidth: 600
            title: "Inactive window"
            active: false
            actions: [save, open]
        }
        AtlasHeaderBar {
            Layout.preferredWidth: 600
            title: "No window buttons"
            active: true
            windowButtons: false
            actions: [undo, redo]
        }
    }
}
