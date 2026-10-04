import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasPasswordField. Tests set `animate` to false.
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

        Caption { text: "Default (empty, placeholder)" }
        AtlasPasswordField { placeholderText: qsTr("Password") }
        Caption { text: "With value (hidden)" }
        AtlasPasswordField { text: "correct horse"; placeholderText: qsTr("Password") }
        Caption { text: "Error" }
        AtlasPasswordField { text: "abc"; placeholderText: qsTr("Password"); errorText: qsTr("Use at least 8 characters") }
        Caption { text: "Disabled" }
        AtlasPasswordField { text: "secret value"; enabled: false }
    }
}
