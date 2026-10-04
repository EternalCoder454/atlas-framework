import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for SecondaryButton: fixed content, no timers or randomness. `animate`
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
        SecondaryButton { text: "Cancel" }
        SecondaryButton { text: "Details"; icon.name: "documentinfo" }
        SecondaryButton { text: "Off"; enabled: false }
    }
}
