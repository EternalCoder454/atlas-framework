import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasComboBox. Tests set `animate` to false.
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

        Caption { text: "Default (with value)" }
        AtlasComboBox { model: [qsTr("Light"), qsTr("Dark"), qsTr("Automatic")]; currentIndex: 2 }
        Caption { text: "Placeholder (nothing chosen)" }
        AtlasComboBox { model: [qsTr("Light"), qsTr("Dark")]; currentIndex: -1; placeholderText: qsTr("Choose a theme") }
        Caption { text: "Disabled" }
        AtlasComboBox { model: [qsTr("Light")]; enabled: false }
        Caption { text: "Long text" }
        AtlasComboBox { model: ["A very long choice that cannot fit in the combo box"]; Layout.preferredWidth: Kirigami.Units.gridUnit * 10 }
        Caption { text: "Empty model" }
        AtlasComboBox { model: []; placeholderText: qsTr("No choices") }
    }
}
