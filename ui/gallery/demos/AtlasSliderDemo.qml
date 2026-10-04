import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasSlider. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.largeSpacing

        Caption { text: "Default (0.4)" }
        AtlasSlider { value: 0.4 }
        Caption { text: "Minimum" }
        AtlasSlider { value: 0 }
        Caption { text: "Maximum" }
        AtlasSlider { value: 1 }
        Caption { text: "Disabled" }
        AtlasSlider { value: 0.6; enabled: false }
        Caption { text: "Stepped 0 to 10" }
        AtlasSlider { from: 0; to: 10; stepSize: 1; value: 3; snapMode: AtlasSlider.SnapAlways }
        Caption { text: "Vertical" }
        AtlasSlider { orientation: Qt.Vertical; value: 0.7; Layout.preferredHeight: Kirigami.Units.gridUnit * 5 }
    }
}
