import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonSearchResults with sections, icons, symbols and shortcut hints, and an
// empty list below it. Not part of any build target.
Rectangle {
    id: root

    // Nothing runs by itself; kept so every demo takes the same switch.
    property bool animate: true
    property string last: "(nothing activated)"

    implicitWidth: Kirigami.Units.gridUnit * 40
    implicitHeight: Kirigami.Units.gridUnit * 26
    color: Kirigami.Theme.backgroundColor

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.smallSpacing

        TelamonSearchResults {
            id: results
            objectName: "results"
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 14
            focus: true
            Accessible.name: "Results"
            textRole: "title"
            subtitleRole: "subtitle"
            iconRole: "icon"
            symbolRole: "symbol"
            sectionRole: "kind"
            shortcutRole: "shortcut"
            model: [
                {
                    kind: "Applications",
                    title: "Text Editor",
                    subtitle: "Edit text files",
                    icon: "accessories-text-editor",
                    shortcut: "Ctrl+1"
                },
                {
                    kind: "Applications",
                    title: "Terminal",
                    subtitle: "Run commands",
                    icon: "utilities-terminal",
                    shortcut: "Ctrl+2"
                },
                {
                    kind: "Applications",
                    title: "System Settings",
                    subtitle: "Configure the desktop",
                    icon: "preferences-system"
                },
                {
                    kind: "Files",
                    title: "notes.txt",
                    subtitle: "/home/user/Documents",
                    symbol: Symbols.Description
                },
                {
                    kind: "Files",
                    title: "Projects",
                    subtitle: "/home/user",
                    symbol: Symbols.Folder
                },
                {
                    kind: "Calculator",
                    title: "42",
                    subtitle: "6 × 7",
                    symbol: Symbols.Calculate,
                    shortcut: "Enter"
                }
            ]
            onActivated: index => root.last = "activated " + index
        }
        Text {
            objectName: "status"
            text: root.last
            color: Kirigami.Theme.textColor
            font: Kirigami.Theme.defaultFont
        }
        TelamonSearchResults {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 6
            Accessible.name: "Empty results"
            model: []
            placeholderText: "No Results"
        }
    }
}
