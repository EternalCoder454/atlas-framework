import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonPage: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 480
    implicitHeight: 300
    width: implicitWidth
    height: implicitHeight

    TelamonPage {
        anchors.fill: parent
        title: "Settings"
        subtitle: "Choose how the app looks and behaves."
        headerTrailing: [
            SecondaryButton { text: "Reset" }
        ]
        Section {
            Layout.fillWidth: true
            title: "General"
            SectionRow { title: "Language"; value: "English" }
            SectionRow { title: "Updates"; showSwitch: true; switchChecked: true }
        }
    }
}
