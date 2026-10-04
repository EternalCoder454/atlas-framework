import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for MiniBars: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 320
    implicitHeight: 110
    width: implicitWidth
    height: implicitHeight

    MiniBars {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6
        values: [12, 55, 90, 33, 70, 5, 100, 48]
        maximum: 100
    }
}
