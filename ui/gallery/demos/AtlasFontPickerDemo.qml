import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasFontPicker (the popup is closed). Tests set
// `animate` to false.
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

        Caption { text: "Default" }
        AtlasFontPicker { font.family: "Noto Sans"; font.pointSize: 11 }
        Caption { text: "Monospace only" }
        AtlasFontPicker { font.family: "Noto Sans Mono"; font.pointSize: 10; fixedOnly: true }
        Caption { text: "Disabled" }
        AtlasFontPicker { font.family: "Noto Serif"; font.pointSize: 12; enabled: false }
    }
}
