import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasListView with symbols and subtitles and two rows selected, beside an
// empty one that shows its placeholder. Not part of any build target.
Rectangle {
    id: root

    // Nothing runs by itself; kept so every demo takes the same switch.
    property bool animate: true

    implicitWidth: Kirigami.Units.gridUnit * 36
    implicitHeight: Kirigami.Units.gridUnit * 20
    color: Kirigami.Theme.backgroundColor

    RowLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.gridUnit

        AtlasListView {
            id: list
            objectName: "list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            Accessible.name: "Files"
            selectionMode: AtlasListView.MultiSelection
            textRole: "name"
            subtitleRole: "path"
            symbolRole: "symbol"
            model: [
                {
                    name: "Documents",
                    path: "/home/ada/Documents",
                    symbol: Symbols.Folder
                },
                {
                    name: "notes.txt",
                    path: "/home/ada/notes.txt",
                    symbol: Symbols.Description
                },
                {
                    name: "report.pdf",
                    path: "/home/ada/Documents/report.pdf",
                    symbol: Symbols.Description
                },
                {
                    name: "Pictures",
                    path: "/home/ada/Pictures",
                    symbol: Symbols.Folder
                },
                {
                    name: "A file with a very long name that does not fit the row.tar.gz",
                    path: "/home/ada/Downloads",
                    symbol: Symbols.Description
                }
            ]
            Component.onCompleted: {
                select(1);
                _toggle(3);
            }
        }
        AtlasListView {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            Layout.fillHeight: true
            Accessible.name: "Empty list"
            model: []
            placeholderText: "Nothing here"
            placeholderSymbol: Symbols.FolderOpen
        }
    }
}
