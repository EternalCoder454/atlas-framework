import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for UsageBar: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 380
    implicitHeight: 150
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 16
        UsageBar {
            Layout.fillWidth: true
            values: [40, 25, 10]
            total: 100
            labels: ["Apps", "Cache", "Other"]
            texts: ["40 GB", "25 GB", "10 GB"]
        }
        UsageBar { Layout.fillWidth: true; values: [70]; total: 100 }
    }
}
