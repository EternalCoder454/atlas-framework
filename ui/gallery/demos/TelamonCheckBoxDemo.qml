import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonCheckBox. Tests set `animate` to false.
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

        Caption { text: "Unchecked / checked / indeterminate" }
        TelamonCheckBox { text: qsTr("Unchecked") }
        TelamonCheckBox { text: qsTr("Checked"); checked: true }
        TelamonCheckBox { text: qsTr("Indeterminate"); tristate: true; checkState: Qt.PartiallyChecked }
        Caption { text: "Disabled" }
        TelamonCheckBox { text: qsTr("Disabled"); enabled: false }
        TelamonCheckBox { text: qsTr("Disabled and checked"); enabled: false; checked: true }
        Caption { text: "Long text" }
        TelamonCheckBox { text: "A very long label that does not fit and is cut off"; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
        Caption { text: "No text" }
        TelamonCheckBox { checked: true; Accessible.name: qsTr("Option") } // no visible label: the app names it
    }
}
