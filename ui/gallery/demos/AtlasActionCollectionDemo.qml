import QtQuick
import Atlas.Ui

// AtlasActionCollection read by AtlasShortcutsDialog, with the shortcuts
// editable and one of them changed (so its Reset shows). No settings, so
// nothing is written. Fixed content, no timers. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: 460
    width: implicitWidth
    height: implicitHeight

    AtlasActionCollection {
        id: actions
        shortcutsEditable: true
        AtlasAction { objectName: "new"; text: "New"; shortcut: "Ctrl+N"; section: "File" }
        AtlasAction { objectName: "open"; text: "Open"; shortcut: "Ctrl+O"; section: "File" }
        AtlasAction { objectName: "save"; text: "&Save"; shortcut: "Ctrl+S"; section: "File" }
        AtlasAction { objectName: "copy"; text: "Copy"; shortcut: "Ctrl+C"; section: "Edit" }
        AtlasAction { objectName: "paste"; text: "Paste"; shortcut: "Ctrl+V"; section: "Edit" }
        AtlasAction { objectName: "find"; text: "Find"; shortcut: "Ctrl+F"; category: "Search" }
        Component.onCompleted: setShortcut("save", "Ctrl+Alt+S")
    }

    AtlasShortcutsDialog {
        parent: root
        collection: actions
        Component.onCompleted: open()
    }
}
