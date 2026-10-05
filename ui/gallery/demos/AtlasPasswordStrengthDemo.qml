import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasPasswordStrength: every score, nothing typed and a
// custom label, under a password field. Fixed content; `animate` is switched
// off by tests/visual before the picture.
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
        width: Kirigami.Units.gridUnit * 18
        spacing: Kirigami.Units.smallSpacing

        AtlasPasswordField {
            Layout.fillWidth: true
            text: "correct horse"
            placeholderText: qsTr("Password")
        }
        AtlasPasswordStrength {
            Layout.fillWidth: true
            score: 3
        }
        Caption { text: "Nothing typed (-1)" }
        AtlasPasswordStrength { Layout.fillWidth: true; score: -1 }
        Caption { text: "0" }
        AtlasPasswordStrength { Layout.fillWidth: true; score: 0 }
        Caption { text: "1" }
        AtlasPasswordStrength { Layout.fillWidth: true; score: 1 }
        Caption { text: "2" }
        AtlasPasswordStrength { Layout.fillWidth: true; score: 2 }
        Caption { text: "4" }
        AtlasPasswordStrength { Layout.fillWidth: true; score: 4 }
        Caption { text: "Custom label" }
        AtlasPasswordStrength { Layout.fillWidth: true; score: 2; text: "Needs a number" }
    }
}
