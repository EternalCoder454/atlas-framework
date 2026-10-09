import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonPasswordStrength: every score, nothing typed and a
// custom label, under a password field. Fixed content; `animate` is switched
// off by tests/visual before the picture.
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
        width: Kirigami.Units.gridUnit * 18
        spacing: Kirigami.Units.smallSpacing

        TelamonPasswordField {
            Layout.fillWidth: true
            text: "correct horse"
            placeholderText: qsTr("Password")
        }
        TelamonPasswordStrength {
            Layout.fillWidth: true
            score: 3
        }
        Caption { text: "Nothing typed (-1)" }
        TelamonPasswordStrength { Layout.fillWidth: true; score: -1 }
        Caption { text: "0" }
        TelamonPasswordStrength { Layout.fillWidth: true; score: 0 }
        Caption { text: "1" }
        TelamonPasswordStrength { Layout.fillWidth: true; score: 1 }
        Caption { text: "2" }
        TelamonPasswordStrength { Layout.fillWidth: true; score: 2 }
        Caption { text: "4" }
        TelamonPasswordStrength { Layout.fillWidth: true; score: 4 }
        Caption { text: "Custom label" }
        TelamonPasswordStrength { Layout.fillWidth: true; score: 2; text: "Needs a number" }
    }
}
