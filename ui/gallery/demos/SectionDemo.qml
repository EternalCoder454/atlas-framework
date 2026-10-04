import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for Section: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 460
    implicitHeight: 330
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12
        Section {
            Layout.fillWidth: true
            title: "Network"
            footer: "Applies to every connection."
            SectionRow { title: "Wi-Fi"; subtitle: "Connected to Atlas"; value: "5 GHz"; iconName: "network-wireless" }
            SectionRow { title: "Metered"; showSwitch: true; switchChecked: true }
            SectionRow { title: "Proxy"; chevron: true; value: "None" }
        }
        Section {
            Layout.fillWidth: true
            title: "Folded"
            foldable: true
            folded: true
            SectionRow { title: "Hidden" }
        }
    }
}
