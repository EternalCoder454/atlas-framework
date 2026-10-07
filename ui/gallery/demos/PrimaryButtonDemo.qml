import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for PrimaryButton: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 360
    implicitHeight: 80
    width: implicitWidth
    height: implicitHeight

    RowLayout {
        anchors.centerIn: parent
        spacing: 10
        PrimaryButton { text: "Install" }
        PrimaryButton { text: "Update"; icon.name: "view-refresh" }
        PrimaryButton { text: "Off"; enabled: false }
    }
}
