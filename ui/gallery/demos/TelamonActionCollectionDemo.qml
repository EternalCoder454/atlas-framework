import QtQuick
import Telamon.Ui

// TelamonActionCollection read by TelamonShortcutsDialog, with the shortcuts
// editable and one of them changed (so its Reset shows). No settings, so
// nothing is written. Fixed content, no timers. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: 460
    width: implicitWidth
    height: implicitHeight

    TelamonActionCollection {
        id: actions
        shortcutsEditable: true
        TelamonAction { objectName: "new"; text: "New"; shortcut: "Ctrl+N"; section: "File" }
        TelamonAction { objectName: "open"; text: "Open"; shortcut: "Ctrl+O"; section: "File" }
        TelamonAction { objectName: "save"; text: "&Save"; shortcut: "Ctrl+S"; section: "File" }
        TelamonAction { objectName: "copy"; text: "Copy"; shortcut: "Ctrl+C"; section: "Edit" }
        TelamonAction { objectName: "paste"; text: "Paste"; shortcut: "Ctrl+V"; section: "Edit" }
        TelamonAction { objectName: "find"; text: "Find"; shortcut: "Ctrl+F"; category: "Search" }
        Component.onCompleted: setShortcut("save", "Ctrl+Alt+S")
    }

    TelamonShortcutsDialog {
        parent: root
        collection: actions
        Component.onCompleted: open()
    }
}
