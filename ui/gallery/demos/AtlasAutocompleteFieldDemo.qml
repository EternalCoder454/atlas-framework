import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasAutocompleteField (the popup is closed: it opens
// while typing). Tests set `animate` to false.
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

        Caption { text: "Empty (placeholder)" }
        AtlasAutocompleteField { model: ["Berlin", "Bern", "Bergen", "Paris"]; placeholderText: qsTr("City") }
        Caption { text: "With text" }
        AtlasAutocompleteField { model: ["Berlin", "Bern", "Bergen", "Paris"]; text: "Ber" }
        Caption { text: "Disabled" }
        AtlasAutocompleteField { model: ["Berlin"]; text: "Ber"; enabled: false }
    }
}
