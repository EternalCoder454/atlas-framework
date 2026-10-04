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
        AtlasSwitch { checked: false }
        AtlasSwitch { checked: true }
        AtlasSwitch { checked: true; enabled: false }
        AtlasSwitch { checked: false; enabled: false }
    }
}
