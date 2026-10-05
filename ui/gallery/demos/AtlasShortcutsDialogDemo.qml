import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasShortcutsDialog open over a few sections of actions. Fixed content, no
// timers or randomness. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: 460
    width: implicitWidth
    height: implicitHeight

    AtlasAction { text: "New"; shortcut: "Ctrl+N"; section: "File" }
    AtlasAction { text: "Open"; shortcut: "Ctrl+O"; section: "File" }
    AtlasAction { text: "&Save"; shortcut: "Ctrl+S"; section: "File" }
    AtlasAction { text: "Quit"; shortcut: "Ctrl+Q"; section: "File" }
    AtlasAction { text: "Copy"; shortcut: "Ctrl+C"; section: "Edit" }
    AtlasAction { text: "Paste"; shortcut: "Ctrl+V"; section: "Edit" }
    AtlasAction { text: "Find"; shortcut: "Ctrl+F" }
    AtlasAction { text: "No shortcut, not listed" }

    AtlasShortcutsDialog {
        parent: root
        Component.onCompleted: open()
    }
}
