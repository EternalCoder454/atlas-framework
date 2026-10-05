import QtQuick
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasCommandPalette open with the query "s". Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: 420
    width: implicitWidth
    height: implicitHeight

    AtlasAction {
        id: save
        text: "&Save"
        symbol: Symbols.Save
        shortcut: "Ctrl+S"
        section: "File"
    }
    AtlasAction {
        id: saveAs
        text: "Save As..."
        symbol: Symbols.SaveAs
        shortcut: "Ctrl+Shift+S"
        section: "File"
    }
    AtlasAction {
        id: openFile
        text: "Open"
        symbol: Symbols.FolderOpen
        shortcut: "Ctrl+O"
        section: "File"
    }
    AtlasAction {
        id: settings
        text: "Settings"
        symbol: Symbols.Settings
        shortcut: "Ctrl+,"
        section: "Application"
    }
    AtlasAction {
        id: paste
        text: "Paste"
        symbol: Symbols.ContentPaste
        enabled: false
    }

    AtlasCommandPalette {
        parent: root
        actions: [save, saveAs, openFile, settings, paste]
        Component.onCompleted: {
            query = "s";
            open();
        }
    }
}
