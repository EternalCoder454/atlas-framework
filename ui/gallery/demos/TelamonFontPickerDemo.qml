import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonFontPicker (the popup is closed). Tests set
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
        TelamonFontPicker { font.family: "Noto Sans"; font.pointSize: 11 }
        Caption { text: "Monospace only" }
        TelamonFontPicker { font.family: "Noto Sans Mono"; font.pointSize: 10; fixedOnly: true }
        Caption { text: "Disabled" }
        TelamonFontPicker { font.family: "Noto Serif"; font.pointSize: 12; enabled: false }
    }
}
