import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonTextArea. Tests set `animate` to false.
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
        TelamonTextArea { placeholderText: qsTr("Notes"); Layout.preferredWidth: Kirigami.Units.gridUnit * 16 }
        Caption { text: "With value" }
        TelamonTextArea { text: "First line\nSecond line"; Layout.preferredWidth: Kirigami.Units.gridUnit * 16 }
        Caption { text: "Long text (wraps)" }
        TelamonTextArea { text: "A long paragraph that keeps going so it has to wrap onto several lines inside the rounded field, showing how the height grows with the text."; Layout.preferredWidth: Kirigami.Units.gridUnit * 16 }
        Caption { text: "Disabled" }
        TelamonTextArea { text: "Not editable"; enabled: false; Layout.preferredWidth: Kirigami.Units.gridUnit * 16 }
    }
}
