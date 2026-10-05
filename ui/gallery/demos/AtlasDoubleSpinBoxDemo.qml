import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasDoubleSpinBox. Tests set `animate` to false.
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

        Caption { text: "Default (two decimals)" }
        AtlasDoubleSpinBox { value: 2.5; locale: Qt.locale("en_US") }
        Caption { text: "One decimal, suffix, editable" }
        AtlasDoubleSpinBox { from: 0; to: 10; value: 1.5; stepSize: 0.5; decimals: 1; editable: true; suffix: " s"; locale: Qt.locale("en_US") }
        Caption { text: "German locale" }
        AtlasDoubleSpinBox { from: 0; to: 10000; value: 1234.5; stepSize: 0.25; editable: true; locale: Qt.locale("de_DE") }
        Caption { text: "At minimum (minus disabled)" }
        AtlasDoubleSpinBox { from: 0; to: 1; value: 0; stepSize: 0.1; decimals: 1; locale: Qt.locale("en_US") }
        Caption { text: "At maximum (plus disabled)" }
        AtlasDoubleSpinBox { from: 0; to: 1; value: 1; stepSize: 0.1; decimals: 1; locale: Qt.locale("en_US") }
        Caption { text: "Disabled" }
        AtlasDoubleSpinBox { value: 5.25; enabled: false; locale: Qt.locale("en_US") }
        Caption { text: "Without buttons, prefix" }
        AtlasDoubleSpinBox { from: 0; to: 1000; value: 42.5; editable: true; showButtons: false; prefix: "$"; locale: Qt.locale("en_US") }
    }
}
