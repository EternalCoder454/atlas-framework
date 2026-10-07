import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for Symbol: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 320
    implicitHeight: 100
    width: implicitWidth
    height: implicitHeight

    RowLayout {
        anchors.centerIn: parent
        spacing: 16
        Symbol { name: "home"; size: 32 }
        Symbol { name: "settings"; size: 32; filled: true }
        Symbol { name: "check_circle"; size: 32; color: Kirigami.Theme.positiveTextColor }
        Symbol { name: "delete"; size: 32; weight: 700 }
        Symbol { name: "favorite"; size: 32; style: Symbol.Outlined }
    }
}
