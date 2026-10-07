import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonShortcutsDialog open over a few sections of actions. Fixed content, no
// timers or randomness. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: 460
    width: implicitWidth
    height: implicitHeight

    TelamonAction { text: "New"; shortcut: "Ctrl+N"; section: "File" }
    TelamonAction { text: "Open"; shortcut: "Ctrl+O"; section: "File" }
    TelamonAction { text: "&Save"; shortcut: "Ctrl+S"; section: "File" }
    TelamonAction { text: "Quit"; shortcut: "Ctrl+Q"; section: "File" }
    TelamonAction { text: "Copy"; shortcut: "Ctrl+C"; section: "Edit" }
    TelamonAction { text: "Paste"; shortcut: "Ctrl+V"; section: "Edit" }
    TelamonAction { text: "Find"; shortcut: "Ctrl+F" }
    TelamonAction { text: "No shortcut, not listed" }

    TelamonShortcutsDialog {
        parent: root
        Component.onCompleted: open()
    }
}
