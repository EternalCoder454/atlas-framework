import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasTextField. Tests set `animate` to false.
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
        AtlasTextField { placeholderText: qsTr("Name") }
        Caption { text: "With value, clearable" }
        AtlasTextField { text: "Ada Lovelace"; clearable: true; placeholderText: qsTr("Name") }
        Caption { text: "Error" }
        AtlasTextField { text: "ada@"; placeholderText: qsTr("Email"); errorText: qsTr("Enter a full email address, like ada@example.org") }
        Caption { text: "Disabled" }
        AtlasTextField { text: "Read only value"; enabled: false }
        Caption { text: "Long text" }
        AtlasTextField { text: "A very long value that does not fit in the field and must be cut off cleanly at the edge"; clearable: true; Component.onCompleted: cursorPosition = 0 }
    }
}
