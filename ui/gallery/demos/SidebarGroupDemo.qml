import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for SidebarGroup: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 260
    implicitHeight: 250
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 4
        SidebarGroup {
            Layout.fillWidth: true
            text: "System"
            iconName: "computer"
            expanded: true
            SidebarItem { Layout.fillWidth: true; text: "CPU"; sub: true; selected: true }
            SidebarItem { Layout.fillWidth: true; text: "Memory"; sub: true }
        }
        SidebarGroup {
            Layout.fillWidth: true
            text: "Storage"
            iconName: "drive-harddisk"
            expanded: false
            SidebarItem { Layout.fillWidth: true; text: "Hidden"; sub: true }
        }
        SidebarGroup {
            Layout.fillWidth: true
            text: "Network"
            symbol: Symbols.codepoint("home")
            badge: "dialog-warning"
            badgeText: "1 problem"
            expanded: false
            SidebarItem { Layout.fillWidth: true; text: "eth0"; sub: true }
        }
    }
}
