import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonIconGrid over a plain array: folders and files by symbol, and apps by
// theme icon. Not part of any build target.
Rectangle {
    id: root

    // Nothing runs by itself; kept so every demo takes the same switch.
    property bool animate: true
    property string last: "(nothing activated)"

    implicitWidth: Kirigami.Units.gridUnit * 36
    implicitHeight: Kirigami.Units.gridUnit * 22
    color: Kirigami.Theme.backgroundColor

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.smallSpacing

        TelamonIconGrid {
            objectName: "grid"
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            Accessible.name: "Files"
            textRole: "name"
            iconRole: "icon"
            symbolRole: "symbol"
            model: [
                {
                    name: "Documents",
                    symbol: Symbols.Folder
                },
                {
                    name: "Pictures",
                    symbol: Symbols.Folder
                },
                {
                    name: "notes.txt",
                    symbol: Symbols.Description
                },
                {
                    name: "A file with a very long name indeed.tar.gz",
                    symbol: Symbols.Description
                },
                {
                    name: "Text Editor",
                    icon: "accessories-text-editor"
                },
                {
                    name: "Terminal",
                    icon: "utilities-terminal"
                },
                {
                    name: "Settings",
                    icon: "preferences-system"
                },
                {
                    name: "Music",
                    symbol: Symbols.Folder
                },
                {
                    name: "Videos",
                    symbol: Symbols.Folder
                },
                {
                    name: "report.pdf",
                    symbol: Symbols.Description
                },
                {
                    name: "Downloads",
                    symbol: Symbols.Folder
                },
                {
                    name: "Desktop",
                    symbol: Symbols.Folder
                },
                {
                    name: "photo.png"
                }
            ]
            onActivated: index => root.last = "activated " + index
            onContextMenuRequested: (index, x, y) => root.last = "menu " + index + " at " + Math.round(x) + "," + Math.round(y)
        }
        Text {
            textFormat: Text.PlainText
            objectName: "status"
            text: root.last
            color: Kirigami.Theme.textColor
            font: Kirigami.Theme.defaultFont
        }
    }
}
