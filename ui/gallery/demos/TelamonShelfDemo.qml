import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonShelf: a row of the default cards, longer than the width so the end
// button shows. Not part of any build target.
Rectangle {
    id: root

    // Nothing runs by itself; the row only scrolls on a press or a key.
    property bool animate: true

    implicitWidth: Kirigami.Units.gridUnit * 40
    implicitHeight: Kirigami.Units.gridUnit * 14
    color: Kirigami.Theme.backgroundColor

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.largeSpacing

        TelamonShelf {
            Layout.fillWidth: true
            title: "Editors' choice"
            model: [
                {
                    name: "Atlas Notepad",
                    summary: "Fast, plain text editing",
                    sizeText: "12 MB",
                    rating: 4.6,
                    verified: true,
                    iconName: "accessories-text-editor"
                },
                {
                    name: "Atlas Monitor",
                    summary: "Processes, memory and disks",
                    sizeText: "8 MB",
                    rating: 4.2,
                    installState: "installed"
                },
                {
                    name: "Atlas Updater",
                    summary: "Keeps AtlasOS up to date",
                    sizeText: "21 MB",
                    installState: "update"
                },
                {
                    name: "Atlas Disks",
                    summary: "Partitions and drives",
                    sizeText: "14 MB",
                    rating: 4.0
                },
                {
                    name: "Atlas Archive",
                    summary: "Zip, tar and more",
                    sizeText: "9 MB"
                }
            ]
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
