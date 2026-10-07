import QtQuick
import QtQuick.Layouts
import Telamon.Ui

// Visual-test scene for the filled (selected) look of a SidebarItem's symbol,
// drawn by the scene graph's GPU renderer (visual-filled-symbols, which runs it
// at scale 1 and 1.7): the picture of a symbol at FILL 1 differs between the
// software renderer and the distance-field text of the GPU one, and only the
// GPU one is what a desktop runs. Each symbol is shown selected and not, so a
// glyph shared between the two states is drawn both ways in one scene. Fixed
// content, no timers or randomness; `animate` is switched off before the grab.
Item {
    id: root

    property bool animate: true

    implicitWidth: 260
    implicitHeight: 330
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 4
        SidebarItem { Layout.fillWidth: true; text: "Sound"; symbol: Symbols.VolumeUp; selected: true }
        SidebarItem { Layout.fillWidth: true; text: "Displays"; symbol: Symbols.Monitor; selected: true }
        SidebarItem { Layout.fillWidth: true; text: "Home"; symbol: Symbols.Home; selected: true }
        SidebarItem { Layout.fillWidth: true; text: "Sound"; symbol: Symbols.VolumeUp }
        SidebarItem { Layout.fillWidth: true; text: "Displays"; symbol: Symbols.Monitor }
        SidebarItem { Layout.fillWidth: true; text: "Home"; symbol: Symbols.Home }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            SidebarItem { text: "Sound"; symbol: Symbols.VolumeUp; compact: true; selected: true }
            SidebarItem { text: "Displays"; symbol: Symbols.Monitor; compact: true; selected: true }
            SidebarItem { text: "Home"; symbol: Symbols.Home; compact: true; selected: true }
        }
    }
}
