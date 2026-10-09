import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonFloatingToolbar over some text. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 240

    TelamonAction {
        id: bold
        text: "Bold"
        symbol: Symbols.FormatBold
        checkable: true
        checked: true
        section: "Format"
    }
    TelamonAction {
        id: italic
        text: "Italic"
        symbol: Symbols.FormatItalic
        checkable: true
        section: "Format"
    }
    TelamonAction {
        id: link
        text: "Link"
        symbol: Symbols.Link
        section: "Insert"
    }
    TelamonAction {
        id: code
        text: "Code"
        symbol: Symbols.Code
        section: "Insert"
        enabled: false
    }

    QQC2.Label {
        textFormat: Text.PlainText
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: "The capsule floats over the page without taking the keyboard focus from the text beneath it. It fades in and out with `shown`, and stays inside its parent."
    }
    TelamonFloatingToolbar {
        actions: [bold, italic, link, code]
        shown: true
        x: Math.round((parent.width - width) / 2)
        y: parent.height - height - Kirigami.Units.gridUnit
    }
    // A tall capsule that stays quiet until the pointer is near.
    TelamonFloatingToolbar {
        actions: [bold, italic, link]
        orientation: Qt.Vertical
        autoDim: true
        shown: true
        x: parent.width - width - Kirigami.Units.gridUnit
        y: Math.round((parent.height - height) / 2)
    }
}
