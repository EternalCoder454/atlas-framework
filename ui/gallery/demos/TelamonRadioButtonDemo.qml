import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonRadioButton. Tests set `animate` to false.
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

        Caption { text: "Group" }
        TelamonRadioButton { text: qsTr("Light") }
        TelamonRadioButton { text: qsTr("Dark"); checked: true }
        Caption { text: "Disabled" }
        TelamonRadioButton { text: qsTr("Disabled"); enabled: false }
        TelamonRadioButton { text: qsTr("Disabled and checked"); enabled: false; checked: true; autoExclusive: false }
        Caption { text: "Long text" }
        TelamonRadioButton { text: "A very long label that does not fit and is cut off"; Layout.preferredWidth: Kirigami.Units.gridUnit * 12; autoExclusive: false }
    }
}
