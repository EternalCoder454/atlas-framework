import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasFlowLayout: chips that wrap, and a last item that fills the row.
// Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 420
    implicitHeight: flow.implicitHeight + Kirigami.Units.gridUnit * 2

    AtlasFlowLayout {
        id: flow
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.smallSpacing
        rowSpacing: Kirigami.Units.largeSpacing

        Repeater {
            model: ["Documents", "Pictures", "Music", "Videos", "Downloads", "Projects", "Archive", "Trash"]
            delegate: AtlasButton {
                required property string modelData
                text: modelData
            }
        }
        AtlasTextField {
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 8
            placeholderText: "Fills the rest of its row"
        }
    }
}
