import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonTransparencySwitch: fixed content, no timers or
// randomness. Without a compositor (the test environment) the row shows its
// disabled state with the reason.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 120
    width: implicitWidth
    height: implicitHeight

    Section {
        anchors.centerIn: parent
        width: parent.width - 40
        TelamonTransparencySwitch {}
    }
}
