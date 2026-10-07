import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonToolbar wide enough for every action, and narrow, with the rest
// behind the "more" button. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    TelamonAction {
        id: undo
        text: "Undo"
        symbol: Symbols.Undo
        section: "Edit"
    }
    TelamonAction {
        id: redo
        text: "Redo"
        symbol: Symbols.Redo
        section: "Edit"
        enabled: false
    }
    TelamonAction {
        id: bold
        text: "Bold"
        symbol: Symbols.FormatBold
        section: "Format"
        checkable: true
        checked: true
    }
    TelamonAction {
        id: italic
        text: "Italic"
        symbol: Symbols.FormatItalic
        section: "Format"
        checkable: true
    }
    TelamonAction {
        id: link
        text: "Link"
        symbol: Symbols.Link
        section: "Insert"
    }
    TelamonAction {
        id: image
        text: "Image"
        symbol: Symbols.Image
        section: "Insert"
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        spacing: Kirigami.Units.gridUnit

        QQC2.Label {
            text: "Wide"
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }
        TelamonToolbar {
            Layout.fillWidth: true
            actions: [undo, redo, bold, italic, link, image]
            leading: QQC2.Label {
                text: "Notes"
                font.bold: true
            }
        }
        QQC2.Label {
            text: "Narrow: the rest is behind More"
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }
        TelamonToolbar {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            flat: false
            actions: [undo, redo, bold, italic, link, image]
        }
        QQC2.Label {
            text: "Scroll: one button per step, with chevrons"
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }
        TelamonToolbar {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 11
            flat: false
            overflow: TelamonToolbar.Scroll
            actions: [undo, redo, bold, italic, link, image]
        }
        QQC2.Label {
            text: "Vertical"
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }
        TelamonToolbar {
            flat: false
            orientation: Qt.Vertical
            actions: [undo, redo, bold, italic]
        }
    }
}
