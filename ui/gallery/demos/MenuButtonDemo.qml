import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import QtQuick.Controls as QQC2
import Telamon.Ui

// Visual-test scene for MenuButton: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 260
    implicitHeight: 150
    width: implicitWidth
    height: implicitHeight

    MenuButton {
        x: 16
        y: 16
        text: "Actions"
        QQC2.MenuItem { text: "One" }
    }
}
