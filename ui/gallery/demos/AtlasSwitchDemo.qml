import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasSwitch: fixed content, no timers or randomness. `animate`
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
        AtlasSwitch { Accessible.name: "Demo switch"; checked: false }
        AtlasSwitch { Accessible.name: "Demo switch"; checked: true }
        AtlasSwitch { Accessible.name: "Demo switch"; checked: true; enabled: false }
        AtlasSwitch { Accessible.name: "Demo switch"; checked: false; enabled: false }
    }
}
