import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonSpinBox. Tests set `animate` to false.
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

        Caption { text: "Default" }
        TelamonSpinBox { value: 8 }
        Caption { text: "Editable with suffix" }
        TelamonSpinBox { from: 1; to: 64; value: 16; editable: true; suffix: " GB" }
        Caption { text: "At minimum (minus disabled)" }
        TelamonSpinBox { from: 0; to: 10; value: 0 }
        Caption { text: "At maximum (plus disabled)" }
        TelamonSpinBox { from: 0; to: 10; value: 10 }
        Caption { text: "Disabled" }
        TelamonSpinBox { value: 5; enabled: false }
        Caption { text: "Without buttons" }
        TelamonSpinBox { from: 0; to: 100; value: 42; editable: true; showButtons: false; suffix: " %" }
        Caption { text: "Long number" }
        TelamonSpinBox { from: 0; to: 2000000000; value: 1234567890 }
    }
}
