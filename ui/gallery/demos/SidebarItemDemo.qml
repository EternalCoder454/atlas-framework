import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for SidebarItem: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
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
        SidebarItem { Layout.fillWidth: true; text: "Overview"; icon.name: "go-home"; selected: true }
        SidebarItem { Layout.fillWidth: true; text: "Updates"; icon.name: "update-none"; badge: "3" }
        SidebarItem { Layout.fillWidth: true; text: "Disk"; icon.name: "drive-harddisk"; value: "62%" }
        SidebarItem { Layout.fillWidth: true; text: "Sub item"; sub: true }
        SidebarItem { Layout.fillWidth: true; text: "Symbol"; symbol: Symbols.codepoint("settings") }
        SidebarItem { text: "Compact"; icon.name: "drive-harddisk"; value: "62%"; compact: true }
        SidebarItem { Layout.fillWidth: true; text: "Off"; icon.name: "dialog-error"; enabled: false }
    }
}
