import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasCheckBox. Tests set `animate` to false.
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
        AtlasCheckBox { text: qsTr("Unchecked") }
        AtlasCheckBox { text: qsTr("Checked"); checked: true }
        AtlasCheckBox { text: qsTr("Indeterminate"); tristate: true; checkState: Qt.PartiallyChecked }
        Caption { text: "Disabled" }
        AtlasCheckBox { text: qsTr("Disabled"); enabled: false }
        AtlasCheckBox { text: qsTr("Disabled and checked"); enabled: false; checked: true }
        Caption { text: "Long text" }
        AtlasCheckBox { text: "A very long label that does not fit and is cut off"; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
        Caption { text: "No text" }
        AtlasCheckBox { checked: true; Accessible.name: qsTr("Option") } // no visible label: the app names it
    }
}
