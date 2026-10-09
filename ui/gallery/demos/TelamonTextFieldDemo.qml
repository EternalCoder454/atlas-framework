import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonTextField. Tests set `animate` to false.
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

        Caption { text: "Default (empty, placeholder)" }
        TelamonTextField { placeholderText: qsTr("Name") }
        Caption { text: "With value, clearable" }
        TelamonTextField { text: "Ada Lovelace"; clearable: true; placeholderText: qsTr("Name") }
        Caption { text: "Error" }
        TelamonTextField { text: "ada@"; placeholderText: qsTr("Email"); errorText: qsTr("Enter a full email address, like ada@example.org") }
        Caption { text: "Counter (at the limit)" }
        TelamonTextField { text: "Ada Lovelace, Countess"; maximumLength: 22; showCounter: true; placeholderText: qsTr("Name") }
        Caption { text: "Prefix and suffix" }
        TelamonTextField { text: "12.5"; prefix: "$"; suffix: "kg"; placeholderText: qsTr("Weight") }
        Caption { text: "Invalid (typing)" }
        TelamonTextField {
            text: "ada@"
            validateOn: "typing"
            validator: RegularExpressionValidator { regularExpression: /[^@\s]+@[^@\s]+\.[a-z]+/ }
            invalidText: qsTr("Enter a full email address")
            Component.onCompleted: textEdited()
        }
        Caption { text: "Disabled" }
        TelamonTextField { text: "Read only value"; enabled: false }
        Caption { text: "Long text" }
        TelamonTextField { text: "A very long value that does not fit in the field and must be cut off cleanly at the edge"; clearable: true; Component.onCompleted: cursorPosition = 0 }
    }
}
