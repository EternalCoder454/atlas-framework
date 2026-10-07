import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for InfoBanner: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 480
    implicitHeight: 190
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8
        InfoBanner { Layout.fillWidth: true; type: "info"; text: "An update is available." }
        InfoBanner { Layout.fillWidth: true; type: "warning"; text: "The disk is almost full."; closable: true; closeName: "Dismiss" }
        InfoBanner { Layout.fillWidth: true; type: "error"; text: "The download failed." }
    }
}
