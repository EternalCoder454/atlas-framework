import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonSlider. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.largeSpacing

        Caption { text: "Default (0.4)" }
        TelamonSlider { value: 0.4 }
        Caption { text: "Minimum" }
        TelamonSlider { value: 0 }
        Caption { text: "Maximum" }
        TelamonSlider { value: 1 }
        Caption { text: "Disabled" }
        TelamonSlider { value: 0.6; enabled: false }
        Caption { text: "Stepped 0 to 10" }
        TelamonSlider { from: 0; to: 10; stepSize: 1; value: 3; snapMode: TelamonSlider.SnapAlways }
        Caption { text: "Vertical" }
        TelamonSlider { orientation: Qt.Vertical; value: 0.7; Layout.preferredHeight: Kirigami.Units.gridUnit * 5 }
    }
}
