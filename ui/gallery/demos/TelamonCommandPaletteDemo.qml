import QtQuick
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonCommandPalette open with the query "s". Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: 420
    width: implicitWidth
    height: implicitHeight

    TelamonAction {
        id: save
        text: "&Save"
        symbol: Symbols.Save
        shortcut: "Ctrl+S"
        section: "File"
    }
    TelamonAction {
        id: saveAs
        text: "Save As..."
        symbol: Symbols.SaveAs
        shortcut: "Ctrl+Shift+S"
        section: "File"
    }
    TelamonAction {
        id: openFile
        text: "Open"
        symbol: Symbols.FolderOpen
        shortcut: "Ctrl+O"
        section: "File"
    }
    TelamonAction {
        id: settings
        text: "Settings"
        symbol: Symbols.Settings
        shortcut: "Ctrl+,"
        section: "Application"
    }
    TelamonAction {
        id: paste
        text: "Paste"
        symbol: Symbols.ContentPaste
        enabled: false
    }

    TelamonCommandPalette {
        parent: root
        actions: [save, saveAs, openFile, settings, paste]
        Component.onCompleted: {
            query = "s";
            open();
        }
    }
}
