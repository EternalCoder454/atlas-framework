import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for Toast: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 320
    implicitHeight: 160
    width: implicitWidth
    height: implicitHeight

    Toast {
        id: toast
        interval: 3600000
        Component.onCompleted: show("Copied to clipboard")
    }
}
