import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasAppCard (verified and compact too): not yet installed, installing, installed, a custom action, a
// long name and a symbol instead of an icon. Not part of any build target.
Rectangle {
    id: root

    // Nothing here moves on its own; kept so every demo takes the same switch.
    property bool animate: true

    // Two columns, so the scene stays inside the 900x700 test stage (also
    // at 200 % text).
    implicitWidth: Kirigami.Units.gridUnit * 48
    implicitHeight: columns.implicitHeight + Kirigami.Units.gridUnit * 2
    color: Kirigami.Theme.backgroundColor

    // Row by row, so Tab goes in reading order.
    GridLayout {
        id: columns
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        columns: 2
        rowSpacing: Kirigami.Units.largeSpacing
        columnSpacing: Kirigami.Units.largeSpacing

        AtlasAppCard {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            name: "Atlas Notepad"
            summary: "Fast, plain text editing with tabs and find and replace"
            icon.name: "accessories-text-editor"
            rating: 4.6
            sizeText: "12 MB"
        }
        AtlasAppCard {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            name: "Custom action"
            summary: "Another control in the action slot"
            rating: 5
            actionComponent: Component {
                TextButton {
                    text: "Manage"
                }
            }
        }
        AtlasAppCard {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            name: "Atlas Monitor"
            summary: "Processes, memory and disks"
            symbol: Symbols.Monitor
            rating: 4.2
            sizeText: "8 MB"
            installState: "installing"
            progress: 0.4
        }
        AtlasAppCard {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            name: "Atlas Terminal"
            summary: "Verified by AtlasOS"
            symbol: Symbols.Terminal
            sizeText: "6 MB"
            verified: true
        }
        AtlasAppCard {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            name: "Atlas Updater"
            summary: "Keeps AtlasOS up to date"
            symbol: Symbols.Update
            sizeText: "21 MB"
            installState: "installed"
        }
        AtlasAppCard {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            compact: true
            verified: true
            name: "Atlas Notepad"
            summary: "Fast, plain text editing"
            icon.name: "accessories-text-editor"
            sizeText: "12 MB"
            installState: "update"
        }
        AtlasAppCard {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            name: "An application with a really long name that cannot possibly fit"
            summary: "A summary that is long enough to need two lines, and then a little more so the second line has to be cut short with an ellipsis"
            rating: 3.9
            sizeText: "1.2 GB"
            installState: "update"
        }
        AtlasAppCard {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            compact: true
            name: "A compact row with a really long name that cannot possibly fit"
            summary: "A long summary that has to be cut to one line"
            symbol: Symbols.Monitor
            sizeText: "1.2 GB"
            installState: "removing"
            progress: 0.4
        }
    }
}
