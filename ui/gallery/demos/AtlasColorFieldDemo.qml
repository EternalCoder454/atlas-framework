import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasColorField. Tests set `animate` to false.
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
        AtlasColorField { color: "#3daee9" } // atlas-lint: allow-raw sample colour
        Caption { text: "Not opaque (showAlpha)" }
        AtlasColorField { color: "#803daee9"; showAlpha: true } // atlas-lint: allow-raw sample colour
        Caption { text: "Disabled" }
        AtlasColorField { color: "#da4453"; enabled: false } // atlas-lint: allow-raw sample colour
    }
}
