import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonColorField. Tests set `animate` to false.
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

        Caption { text: "Default" }
        TelamonColorField { color: "#3daee9" } // telamon-lint: allow-raw sample colour
        Caption { text: "Not opaque (showAlpha)" }
        TelamonColorField { color: "#803daee9"; showAlpha: true } // telamon-lint: allow-raw sample colour
        Caption { text: "Disabled" }
        TelamonColorField { color: "#da4453"; enabled: false } // telamon-lint: allow-raw sample colour
    }
}
