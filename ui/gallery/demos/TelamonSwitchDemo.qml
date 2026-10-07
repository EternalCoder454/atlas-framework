import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonSwitch: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 260
    implicitHeight: 90
    width: implicitWidth
    height: implicitHeight

    RowLayout {
        anchors.centerIn: parent
        spacing: 20
        TelamonSwitch { Accessible.name: "Demo switch"; checked: false }
        TelamonSwitch { Accessible.name: "Demo switch"; checked: true }
        TelamonSwitch { Accessible.name: "Demo switch"; checked: true; enabled: false }
        TelamonSwitch { Accessible.name: "Demo switch"; checked: false; enabled: false }
    }
}
