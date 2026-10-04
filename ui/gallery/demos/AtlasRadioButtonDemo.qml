import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasRadioButton. Tests set `animate` to false.
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

        Caption { text: "Group" }
        AtlasRadioButton { text: qsTr("Light") }
        AtlasRadioButton { text: qsTr("Dark"); checked: true }
        Caption { text: "Disabled" }
        AtlasRadioButton { text: qsTr("Disabled"); enabled: false }
        AtlasRadioButton { text: qsTr("Disabled and checked"); enabled: false; checked: true; autoExclusive: false }
        Caption { text: "Long text" }
        AtlasRadioButton { text: "A very long label that does not fit and is cut off"; Layout.preferredWidth: Kirigami.Units.gridUnit * 12; autoExclusive: false }
    }
}
