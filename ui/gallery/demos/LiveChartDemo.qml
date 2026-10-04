import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for LiveChart: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 360
    implicitHeight: 170
    width: implicitWidth
    height: implicitHeight

    LiveChart {
        anchors.fill: parent
        anchors.margins: 10
        values: [10, 20, 35, 30, 55, 60, 45, 70, 65, 80, 50, 40, 55, 75, 90, 60]
        values2: [5, 8, 12, 10, 20, 25, 18, 30, 28, 35, 20, 15, 22, 30, 40, 25]
        maximum: 100
        label: "Load"
        valueText: "60%"
        topText: "100%"
        spanText: "60 seconds"
    }
}
