import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonCodeView: framed with a copy button and line numbers, a capped one
// that scrolls, and an unframed wrapped one. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        spacing: Kirigami.Units.smallSpacing

        Caption { text: "Copy and line numbers" }
        TelamonCodeView {
            Layout.fillWidth: true
            showCopy: true
            lineNumbers: true
            text: "int main()\n{\n    return 0;\n}"
        }
        Caption { text: "Capped height, scrolls" }
        TelamonCodeView {
            Layout.fillWidth: true
            maximumHeight: Kirigami.Units.gridUnit * 5
            text: "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10"
        }
        Caption { text: "Unframed, wrapped" }
        TelamonCodeView {
            Layout.fillWidth: true
            framed: false
            wrap: true
            text: "A long line of plain text that wraps at the width of the view instead of scrolling sideways, <b>not bold</b>."
        }
        Caption { text: "Unframed, inset" }
        TelamonCodeView {
            Layout.fillWidth: true
            framed: false
            inset: true
            wrap: true
            text: "Room at both edges, as a SectionRow's text has."
        }
    }
}
