import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonProgressBar: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 320
    implicitHeight: 260
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14
        TelamonProgressBar { Layout.fillWidth: true; animated: root.animate; value: 0 }
        TelamonProgressBar { Layout.fillWidth: true; animated: root.animate; value: 0.35 }
        TelamonProgressBar { Layout.fillWidth: true; animated: root.animate; value: 1 }
        TelamonProgressBar { Layout.fillWidth: true; animated: root.animate; value: 0.42; text: "42 %" }
        TelamonProgressBar { Layout.fillWidth: true; value: 0.6; status: "paused"; text: "3 of 5" }
        TelamonProgressBar { Layout.fillWidth: true; value: 0.3; status: "error"; text: "Failed" }
        TelamonProgressBar { Layout.fillWidth: true; animated: root.animate; indeterminate: true; text: "Working" }
        TelamonProgressBar { Layout.fillWidth: true; indeterminate: true; status: "paused"; text: "Paused" }
    }
}
