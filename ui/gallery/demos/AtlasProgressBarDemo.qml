import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasProgressBar: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 320
    implicitHeight: 230
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14
        AtlasProgressBar { Layout.fillWidth: true; value: 0 }
        AtlasProgressBar { Layout.fillWidth: true; value: 0.35 }
        AtlasProgressBar { Layout.fillWidth: true; value: 1 }
        AtlasProgressBar { Layout.fillWidth: true; value: 0.42; text: "42 %" }
        AtlasProgressBar { Layout.fillWidth: true; value: 0.6; status: "paused"; text: "3 of 5" }
        AtlasProgressBar { Layout.fillWidth: true; value: 0.3; status: "error"; text: "Failed" }
        AtlasProgressBar { Layout.fillWidth: true; indeterminate: true; status: "paused"; text: "Paused" }
    }
}
