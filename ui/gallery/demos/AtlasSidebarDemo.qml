import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasSidebar: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: 330
    width: implicitWidth
    height: implicitHeight

    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 20

        AtlasSidebar {
            Layout.preferredWidth: 250
            Layout.fillHeight: true
            SidebarItem { Layout.fillWidth: true; text: "Overview"; symbol: Symbols.codepoint("home"); selected: true }
            SidebarItem { Layout.fillWidth: true; text: "Updates"; symbol: Symbols.codepoint("update"); value: "3" }
            SidebarGroup {
                text: "Disk"
                iconName: "drive-harddisk"
                SidebarItem { Layout.fillWidth: true; text: "sda"; sub: true }
                SidebarItem { Layout.fillWidth: true; text: "sdb"; sub: true }
            }
            SidebarItem { Layout.fillWidth: true; text: "Settings"; symbol: Symbols.codepoint("settings") }
        }

        AtlasSidebar {
            Layout.preferredWidth: 250
            Layout.fillHeight: true
            filterText: "zzz"
            placeholderText: "No matches"
            placeholderSymbol: Symbols.codepoint("search")
            SidebarItem { Layout.fillWidth: true; text: "Overview"; symbol: Symbols.codepoint("home") }
            SidebarItem { Layout.fillWidth: true; text: "Updates"; symbol: Symbols.codepoint("update") }
        }
    }
}
