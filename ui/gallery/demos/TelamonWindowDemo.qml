import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonWindow. The one demo whose root is a window: the
// harness shows it and grabs the whole window.
TelamonWindow {
    id: root

    property bool animate: true

    width: 480
    height: 300
    title: "Telamon window"
    visible: false

    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 140
            color: root.sidebarColor(Kirigami.Theme.backgroundColor)
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                SidebarItem { Layout.fillWidth: true; text: "Overview"; icon.name: "go-home"; selected: true }
                SidebarItem { Layout.fillWidth: true; text: "Updates"; icon.name: "update-none" }
                Item { Layout.fillHeight: true }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            Section {
                Layout.fillWidth: true
                title: "General"
                SectionRow { title: "Language"; value: "English" }
            }
            Item { Layout.fillHeight: true }
        }
    }
}
